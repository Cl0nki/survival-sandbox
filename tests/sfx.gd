extends SceneTree

## Sound: the manifest reader, voice pool, cooldowns, footstep spacing, and the link
## between the Sounds tool's event list and the code that plays them.
## godot --headless --path <project> --script res://tests/sfx.gd

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const WORK_DIR := "user://sfx_test"
const EVENT_SOURCES := {
	"res://scripts/player/player_controller.gd": ["hurt"],
	"res://scripts/world/ground_surface.gd": [
		"footstep", "footstep_grass", "footstep_forest", "footstep_dirt", "footstep_gravel",
		"footstep_sand", "footstep_rock", "footstep_asphalt",
	],
	"res://scripts/audio/sfx.gd": ["shot", "shot_far", "bullet_impact", "bullet_hit"],
	"res://scripts/enemies/creature_view.gd": ["hog_grunt", "hog_alert", "hog_charge", "hog_hurt", "hog_die"],
	"res://scripts/items/loot_container.gd": ["craft_start", "craft_done"],
	"res://scripts/deployables/crafter.gd": ["craft_start", "craft_done"],
	"res://scripts/deployables/smelter.gd": ["craft_start", "craft_done"],
}

var _failures := PackedStringArray()
var _checks := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(30.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("SFX_OK")
		quit(0)
	else:
		quit(1)


func _run() -> void:
	_prepare_files()
	await _manager()
	_facade()
	_real_manifest()
	_tool_matches_game()
	_ground_surface()
	_shooting_helpers()
	_hog_voices()
	await _footsteps()
	await _footsteps_follow_the_ground()


func _prepare_files() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(WORK_DIR))
	_write_wav(WORK_DIR + "/step_a.wav", 0.1)
	_write_wav(WORK_DIR + "/step_b.wav", 0.2)
	_write_wav(WORK_DIR + "/bang.wav", 0.1)
	var manifest := {
		"version": 1,
		"events": {
			"footstep": {
				"files": [WORK_DIR + "/step_a.wav", WORK_DIR + "/step_b.wav", WORK_DIR + "/missing.wav"],
				"volume_db": -6.0, "pitch_min": 1.2, "pitch_max": 0.9, "cooldown": 0.0, "max_distance": 20.0,
			},
			"shot": {
				"files": [WORK_DIR + "/bang.wav"],
				"volume_db": 0.0, "pitch_min": 1.0, "pitch_max": 1.0, "cooldown": 10.0, "max_distance": 90.0,
			},
			"hurt": {"files": [], "volume_db": 0.0, "pitch_min": 1.0, "pitch_max": 1.0, "cooldown": 0.0, "max_distance": 40.0},
		},
	}
	var handle := FileAccess.open(WORK_DIR + "/sounds.json", FileAccess.WRITE)
	handle.store_string(JSON.stringify(manifest))
	handle.close()


func _write_wav(path: String, seconds: float) -> void:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = 8000
	wav.stereo = false
	var data := PackedByteArray()
	data.resize(int(8000.0 * seconds) * 2)
	wav.data = data
	wav.save_to_wav(path)


