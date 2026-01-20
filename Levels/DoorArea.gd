# Door.gd (attach to each Area2D representing a door)
extends Area2D

@export var target_scene_path: String = ""        # e.g. "res://scenes/HouseInterior.tscn"
@export var target_entry_name: String = ""        # name of marker in target scene
@export var door_name: String = ""                # optional identifier local to this level

signal door_player_entered(target_scene_path: String, target_entry_name: String, door_name: String)

func _ready() -> void:
	# ensure in group so level.gd can auto-connect
	if not is_in_group("doors_in_level"):
		add_to_group("doors_in_level")
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	# defensive checks
	if body == null:
		return
	# check for player group to be safe
	if not body.is_in_group("player"):
		return

	print("[DoorArea] Player entered door:", door_name, " -> target_scene:", target_scene_path, " entry:", target_entry_name)

	# If there's a GameState autoload, tell it about the spawn + preserve current caution time.
	# Use call_deferred so we don't run scene-change logic inside a physics callback.
	var gs = get_node_or_null("/root/GameState")
	if gs != null:
		print("[DoorArea] GameState found; scheduling prepare_transfer_spawn deferred")
		# defer the call to avoid changing tree during physics queries
		call_deferred("_deferred_prepare_game_state", gs, target_entry_name)
	else:
		print("[DoorArea] GameState NOT found at /root/GameState — ensure autoload is registered")
	# Emit the signal deferred as well to avoid immediate scene-switch during physics callback
	call_deferred("_deferred_emit_door_signal", target_scene_path, target_entry_name, door_name)

func _deferred_prepare_game_state(gs: Node, entry_name: String) -> void:
	if gs == null or not is_instance_valid(gs):
		return
	if gs.has_method("prepare_transfer_spawn"):
		gs.prepare_transfer_spawn(entry_name, gs.caution_time_remaining)

func _deferred_emit_door_signal(target_scene_path: String, target_entry_name: String, dname: String) -> void:
	emit_signal("door_player_entered", target_scene_path, target_entry_name, dname)
