extends Control

@onready var gameplay := get_tree().get_first_node_in_group("gameplay")

func _ready() -> void:
	visible = false

func open():
	visible = true
	get_tree().paused = true
	grab_focus()

func close():
	visible = false
	get_tree().paused = false

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and visible:
		close()
	elif event.is_action_pressed("ui_cancel"):
		open()

func _on_resume_pressed():
	close()

func _on_save_pressed() -> void:
	SaveManager.save_game()

func _on_load_pressed() -> void:
	if SaveManager.has_save():
		close()
		var data = await SaveManager.load_game()
		gameplay.load_from_save(data)

func _on_restart_pressed():
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_title_screen_pressed():
	get_tree().paused = false
	get_tree().change_scene_to_file("res://ui/main_menu.tscn")
