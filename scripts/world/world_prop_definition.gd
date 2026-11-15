extends Resource
class_name WorldPropDefinition

## One non-placeable world object (tree, boulder, wreck, crate). It sits next to
## the deployables: one id, one gameplay box, one art slot, one Meshy entry.
## Health, tool and yield stay with the system that owns them (ResourceCatalog
## for harvest nodes). The pipeline reads this file for icons and target sizes.

## Kinds: "resource" is a harvest node, "crate" is a storage box.
@export var id := ""
@export var display_name := ""
@export var description := ""
## Always "world_prop". The art gallery groups on it, like the item categories.
@export var category := "world_prop"
@export var kind := "resource"
## ResourceCatalog id for harvest nodes. Empty for crates.
@export var deposit_id := ""
## Visual box in meters (width, height, depth). The mesh is fitted to it and
## the Meshy job uses it as target_size. Collision hulls stay in the builders.
@export var body_size := Vector3(1.0, 1.0, 1.0)
@export var swatch := Color(0.5, 0.5, 0.5)
