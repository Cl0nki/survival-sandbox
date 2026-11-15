extends CharacterBody3D

## NPC visual: the same clip library as the player, on this mesh's profile skeleton.
## %GeneralSkeleton only resolves inside the imported model, so the tree has to
## drive that model's AnimationPlayer.

@onready var _tree: AnimationTree = $AnimationTree
@onready var _model: Node3D = $VisualRoot/Model


func _ready() -> void:
	var player := HumanoidClips.install(_model)
	if player == null or _tree == null:
		return
	_tree.anim_player = _tree.get_path_to(player)
	_tree.active = true
	_tree.set("parameters/loco/blend_position", 0.0)
