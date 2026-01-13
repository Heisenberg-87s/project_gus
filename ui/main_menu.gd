extends Control

@onready var anim: AnimationPlayer = $AnimationPlayer
var started := false

func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)

func _unhandled_input(event: InputEvent) -> void:
	if started:
		return

	if event.is_action_pressed("ui_accept"):
		started = true
		anim.play("MenuFade")

func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "MenuFade":
		get_tree().change_scene_to_file("res://Levels/gameplay.tscn")
