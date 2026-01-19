extends Node2D

@onready var anim := $AnimationPlayer

func _ready():
	anim.play("Intro")
	anim.animation_finished.connect(_on_anim_end)

func _on_anim_end(name: StringName) -> void:
	if name == "Intro":
		get_tree().change_scene_to_file("res://Levels/gameplay.tscn")
