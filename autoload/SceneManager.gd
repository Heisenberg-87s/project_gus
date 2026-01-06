extends Node

# Autoload (Singleton) to hold the "next spawn" info across scene changes.
# Add this file as an Autoload named "SceneManager" (Project Settings -> Autoload)

# Facing enum (ใช้ค่าเดียวกับ DoorArea)
enum Facing { NONE, UP, DOWN, LEFT, RIGHT }

var next_scene_path: String = ""    # optional: path that will be loaded (res://...) for debugging/history
var next_spawn_id: String = ""      # marker node NAME to find in the incoming scene
var next_player_facing: int = Facing.NONE # store enum value
var next_lock_input: bool = false   # optional: if true player will start with input locked

func set_next(scene_path: String, spawn_id: String, facing: int = Facing.NONE, lock_input: bool = false) -> void:
	next_scene_path = scene_path
	next_spawn_id = spawn_id
	next_player_facing = facing
	next_lock_input = lock_input

func clear() -> void:
	next_scene_path = ""
	next_spawn_id = ""
	next_player_facing = Facing.NONE
	next_lock_input = false

func has_pending() -> bool:
	return next_scene_path != "" or next_spawn_id != ""

func consume() -> Dictionary:
	var d = {
		"scene": next_scene_path,
		"spawn_id": next_spawn_id,
		"facing": next_player_facing,
		"lock_input": next_lock_input
	}
	clear()
	return d
