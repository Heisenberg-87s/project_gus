# Gameplay.gd (attach to Gameplay Node)
extends Node

@export var initial_level_scene_path: String = ""
@onready var player_node: Node = $Player
@onready var level_holder: Node2D = $LevelHolder

var current_level: Node = null
var current_level_path: String = ""
var is_loading_from_save: bool = false

func _ready() -> void:
	if not is_in_group("gameplay"):
		add_to_group("gameplay")

	# ❌ อย่าโหลด initial level ถ้ามาจาก save
	if is_loading_from_save:
		print("[Gameplay] skip initial level (loading from save)")
		return

	if initial_level_scene_path != "":
		_load_initial_level(initial_level_scene_path)
	else:
		push_error("Gameplay: initial_level_scene_path not set")



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
	var player_data: Dictionary = data.get("player", {})
	
	if scene_path == "":
		push_error("Gameplay: save data missing scene_path")
		return

	# load level into LevelHolder
	_perform_level_switch(scene_path, LevelDataHandoff.new())

	await get_tree().process_frame

	# re-acquire player safely
	if not is_instance_valid(player_node):
		player_node = get_tree().get_first_node_in_group("player")
	if player_node == null:
		push_error("Gameplay: player not found after load")
		return

	var p: Dictionary = data.get("player", {})
	if p == null:
		return

	# restore position
	if p.has("pos_x") and p.has("pos_y"):
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

func get_current_level_path() -> String:
	return current_level_path
