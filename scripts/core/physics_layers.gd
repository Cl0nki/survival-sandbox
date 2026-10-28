extends RefCounted
class_name PhysicsLayers

## Bit values for Godot physics layers. Layer 1 in the inspector is bit 0 (value 1).
## BUILDING holds player-built pieces. Movement, aim, and shots include it.
## The orbit camera pull-in leaves it out, so ceilings do not crush the
## top-down camera; upper floors are cut away visually instead.

const WORLD := 1
const PLAYER := 2
const DAMAGEABLE := 4
const BUILDING := 8
const HITS_MASK := WORLD | DAMAGEABLE | BUILDING
