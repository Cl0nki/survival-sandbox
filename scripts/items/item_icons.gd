extends RefCounted
class_name ItemIcons

## Flat placeholder pictures generated from each item's swatch.
## There are no art files. The shape marks the category.

const SIZE := 48

static var _cache: Dictionary = {}


static func texture_for(definition: ItemDefinition) -> Texture2D:
	if definition == null or definition.id.is_empty():
		return null
	if _cache.has(definition.id):
		return _cache[definition.id] as Texture2D
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(definition.swatch)
	var edge := definition.swatch.darkened(0.5)
	var ink := definition.swatch.lightened(0.55)
	for i in SIZE:
		image.set_pixel(i, 0, edge)
		image.set_pixel(i, SIZE - 1, edge)
		image.set_pixel(0, i, edge)
		image.set_pixel(SIZE - 1, i, edge)
	match definition.category:
		"medical":
			_rect(image, 20, 8, 8, 32, ink)
			_rect(image, 8, 20, 32, 8, ink)
		"ammo":
			_rect(image, 10, 12, 28, 6, ink)
			_rect(image, 10, 21, 28, 6, ink)
			_rect(image, 10, 30, 28, 6, ink)
		"food":
			_disc(image, 24, 24, 12, ink)
		"weapon":
			_rect(image, 8, 18, 32, 6, ink)
			_rect(image, 16, 24, 8, 14, ink)
		"tool":
			_rect(image, 10, 10, 28, 8, ink)
			_rect(image, 21, 18, 6, 22, ink)
		_:
			_rect(image, 14, 14, 20, 20, ink)
	var texture := ImageTexture.create_from_image(image)
	_cache[definition.id] = texture
	return texture


static func _rect(image: Image, x: int, y: int, width: int, height: int, color: Color) -> void:
	for py in height:
		for px in width:
			var sx := x + px
			var sy := y + py
			if sx < 1 or sy < 1 or sx >= SIZE - 1 or sy >= SIZE - 1:
				continue
			image.set_pixel(sx, sy, color)


static func _disc(image: Image, cx: int, cy: int, radius: int, color: Color) -> void:
	for py in range(cy - radius, cy + radius + 1):
		for px in range(cx - radius, cx + radius + 1):
			if px < 1 or py < 1 or px >= SIZE - 1 or py >= SIZE - 1:
				continue
			if Vector2(px - cx, py - cy).length() <= float(radius):
				image.set_pixel(px, py, color)
