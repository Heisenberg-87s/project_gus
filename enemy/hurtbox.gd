extends Area2D
# Hurtbox Area for Enemy
# - Child of Enemy node.
# - Calls parent.stun(duration) on bullet/punch hits.
@export var bullet_stun_duration: float = 30.0
@export var punch_stun_duration: float = 10.0

@onready var _enemy := get_parent()

func _ready() -> void:
	add_to_group("enemy_hurtboxes")
	connect("area_entered", Callable(self, "_on_area_entered"))
	connect("body_entered", Callable(self, "_on_body_entered"))

func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return
	# bullet Area2D: check by group or class_name
	if area.is_in_group("bullets"):
		_apply_bullet_hit(area)
		return
	if area.is_in_group("player_melee"):
		_apply_punch_hit(area)
		return

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("bullets"):
		_apply_bullet_hit(body)
		return
	if body.is_in_group("player_melee"):
		_apply_punch_hit(body)
		return

func _apply_bullet_hit(source: Node) -> void:
	if _enemy and is_instance_valid(_enemy):
		if _enemy.has_method("stun"):
			_enemy.stun(bullet_stun_duration)
		elif _enemy.has_method("take_damage"):
			_enemy.take_damage(30)
	# destroy bullet if it exposes queue_free
	if is_instance_valid(source) and source.has_method("queue_free"):
		source.queue_free()

func _apply_punch_hit(source: Node) -> void:
	if _enemy and is_instance_valid(_enemy):
		if _enemy.has_method("stun"):
			_enemy.stun(punch_stun_duration)
		elif _enemy.has_method("take_damage"):
			_enemy.take_damage(10)
