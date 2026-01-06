extends Area2D

@export var target_scene: PackedScene
@export var target_spawn_marker_path: NodePath = NodePath("")  # Drag a Marker2D from the same scene (optional)
@export var target_spawn_id: String = ""                       # Fallback: name of Marker2D in the target scene

# Local enum shown as dropdown in Inspector (ordering must match SceneManager.Facing)
enum Facing { NONE, UP, DOWN, LEFT, RIGHT }
@export var target_player_facing: Facing = Facing.NONE         # dropdown in Inspector
@export var lock_input_on_load: bool = false                   # optional: lock player input after spawn

func _ready() -> void:
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	if body == null:
		return

	# Identify player: prefer group "player"
	var is_player := false
	if body.has_method("get_groups") and "player" in body.get_groups():
		is_player = true
	elif body is player:
		is_player = true

	if not is_player:
		return

	# Validate target scene (must be dragged in)
	if target_scene == null:
		print("Warning (DoorArea): target_scene not assigned on %s" % get_path())
		return

	# Determine spawn identifier (preference order):
	# 1) If user dragged a Marker2D from the CURRENT scene into target_spawn_marker_path, prefer that node's name.
	# 2) Else if target_spawn_id string provided, use it.
	var spawn_name: String = ""
	if target_spawn_marker_path != NodePath(""):
		var local_node := get_node_or_null(target_spawn_marker_path)
		if local_node != null and local_node is Marker2D:
			spawn_name = local_node.name
		else:
			print("Warning (DoorArea): target_spawn_marker_path invalid or not a Marker2D on %s" % get_path())

	if spawn_name == "" and target_spawn_id != "":
		spawn_name = target_spawn_id

	# Determine resource path (if packed scene has it)
	var res_path: String = target_scene.resource_path if target_scene.resource_path != null else ""

# ใน _on_body_entered ก่อนเรียก SceneManager.set_next ให้เพิ่ม:
	print("DoorArea triggered:", get_path())
	print("  target_scene.resource_path:", target_scene.resource_path)
	print("  target_spawn_marker_path:", str(target_spawn_marker_path))
	print("  target_spawn_id (string):", target_spawn_id)
	print("  target_player_facing (enum):", int(target_player_facing))
	print("  lock_input_on_load:", lock_input_on_load)
# แล้วค่อย SceneManager.set_next(...)
	# Store next spawn info in SceneManager (pass facing enum as int)
	# Note: SceneManager must be autoloaded; its Facing enum ordering matches this enum.
	SceneManager.set_next(res_path, spawn_name, int(target_player_facing), lock_input_on_load)

	# Change scene using PackedScene API if available; else fallback to resource_path change
	if get_tree().has_method("change_scene_to_packed"):
		get_tree().change_scene_to_packed(target_scene)
		return

	# fallback: if resource path exists and file present, change by file
	if res_path != "" and FileAccess.file_exists(res_path):
		get_tree().change_scene_to_file(res_path)
		return

	# If we couldn't change scene, warn and clear pending (avoid stale next)
	print("Warning (DoorArea): cannot change to target_scene (no change_scene_to_packed and no valid resource_path).")
	SceneManager.clear()
