extends RefCounted
class_name DebugFlags

## Reads the F1 debug toggle from the InputBindings autoload at call time.
## Naming the autoload directly in a script fails to compile under
## `godot --script`, which is how every headless test runs. A lookup does not.


static func enabled() -> bool:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var bindings := tree.root.get_node_or_null("InputBindings")
	return bindings != null and bool(bindings.get("debug_enabled"))
