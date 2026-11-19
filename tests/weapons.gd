extends SceneTree

## The weapon roster: two or more guns per ammunition type, a shotgun, a sword,
## original names, a recipe for each, sane firing numbers, pellet spread, and the
## melee arc.
## godot --headless --path <project> --script res://tests/weapons.gd

const AMMO := ["ammo_9mm", "ammo_45acp", "ammo_556", "ammo_762", "ammo_12gauge", "ammo_50bmg"]
const NEW_GUNS := [
	"courier_pistol", "hornet_pdw", "marshal_pistol", "rattler_smg", "ridgeback_rifle",
	"hailstorm_lmg", "kodiak_rifle", "falconer_rifle", "breacher_shotgun", "mule_shotgun",
	"goliath_amr", "titan_hmg",
]
## Real makers and models. The stand-ins must not borrow them.
const BRANDS := [
	"p90", "browning", "barrett", "barret", "glock", "colt", "ak-47", "ak47", "m16", "ar-15", "ar15",
	"uzi", "thompson", "remington", "winchester", "mossberg", "beretta", "desert eagle", "kalashnikov",
	"heckler", "fn ", "sig ", "m249", "m2 ", "m1911", "1911", "springfield", "ruger", "smith",
]
## The bench that runs a tier of the "bench" recipe family.
const BENCH := {1: "workbench", 2: "workbench_iron", 3: "workbench_steel", 4: "workbench_composite"}

var _failures := PackedStringArray()
var _checks := 0


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	await _run()
	print("checks=%d failures=%d" % [_checks, _failures.size()])
	for failure in _failures:
		print("FAIL ", failure)
	if _failures.is_empty():
		print("WEAPONS_OK")
		quit(0)
	else:
		quit(1)


func _run() -> void:
	_roster()
	_recipes()
	_numbers()
	_names()
	_spread()
	await _melee()


func _guns_for(ammo: String) -> Array[String]:
	var found: Array[String] = []
	for item_id in ItemCatalog.all_ids():
		var spec := WeaponSpec.for_item(item_id)
		if spec != null and spec.kind == WeaponSpec.FIREARM and spec.ammo_id == ammo:
			found.append(item_id)
	return found


func _roster() -> void:
	for ammo in AMMO:
		_check(ItemCatalog.known(ammo), "%s is not an item" % ammo)
		var guns := _guns_for(ammo)
		_check(guns.size() >= 2, "%s has %d gun(s): %s" % [ammo, guns.size(), guns])
	for gun in NEW_GUNS:
		_check(ItemCatalog.known(gun), "%s missing" % gun)
	var shotguns := 0
	for gun in _guns_for("ammo_12gauge"):
		if WeaponSpec.for_item(gun).pellets > 1:
			shotguns += 1
	_check(shotguns >= 1, "no shotgun fires more than one pellet")
	var sword := WeaponSpec.for_item("sword")
	_check(sword != null and sword.is_melee(), "sword is not a melee weapon")
	_check(sword != null and not sword.uses_ammo(), "sword uses ammunition")
	var pistol := WeaponSpec.for_item("pistol")
	_check(pistol != null and pistol.ammo_id == "ammo_9mm" and pistol.damage == 34, "pistol changed")
	var debug_gun := WeaponSpec.for_item("debugweapon")
	_check(debug_gun != null and not debug_gun.uses_ammo(), "debug weapon should not use ammunition")
	_check(
		debug_gun != null and debug_gun.damage == WeaponSpec.DEFAULT_DAMAGE
			and is_equal_approx(debug_gun.cooldown_seconds, WeaponSpec.DEFAULT_COOLDOWN),
		"debug weapon lost its default stats"
	)
	_check(WeaponSpec.for_item("log") == null and WeaponSpec.for_item("") == null, "a non-weapon has a spec")
	_check(not WeaponSpec.is_weapon("blast_gun"), "the blast gun is a weapon")


