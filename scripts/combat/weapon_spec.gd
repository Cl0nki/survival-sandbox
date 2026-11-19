extends RefCounted
class_name WeaponSpec

## What one weapon item does when fired. The numbers live in the item's .tres
## (ItemDefinition.weapon_*). The player and the server both read them here, so
## a new gun is a new resource and a recipe, not new firing code.

const FIREARM := "firearm"
const MELEE := "melee"

## Equipment slots, in the order they sit in the player's bag and the order Q cycles.
const SLOT_PRIMARY := "primary"
const SLOT_SIDEARM := "sidearm"
const SLOT_MELEE := "melee"
const SLOTS := [SLOT_PRIMARY, SLOT_SIDEARM, SLOT_MELEE]

## Match HitscanWeapon's defaults, which the debug weapon still uses.
const DEFAULT_DAMAGE := 34
const DEFAULT_RANGE := 40.0
const DEFAULT_COOLDOWN := 0.35
## Held placeholder box length before any scaling, from player.tscn.
const PLACEHOLDER_LENGTH := 0.26
## Swing arc for a melee weapon. Three rays, this far apart.
const MELEE_ARC_RAD := 0.38

var item_id := ""
var display_name := ""
var kind := FIREARM
var ammo_id := ""
var damage := DEFAULT_DAMAGE
var range_meters := DEFAULT_RANGE
var cooldown_seconds := DEFAULT_COOLDOWN
var pellets := 1
var spread_deg := 0.0
var automatic := false
var length := 0.0
var swatch := Color(0.7, 0.7, 0.7, 1)


## Null when the item is not a weapon.
static func for_item(item_id: String) -> WeaponSpec:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or definition.weapon_kind.is_empty():
		return null
	var spec := WeaponSpec.new()
	spec.item_id = definition.id
	spec.display_name = definition.display_name
	spec.kind = MELEE if definition.weapon_kind == MELEE else FIREARM
	spec.ammo_id = definition.ammo_id
	if definition.weapon_damage > 0:
		spec.damage = definition.weapon_damage
	if definition.weapon_range > 0.0:
		spec.range_meters = definition.weapon_range
	if definition.weapon_cooldown > 0.0:
		spec.cooldown_seconds = definition.weapon_cooldown
	spec.pellets = clampi(definition.weapon_pellets, 1, 16)
	spec.spread_deg = clampf(definition.weapon_spread_deg, 0.0, 30.0)
	spec.automatic = definition.weapon_automatic
	spec.length = definition.weapon_length
	spec.swatch = definition.swatch
	return spec


## "", "firearm" or "melee". Cheap, for per-snapshot checks.
static func kind_of(item_id: String) -> String:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null:
		return ""
	return definition.weapon_kind


static func is_weapon(item_id: String) -> bool:
	return not kind_of(item_id).is_empty()


## The equipment slot an item fits, or "" when it is not a weapon.
static func slot_of(item_id: String) -> String:
	var definition := ItemCatalog.get_item(item_id)
	if definition == null or definition.weapon_kind.is_empty():
		return ""
	if SLOTS.has(definition.weapon_slot):
		return definition.weapon_slot
	return SLOT_MELEE if definition.weapon_kind == MELEE else SLOT_PRIMARY


func is_melee() -> bool:
	return kind == MELEE


func uses_ammo() -> bool:
	return not ammo_id.is_empty()


func ammo_name() -> String:
	var definition := ItemCatalog.get_item(ammo_id)
	return ammo_id if definition == null else definition.display_name


func no_ammo_notice() -> String:
	return "No %s." % ammo_name()


## Length of the held placeholder box.
func model_length() -> float:
	return length if length > 0.0 else PLACEHOLDER_LENGTH


## Shots per second at full rate.
func rounds_per_second() -> float:
	return 1.0 / maxf(cooldown_seconds, 0.001)
