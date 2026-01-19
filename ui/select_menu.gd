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

	var data = await SaveManager.load_game()

	var gameplay = get_tree().get_first_node_in_group("gameplay")
	gameplay.load_from_save(data)


func _on_exit_pressed() -> void:
	get_tree().quit()
