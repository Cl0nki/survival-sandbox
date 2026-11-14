extends SceneTree

## Replaced by retarget_meshy_to_pro.gd. Kept so old rebuild commands do not
## paste local quaternions back onto the Pro skeleton.

func _init() -> void:
	print("SKIP merge_meshy_walk_strafe: use retarget_meshy_to_pro.gd")
	quit(0)
	return
