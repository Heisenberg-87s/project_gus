extends Area2D
class_name Bullet

@export var speed: float = 900.0
var velocity: Vector2 = Vector2.ZERO

func _ready() -> void:
	add_to_group("bullets")
	connect("body_entered", Callable(self, "_on_entered"))
	connect("area_entered", Callable(self, "_on_entered"))

func set_direction(dir: Vector2) -> void:
	velocity = dir.normalized() * speed
	rotation = velocity.angle()

func _physics_process(delta: float) -> void:
	if velocity == Vector2.ZERO:
		return
	position += velocity * delta
	if position.length() > 5000:
		queue_free()

func _on_entered(other: Node) -> void:
	if other == null:
		return
	# direct enemy body hit (legacy)
	if other.is_in_group("enemies"):
		if other.has_method("hurt"):
			other.hurt()   # <<<--- ใช้แอนิเมชัน hurt
		elif other.has_method("stun"):
			other.stun(30.0)
		elif other.has_method("knockout"):
			other.knockout()
		queue_free()
		return

	# hit an enemy hurtbox Area2D
	if other.is_in_group("enemy_hurtboxes"):
		# ask hurtbox to apply bullet hit
		if other.has_method("_apply_bullet_hit"):
			other._apply_bullet_hit(self)
		else:
			var p = other.get_parent()
			if p:
				if p.has_method("hurt"):
					p.hurt()
				elif p.has_method("stun"):
					p.stun(30.0)
		queue_free()
		return

	# hit walls
	if other.is_in_group("walls"):
		queue_free()
		return
