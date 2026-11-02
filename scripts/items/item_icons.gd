extends RefCounted
class_name ItemIcons

## Inventory icons. An approved file at res://assets/icons/<id>.png replaces the
## swatch placeholder. The slot draws that file across its whole face, so the
## source stays at the generated size instead of being reduced to the old 48px mark.
## The world mesh is separate.

const SIZE := 48
const SOURCE_LIMIT := 1024

static var _cache: Dictionary = {}


static func texture_for(definition: ItemDefinition) -> Texture2D:
	if definition == null or definition.id.is_empty():
		return null
	if _cache.has(definition.id):
		return _cache[definition.id] as Texture2D
	var art := _load_art(definition.id)
	if art != null:
		_cache[definition.id] = art
		return art
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
		"harvest":
			_rect(image, 16, 22, 16, 16, ink)
			_rect(image, 20, 14, 8, 10, ink)
		"refined":
			_rect(image, 12, 12, 24, 24, ink)
			_rect(image, 18, 18, 12, 12, edge)
		"component":
			_rect(image, 8, 8, 12, 12, ink)
			_rect(image, 28, 8, 12, 12, ink)
			_rect(image, 8, 28, 12, 12, ink)
			_rect(image, 28, 28, 12, 12, ink)
		"explosive":
			_disc(image, 24, 26, 10, ink)
			_rect(image, 21, 8, 6, 12, ink)
		_:
			_rect(image, 14, 14, 20, 20, ink)
	var texture := ImageTexture.create_from_image(image)
	_cache[definition.id] = texture
	return texture


static func _load_art(item_id: String) -> Texture2D:
	var path := "res://assets/icons/%s.png" % item_id
	if not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		return null
	var image := Image.new()
	if image.load(path) != OK:
		var loaded := load(path) as Texture2D
		if loaded == null:
			return null
		image = loaded.get_image()
		if image == null:
			return null
	var largest := maxi(image.get_width(), image.get_height())
	if largest > SOURCE_LIMIT:
		var scale := float(SOURCE_LIMIT) / float(largest)
		image.resize(maxi(int(round(image.get_width() * scale)), 1), maxi(int(round(image.get_height() * scale)), 1), Image.INTERPOLATE_LANCZOS)
	return ImageTexture.create_from_image(image)


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
