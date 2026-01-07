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
	# check for player group to be safe
	if body.is_in_group("player"):
		emit_signal("door_player_entered", target_scene_path, target_entry_name, door_name)
