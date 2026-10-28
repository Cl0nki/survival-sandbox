extends Node3D

## Manual verification scene: the local arena with every Phase 1 scenario from
## BuildingScenarios prebuilt and labelled. Play it, take hotbar slot 2 (Build
## Tool), and press F3 for the building debug view.

var system: BuildingSystem
var failures := PackedStringArray()


func _ready() -> void:
	var arena := (load("res://scenes/world/test_arena.tscn") as PackedScene).instantiate()
	arena.set("force_mode", NetConfig.MODE_LOCAL)
	add_child(arena)
	system = arena.get_node("BuildingSystem") as BuildingSystem
	failures = BuildingScenarios.build_all(system.authority)
	for failure in failures:
		push_warning("Building scenario failed: %s" % failure)
	for sign: Array in BuildingScenarios.sign_positions(system.grid):
		var label := Label3D.new()
		label.text = str(sign[0])
		label.position = sign[1]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.font_size = 48
		label.pixel_size = 0.004
		label.outline_size = 10
		label.modulate = Color(1.0, 0.95, 0.75)
		add_child(label)
