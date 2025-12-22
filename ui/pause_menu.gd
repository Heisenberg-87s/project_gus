extends Control

# Pause menu - เรียกใช้ SaveManager (AutoLoad) เพื่อ save/load scene path (Godot 4)
# เชื่อมสัญญาณปุ่มใน editor:
# Resume -> _on_resume_pressed
# Restart -> _on_restart_pressed
# Save -> _on_save_pressed
# Load -> _on_load_pressed

var _is_paused: bool = false

func _ready() -> void:
	visible = _is_paused

func _set_paused(value: bool) -> void:
	_is_paused = value
	get_tree().paused = value
	visible = value

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		_set_paused(not _is_paused)

func _on_resume_pressed() -> void:
	_set_paused(false)

func _on_restart_pressed() -> void:
	_set_paused(false)
	get_tree().reload_current_scene()

func _on_save_pressed() -> void:
	# SaveManager ต้องมีค่า last_scene_path ก่อนถึงจะบันทึกได้
	if SaveManager.save_current_scene_to_disk():
		print("Game saved: ", SaveManager.last_scene_path)
	else:
		print("Save failed: no known current scene path.")
		print("Make sure you set SaveManager.set_current_scene_path(path) or use SaveManager.change_scene_and_track(path) when changing scenes.")

func _on_load_pressed() -> void:
	var err := SaveManager.load_saved_scene()
	if err == OK:
		_set_paused(false)
		print("Loaded scene: ", SaveManager.last_scene_path)
	else:
		print("Load failed: no save or could not load (error code: ", err, ").")
