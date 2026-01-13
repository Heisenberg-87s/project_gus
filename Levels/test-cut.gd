extends Area2D

@onready var collision: CollisionShape2D = $CollisionShape2D
@onready var codec := get_node("/root/Gameplay/CanvasLayer_Codec")

func _ready() -> void:
	body_entered.connect(_on_body_entered)

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		codec.play_codec()
		collision.set_deferred("disabled", true)
