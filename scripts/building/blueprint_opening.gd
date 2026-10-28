extends Resource
class_name BlueprintOpening

## One boundary override inside a room blueprint, in the blueprint's local
## (unrotated) cells. On a perimeter side it replaces the default wall. On an
## interior side it adds a partition piece. kind is a BuildTypes.Kind edge kind
## or BuildTypes.EDGE_OPEN.

@export var cell := Vector2i.ZERO
@export var side: BuildTypes.Side = BuildTypes.Side.SOUTH
@export var kind := BuildTypes.Kind.DOORWAY as int
