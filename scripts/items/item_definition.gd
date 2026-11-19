extends Resource
class_name ItemDefinition

## Data for one prototype item. Gameplay code looks these up by id.
## It does not accept a definition sent by a client.

@export var id := ""
@export var display_name := ""
@export var description := ""
@export var max_stack := 1
@export var weight := 0.0
@export var category := "misc"
@export var can_pickup := true
@export var can_store := true
## Cells the item covers in the storage grid and in chests, width by height.
## Hotbar, weapon and station slots hold any item in one slot.
@export var grid_w := 1
@export var grid_h := 1
@export var swatch := Color(0.7, 0.7, 0.7, 1)
## Empty means this item is not a harvest tool.
@export var harvest_kind := ""
@export var harvest_tier := 0
@export var harvest_power := 0
## Empty means this item is not a weapon. "firearm" fires a hitscan shot and
## "melee" swings at close range. Read through WeaponSpec, not directly.
## A stat left at zero falls back to the HitscanWeapon defaults.
@export var weapon_kind := ""
## Which equipment slot takes this weapon: "primary", "sidearm" or "melee".
## Empty picks by kind, melee for a blade and primary for a firearm.
@export var weapon_slot := ""
## Item id of the round one shot spends. Empty means no ammunition.
@export var ammo_id := ""
## Damage per pellet.
@export var weapon_damage := 0
@export var weapon_range := 0.0
@export var weapon_cooldown := 0.0
@export var weapon_pellets := 1
## Half-angle of the cone the pellets scatter in.
@export var weapon_spread_deg := 0.0
## Holding fire keeps shooting at the cooldown.
@export var weapon_automatic := false
## Overall length in meters, for the held placeholder and the mounted mesh.
## Zero keeps the pistol-sized default.
@export var weapon_length := 0.0
