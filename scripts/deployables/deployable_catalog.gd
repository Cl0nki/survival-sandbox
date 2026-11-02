extends RefCounted
class_name DeployableCatalog

## Placeable kinds. A chest, the crafting stations, the fires, and the smelters
## stand on cells. A door or window bars of each building tier mounts on the matching opening.

const CELL_HEALTH := 100
const CHEST_HEIGHT := 0.72
const BENCH_HEIGHT := 0.84
const SMELTER_HEIGHT := 1.15
const PUMP_HEIGHT := 0.84

const _SLUGS: PackedStringArray = ["", "scrap", "wood", "brick", "stone", "concrete", "composite"]


static func door_id(tier: int) -> String:
	return "door_%s" % _SLUGS[BuildingTier.clamp_tier(tier)]


static func window_id(tier: int) -> String:
	return "window_%s" % _SLUGS[BuildingTier.clamp_tier(tier)]


static func known(kind: String) -> bool:
	return kind == "chest" or CraftRules.known(kind) or SmeltRules.known(kind) or FillRules.known(kind) or tier_of(kind) > 0


static func all_ids() -> PackedStringArray:
	var ids := PackedStringArray(["chest"])
	for kind in CraftRules.ids():
		ids.append(kind)
	for kind in SmeltRules.ids():
		ids.append(kind)
	for kind in FillRules.ids():
		ids.append(kind)
	for tier in range(BuildingTier.MIN, BuildingTier.MAX + 1):
		ids.append(door_id(tier))
	for tier in range(BuildingTier.MIN, BuildingTier.MAX + 1):
		ids.append(window_id(tier))
	return ids


static func tier_of(kind: String) -> int:
	for tier in range(BuildingTier.MIN, BuildingTier.MAX + 1):
		if kind == door_id(tier) or kind == window_id(tier):
			return tier
	return 0


static func is_window(kind: String) -> bool:
	return kind.begins_with("window_") and tier_of(kind) > 0


static func display_name(kind: String) -> String:
	if kind == "chest":
		return "Chest"
	if CraftRules.known(kind):
		return CraftRules.display_name(kind)
	if SmeltRules.known(kind):
		return SmeltRules.display_name(kind)
	if FillRules.known(kind):
		return FillRules.display_name(kind)
	var tier := tier_of(kind)
	if tier == 0:
		return kind
	var prefix := BuildingTier.display_name(tier)
	if kind.begins_with("door_"):
		return "%s Door" % prefix
	return "%s Window Bars" % prefix


static func max_health(kind: String) -> int:
	if kind == "chest":
		return CELL_HEALTH
	if CraftRules.known(kind):
		return CraftRules.max_health(kind)
	if SmeltRules.known(kind):
		return SmeltRules.max_health(kind)
	if FillRules.known(kind):
		return FillRules.max_health(kind)
	var tier := tier_of(kind)
	if tier == 0:
		return 0
	return BuildingTier.health_of(tier) / 2


## Cell footprint in local cells. Zero means this kind mounts on an opening.
static func footprint(kind: String) -> Vector2i:
	if kind == "chest":
		return Vector2i(2, 1)
	if CraftRules.known(kind):
		return CraftRules.footprint(kind)
	if SmeltRules.known(kind):
		return SmeltRules.footprint(kind)
	if FillRules.known(kind):
		return FillRules.footprint(kind)
	return Vector2i.ZERO


static func body_height(kind: String) -> float:
	if kind == "chest":
		return CHEST_HEIGHT
	if CraftRules.known(kind):
		return CraftRules.body_height(kind)
	if SmeltRules.known(kind):
		return SMELTER_HEIGHT
	if FillRules.known(kind):
		return PUMP_HEIGHT
	return BENCH_HEIGHT


## BuildTypes edge kind this deployable fits, or -1 when it stands on cells.
static func slot_kind(kind: String) -> int:
	if tier_of(kind) == 0:
		return -1
	if kind.begins_with("door_"):
		return BuildTypes.Kind.DOORWAY
	if kind.begins_with("window_"):
		return BuildTypes.Kind.WINDOW
	return -1


static func on_cells(kind: String) -> bool:
	return footprint(kind) != Vector2i.ZERO
