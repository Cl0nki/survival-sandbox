extends RefCounted
class_name HarvestSwing

## Shared melee harvest query. Local play and the server call the same math.

## Horizontal metres from the player body to the contact point.
## A 1 m ray from the muzzle still reached a wreck from about 3 m away,
## because the muzzle sits forward and the hull is wider than the mesh.
const RANGE := 1.5


const GROUND_EXTRACT_SCALE := 300.0


static func damage_for(tool: ItemDefinition, deposit: ResourceDeposit) -> int:
	if tool == null or deposit == null:
		return 0
	if tool.harvest_kind != deposit.tool_kind or tool.harvest_power <= 0:
		return 0
	var resist := maxf(deposit.resistance, 0.01)
	return maxi(1, int(round(float(tool.harvest_power) * deposit.tool_multiplier / resist)))


static func ground_extract(tool: ItemDefinition, spec: GroundDepositDefinition) -> int:
	if tool == null or spec == null:
		return 0
	if spec.harvest_kind == "" or tool.harvest_kind != spec.harvest_kind or tool.harvest_power <= 0:
		return 0
	return maxi(1, int(round(float(tool.harvest_power) * GROUND_EXTRACT_SCALE / float(maxi(spec.resistance, 1)))))


## Farthest point of the swing: where the aim ray leaves the reach circle.
static func reach_point(body_pos: Vector3, origin: Vector3, direction: Vector3) -> Vector3:
	if direction.length_squared() < 0.000001:
		return origin
	var dir := direction.normalized()
	var flat_origin := Vector2(origin.x - body_pos.x, origin.z - body_pos.z)
	var flat_dir := Vector2(dir.x, dir.z)
	var a := flat_dir.length_squared()
	if a < 0.0001:
		if flat_origin.length() > RANGE:
			return origin
		return origin + dir * 2.0
	var b := 2.0 * flat_origin.dot(flat_dir)
	var c := flat_origin.length_squared() - RANGE * RANGE
	var disc := b * b - 4.0 * a * c
	if disc < 0.0:
		return origin
	var root := sqrt(disc)
	var t_far := (-b + root) / (2.0 * a)
	var t_near := (-b - root) / (2.0 * a)
	var t := t_far if t_far >= 0.0 else t_near
	if t < 0.05:
		return origin
	return origin + dir * t


static func in_reach(body_pos: Vector3, point: Vector3) -> bool:
	return Vector2(point.x - body_pos.x, point.z - body_pos.z).length() <= RANGE + 0.02


static func tool_label(kind: String) -> String:
	match kind:
		"pickaxe":
			return "pickaxe"
		"shovel":
			return "shovel"
		"hatchet":
			return "hatchet"
		"crowbar":
			return "crowbar"
		_:
			return "harvest tool"


static func try_strike(
	body: Node3D,
	origin: Vector3,
	direction: Vector3,
	tool_id: String,
	bag: Inventory
) -> Dictionary:
	var miss := {
		"ok": false,
		"notice": "Nothing to harvest.",
		"changed": false,
		"point": origin,
		"collider": null,
		"node_id": "",
		"deposit_id": "",
		"health": 0,
		"depleted": false,
		"yielded": 0,
		"leftover": 0,
		"item_id": "",
		"damage": 0,
	}
	if body == null or direction.length_squared() < 0.000001:
		return miss
	var world := body.get_world_3d()
	if world == null or world.direct_space_state == null:
		return miss
	var exclude: Array = []
	if body is CollisionObject3D:
		exclude.append((body as CollisionObject3D).get_rid())
	var end := reach_point(body.global_position, origin, direction)
	var span := origin.distance_to(end)
	var hit := HitscanWeapon.resolve_shot(world.direct_space_state, origin, direction, span, exclude)
	miss["point"] = end
	if not in_reach(body.global_position, hit["point"]):
		return miss
	miss["point"] = hit["point"]
	miss["collider"] = hit["collider"]
	var node := hit["collider"] as ResourceNode
	if node != null:
		var rock := node.harvest(tool_id, bag)
		rock["point"] = hit["point"]
		rock["normal"] = hit.get("normal", Vector3.UP)
		rock["collider"] = node
		return rock
	var ground := GroundDeposit.covering(body, hit["point"])
	if ground == null:
		return miss
	var patch := ground.harvest(tool_id, bag)
	patch["point"] = hit["point"]
	patch["normal"] = hit.get("normal", Vector3.UP)
	patch["collider"] = ground
	return patch
