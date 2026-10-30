extends Resource
class_name BuildingConfig

## Module dimensions and placement rules. Every building transform and mesh is
## derived from these numbers, so changing one keeps all pieces consistent.
## Vertical pieces span the full floor-to-floor height (wall height equals
## floor_height) so stacked walls and posts meet without gaps.

@export var cell_size := 1.0
@export var floor_height := 3.0
@export var wall_thickness := 0.15
@export var slab_thickness := 0.1
@export var door_height := 2.2
@export var window_sill_height := 1.0
@export var window_head_height := 2.1
## Rooms can sit on levels 0 .. max_levels - 1. A ceiling may use max_levels.
@export var max_levels := 4
## World position of grid vertex (0, 0) on level 0. Y is the ground height.
@export var grid_origin := Vector3.ZERO
## Inclusive cell bounds for placement.
@export var build_min_cell := Vector2i(-17, -17)
@export var build_max_cell := Vector2i(16, 16)
## Fraction of a cell the aim must travel past a boundary before the preview
## switches to the neighbouring anchor. Stops flicker at cell borders.
@export var snap_hysteresis := 0.15
## Physics obstruction queries shrink each piece by this much on every side,
## so resting contact with the ground does not count as a blocker.
@export var obstruction_margin := 0.05
## Costs are always computed and shown. They are only charged when this is on
## and the authority has a wallet.
@export var require_resources := false
@export var cost_item_id := "scrap_metal"
@export var component_costs := {
	"Slab": 2,
	"Wall": 2,
	"Doorway": 2,
	"Window": 2,
	"Post": 1,
	"Stairs": 6,
}
## Blast used by the local explosive key. Damage profiles scale the result.
@export var blast_radius := 4.0
@export var blast_damage := 120
## Visual debris only. The cap is the most chips alive at once.
@export var debris_lifetime_sec := 1.5
@export var debris_cap := 24
## Bullet holes on a separate node, never written into the building mesh.
@export var impact_lifetime_sec := 8.0
@export var impact_cap := 32
## How much one upper floor tile adds to the load. An 8x8 storey has two
## tiles per wall, so 0.5 adds 1 per storey. Four storeys sit at wall_bearing.
@export var slab_weight := 0.5
## How much load one wall or doorway can carry before it buckles.
## Placement never checks this. It matters only after a wall is destroyed.
@export var wall_bearing := 4.0
## Grace before a collapse starts. 0 starts the fall on the same frame.
## Rebuilding the missing support during the grace cancels it.
@export var collapse_delay_sec := 0.0
## Pause after each storey lets go, before the storey under it lets go.
## The roof drops first. 0 runs the whole chain in one frame.
@export var collapse_span_sec := 0.4
## Safety stop for a chain reaction. Each stage visits a piece at most once.
@export var collapse_max_waves := 32


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if cell_size <= 0.0 or floor_height <= 0.0:
		problems.append("cell_size and floor_height must be positive")
	if wall_thickness <= 0.0 or wall_thickness >= cell_size * 0.5:
		problems.append("wall_thickness must be between 0 and half a cell")
	if slab_thickness <= 0.0 or slab_thickness >= floor_height * 0.5:
		problems.append("slab_thickness must be between 0 and half a floor")
	if door_height <= slab_thickness or door_height >= floor_height:
		problems.append("door_height must be inside the floor height")
	if window_sill_height <= slab_thickness or window_head_height <= window_sill_height or window_head_height >= floor_height:
		problems.append("window sill and head must be ordered inside the floor height")
	if max_levels < 1:
		problems.append("max_levels must be at least 1")
	if build_min_cell.x > build_max_cell.x or build_min_cell.y > build_max_cell.y:
		problems.append("build bounds are inverted")
	if blast_radius <= 0.0 or blast_damage < 1:
		problems.append("blast radius and damage must be positive")
	if debris_lifetime_sec < 0.0 or debris_cap < 0 or impact_lifetime_sec < 0.0 or impact_cap < 0:
		problems.append("debris and impact limits must be zero or positive")
	if slab_weight <= 0.0 or wall_bearing <= 0.0:
		problems.append("slab weight and wall bearing must be positive")
	if collapse_delay_sec < 0.0 or collapse_span_sec < 0.0 or collapse_max_waves < 1:
		problems.append("collapse timing and wave cap must be usable")
	return problems


func cost_of(kind: int) -> int:
	return int(component_costs.get(BuildTypes.kind_name(kind), 0))
