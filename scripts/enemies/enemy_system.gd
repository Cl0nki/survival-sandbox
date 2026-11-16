extends Node
class_name EnemySystem

## Server-only home for enemy AI. Phase 2 puts the spawner, the state machine,
## and the replication of enemy poses here. Nothing is spawned yet.
##
## GameNet owns an instance and only routes to it, so enemy code does not
## grow game_net.gd.

var net: GameNet


func bind(game_net: GameNet) -> void:
	net = game_net
	add_to_group(&"enemy_system")


func enemy_count() -> int:
	return 0
