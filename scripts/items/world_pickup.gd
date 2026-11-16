extends Node3D
class_name WorldPickup

## World stack. Only the authority mutates quantity. Clients apply loot_state.
##
## The body is the item's own mesh (HeldToolArt, res://assets/props/<id>.glb).
## Without one it is an ItemPlaceholder. There is no 2D icon in the world.
## The name label stays hidden until the local player hovers the stack with
## the cursor or stands within reach (set_focus).

@export var pickup_id := ""
@export var item_id := ""
@export var quantity := 1

var _label: Label3D
var _focused := false
var _in_reach := false


func _ready() -> void:
	add_to_group(&"loot_pickup")
	_build_visual()
	refresh()


func take_into(bag: Inventory) -> int:
	if bag == null or quantity <= 0 or pickup_id.is_empty():
		return 0
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or not definition.can_pickup:
		return 0
	var amount := mini(quantity, bag.space_for(item_id))
	if amount <= 0:
		return 0
	if not bag.add_exact(item_id, amount):
		return 0
	quantity -= amount
	refresh()
	return amount


func apply_network_quantity(next_quantity: int) -> void:
	quantity = maxi(next_quantity, 0)
	refresh()


## Local presentation only. `focused` is hover or the nearest stack in reach.
## `in_reach` adds the pick up hint.
func set_focus(focused: bool, in_reach: bool = false) -> void:
	if focused == _focused and in_reach == _in_reach:
		return
	_focused = focused
	_in_reach = in_reach
	_apply_label()


func is_focused() -> bool:
	return _focused


func refresh() -> void:
	visible = quantity > 0
	_apply_label()


func _apply_label() -> void:
	if _label == null:
		return
	_label.visible = _focused and quantity > 0
	if not _label.visible:
		return
	var definition := ItemCatalog.get_item(item_id)
	var title := item_id if definition == null else definition.display_name
	var text := "%s x%d" % [title, quantity]
	if _in_reach:
		text += "\n[F] Pick up"
	_label.text = text


func _build_visual() -> void:
	# The label sits at the top of the stack, above the model or placeholder.
	_label = Label3D.new()
	_label.name = "NameLabel"
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0.0, 0.5, 0.0)
	_label.pixel_size = 0.005
	_label.font_size = 28
	_label.outline_size = 6
	_label.visible = false
	add_child(_label)
	if HeldToolArt.mount(self, item_id, HeldToolArt.Pose.GROUND):
		return
	add_child(ItemPlaceholder.build(ItemCatalog.get_item(item_id)))
