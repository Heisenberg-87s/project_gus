extends Area2D

# Bullet for enemies (Godot 4)
@export var speed: float = 400.0
@export var lifetime: float = 5.0
@export var damage: int = 20
@export var bullet_collision_mask: int = 12

# internal motion vars
var direction: Vector2 = Vector2.RIGHT
var linear_velocity: Vector2 = Vector2.ZERO
var _time_left: float = 0.0
var _shooter: Node = null

signal hit(target, position)

func _ready() -> void:
	_time_left = lifetime
	rotation = direction.angle()
	self.collision_mask = int(bullet_collision_mask)

func set_velocity(v: Vector2) -> void:
	linear_velocity = v
	if v.length() > 0:
		direction = v.normalized()
	rotation = direction.angle()

func set_linear_velocity(v: Vector2) -> void:
	set_velocity(v)

func set_direction(dir: Vector2) -> void:
	if dir.length() == 0:
		return
	direction = dir.normalized()
	linear_velocity = direction * speed
	rotation = direction.angle()

func launch(dir: Vector2, speed_override: float = 0.0, shooter: Node = null) -> void:
	if dir.length() == 0:
		return
	direction = dir.normalized()
	if speed_override > 0.0:
		speed = speed_override
	linear_velocity = direction * speed
	_shooter = shooter
	_time_left = lifetime
	rotation = direction.angle()

func _physics_process(delta: float) -> void:
	_time_left -= delta
	if _time_left <= 0.0:
		queue_free()
		return

	var from_pos : Vector2 = global_position
	var move_vec : Vector2 = (linear_velocity if linear_velocity.length() > 0 else direction * speed) * delta
	var to_pos : Vector2 = from_pos + move_vec

	var params := PhysicsRayQueryParameters2D.new()
	params.from = from_pos
	params.to = to_pos
	# exclude must be RID array in Godot 4
	params.exclude = [self.get_rid()]
	if _shooter != null and is_instance_valid(_shooter):
		# protect against adding non-RID objects
		params.exclude.append(_shooter.get_rid())
	params.collision_mask = int(bullet_collision_mask)

	var res = get_world_2d().direct_space_state.intersect_ray(params)
	if res:
		_handle_hit(res)
		return

	global_position = to_pos
	if move_vec.length() > 0:
		rotation = move_vec.angle()

func _handle_hit(res: Dictionary) -> void:
	var collider = res.get("collider", null)
	var pos = res.get("position", global_position)

	# Find the damage target: climb parents until find take_damage or apply_damage
	var damage_target = _find_damage_target(collider)

	# If the collider or the resolved damage_target is the player, ensure bullet is removed.
	var hit_player: bool = false
	if collider != null and collider is Node and (collider as Node).is_in_group("player"):
		hit_player = true
	if damage_target != null and damage_target.is_in_group("player"):
		hit_player = true

	# Apply damage if applicable
	if damage_target != null:
		# Preferred signature: take_damage(amount, source)
		if damage_target.has_method("take_damage"):
			damage_target.take_damage(damage, self)
		elif damage_target.has_method("apply_damage"):
			damage_target.apply_damage(damage, self)
		else:
			# fallback: try to reduce 'health' property if present
			if "health" in damage_target:
				var h = damage_target.get("health")
				if typeof(h) in [TYPE_INT, TYPE_FLOAT]:
					damage_target.set("health", max(h - damage, 0))

	# Emit hit signal for other systems (may be null target)
	emit_signal("hit", damage_target, pos)

	# Remove bullet when it hits anything relevant.
	# Per request: if it hits player, it should disappear — we always free the bullet here.
	queue_free()

func _find_damage_target(collider: Object) -> Node:
	# collider may be an Area2D/PhysicsBody2D or a CollisionObject; climb parents to find an owner with take_damage
	if collider == null:
		return null
	# If collider is a PhysicsBody2D/Area2D that is itself the player/hurtbox, try it and ancestors
	var node := collider
	# In case collider is not a Node (rare), return null
	if not (node is Node):
		return null
	var n := node as Node
	while n != null:
		if n.has_method("take_damage") or n.has_method("apply_damage") or "health" in n:
			return n
		# also support nodes in group "player"
		if n.is_in_group("player"):
			return n
		n = n.get_parent()
	return null
