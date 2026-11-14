extends RefCounted
class_name TechTree

## Read-only craft / smelt encyclopedia: every recipe and how to reach each output.

static var _recipes: Array = []
static var _by_output: Dictionary = {}


static func all_recipes() -> Array:
	_warm()
	var copied: Array = []
	for recipe in _recipes:
		copied.append(recipe.duplicate(true))
	return copied


static func recipes_for_output(output_id: String) -> Array:
	_warm()
	var matched: Array = _by_output.get(output_id, [])
	var copied: Array = []
	for recipe in matched:
		copied.append(recipe.duplicate(true))
	return copied


static func is_craftable(item_id: String) -> bool:
	_warm()
	return _by_output.has(item_id)


static func family_label(family: String) -> String:
	match family:
		"saw":
			return "Saw"
		"kiln":
			return "Kiln"
		"bench":
			return "Workbench"
		"chem":
			return "Chem"
		"armory":
			return "Armory"
		"cook":
			return "Cooking"
		"smelt":
			return "Smelting"
		_:
			return family.capitalize()


## Lowest-tier station that can run this recipe.
static func station_for(recipe: Dictionary) -> Dictionary:
	if recipe.is_empty():
		return {}
	var family := str(recipe.get("family", ""))
	var output := str(recipe.get("output", ""))
	var input := str(recipe.get("input", ""))
	var extra := str(recipe.get("extra", ""))
	if family == "smelt":
		for kind in SmeltRules.ids():
			for entry in SmeltRules.recipes_for(kind):
				if str(entry["output"]) != output or str(entry["input"]) != input:
					continue
				return {
					"kind": kind,
					"name": SmeltRules.display_name(kind),
					"family": family,
					"tier": int(recipe.get("tier", 1)),
				}
		return {"kind": "", "name": "Furnace", "family": family, "tier": int(recipe.get("tier", 1))}
	for kind in CraftRules.ids():
		for entry in CraftRules.recipes_for(kind):
			if str(entry["output"]) != output:
				continue
			if str(entry["input"]) != input:
				continue
			if str(entry.get("extra", "")) != extra:
				continue
			return {
				"kind": kind,
				"name": CraftRules.display_name(kind),
				"family": family,
				"tier": int(recipe.get("tier", 1)),
			}
	return {
		"kind": "",
		"name": family_label(family),
		"family": family,
		"tier": int(recipe.get("tier", 1)),
	}


## Parent-first dependency rows for a recipe.
## Each row: {depth, id, qty, gather, recipe, station}.
static func path_for(recipe: Dictionary) -> Array:
	if recipe.is_empty():
		return []
	var visiting: Dictionary = {}
	var rows: Array = []
	_emit_recipe(recipe, 0, int(recipe.get("out_n", 1)), visiting, rows)
	return rows


static func _emit_recipe(recipe: Dictionary, depth: int, qty: int, visiting: Dictionary, rows: Array) -> void:
	var output := str(recipe.get("output", ""))
	if output == "":
		return
	var station := station_for(recipe)
	rows.append({
		"depth": depth,
		"id": output,
		"qty": qty,
		"gather": false,
		"recipe": recipe.duplicate(true),
		"station": station,
	})
	if visiting.get(output, false):
		return
	visiting[output] = true
	_emit_need(str(recipe.get("input", "")), int(recipe.get("in_n", 1)), depth + 1, visiting, rows)
	var extra := str(recipe.get("extra", ""))
	if extra != "" and int(recipe.get("extra_n", 0)) > 0:
		_emit_need(extra, int(recipe.get("extra_n", 1)), depth + 1, visiting, rows)
	visiting[output] = false


static func _emit_need(item_id: String, qty: int, depth: int, visiting: Dictionary, rows: Array) -> void:
	if item_id == "":
		return
	var options := recipes_for_output(item_id)
	if options.is_empty() or visiting.get(item_id, false):
		rows.append({
			"depth": depth,
			"id": item_id,
			"qty": qty,
			"gather": true,
			"recipe": {},
			"station": {},
		})
		return
	## Prefer the lowest-tier route when several recipes make the same item.
	var best: Dictionary = options[0]
	for option in options:
		if int(option.get("tier", 99)) < int(best.get("tier", 99)):
			best = option
	_emit_recipe(best, depth, qty, visiting, rows)


static func _warm() -> void:
	if not _recipes.is_empty():
		return
	for recipe in CraftRules.all_recipes():
		_recipes.append(recipe)
	for recipe in SmeltRules.all_recipes():
		_recipes.append(recipe)
	_by_output.clear()
	for recipe in _recipes:
		var output := str(recipe["output"])
		if not _by_output.has(output):
			_by_output[output] = []
		(_by_output[output] as Array).append(recipe)