func _recipes() -> void:
	var made: Array[String] = ["pistol", "sword"]
	made.append_array(NEW_GUNS)
	var recipes := CraftRules.all_recipes()
	for weapon in made:
		var found: Dictionary = {}
		for recipe in recipes:
			if str(recipe["output"]) == weapon:
				found = recipe
		_check(not found.is_empty(), "%s has no recipe" % weapon)
		if found.is_empty():
			continue
		var tier := int(found["tier"])
		var bench: String = BENCH[tier]
		var input_id := str(found["input"])
		var extra_id := str(found["extra"])
		var in_n := int(found["in_n"])
		var extra_n := int(found["extra_n"])
		var plan := CraftRules.plan(bench, input_id, in_n, extra_id, extra_n, "coal", 1, "", 0)
		_check(bool(plan["ok"]) and str(plan["output_id"]) == weapon and int(plan["output_count"]) == 1, "%s plan %s" % [weapon, plan])
		_check(ItemCatalog.get_item(input_id).max_stack >= in_n, "%s needs more %s than fits a stack" % [weapon, input_id])
		if extra_n > 0:
			_check(ItemCatalog.get_item(extra_id).max_stack >= extra_n, "%s needs more %s than fits a stack" % [weapon, extra_id])
		if tier > 1:
			var early := CraftRules.plan(BENCH[tier - 1], input_id, in_n, extra_id, extra_n, "coal", 1, "", 0)
			_check(not bool(early["ok"]), "%s could be made a bench too early" % weapon)
	# One recipe per input pair, or the second would never be reachable.
	var seen := {}
	for recipe in recipes:
		if str(recipe["family"]) != "bench":
			continue
		var key := "%s|%s" % [recipe["input"], recipe["extra"]]
		_check(not seen.has(key), "two bench recipes share the inputs %s" % key)
		seen[key] = true


func _numbers() -> void:
	var ids := ["pistol", "debugweapon", "sword"]
	ids.append_array(NEW_GUNS)
	for item_id in ids:
		var spec := WeaponSpec.for_item(item_id)
		if spec == null:
			_check(false, "%s has no spec" % item_id)
			continue
		_check(spec.damage > 0 and spec.range_meters > 0.0 and spec.cooldown_seconds > 0.0, "%s has a zero stat" % item_id)
		# The server drops fire past this many a second, so a faster gun would lose shots.
		_check(
			spec.rounds_per_second() <= float(NetConfig.FIRE_RATE_PER_SEC) - 1.0,
			"%s fires %.1f/s, past the server limit" % [item_id, spec.rounds_per_second()]
		)
		_check(spec.pellets >= 1 and spec.pellets <= 16, "%s pellets %d" % [item_id, spec.pellets])
		if spec.uses_ammo():
			var ammo := ItemCatalog.get_item(spec.ammo_id)
			_check(ammo != null and ammo.category == "ammo", "%s ammo %s is not ammunition" % [item_id, spec.ammo_id])
		_check(ItemCatalog.get_item(item_id).category == "weapon", "%s is not a weapon category" % item_id)
		_check(ItemCatalog.get_item(item_id).max_stack == 1, "%s stacks" % item_id)
	var sword := WeaponSpec.for_item("sword")
	_check(sword.range_meters < 4.0, "sword reach %.1f is not melee" % sword.range_meters)
	_check(WeaponSpec.for_item("goliath_amr").damage > WeaponSpec.for_item("pistol").damage * 3, "the anti-materiel rifle is not the hardest hitter")
	_check(WeaponSpec.for_item("titan_hmg").automatic and WeaponSpec.for_item("hornet_pdw").automatic, "machine guns should hold to fire")
	_check(not WeaponSpec.for_item("pistol").automatic and not WeaponSpec.for_item("falconer_rifle").automatic, "semi-autos should not hold to fire")
	var weapon := HitscanWeapon.new()
	weapon.configure(WeaponSpec.for_item("breacher_shotgun"))
	_check(weapon.pellets == 8 and weapon.damage == 14 and not weapon.melee, "shotgun did not configure the weapon")
	_check(weapon.shot_directions(Vector3.FORWARD).size() == 8, "shotgun should throw eight pellets")
	weapon.configure(WeaponSpec.for_item("sword"))
	_check(weapon.melee and weapon.ammo_id == "", "sword did not configure the weapon")
	weapon.free()


