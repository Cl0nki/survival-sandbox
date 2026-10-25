extends RefCounted
class_name PhysicsLayers

## Bit values for Godot physics layers. Layer 1 in the inspector is bit 0 (value 1).

const WORLD := 1
const PLAYER := 2
const DAMAGEABLE := 4
const HITS_MASK := WORLD | DAMAGEABLE
