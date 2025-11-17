extends Area2D

@export var speed: float = 480.0
var direction: Vector2 = Vector2.ZERO

func _ready():
	body_entered.connect(_on_body_entered)

func _physics_process(delta):
	if direction != Vector2.ZERO:
		position += direction * speed * delta

func _on_body_entered(body):
	if body.is_in_group("player"):
		queue_free()
	elif body.is_in_group("wall"):
		queue_free()
