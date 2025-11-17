extends Area2D
# PunchArea: short-lived Area2D used for melee hit detection
# - Spawned by player when punching
# - Calls enemy.stun(stun_duration) or hurtbox._apply_punch_hit(self)
@export var duration: float = 0.12
@export var radius: float = 18.0
@export var stun_duration: float = 10.0

@onready var _colshape: CollisionShape2D = $CollisionShape2D
var _hit_ids := {}

func _ready() -> void:
	# ensure circle shape with radius
	var circ = CircleShape2D.new()
	circ.radius = radius
	_colshape.shape = circ
	add_to_group("player_melee")
	connect("area_entered", Callable(self, "_on_area_entered"))
	connect("body_entered", Callable(self, "_on_body_entered"))
	# auto free after duration
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self):
		queue_free()

func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if area.is_in_group("enemy_hurtboxes"):
		_apply_to_enemy_hurtbox(area)

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("enemy_hurtboxes"):
		_apply_to_enemy_hurtbox(body)

func _apply_to_enemy_hurtbox(hurtbox: Node) -> void:
	if hurtbox == null:
		return
	var enemy = hurtbox.get_parent()
	if enemy == null:
		return
	var id = enemy.get_instance_id()
	if id in _hit_ids:
		return
	_hit_ids[id] = true
	# prefer hurtbox helper if exists
	if hurtbox.has_method("_apply_punch_hit"):
		hurtbox._apply_punch_hit(self)
	else:
		if enemy.has_method("stun"):
			enemy.stun(stun_duration)
		elif enemy.has_method("take_damage"):
			enemy.take_damage(10)