func _manager() -> void:
	var manager := SfxManager.new()
	manager.manifest_path = WORK_DIR + "/sounds.json"
	root.add_child(manager)
	await process_frame

	_check(manager.sound_count(&"footstep") == 2, "the missing file was not skipped (%d)" % manager.sound_count(&"footstep"))
	_check(manager.has_event(&"shot") and not manager.has_event(&"hurt"), "has_event is wrong")
	_check(not manager.has_event(&"nope"), "an unknown event reported sounds")
	_check(not manager.play(&"nope") and not manager.play_at(&"hurt", Vector3.ZERO), "silent events played")

	var length := (SfxManager.load_stream(WORK_DIR + "/step_b.wav") as AudioStreamWAV).get_length()
	_check(absf(length - 0.2) < 0.02, "a WAV that is not imported did not decode (%f s)" % length)
	_check(SfxManager.load_stream(WORK_DIR + "/missing.wav") == null, "a missing file produced a stream")
	_check(SfxManager.load_stream("res://nothing/here.ogg") == null, "a missing res file produced a stream")

	var bus := AudioServer.get_bus_index(SfxManager.BUS_NAME)
	_check(bus >= 0, "the SFX bus was not created")

	_check(manager.play_at(&"footstep", Vector3(3, 0, 4)), "a footstep did not play")
	var live := 0
	for child in manager.get_children():
		if child is AudioStreamPlayer3D and (child as AudioStreamPlayer3D).playing:
			live += 1
			_check((child as AudioStreamPlayer3D).global_position.is_equal_approx(Vector3(3, 0, 4)), "voice is not where the sound is")
			_check(is_equal_approx((child as AudioStreamPlayer3D).max_distance, 20.0), "max_distance was not applied")
	_check(live == 1, "expected one live 3D voice, saw %d" % live)

	_check(manager.play(&"footstep", -3.0), "a flat sound did not play")
	var flat := manager.get_children().filter(func(node: Node) -> bool: return node is AudioStreamPlayer and (node as AudioStreamPlayer).playing)
	_check(flat.size() == 1, "expected one live flat voice")
	if flat.size() == 1:
		_check(is_equal_approx((flat[0] as AudioStreamPlayer).volume_db, -9.0), "gain was not added to the event volume")

	manager.play(&"footstep", 0.0, 2.0)
	var fast := manager.get_children().filter(func(node: Node) -> bool: return node is AudioStreamPlayer and (node as AudioStreamPlayer).playing)
	var fastest := 0.0
	for voice in fast:
		fastest = maxf(fastest, (voice as AudioStreamPlayer).pitch_scale)
	_check(fastest >= 1.8 - 0.001 and fastest <= 2.4 + 0.001, "the pitch multiplier was not applied (%f)" % fastest)

	_check(manager.play(&"shot"), "the first shot did not play")
	_check(not manager.play(&"shot"), "the shot cooldown did not hold")

	# Reversed pitch values in a manifest are repaired, and a pick never repeats.
	var spec: Dictionary = manager._events[&"footstep"]
	_check(float(spec["pitch_min"]) <= float(spec["pitch_max"]), "pitch range was left reversed")
	var previous: Variant = null
	var repeated := false
	var pitch_ok := true
	for _i in 60:
		var taken: Dictionary = manager._take(&"footstep")
		if previous != null and taken["stream"] == previous:
			repeated = true
		previous = taken["stream"]
		var pitch := float(taken["pitch"])
		if pitch < 0.9 - 0.0001 or pitch > 1.2 + 0.0001:
			pitch_ok = false
	_check(not repeated, "the same footstep file played twice in a row")
	_check(pitch_ok, "pitch left its range")

	# More sounds than voices steals a voice instead of failing.
	var all_played := true
	for _i in SfxManager.VOICES_3D * 2:
		all_played = manager.play_at(&"footstep", Vector3.ZERO) and all_played
	_check(all_played, "a full voice pool refused a sound")

	manager.manifest_path = WORK_DIR + "/does_not_exist.json"
	manager.reload()
	_check(not manager.has_event(&"footstep"), "reload kept old events after the manifest vanished")
	manager.manifest_path = WORK_DIR + "/sounds.json"
	manager.reload()
	_check(manager.has_event(&"footstep"), "reload did not bring the events back")
	manager.queue_free()
	await process_frame


func _facade() -> void:
	# The headless run has no audio hardware, so the facade stays out of the way.
	_check(Sfx.manager() == null, "the facade made a sound node in a headless run")
	_check(not Sfx.play_at(&"footstep", Vector3.ZERO, true) and not Sfx.play(&"shot"), "the facade played in a headless run")
	Sfx.warm()
	Sfx.reload()
	Sfx.set_volume(0.5)


func _real_manifest() -> void:
	var path := SfxManager.MANIFEST_PATH
	if not FileAccess.file_exists(path):
		print("note: no %s yet, so no files to check" % path)
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	_check(parsed is Dictionary and (parsed as Dictionary).get("events") is Dictionary, "the project manifest is not valid")
	if not (parsed is Dictionary):
		return
	var loaded := 0
	for key in ((parsed as Dictionary).get("events", {}) as Dictionary):
		var row: Dictionary = ((parsed as Dictionary)["events"] as Dictionary)[key]
		for file in row.get("files", []):
			var stream := SfxManager.load_stream(str(file))
			_check(stream != null, "%s: %s does not load" % [key, file])
			loaded += 1
	print("note: %d project sound file(s) load" % loaded)


## The tool decides which events exist and the game decides which it plays. Both lists
## must agree, or a sound added in the tool would never be heard.
func _tool_matches_game() -> void:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://tools/ai_asset_pipeline/config/sounds.json"))
	_check(config is Dictionary, "sounds.json config is missing or invalid")
	if not (config is Dictionary):
		return
	var known := {}
	for event in (config as Dictionary)["events"]:
		known[str((event as Dictionary)["id"])] = true
	var played := {}
	for source in EVENT_SOURCES:
		var text := FileAccess.get_file_as_string(source)
		for id in EVENT_SOURCES[source]:
			played[id] = true
			_check(text.contains('&"%s"' % id), "%s no longer plays %s" % [source, id])
	for id in played:
		_check(known.has(id), "the game plays %s but the Sounds tool does not list it" % id)
	for id in known:
		_check(played.has(id), "the Sounds tool lists %s but nothing plays it" % id)


