extends Node

const SAVE_PATH := "user://save.json"

# ======================
# Helpers
# ======================
func get_player() -> Node2D:
	return get_tree().get_first_node_in_group("player")


func get_gameplay() -> Node:
	return get_tree().get_first_node_in_group("gameplay")


func wait_for_player() -> Node2D:
	var player: Node2D = get_player()
	while player == null:
		await get_tree().process_frame
		player = get_player()
	return player


# ======================
# Save
# ======================
func save_game() -> void:
	var gameplay = get_gameplay()
	if gameplay == null:
		push_error("SaveManager: NO GAMEPLAY FOUND")
		return

	if not gameplay.has_method("get_current_level_path"):
		push_error("SaveManager: Gameplay has no get_current_level_path()")
		return

	var level_path: String = gameplay.get_current_level_path()
	if level_path == "":
		push_error("SaveManager: EMPTY LEVEL PATH")
		return

	var player: Node2D = get_player()
	if player == null:
		push_error("SaveManager: NO PLAYER FOUND")
		return

	var pos: Vector2 = player.global_position
	var facing: Vector2 = player.facing

	var data: Dictionary = {
		"scene": level_path, # ✅ level จริง
		"player": {
			"pos_x": pos.x,
			"pos_y": pos.y,
			"health": player.health,
			"mode": player.mode,
			"state": player.state,
			"facing_x": facing.x,
			"facing_y": facing.y
		}
	}

	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	file.store_string(JSON.stringify(data))
	file.close()

	print("[SaveManager] Saved game at:", level_path)


# ======================
# Load
# ======================
func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_game() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save found.")
		return {}

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	return data
