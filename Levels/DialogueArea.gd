extends Area2D

@export var dialogue: DialogueResource
@export var start_node := "start"

@onready var collision := $CollisionShape2D
@onready var dial := get_tree().get_first_node_in_group("dialogue_anim")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if not body.is_in_group("player"):
		return

	if dial:
		dial.dialogue_ready.connect(_on_dialogue_ready, CONNECT_ONE_SHOT)
		dial.play_dialogue()

	collision.set_deferred("disabled", true)

func _on_dialogue_ready():
	DialogueManager.show_dialogue_balloon_scene("res://Dialogue/dialogue.tscn", dialogue, start_node)