func _ground_surface() -> void:
	GroundSurface.clear()
	_check(GroundSurface.at(Vector3(5, 0, 5)) == &"" and not GroundSurface.is_registered(), "an unpainted map reported a surface")
	_check(GroundSurface.footstep_event(&"") == &"footstep", "an unknown surface did not fall back to the plain footstep")
	for surface in [&"grass", &"forest", &"dirt", &"gravel", &"sand", &"rock", &"asphalt"]:
		_check(GroundSurface.footstep_event(surface) == StringName("footstep_%s" % surface), "%s has the wrong footstep event" % surface)

	var base := [
		[Vector3(0, 0, 0), 20.0, GroundSplat.LAYER_MEADOW],
		[Vector3(30, 0, 0), Vector2(10.0, 4.0), GroundSplat.LAYER_ROCK],
	]
	var soil := [[Vector3(0, 0, 0), 4.0, GroundSplat.SOIL_GRAVEL], [Vector3(-8, 0, 0), 2.0, GroundSplat.SOIL_SAND], [Vector3(8, 0, 0), 2.0, GroundSplat.SOIL_CLAY]]
	var asphalt := [[Vector3(0, 0, 0), 2.0, 0]]
	var forest := [[Vector3(0, 0, 8), 6.0, 0]]
	GroundSurface.register(base, soil, asphalt, forest, GroundSurface.GRASS)
	_check(GroundSurface.is_registered(), "register did not register")
	_check(GroundSurface.at(Vector3(0, 1, 0.5)) == &"asphalt", "asphalt did not win over gravel and meadow")
	_check(GroundSurface.at(Vector3(1.5, 1, 0)) == &"gravel", "soil did not win over meadow")
	_check(GroundSurface.at(Vector3(-8, 0, 0)) == &"sand" and GroundSurface.at(Vector3(8, 0, 0)) == &"dirt", "sand or clay is wrong")
	_check(GroundSurface.at(Vector3(0, 0, 8)) == &"forest", "forest floor was not found")
	_check(GroundSurface.at(Vector3(0, 0, 3)) == &"grass", "outside the forest was not meadow")
	_check(GroundSurface.at(Vector3(30, 0, 1)) == &"rock", "a rock region was not found")
	_check(GroundSurface.at(Vector3(300, 0, 300)) == &"grass", "unpainted ground did not use the map's fallback")
	GroundSurface.register([], [], [], [], GroundSurface.DIRT)
	_check(GroundSurface.at(Vector3.ZERO) == &"dirt", "the debug yard fallback is not dirt")
	GroundSurface.clear()


func _shooting_helpers() -> void:
	# Headless: no sound plays, but the picking logic must still be sound.
	_check(Sfx.first_with_sound([&"a", &"b"]) == &"b", "first_with_sound did not return the last event when nothing has a sound")
	_check(Sfx.first_with_sound([]) == &"", "first_with_sound of nothing was not empty")
	_check(not Sfx.has_sound(&"shot"), "has_sound was true in a headless run")
	_check(not Sfx.gunshot(Vector3.ZERO, true) and not Sfx.gunshot(Vector3(500, 0, 0), false), "a gunshot played in a headless run")
	_check(not Sfx.bullet_lands(Vector3.ZERO, Vector3(5, 0, 0), true), "a bullet hit played in a headless run")
	var weapon := HitscanWeapon.new()
	_check(Sfx.SHOT_MISS_METERS < weapon.range_meters, "a shot at full range would count as a hit")
	weapon.free()
	_check(Sfx.FAR_SHOT_METERS < Sfx.SHOT_MISS_METERS, "the far-shot distance is beyond the weapon's reach")


func _hog_voices() -> void:
	_check(CreatureView.voice_for_state(Hog.S_WINDUP) == &"hog_alert", "windup is not the alert voice")
	_check(CreatureView.voice_for_state(Hog.S_CHARGE) == &"hog_charge", "charge is not the charge voice")
	_check(CreatureView.voice_for_state(Hog.S_STUNNED) == &"hog_hurt", "stunned is not the hurt voice")
	_check(CreatureView.voice_for_state(Creature.S_IDLE) == &"" and CreatureView.voice_for_state(Hog.S_WALK) == &"" and CreatureView.voice_for_state(Hog.S_RECOVER) == &"", "a quiet state has a voice")

	var view := CreatureView.new()
	root.add_child(view)
	view.setup(7, 0, 10, 10, Creature.S_IDLE, Vector3.ZERO, 0.0)
	_check(not view._voiced_death, "a living hog already voiced its death")
	view.set_health(4)
	_check(not view._voiced_death and not view.is_dead(), "damage was treated as death")
	view.set_health(0)
	_check(view.is_dead() and view._voiced_death, "death was not voiced once")
	view.queue_free()

	var corpse := CreatureView.new()
	root.add_child(corpse)
	corpse.setup(8, 0, 0, 10, Creature.S_DEAD, Vector3.ZERO, 0.0)
	_check(corpse._voiced_death, "a hog that was dead on arrival voiced its death")
	corpse.queue_free()


