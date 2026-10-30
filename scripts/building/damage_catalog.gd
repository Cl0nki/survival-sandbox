extends RefCounted
class_name DamageCatalog

## One damage profile per component kind. The authority reads these; a request
## never supplies its own health or resistance.

const FILES: Dictionary = {
	BuildTypes.Kind.SLAB: "res://resources/building/damage/slab.tres",
	BuildTypes.Kind.WALL: "res://resources/building/damage/wall.tres",
	BuildTypes.Kind.DOORWAY: "res://resources/building/damage/doorway.tres",
	BuildTypes.Kind.WINDOW: "res://resources/building/damage/window.tres",
	BuildTypes.Kind.POST: "res://resources/building/damage/post.tres",
	BuildTypes.Kind.STAIRS: "res://resources/building/damage/stairs.tres",
}

static var _by_kind: Dictionary = {}
static var _ready := false


static func for_kind(kind: int) -> DamageProfile:
	_ensure()
	var profile := _by_kind.get(kind) as DamageProfile
	if profile != null:
		return profile
	push_error("no damage profile for %s" % BuildTypes.kind_name(kind))
	var fallback := DamageProfile.new()
	fallback.id = "fallback"
	fallback.max_health = 100
	return fallback


static func load_problems() -> PackedStringArray:
	var problems := PackedStringArray()
	var seen := {}
	for kind in FILES.keys():
		var path := str(FILES[kind])
		var loaded := load(path) as DamageProfile
		if loaded == null:
			problems.append("missing or wrong type: %s" % path)
			continue
		problems.append_array(loaded.validate())
		if seen.has(loaded.id):
			problems.append("duplicate damage profile id %s" % loaded.id)
		seen[loaded.id] = true
	if FILES.size() != BuildTypes.KIND_NAMES.size():
		problems.append("a component kind has no damage profile")
	return problems


static func _ensure() -> void:
	if _ready:
		return
	_ready = true
	for kind in FILES.keys():
		var loaded := load(str(FILES[kind])) as DamageProfile
		if loaded == null:
			push_error("damage catalog missing %s" % str(FILES[kind]))
			continue
		var problems := loaded.validate()
		if not problems.is_empty():
			push_error("damage profile %s invalid: %s" % [str(FILES[kind]), ", ".join(problems)])
			continue
		_by_kind[int(kind)] = loaded
