extends Control

@onready var new_game := $VBoxContainer/newgame
@onready var continue_btn := $VBoxContainer/continue
@onready var exit_btn := $VBoxContainer/exit
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var buzz_sfx: AudioStreamPlayer2D = $buzzSFX

func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)
	new_game.grab_focus()
	# ถ้าไม่มี save → disable Continue
	if not SaveManager.has_save():
		continue_btn.disabled = true

func _on_newgame_pressed() -> void:
	anim.play("MenuFade")
	
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "MenuFade":
		get_tree().change_scene_to_file("res://Levels/intro-test.tscn")

func _on_continue_pressed() -> void:
	if not SaveManager.has_save():
		buzz_sfx.play()
		return

	var data: Dictionary = await SaveManager.load_game()
	if data.is_empty():
		buzz_sfx.play()
		return

	var tree := get_tree()
	tree.change_scene_to_file("res://Levels/gameplay.tscn")
	await tree.scene_changed
	await tree.process_frame

	var gameplay := tree.get_first_node_in_group("gameplay")
	if gameplay == null:
		push_error("Continue: Gameplay not found")
		return
		
	gameplay.is_loading_from_save = true
	gameplay.load_from_save(data)


func _on_exit_pressed() -> void:
	get_tree().quit()