func _footsteps_follow_the_ground() -> void:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.configure_net(PlayerController.NetRole.PUPPET, 92)
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	GroundSurface.register([], [[Vector3(0, 0, 0), 400.0, GroundSplat.SOIL_GRAVEL]], [], [], GroundSurface.GRASS)
	player.global_position = Vector3(0, 0.15, 0)
	_move(player, PlayerController.WALK_SPEED, 3.0, 0.016)
	_check(player.last_step_surface == &"gravel", "a step on gravel was recorded as %s" % player.last_step_surface)
	GroundSurface.register([], [], [], [], GroundSurface.GRASS)
	_move(player, PlayerController.WALK_SPEED, 3.0, 0.016)
	_check(player.last_step_surface == &"grass", "a step on grass was recorded as %s" % player.last_step_surface)
	_check(PlayerController.STEP_CROUCH_PITCH < 1.0 and PlayerController.STEP_RUN_PITCH > 1.0, "speed does not shift the footstep pitch the right way")
	GroundSurface.clear()
	player.queue_free()
	await process_frame
	await process_frame


func _footsteps() -> void:
	var player := PLAYER_SCENE.instantiate() as PlayerController
	player.configure_net(PlayerController.NetRole.PUPPET, 91)
	root.add_child(player)
	await process_frame
	player.set_process(false)
	player.set_physics_process(false)
	player.global_position = Vector3(0, 0.15, 0)
	var counts := {"steps": 0, "running": 0, "crouching": 0}
	player.footstep_taken.connect(func(running: bool, crouching: bool) -> void:
		counts["steps"] += 1
		counts["running"] += 1 if running else 0
		counts["crouching"] += 1 if crouching else 0
	)
	var dt := 0.016

	_move(player, 0.0, 1.6, dt)
	_check(counts["steps"] == 0, "standing still made %d steps" % counts["steps"])

	_move(player, PlayerController.WALK_SPEED, 10.0, dt)
	var walked: int = counts["steps"]
	var expected_walk := PlayerController.WALK_SPEED * 10.0 / PlayerController.STEP_STRIDE_WALK
	_check(absf(float(walked) - expected_walk) <= 2.0, "walking 10 s made %d steps, expected about %.1f" % [walked, expected_walk])
	_check(counts["running"] == 0, "walking was counted as running")

	counts["steps"] = 0
	_move(player, PlayerController.RUN_SPEED, 10.0, dt)
	var expected_run := PlayerController.RUN_SPEED * 10.0 / PlayerController.STEP_STRIDE_RUN
	_check(absf(float(counts["steps"]) - expected_run) <= 2.5, "running 10 s made %d steps, expected about %.1f" % [counts["steps"], expected_run])
	_check(counts["running"] >= counts["steps"] - 2, "running was not reported as running")
	_check(float(counts["steps"]) / 30.5 < float(walked) / 16.25, "running steps were not spaced wider than walking steps")

	counts["steps"] = 0
	counts["crouching"] = 0
	player._crouch = 1.0
	_move(player, PlayerController.CROUCH_SPEED, 4.0, dt)
	_check(counts["steps"] > 0 and counts["crouching"] == counts["steps"], "crouch steps were not marked crouching")
	player._crouch = 0.0

	counts["steps"] = 0
	player.global_position += Vector3(60.0, 0, 0)
	_move(player, 0.0, 0.5, dt)
	_check(counts["steps"] == 0, "a teleport made a footstep")

	player._down = true
	_move(player, PlayerController.WALK_SPEED, 3.0, dt)
	_check(counts["steps"] == 0, "a downed body made footsteps")
	player._down = false

	player.queue_free()
	await process_frame
	await process_frame


func _move(player: PlayerController, speed: float, seconds: float, dt: float) -> void:
	var frames := int(seconds / dt)
	for _i in frames:
		player.global_position += Vector3(speed * dt, 0.0, 0.0)
		player._update_footsteps(dt)


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
