extends Node
class_name VitalsSystem

## Server-only. Watches every pawn and runs the death loop: a pawn that reaches
## zero health drops what it carried, waits RESPAWN_DELAY_SEC, then returns at a
## spawn point with an empty bag (or the debug-map loadout).
##
## It polls health instead of listening for a signal, so a death from any source
## (a shot today; an enemy, hunger or cold later) goes through the same path.
## Stamina and hunger will live here too. GameNet only routes to it.

const RESPAWN_DELAY_SEC := 5.0

var net: GameNet
## peer id -> seconds until respawn. Present only while that peer is dead.
var _dead: Dictionary = {}


func bind(game_net: GameNet) -> void:
	net = game_net
	add_to_group(&"vitals_system")


func is_dead(peer_id: int) -> bool:
	return _dead.has(peer_id)


func respawn_in(peer_id: int) -> float:
	return float(_dead.get(peer_id, 0.0))


## A peer left. Its timer goes with it; GameNet stashes the profile separately.
func forget(peer_id: int) -> void:
	_dead.erase(peer_id)


func _physics_process(delta: float) -> void:
	advance(delta)


## One step of the death loop. Public so a test can run it without waiting.
func advance(delta: float) -> void:
	if net == null:
		return
	var players := net.authority_players()
	for key in players.keys():
		var peer_id := int(key)
		var player := players[key] as PlayerController
		if player == null or not is_instance_valid(player):
			_dead.erase(peer_id)
			continue
		if player.health > 0:
			_dead.erase(peer_id)
			continue
		if not _dead.has(peer_id):
			_dead[peer_id] = RESPAWN_DELAY_SEC
			net.server_handle_death(peer_id, RESPAWN_DELAY_SEC)
			continue
		var left := float(_dead[peer_id]) - delta
		if left > 0.0:
			_dead[peer_id] = left
			continue
		_dead.erase(peer_id)
		net.server_respawn(peer_id)
	for key in _dead.keys():
		if not players.has(key):
			_dead.erase(key)
