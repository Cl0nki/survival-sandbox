extends RefCounted
class_name CraftingField

## South-west 10x10. Refining and parts chests are placed by LootLayout.


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Crafting") != null:
		return
	var root := Node3D.new()
	root.name = "Crafting"
	arena.add_child(root)
	ShowcasePad.add(root, ShowcasePad.CRAFTING, Color(0.40, 0.30, 0.22))
	ShowcasePad.label(root, "CRAFTING", ShowcasePad.CRAFTING + Vector3(0.0, 2.6, -3.6), 52, Color(0.88, 0.74, 0.48))
	ShowcasePad.label(root, "REFINING    PARTS", ShowcasePad.CRAFTING + Vector3(0.0, 1.25, -3.35), 22, Color(0.80, 0.68, 0.46))
