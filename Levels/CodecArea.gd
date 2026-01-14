extends Area2D

@export var dialogue: DialogueResource
@export var start_node := "start"

@onready var collision := $CollisionShape2D
@onready var codec := get_tree().get_first_node_in_group("codec_call")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body):
	if not body.is_in_group("player"):
		return

	if codec:
		codec.codec_ready.connect(_on_codec_ready, CONNECT_ONE_SHOT)
		codec.play_codec()

	collision.set_deferred("disabled", true)

func _on_codec_ready():
	DialogueManager.show_dialogue_balloon_scene("res://Dialogue/codec.tscn", dialogue, start_node)
