# level.gd (attach to LevelRoot Node2D in each Level scene)
extends Node2D
class_name LevelBase

signal request_scene_change(target_scene_path: String, target_entry_name: String, door_name: String)

@onready var player = $Player


func _ready() -> void:
	# Auto-connect doors in group
	for door in get_tree().get_nodes_in_group("doors_in_level"):
		if door.has_signal("door_player_entered") and not door.is_connected("door_player_entered", Callable(self, "_on_door_triggered")):
			door.connect("door_player_entered", Callable(self, "_on_door_triggered"))

func _on_door_triggered(target_scene_path: String, target_entry_name: String, door_name: String) -> void:
	emit_signal("request_scene_change", target_scene_path, target_entry_name, door_name)

# Provide any per-level context (e.g., door-specific flags)
func provide_handoff_context(door_name: String, player_node: Node) -> Dictionary:
	var ctx: Dictionary = {}
	# populate as needed
	return ctx

# Receive player_node + handoff and place player appropriately
func receive_data(player_node: Node, handoff: LevelDataHandoff) -> void:
	# Defensive approach: find EntryMarkers node safely
	var entry_markers: Node = get_node_or_null("EntryMarkers")
	if entry_markers == null:
		push_warning("LevelBase.receive_data: EntryMarkers node not found in level '%s'. Will attempt global search for marker '%s'." % [name, handoff.entry_door_name])

	# Find marker node (preferred inside EntryMarkers)
	var marker_node: Node = null
	if entry_markers:
		marker_node = entry_markers.get_node_or_null(handoff.entry_door_name)
	if marker_node == null:
		# Try to find anywhere in subtree using our recursive helper
		marker_node = _find_node_by_name(self, handoff.entry_door_name)
	if marker_node == null:
		push_warning("LevelBase.receive_data: Entry marker '%s' not found in level '%s'. Will preserve player's previous global position." % [handoff.entry_door_name, name])
	# Defer actual reparent/placement to avoid modifying tree mid-traversal
	call_deferred("_deferred_place_player", player_node, marker_node, handoff)

func _deferred_place_player(player_node: Node, marker_node: Node, handoff: LevelDataHandoff) -> void:
	# preserve previous global position
	var prev_global := Vector2.ZERO
	if player_node is Node2D:
		prev_global = player_node.global_position

	# Reparent player safely
	var old_parent = player_node.get_parent()
	if old_parent:
		old_parent.remove_child(player_node)

	# Prefer adding to an Actors container if present
	var actors = get_node_or_null("Actors")
	if actors == null:
		actors = self
	actors.add_child(player_node)

	# Position player:
	# - if found a Node2D marker -> use its global_position
	# - else -> restore previous global position (do NOT place at level origin)
	if marker_node and marker_node is Node2D:
		player_node.global_position = marker_node.global_position + handoff.spawn_offset
	else:
		player_node.global_position = prev_global + handoff.spawn_offset

	# Facing (Vector2)
	if handoff.player_facing_direction != Vector2.ZERO and player_node.has_method("set_facing"):
		player_node.call("set_facing", handoff.player_facing_direction)

	# Camera handling: if player contains Camera2D, make it current safely
	var cam = player_node.get_node_or_null("Camera2D")
	if cam and cam is Camera2D:
		cam.make_current()   # safer than cam.current = true

	# Optional hook for level-specific setup
	if has_method("on_player_spawned"):
		call_deferred("on_player_spawned", player_node, handoff)

	# After player is placed, if GameState autoload indicates a transfer-caution, notify enemies in this newly-loaded level
	call_deferred("_handle_transfer_caution")

func _handle_transfer_caution() -> void:
	var gs = get_node_or_null("/root/GameState")
	if gs == null:
		print("[LevelBase] GameState not found; skipping transfer caution")
		return
	print("[LevelBase] _handle_transfer_caution: GameState.is_in_caution=", gs.is_in_caution, " last_marker=", gs.last_player_spawn_marker)
	if not gs.is_in_caution:
		# nothing to do; clear saved marker to avoid repeats
		gs.last_player_spawn_marker = ""
		return
	if gs.last_player_spawn_marker == "":
		return

	# Find spawn marker by name (search entire level)
	var marker_node: Node = null
	# prefer EntryMarkers container
	var entry_markers = get_node_or_null("EntryMarkers")
	if entry_markers:
		marker_node = entry_markers.get_node_or_null(gs.last_player_spawn_marker)
	if marker_node == null:
		marker_node = _find_node_by_name(self, gs.last_player_spawn_marker)
	if marker_node == null or not (marker_node is Node2D):
		push_warning("LevelBase: transfer spawn marker '%s' not found in level '%s'." % [gs.last_player_spawn_marker, name])
		# clear marker after attempt
		gs.last_player_spawn_marker = ""
		return

	# Notify enemies to enter caution and walk to marker position
	var target_pos: Vector2 = (marker_node as Node2D).global_position
	print("[LevelBase] instructing enemies to enter caution and go to marker:", gs.last_player_spawn_marker, "pos=", target_pos)
	var enemies = get_tree().get_nodes_in_group("enemies")
	for e in enemies:
		if not is_instance_valid(e):
			continue
		if e.has_method("enter_caution_from_transfer"):
			print("[LevelBase] calling enter_caution_from_transfer on", e.name)
			e.call_deferred("enter_caution_from_transfer", target_pos)
	# Clear marker after handing off
	gs.last_player_spawn_marker = ""

# Recursive search helper: depth-first search by node name
func _find_node_by_name(start_node: Node, target_name: String) -> Node:
	if start_node == null:
		return null
	for child in start_node.get_children():
		if child is Node:
			if child.name == target_name:
				return child
			var found := _find_node_by_name(child, target_name)
			if found:
				return found
	return null
