extends Node

const SAVE_PATH := "user://save.json"

func get_player():
	return get_tree().get_first_node_in_group("player")

func wait_for_player() -> Node2D:
	var player: Node2D = get_player()
	while player == null:
		await get_tree().process_frame
		player = get_player()
	return player


func save_game():
	var player: Node2D = get_player()
	if player == null:
		push_error("NO PLAYER FOUND")
		return

	var pos: Vector2 = player.global_position
	var facing: Vector2 = player.facing

	var data: Dictionary = {
		"scene": get_tree().current_scene.scene_file_path,
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


func has_save() -> bool:
	var exists = FileAccess.file_exists(SAVE_PATH)
	print("HAS SAVE ?", exists, " PATH =", SAVE_PATH)
	return FileAccess.file_exists(SAVE_PATH)


func load_game():
	if not FileAccess.file_exists(SAVE_PATH):
		print("No save found.")
		return

	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	var data: Dictionary = JSON.parse_string(file.get_as_text())
	file.close()

	get_tree().change_scene_to_file(data["scene"])

	var player: Node2D = await wait_for_player()
	var p: Dictionary = data["player"]

	player.global_position = Vector2(
		float(p["pos_x"]),
		float(p["pos_y"])
	)

	player.health = int(p["health"])
	player.mode = int(p["mode"])
	player.state = int(p["state"])

	player.facing = Vector2(
		float(p["facing_x"]),
		float(p["facing_y"])
	)
