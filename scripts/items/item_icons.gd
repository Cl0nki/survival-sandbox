extends RefCounted
class_name ItemIcons

## Inventory icons. An approved file at res://assets/icons/<id>.png replaces the
## swatch placeholder. The slot draws that file across its whole face, so the
## source stays at the generated size instead of being reduced to the old 48px mark.
## The world mesh is separate.

const SIZE := 48
const SOURCE_LIMIT := 1024

static var _cache: Dictionary = {}

## Height of each firearm's trigger in its icon, measured in pixels of a 512 px wide
## picture (the 1024 px icons are measured at half size). The trigger is the one part
## every gun has at the same real size, so the inventory scales each weapon icon by it
## and the guns keep their true size next to each other. A weapon missing here (melee,
## new art not measured yet) is just fitted to its slot. Re-measure when the art changes.
const TRIGGER_REFERENCE := 512.0
const TRIGGER_SIZE := {
	"pistol": 51.0,
	"courier_pistol": 42.0,
	"marshal_pistol": 41.0,
	"debugweapon": 44.0,
	"rattler_smg": 29.0,
	"hornet_pdw": 28.0,
	"mule_shotgun": 24.0,
	"breacher_shotgun": 27.0,
	"ridgeback_rifle": 18.0,
	"falconer_rifle": 17.0,
	"kodiak_rifle": 17.0,
	"hailstorm_lmg": 17.5,
	"titan_hmg": 15.0,
	"goliath_amr": 13.5,
}


## The trigger's height as a fraction of the icon's width, or 0.0 when not measured.
static func trigger_fraction(item_id: String) -> float:
	if not TRIGGER_SIZE.has(item_id):
		return 0.0
	return float(TRIGGER_SIZE[item_id]) / TRIGGER_REFERENCE


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
			if definition.weapon_kind == WeaponSpec.MELEE:
				# Blade running up to the right, crossguard, grip.
				_rect(image, 22, 8, 6, 26, ink)
				_rect(image, 14, 33, 22, 4, ink)
				_rect(image, 22, 37, 6, 6, ink)
			else:
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


static var _content_cache: Dictionary = {}
const CONTENT_PROBE := 128
## Alpha a probe pixel needs to count as drawn.
const CONTENT_ALPHA := 0.35


## The part of the icon that is drawn, in texture pixels. The art is square with clear
## margins, so a slot can size the picture to the drawing instead of to the whole square.
static func content_rect(definition: ItemDefinition) -> Rect2:
	var texture := texture_for(definition)
	if texture == null:
		return Rect2()
	if _content_cache.has(definition.id):
		return _content_cache[definition.id] as Rect2
	var whole := Rect2(Vector2.ZERO, texture.get_size())
	var used := whole
	var image := texture.get_image()
	if image != null:
		var found := _visible_bounds(image)
		if found.size.x > 0.0 and found.size.y > 0.0:
			used = found
	_content_cache[definition.id] = used
	return used


## Bounds of the pixels that read as solid, found on a shrunken copy. Soft edges, glow and
## stray faint pixels would otherwise count and make the drawing look smaller than it is.
static func _visible_bounds(image: Image) -> Rect2:
	var probe := image.duplicate() as Image
	probe.convert(Image.FORMAT_RGBA8)
	var width := probe.get_width()
	var height := probe.get_height()
	probe.resize(CONTENT_PROBE, CONTENT_PROBE, Image.INTERPOLATE_BILINEAR)
	var low := Vector2i(CONTENT_PROBE, CONTENT_PROBE)
	var high := Vector2i(-1, -1)
	for y in CONTENT_PROBE:
		for x in CONTENT_PROBE:
			if probe.get_pixel(x, y).a < CONTENT_ALPHA:
				continue
			low = Vector2i(mini(low.x, x), mini(low.y, y))
			high = Vector2i(maxi(high.x, x), maxi(high.y, y))
	if high.x < 0:
		return Rect2()
	var step := Vector2(float(width) / CONTENT_PROBE, float(height) / CONTENT_PROBE)
	return Rect2(Vector2(low) * step, Vector2(high - low + Vector2i.ONE) * step)


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
