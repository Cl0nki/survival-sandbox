extends SceneTree

## Headless check for ground stacks: an item without a mesh gets a 3D
## placeholder, there is no 2D icon sprite, and the name only shows on focus.
## godot --headless --path <project> --script res://tests/pickup_visual.gd


func _init() -> void:
	physics_frame.connect(_boot, CONNECT_ONE_SHOT)


func _boot() -> void:
	var code := _run()
	if code == 0:
		print("PICKUP_VISUAL_OK")
	quit(code)


func _run() -> int:
	var arena := Node3D.new()
	root.add_child(arena)
	var seen := 0
	for item_id in ItemCatalog.all_ids():
		var definition := ItemCatalog.get_item(item_id)
		if definition == null or not definition.can_pickup:
			continue
		var pickup := WorldPickup.new()
		pickup.pickup_id = "check_%s" % item_id
		pickup.item_id = item_id
		pickup.quantity = 3
		arena.add_child(pickup)
		seen += 1
		if _has_sprite(pickup):
			print("FAIL %s still has a 2D sprite" % item_id)
			return 1
		var has_model := pickup.get_node_or_null("ToolArt") != null
		var placeholder := pickup.get_node_or_null(ItemPlaceholder.NODE_NAME)
		if has_model == (placeholder != null):
			print("FAIL %s must have exactly one of model or placeholder" % item_id)
			return 1
		if placeholder != null and placeholder.get_child_count() == 0:
			print("FAIL %s placeholder is empty" % item_id)
			return 1
		var label := pickup.get_node("NameLabel") as Label3D
		if label.visible:
			print("FAIL %s label visible without focus" % item_id)
			return 1
		pickup.set_focus(true, false)
		if not label.visible or not label.text.contains("x3"):
			print("FAIL %s label missing on focus" % item_id)
			return 1
		if label.text.contains("[F]"):
			print("FAIL %s shows the pick up hint out of reach" % item_id)
			return 1
		pickup.set_focus(true, true)
		if not label.text.contains("[F]"):
			print("FAIL %s missing pick up hint in reach" % item_id)
			return 1
		pickup.set_focus(false, false)
		if label.visible:
			print("FAIL %s label stays after focus left" % item_id)
			return 1
	if seen == 0:
		print("FAIL no pickup items")
		return 1
	print("checked %d pickups" % seen)
	return 0


func _has_sprite(node: Node) -> bool:
	if node is Sprite3D:
		return true
	for child in node.get_children():
		if _has_sprite(child):
			return true
	return false
