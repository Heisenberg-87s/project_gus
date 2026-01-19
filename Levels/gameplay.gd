# Gameplay.gd (attach to Gameplay Node)
extends Node

@export var initial_level_scene_path: String = ""
@onready var player_node: Node = $Player    # keep name different from class_name

var current_level: Node = null
var current_level_path := ""

func _ready() -> void:
	if initial_level_scene_path != "":
		_load_initial_level(initial_level_scene_path)
	else:
		push_error("Gameplay: initial_level_scene_path not set")

func _load_initial_level(path: String) -> void:
	var new_level = SceneManager.instantiate_scene(path)
	if new_level == null:
		push_error("Gameplay: Failed to instantiate initial level: %s" % path)
		return
	add_child(new_level)
	current_level = new_level
	if current_level.has_signal("request_scene_change"):
		current_level.connect("request_scene_change", Callable(self, "_on_level_request_change"))
	# Default spawn: deferred so level nodes are ready
	var handoff := LevelDataHandoff.new()
	handoff.entry_door_name = "spawn_default"
	# set facing from player_node
	if player_node.has_method("get_facing"):
		handoff.player_facing_direction = player_node.call("get_facing")
	current_level.call_deferred("receive_data", player_node, handoff)

# Handler when a level requests a change (level emits request_scene_change)
func _on_level_request_change(target_scene_path: String, entry_name: String, door_name: String) -> void:
	if current_level == null:
		return
	var level_ctx: Dictionary = {}
	if current_level.has_method("provide_handoff_context"):
		level_ctx = current_level.call("provide_handoff_context", door_name, player_node)

	var handoff := LevelDataHandoff.new()
	handoff.entry_door_name = entry_name
	if player_node.has_method("get_facing"):
		handoff.player_facing_direction = player_node.call("get_facing")
	handoff.extra = level_ctx

	# Defer level switching to avoid modifying collision/physics state during physics callbacks (e.g., body_entered).
	# This prevents the "Can't change this state while flushing queries" error.
	print("[Gameplay] deferring level switch to:", target_scene_path, " entry:", entry_name)
	call_deferred("_perform_level_switch", target_scene_path, handoff)

func _perform_level_switch(target_scene_path: String, handoff: LevelDataHandoff) -> void:
	# Instantiate new level first (so its nodes are available for search)
	var new_level = SceneManager.instantiate_scene(target_scene_path)
	if new_level == null:
		push_error("Gameplay: Failed to instantiate target level: %s" % target_scene_path)
		return

	# Add new level to tree
	add_child(new_level)

	# Remove old level (disconnect signals and free)
	if current_level:
		if current_level.is_connected("request_scene_change", Callable(self, "_on_level_request_change")):
			current_level.disconnect("request_scene_change", Callable(self, "_on_level_request_change"))
		remove_child(current_level)
		current_level.queue_free()
		current_level = null

	# Set current_level and connect
	current_level = new_level
	if current_level.has_signal("request_scene_change"):
		current_level.connect("request_scene_change", Callable(self, "_on_level_request_change"))

	# Pass player + handoff to new level for placement (deferred so level fully ready)
	current_level.call_deferred("receive_data", player_node, handoff)

# ===== save and load ======
func load_level(path: String, from_save := false):
	current_level_path = path

	get_tree().change_scene_to_file(path)

	if from_save:
		await get_tree().process_frame
		_apply_save()

func _apply_save() -> void:
	var data = await SaveManager.load_game()
	if not data:
		return

	var player = get_tree().get_first_node_in_group("player")
	if not player:
		return

	var p = data["player"]

	player.global_position = Vector2(p.position.x, p.position.y)
	player.health = p.health
	player.mode = p.mode
	player.state = p.state
	player.facing_direction = p.direction

	
	
func load_from_save(data: Dictionary) -> void:
	if data.is_empty():
		return

	var scene_path = data["scene_path"]
	var player_data = data["player"]

	# โหลดด่าน
	_perform_level_switch(scene_path, LevelDataHandoff.new())

	await get_tree().process_frame

	# restore player
	player_node.global_position = player_data["position"]
	player_node.health = player_data["health"]
	player_node.mode = player_data["mode"]
	player_node.stance = player_data["stance"]
	player_node.set_facing(player_data["direction"])
	
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		var pause = $CanvasLayer/PauseMenu
		if pause.visible:
			pause.close()
		else:
			pause.open()
