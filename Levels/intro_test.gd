extends Node2D

@onready var anim: AnimationPlayer = $AnimationPlayer
var skipped := false

func _ready():
	anim.play("intro")
	anim.animation_finished.connect(_on_anim_end)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not skipped:
		skip_intro()

func skip_intro():
	skipped = true

	if anim.is_playing():
		anim.stop()

	# ไปต่อเหมือน animation จบ
	_go_to_gameplay()

func _on_anim_end(name: StringName) -> void:
	if name == "intro" and not skipped:
		_go_to_gameplay()

func _go_to_gameplay():
	get_tree().change_scene_to_file("res://Levels/gameplay.tscn")
