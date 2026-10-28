extends Resource
class_name ItemDefinition

## Data for one prototype item. Gameplay code looks these up by id.
## It does not accept a definition sent by a client.

@export var id := ""
@export var display_name := ""
@export var description := ""
@export var max_stack := 1
@export var weight := 0.0
@export var category := "misc"
@export var can_pickup := true
@export var can_store := true
@export var swatch := Color(0.7, 0.7, 0.7, 1)
