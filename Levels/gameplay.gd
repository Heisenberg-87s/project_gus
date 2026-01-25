# Gameplay.gd (attach to Gameplay Node)
extends Node

@export var initial_level_scene_path: String = ""
@onready var player_node: Node = $Player
@onready var level_holder: Node2D = $LevelHolder

var current_level: Node = null
var current_level_path: String = ""
var pending_player_data: Dictionary = {}
var is_loading_from_save: bool = false

var active_level_camera: Camera2D = null


func _ready() -> void:
	if not is_in_group("gameplay"):
		add_to_group("gameplay")

	if SaveManager.is_continue:
		is_loading_from_save = true
		var data := SaveManager.pending_continue_data
		SaveManager.is_continue = false
		SaveManager.pending_continue_data = {}

		# 🔥 defer ให้ Gameplay พร้อมก่อน
		call_deferred("load_from_save", data)
		return

	# New game
	if initial_level_scene_path != "":
		_load_initial_level(initial_level_scene_path)
	else:
		push_error("Gameplay: initial_level_scene_path not set")
		

func _process(delta: float) -> void:
	_apply_player_save_if_ready()

# =========================
# INITIAL LOAD
# =========================
func _load_initial_level(path: String) -> void:
	var new_level = SceneManager.instantiate_scene(path)
	if new_level == null:
		push_error("Gameplay: Failed to instantiate initial level: %s" % path)
		return

	current_level_path = path # FIX: remember current level path

	level_holder.add_child(new_level)
	current_level = new_level

	if current_level.has_signal("request_scene_change"):
		current_level.connect("request_scene_change", Callable(self, "_on_level_request_change"))

	var handoff := LevelDataHandoff.new()
	handoff.entry_door_name = "spawn_default"

	if player_node != null and player_node.has_method("get_facing"):
		handoff.player_facing_direction = player_node.call("get_facing")

	current_level.call_deferred("receive_data", player_node, handoff)


# =========================
# LEVEL CHANGE (DOOR)
# =========================
func _on_level_request_change(target_scene_path: String, entry_name: String, door_name: String) -> void:
	if current_level == null:
		return

	var level_ctx: Dictionary = {}
	if current_level.has_method("provide_handoff_context"):
		level_ctx = current_level.call("provide_handoff_context", door_name, player_node)

	var handoff := LevelDataHandoff.new()
	handoff.entry_door_name = entry_name
	handoff.extra = level_ctx

	if player_node != null and player_node.has_method("get_facing"):
		handoff.player_facing_direction = player_node.call("get_facing")

	print("[Gameplay] deferring level switch ->", target_scene_path)
	call_deferred("_perform_level_switch", target_scene_path, handoff)


func _perform_level_switch(target_scene_path: String, handoff: LevelDataHandoff) -> void:
	var new_level = SceneManager.instantiate_scene(target_scene_path)
	if new_level == null:
		push_error("Gameplay: Failed to instantiate target level: %s" % target_scene_path)
		return

	current_level_path = target_scene_path # FIX: update level path

	# --- ensure player is not freed with old level ---
	if current_level != null and is_instance_valid(player_node):
		var ancestor := player_node.get_parent()
		var in_old_level := false
		while ancestor != null:
			if ancestor == current_level:
				in_old_level = true
				break
			ancestor = ancestor.get_parent()

		if in_old_level:
			var saved_pos := Vector2.ZERO
			if player_node is Node2D:
				saved_pos = player_node.global_position

			var old_parent = player_node.get_parent()
			if old_parent:
				old_parent.remove_child(player_node)

			level_holder.add_child(player_node)

			if player_node is Node2D:
				player_node.global_position = saved_pos

	# --- remove old level ---
	if current_level:
		if current_level.is_connected("request_scene_change", Callable(self, "_on_level_request_change")):
			current_level.disconnect("request_scene_change", Callable(self, "_on_level_request_change"))

		var p = current_level.get_parent()
		if p:
			p.remove_child(current_level)

		current_level.queue_free()
		current_level = null

	# --- add new level ---
	level_holder.add_child(new_level)
	current_level = new_level

	if current_level.has_signal("request_scene_change"):
		current_level.connect("request_scene_change", Callable(self, "_on_level_request_change"))

	current_level.call_deferred("receive_data", player_node, handoff)


