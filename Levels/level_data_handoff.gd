# LevelDataHandoff.gd
# Simple data container passed from Gameplay -> new Level
class_name LevelDataHandoff
extends Resource

@export var entry_door_name: String = ""
@export var player_facing_direction: Vector2 = Vector2.ZERO  # now Vector2
@export var spawn_offset: Vector2 = Vector2.ZERO
@export var extra: Dictionary = {}
