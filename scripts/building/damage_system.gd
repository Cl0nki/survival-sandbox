extends RefCounted
class_name DamageSystem

## Applies one damage event to one piece. The same event id is refused the
## second time, which is what keeps a retried shot or a repeated explosion
## from landing twice. Scaling is a pure function of the profile.


var _seen: Dictionary = {}


## Returns false when this event id was already claimed.
func claim(event_id: String) -> bool:
	if event_id.is_empty():
		return true
	if _seen.has(event_id):
		return false
	_seen[event_id] = true
	return true


static func scale(raw: int, factor: float) -> int:
	if raw <= 0 or factor <= 0.0:
		return 0
	return roundi(float(raw) * factor)