func _names() -> void:
	var ids := ["sword"]
	ids.append_array(NEW_GUNS)
	var seen := {}
	for item_id in ids:
		var definition := ItemCatalog.get_item(item_id)
		if definition == null:
			continue
		var text := " %s %s %s " % [definition.id, definition.display_name, definition.description]
		for brand in BRANDS:
			_check(not text.to_lower().contains(brand), "%s mentions %s" % [item_id, brand.strip_edges()])
		_check(not seen.has(definition.display_name), "duplicate name %s" % definition.display_name)
		seen[definition.display_name] = true


func _spread() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var aim := Vector3(0.3, 0.1, -1.0).normalized()
	var widest := 0.0
	for _i in 400:
		var shot := HitscanWeapon.scatter(aim, 6.0, rng)
		_check(is_equal_approx(shot.length(), 1.0), "scattered direction is not a unit vector")
		widest = maxf(widest, rad_to_deg(aim.angle_to(shot)))
	_check(widest <= 6.05, "a pellet left the cone: %.2f deg" % widest)
	_check(widest > 3.0, "the cone is never used: widest %.2f deg" % widest)
	_check(HitscanWeapon.scatter(aim, 0.0, rng).is_equal_approx(aim), "no spread should keep the aim")
	var far_aim := Vector3.UP
	var shot_up := HitscanWeapon.scatter(far_aim, 5.0, rng)
	_check(rad_to_deg(far_aim.angle_to(shot_up)) <= 5.05, "straight-up aim scattered wrongly")


func _melee() -> void:
	var damaged := GDScript.new()
	damaged.source_code = "extends StaticBody3D\nvar taken := 0\nfunc receive_damage(amount: int, _point: Vector3) -> bool:\n\ttaken += amount\n\treturn true\n"
	damaged.reload()
	var stage := Node3D.new()
	root.add_child(stage)
	var ahead := _target(stage, damaged, Vector3(0.0, 0.0, -1.5))
	var beside := _target(stage, damaged, Vector3(0.44, 0.0, -1.43))
	var far := _target(stage, damaged, Vector3(-4.0, 0.0, -3.0))
	await physics_frame
	await physics_frame
	var space := root.world_3d.direct_space_state
	var reach := WeaponSpec.for_item("sword").range_meters
	var origin := Vector3(0.0, 0.0, 0.0)

	var straight := HitscanWeapon.resolve_melee(space, origin, Vector3(0.0, 0.0, -1.0), reach)
	_check(straight["collider"] == ahead, "a swing straight at a target missed (%s)" % straight["collider"])

	# Take the target in front away. The one off to the side is inside the arc.
	ahead.free()
	await physics_frame
	await physics_frame
	space = root.world_3d.direct_space_state
	var arc := HitscanWeapon.resolve_melee(space, origin, Vector3(0.0, 0.0, -1.0), reach)
	_check(arc["collider"] == beside, "the swing arc missed a target to the side (%s)" % arc["collider"])

	var out_of_reach := HitscanWeapon.resolve_melee(space, origin, Vector3(-1.0, 0.0, -0.75).normalized(), reach)
	_check(out_of_reach["collider"] != far, "a blade reached a target 5 m away")
	_check(not bool(out_of_reach["damaged"]), "a missed swing reported damage")
	stage.queue_free()


func _target(stage: Node3D, script: GDScript, at: Vector3) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.set_script(script)
	body.collision_layer = PhysicsLayers.DAMAGEABLE
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.5, 1.0, 0.5)
	shape.shape = box
	body.add_child(shape)
	stage.add_child(body)
	body.global_position = at
	return body


func _check(ok: bool, message: String) -> void:
	_checks += 1
	if not ok:
		_failures.append(message)
