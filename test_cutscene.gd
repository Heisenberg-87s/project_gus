extends Node2D

func _ready() -> void:
	pass
	
func _unhandled_input(event: InputEvent) -> void:
	if Input.is_action_just_pressed("ui_accept"):
		DialogueManager.show_dialogue_balloon(load("res://Dialogue/Test.dialogue"), "start")
		return
