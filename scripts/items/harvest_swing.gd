extends RefCounted
class_name HarvestSwing

## Shared melee harvest query. Local play and the server call the same math.

const RANGE := 3.0


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
	var hit := HitscanWeapon.resolve_shot(world.direct_space_state, origin, direction, RANGE, exclude)
	miss["point"] = hit["point"]
	miss["collider"] = hit["collider"]
	var node := hit["collider"] as ResourceNode
	if node != null:
		var rock := node.harvest(tool_id, bag)
		rock["point"] = hit["point"]
		rock["collider"] = node
		return rock
	var ground := GroundDeposit.covering(body, hit["point"])
	if ground == null:
		return miss
	var patch := ground.harvest(tool_id, bag)
	patch["point"] = hit["point"]
	patch["collider"] = ground
	return patch