# =========================
# SAVE / LOAD ENTRY POINT
# =========================
func load_from_save(data: Dictionary) -> void:
	if data == null or data.is_empty():
		return

	var scene_path: String = data.get("scene_path", data.get("scene", ""))
	if scene_path == "":
		push_error("Gameplay: save data missing scene_path")
		return

	# 🔥 1. โหลดด่านก่อน
	_perform_level_switch(scene_path, LevelDataHandoff.new())

	# 🔥 2. เก็บ player data ไว้เฉย ๆ
	pending_player_data = data.get("player", {})


# ==== spawn on spawnpoint =======
func _spawn_player_from_level_if_exists() -> bool:
	if current_level == null or not is_instance_valid(player_node):
		return false

	if current_level.has_method("try_get_spawnpoint"):
		var sp: Node2D = current_level.call("try_get_spawnpoint")
		if sp:
			player_node.global_position = sp.global_position
			return true

	return false

# ===== Change cam to Level cam =====
func _apply_level_camera_override() -> void:
	if current_level == null or not is_instance_valid(player_node):
		return

	var default_cam: Camera2D = player_node.get_node_or_null("Camera2D")

	if not current_level.has_method("try_get_level_camera"):
		return

	var level_cam: Camera2D = current_level.call("try_get_level_camera")
	if level_cam == null:
		# ไม่มี cam ในด่าน → ใช้ default
		if default_cam:
			default_cam.enabled = true
			default_cam.make_current()
		return

	# 🔥 reparent กล้องด่านมาใต้ player
	var old_parent := level_cam.get_parent()
	if old_parent:
		old_parent.remove_child(level_cam)

	player_node.add_child(level_cam)
	level_cam.position = Vector2.ZERO
	level_cam.enabled = true
	level_cam.make_current()

	# disable default camera
	if default_cam and default_cam != level_cam:
		default_cam.enabled = false


func _post_level_player_ready() -> void:
	if current_level == null or not is_instance_valid(player_node):
		return

	var default_cam: Camera2D = player_node.get_node_or_null("Camera2D")

	# =========================
	# CLEAN OLD LEVEL CAMERA
	# =========================
	if active_level_camera:
		if is_instance_valid(active_level_camera):
			active_level_camera.queue_free()
		active_level_camera = null

	if default_cam:
		default_cam.enabled = true
		default_cam.make_current()

	# =========================
	# SPAWNPOINT
	# =========================
	if current_level.has_method("find_spawnpoint"):
		var sp: Node2D = current_level.call("find_spawnpoint")
		if sp:
			player_node.global_position = sp.global_position

	# =========================
	# LEVEL CAMERA
	# =========================
	if current_level.has_method("find_level_camera"):
		var level_cam: Camera2D = current_level.call("find_level_camera")
		if level_cam:
			# reparent
			if level_cam.get_parent():
				level_cam.get_parent().remove_child(level_cam)

			player_node.add_child(level_cam)
			level_cam.position = Vector2.ZERO
			level_cam.enabled = true
			level_cam.make_current()

			active_level_camera = level_cam

			if default_cam:
				default_cam.enabled = false

func _apply_player_save_if_ready() -> void:
	if pending_player_data.is_empty():
		return

	if not is_instance_valid(player_node):
		player_node = get_tree().get_first_node_in_group("player")
	if player_node == null:
		return

	var p: Dictionary = pending_player_data

	# 🔥 พยายาม spawn จาก level ก่อน
	var spawned := _spawn_player_from_level_if_exists()

	# fallback ถ้าไม่มี spawnpoint
	if not spawned and p.has("pos_x") and p.has("pos_y"):
		player_node.global_position = Vector2(float(p.pos_x), float(p.pos_y))

	# restore stats
	if p.has("health") and "health" in player_node:
		player_node.health = p.health
	if p.has("mode") and "mode" in player_node:
		player_node.mode = p.mode
	if p.has("state") and "state" in player_node:
		player_node.state = p.state

	# restore facing
	if p.has("direction"):
		if player_node.has_method("set_facing"):
			player_node.call("set_facing", p.direction)
		elif "facing" in player_node:
			player_node.facing = p.direction

	# 🔥 apply เสร็จแล้ว clear
	pending_player_data.clear()


func get_current_level_path() -> String:
	return current_level_path
