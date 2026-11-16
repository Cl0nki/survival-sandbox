extends RefCounted

## Name shows on hover, while standing close, or in F1 debug mode.
## HP shows only in F1 debug mode.


static func text(title: String, health: int, show_hp: bool, in_reach: bool, extra: String = "") -> String:
	var lines := PackedStringArray()
	lines.append(title)
	if show_hp:
		lines.append("%d HP" % health)
	if extra != "":
		lines.append(extra)
	if in_reach:
		lines.append("[F]")
	return "\n".join(lines)
