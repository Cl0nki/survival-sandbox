extends Resource
class_name DamageProfile

## How one material answers bullets, direct hits, and blasts.
## Factors are the fraction of incoming damage that is taken: 1 takes all of
## it, 0.5 takes half, 0 takes none. Health and factors are configuration;
## the damage system applies the same formula to every piece.

@export var id := ""
@export var max_health := 100
## Fraction of bullet damage taken.
@export var bullet_factor := 1.0
## Fraction of a direct impact (melee, collision) taken.
@export var direct_factor := 1.0
## Fraction of explosion damage taken, after distance falloff.
@export var blast_factor := 1.0
## Solid materials stop a blast. Glass does not.
@export var obstructs_blast := true
@export var debris_count := 3


func validate() -> PackedStringArray:
	var problems := PackedStringArray()
	if id.is_empty():
		problems.append("damage profile without id")
	if max_health < 1:
		problems.append("%s health must be positive" % id)
	if bullet_factor < 0.0 or direct_factor < 0.0 or blast_factor < 0.0:
		problems.append("%s damage factors must be zero or positive" % id)
	if debris_count < 0:
		problems.append("%s debris count is negative" % id)
	return problems
