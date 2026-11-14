extends RefCounted
class_name CraftingField

## Three craft tiles. Mills is the saw and kiln row. Benches and Chem are the
## south-east pads. Stock chests are placed by LootLayout.


static func build(arena: Node3D) -> void:
	if arena.get_node_or_null("Crafting") != null:
		return
	var root := Node3D.new()
	root.name = "Crafting"
	arena.add_child(root)
	## City asphalt pads — labels only, no dirt/rock scatter.
	ShowcasePad.label(root, "MILLS", ShowcasePad.CRAFTING + Vector3(0.0, 2.6, -4.2), 52, Color(0.88, 0.74, 0.48))
	ShowcasePad.label(root, "BENCHES", ShowcasePad.BENCHES + Vector3(0.0, 2.6, -4.2), 52, Color(0.78, 0.82, 0.88))
	ShowcasePad.label(root, "CHEM", ShowcasePad.CHEM + Vector3(0.0, 2.6, -4.2), 52, Color(0.70, 0.86, 0.62))
