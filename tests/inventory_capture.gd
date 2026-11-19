extends SceneTree

## Renders the open inventory with the weapon slots, for visual review.
## Needs a renderer, so do NOT use --headless:
##
## godot --path <project> --resolution 1600x900 --script res://tests/inventory_capture.gd
##
## Shots land in user://inventory_shots/


func _init() -> void:
	process_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	create_timer(60.0).timeout.connect(func() -> void: quit(2), CONNECT_ONE_SHOT)
	await _run()
	quit(0)


func _run() -> void:
	var out := ProjectSettings.globalize_path("user://inventory_shots")
	DirAccess.make_dir_recursive_absolute(out)
	var arena := (load("res://scenes/world/test_arena.tscn") as PackedScene).instantiate()
	root.add_child(arena)
	for _i in 30:
		await physics_frame
	var player := arena.get_node("Player") as PlayerController
	var bag := player.inventory
	bag.slots[9] = {"id": "workbench", "qty": 1}
	bag.slots[11] = {"id": "log", "qty": 20}
	bag.slots[12] = {"id": "ridgeback_rifle", "qty": 1}
	bag.slots[16] = {"id": "armory", "qty": 1}
	bag.slots[18] = {"id": "titan_hmg", "qty": 1}
	bag.slots[22] = {"id": "hailstorm_lmg", "qty": 1}
	bag.slots[34] = {"id": "log", "qty": 5}
	bag.slots[PlayerSlots.PRIMARY] = {"id": "kodiak_rifle", "qty": 1}
	bag.slots[PlayerSlots.SIDEARM] = {"id": "courier_pistol", "qty": 1}
	player.select_slot(PlayerSlots.PRIMARY)
	await _shot(out, "1_hud")
	var ui: InventoryUI = player._item_ui
	ui._screen.visible = true
	ui._hud.visible = false
	ui._refresh()
	await _shot(out, "2_open")
	player.select_slot(0)
	bag.slots[PlayerSlots.PRIMARY] = {"id": "", "qty": 0}
	bag.slots[PlayerSlots.SIDEARM] = {"id": "", "qty": 0}
	ui._refresh()
	await _shot(out, "3_empty")
	print("INVENTORY_CAPTURE_DONE ", out)


func _shot(out: String, name: String, delay := 0.4) -> void:
	await create_timer(delay).timeout
	for _i in 4:
		await process_frame
	var image := root.get_viewport().get_texture().get_image()
	image.save_png(out.path_join(name + ".png"))


class PlayerSlots:
	const PRIMARY := NetConfig.BAG_SLOTS
	const SIDEARM := NetConfig.BAG_SLOTS + 1
