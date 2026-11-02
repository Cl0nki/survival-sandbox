extends RefCounted
class_name FillRules

## One-slot stations. An empty container put in the slot comes back full.
## The well takes a bucket or a water bottle. The gas pump jack takes a gas
## bottle. The crude pump jack takes an oil drum.

const SLOT := 0
const SLOTS := 1

static var _specs: Dictionary = {}


static func known(kind: String) -> bool:
	return not _spec(kind).is_empty()


static func ids() -> PackedStringArray:
	_warm()
	var packed := PackedStringArray()
	for kind in _specs.keys():
		packed.append(str(kind))
	return packed


static func display_name(kind: String) -> String:
	var spec := _spec(kind)
	if spec.is_empty():
		return kind
	return str(spec["name"])


static func footprint(kind: String) -> Vector2i:
	var spec := _spec(kind)
	if spec.is_empty():
		return Vector2i.ZERO
	return spec["footprint"]


static func max_health(kind: String) -> int:
	return int(_spec(kind).get("hp", 0))


static func color_of(kind: String) -> Color:
	var spec := _spec(kind)
	if spec.is_empty():
		return Color(0.4, 0.42, 0.44)
	return spec["color"]


static func seconds(kind: String) -> float:
	return float(_spec(kind).get("seconds", 0.0))


static func hint(kind: String) -> String:
	var spec := _spec(kind)
	if spec.is_empty():
		return ""
	return str(spec["hint"])


static func filled_id(kind: String, item_id: String) -> String:
	var spec := _spec(kind)
	if spec.is_empty() or item_id.is_empty():
		return ""
	return str((spec["fills"] as Dictionary).get(item_id, ""))


static func accepts(kind: String, item_id: String) -> bool:
	return filled_id(kind, item_id) != ""


static func _spec(kind: String) -> Dictionary:
	_warm()
	return _specs.get(kind, {})


static func _warm() -> void:
	if not _specs.is_empty():
		return
	_put(
		"water_well", "Water Well", Vector2i(1, 1), 200, 4.0,
		Color(0.45, 0.52, 0.56),
		"1x1. Only on a ground water cell. An empty bucket or water bottle comes out full.",
		{"bucket_empty": "bucket_full", "water_bottle_empty": "water_bottle_full"}
	)
	_put(
		"pump_jack_gas", "Gas Pump Jack", Vector2i(3, 3), 300, 5.0,
		Color(0.62, 0.64, 0.32),
		"3x3. Only on the natural gas patch. An empty gas bottle comes out full.",
		{"gas_bottle_empty": "gas_bottle_full"}
	)
	_put(
		"pump_jack_oil", "Crude Pump Jack", Vector2i(2, 2), 400, 6.0,
		Color(0.24, 0.18, 0.14),
		"2x2. Only on the crude oil patch. An empty oil drum comes out full.",
		{"oil_drum_empty": "oil_drum_full"}
	)


static func _put(
	kind: String,
	station_name: String,
	size: Vector2i,
	hp: int,
	duration: float,
	color: Color,
	blurb: String,
	fills: Dictionary
) -> void:
	_specs[kind] = {
		"name": station_name,
		"footprint": size,
		"hp": hp,
		"seconds": duration,
		"color": color,
		"hint": blurb,
		"fills": fills,
	}
