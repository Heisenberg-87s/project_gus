extends CharacterBody2D
class_name player

enum Mode { NORMAL, GUN }
enum State { IDLE, WALK, RUN, SNEAK, CRAWL, PUNCH }

# ===== MOVEMENT CONFIG =====
const MAX_SPEED: float = 150.0
const ACCELERATION: float = 1400.0
const FRICTION: float = 1500.0

@export var run_speed := 250.0
@export var crouch_speed := 100.0
@export var crawl_speed := 70.0

# ===== SPRITE Y OFFSET (SNEAK/CRAWL) =====
@export var sneak_offset_y := 5.0
@export var crawl_offset_y := 9.0
@export var offset_lerp_speed := 15.0
var _base_sprite_pos: Vector2 = Vector2.ZERO
var _current_offset_y: float = 0.0

# ===== NODES =====
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
@onready var muzzle_default: Marker2D = get_node_or_null("Muzzle") as Marker2D
var _active_muzzle: Marker2D = null

@onready var _punch_point_up: Node2D = get_node_or_null("PunchPoint_up") as Node2D
@onready var _punch_point_down: Node2D = get_node_or_null("PunchPoint_down") as Node2D
@onready var _punch_point_left: Node2D = get_node_or_null("PunchPoint_left") as Node2D
@onready var _punch_point_right: Node2D = get_node_or_null("PunchPoint_right") as Node2D

# ===== MODE/STATE/INPUT VARS =====
var mode: int = Mode.NORMAL
var state: int = State.IDLE
var direction: Vector2 = Vector2.ZERO
var cardinal_direction: Vector2 = Vector2.DOWN
var facing: Vector2 = Vector2.DOWN

# ===== PUNCH (melee) =====
@export var punch_duration: float = 0.20
@export var punch_cooldown: float = 0.4
@export var punch_move_multiplier: float = 0.4
@export var punch_reach: float = 28.0
@export var punch_radius: float = 18.0
@export var punch_side_offset_y: float = 6.0

var _punch_timer: float = 0.0
var _punch_cooldown_timer: float = 0.0
var _punch_auto_end_by_anim: bool = false

# ===== GUN/SFX =====
const BULLET = preload("res://bullet.tscn")
const PUNCH_AREA_SCENE = preload("res://player/punch_area.tscn")
@export var gun_cooldown_time: float = 0.25
var _gun_cooldown: float = 0.0

# temporary shoot animation
var _temp_anim_name: String = ""
var _temp_anim_timer: float = 0.0
@export var shoot_anim_time: float = 0.12
var _current_anim: String = ""

# ===== Crouch / Sit stand-delay (new) =====
# หมอบ/คลาน เข้าทันทีเมื่อกด แต่การลุก (ออกจาก SNEAK/CRAWL) จะหน่วงเวลา
@export var stand_from_crouch_delay_min: float = 0.2
@export var stand_from_crouch_delay_max: float = 0.4
var _crouch_pending_stand: bool = false
var _crouch_delay_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	_select_muzzle_for_cardinal(cardinal_direction)
	if animated_sprite:
		animated_sprite.connect("animation_finished", Callable(self, "_on_animation_finished"))
	_update_animation(true)

func _process(delta: float) -> void:
	# ---- Visual Y offset for sneak/crawl ----
	var desired_offset: float = (sneak_offset_y if state == State.SNEAK else crawl_offset_y if state == State.CRAWL else 0.0)
	var t: float = clamp(delta * offset_lerp_speed, 0.0, 1.0)
	_current_offset_y = lerp(_current_offset_y, desired_offset, t)
	animated_sprite.position = _base_sprite_pos + Vector2(0.0, _current_offset_y)

	# ---- Timers ----
	_gun_cooldown = max(_gun_cooldown - delta, 0.0) if _gun_cooldown > 0.0 else 0.0
	_punch_timer = max(_punch_timer - delta, 0.0) if _punch_timer > 0.0 else 0.0
	_punch_cooldown_timer = max(_punch_cooldown_timer - delta, 0.0) if _punch_cooldown_timer > 0.0 else 0.0
	if _temp_anim_timer > 0.0:
		_temp_anim_timer = max(_temp_anim_timer - delta, 0.0)
		if _temp_anim_timer <= 0.0:
			_temp_anim_name = ""
			_update_animation(true)

	# ---- Crouch/stand delay handling (new) ----
	# If currently in SNEAK or CRAWL and player released the key, start pending stand timer.
	# If player presses again while pending, cancel pending and remain crouched/crawling.
	if state == State.SNEAK:
		if Input.is_action_pressed("sneak"):
			if _crouch_pending_stand:
				_crouch_pending_stand = false
				_crouch_delay_timer = 0.0
		else:
			if not _crouch_pending_stand:
				_crouch_pending_stand = true
				_crouch_delay_timer = lerp(stand_from_crouch_delay_min, stand_from_crouch_delay_max, randf())
	elif state == State.CRAWL:
		if Input.is_action_pressed("crawl"):
			if _crouch_pending_stand:
				_crouch_pending_stand = false
				_crouch_delay_timer = 0.0
		else:
			if not _crouch_pending_stand:
				_crouch_pending_stand = true
				_crouch_delay_timer = lerp(stand_from_crouch_delay_min, stand_from_crouch_delay_max, randf())

	# decrement crouch pending timer
	if _crouch_pending_stand and _crouch_delay_timer > 0.0:
		_crouch_delay_timer = max(_crouch_delay_timer - delta, 0.0)
		if _crouch_delay_timer <= 0.0:
			_crouch_pending_stand = false
			# force re-evaluate state to allow standing
			if _set_state(true):
				_select_muzzle_for_cardinal(cardinal_direction)
				_update_animation(true)

	# ---- Update input ----
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	if direction != Vector2.ZERO:
		facing = direction.normalized()
		_set_direction_immediate()
	if Input.is_action_just_pressed("weapon_swap"):
		_toggle_mode()
	if Input.is_action_just_pressed("attack"):
		if mode == Mode.GUN:
			_try_shoot()
		elif _punch_cooldown_timer <= 0.0 and state != State.PUNCH:
			_start_punch()

	# ---- State updates ----
	# Note: _set_state() now respects _crouch_pending_stand (won't leave crouch/crawl while pending)
	if state != State.PUNCH:
		if _set_state():
			_select_muzzle_for_cardinal(cardinal_direction)
			_update_animation(true)

	# ---- End punch ----
	if state == State.PUNCH and not _punch_auto_end_by_anim and _punch_timer <= 0.0:
		_end_punch()
	_update_animation()
	# ---- Reload scene ----
	if Input.is_action_just_pressed("reload_scene"):
		get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	var target_speed: float = _get_speed_for_state()
	var input_dir: Vector2 = direction.normalized()
	var speed_mult: float = clamp(punch_move_multiplier, 0.0, 1.0) if state == State.PUNCH else 1.0
	var target_vel: Vector2 = input_dir * target_speed * speed_mult if direction != Vector2.ZERO else Vector2.ZERO
	velocity = velocity.move_toward(target_vel, ACCELERATION * delta)
	move_and_slide()

func _set_direction_immediate() -> void:
	if direction == Vector2.ZERO: return
	var new_dir: Vector2 = (
		Vector2.LEFT if direction.x < 0 and direction.y == 0 else
		Vector2.RIGHT if direction.x > 0 and direction.y == 0 else
		Vector2.UP if direction.y < 0 and direction.x == 0 else
		Vector2.DOWN if direction.y > 0 and direction.x == 0 else cardinal_direction
	)
	if new_dir != cardinal_direction:
		cardinal_direction = new_dir
		animated_sprite.scale.x = -1 if cardinal_direction == Vector2.LEFT else 1
		_select_muzzle_for_cardinal(cardinal_direction)

func _set_direction() -> bool:
	if direction == Vector2.ZERO: return false
	_set_direction_immediate()
	return true

func _get_muzzle_from_names(names: Array) -> Marker2D:
	for name in names:
		var n = get_node_or_null(name)
		if n != null and n is Marker2D:
			return n
	return null

func _select_muzzle_for_cardinal(card: Vector2) -> void:
	var dir_str: String = "up" if card == Vector2.UP else "down" if card == Vector2.DOWN else "side"
	var state_str: String = _state_to_string(state)
	var cands: Array = []
	if state == State.SNEAK or state == State.CRAWL:
		cands.append("Muzzle_%s_%s" % [state_str, dir_str])
		cands.append("Muzzle_%s" % state_str)
	cands.append("Muzzle_%s" % dir_str)
	cands.append("Muzzle")
	var m = _get_muzzle_from_names(cands)
	_active_muzzle = m if m != null else muzzle_default

func _set_state(force: bool=false) -> bool:
	# If we are pending a stand from crouch/crawl, prevent leaving crouch until timer done (unless forced).
	if _crouch_pending_stand and not force and (state == State.SNEAK or state == State.CRAWL):
		return false

	var new_state: int = (
		State.CRAWL if Input.is_action_pressed("crawl") else
		State.SNEAK if Input.is_action_pressed("sneak") else
		State.RUN if Input.is_action_pressed("run") and direction != Vector2.ZERO else
		State.IDLE if direction == Vector2.ZERO else State.WALK
	)
	if state == State.PUNCH and not force:
		return false
	if new_state == state:
		return false
	state = new_state
	return true

func _start_punch() -> void:
	if mode != Mode.NORMAL: return
	_punch_timer = punch_duration
	_punch_cooldown_timer = punch_cooldown
	state = State.PUNCH
	_temp_anim_name = ""
	_temp_anim_timer = 0.0
	var dir_str: String = "side" if abs(facing.x) > 0.5 else ("up" if facing.y < 0 else "down")
	var punch_candidates: Array = [
		"fist_punch_%s" % dir_str, "punch_%s" % dir_str,
		"fist_punch", "punch"
	]
	var played: bool = false
	if animated_sprite.sprite_frames != null:
		for pa in punch_candidates:
			if animated_sprite.sprite_frames.has_animation(pa):
				_current_anim = pa
				animated_sprite.animation = pa
				animated_sprite.frame = 0
				animated_sprite.play()
				played = true
				break
	if not played:
		_update_animation(true)
	_do_punch_hit()

func _end_punch() -> void:
	_set_state(true)
	_set_direction()
	_select_muzzle_for_cardinal(cardinal_direction)
	_update_animation(true)

func _do_punch_hit() -> void:
	var dir_vec: Vector2 = cardinal_direction if cardinal_direction != Vector2.ZERO else (facing.normalized() if facing != Vector2.ZERO else Vector2.DOWN)
	var reach: float = max(50.0, punch_reach)
	var radius: float = max(1.0, punch_radius)
	var hit_pos: Vector2 = (
		_punch_point_up.global_position if dir_vec == Vector2.UP and _punch_point_up else
		_punch_point_down.global_position if dir_vec == Vector2.DOWN and _punch_point_down else
		_punch_point_left.global_position if dir_vec.x < 0 and _punch_point_left else
		_punch_point_right.global_position if dir_vec.x > 0 and _punch_point_right else
		global_position + (dir_vec * (reach * 0.5 + radius * 0.2))
	)
	if abs(dir_vec.x) > 0.5 and not (dir_vec == Vector2.LEFT and _punch_point_left or dir_vec == Vector2.RIGHT and _punch_point_right):
		hit_pos.y -= punch_side_offset_y
	var pa = PUNCH_AREA_SCENE.instantiate()
	pa.global_position = hit_pos
	pa.radius = radius
	pa.duration = clamp(punch_duration * 0.9, 0.06, punch_duration + 0.05)
	pa.stun_duration = 10.0
	get_tree().current_scene.add_child(pa)

func _try_shoot() -> void:
	if mode != Mode.GUN or _gun_cooldown > 0.0:
		return
	_gun_cooldown = gun_cooldown_time
	var pos: Vector2 = (_active_muzzle.global_position if _active_muzzle != null and is_instance_valid(_active_muzzle)
		else (muzzle_default.global_position if muzzle_default != null and is_instance_valid(muzzle_default) else global_position))
	var dir: Vector2 = facing.normalized()
	var bullet = BULLET.instantiate()
	bullet.global_position = pos
	if bullet.has_method("set_direction"):
		bullet.set_direction(dir)
	else:
		bullet.rotation = dir.angle()
	get_tree().current_scene.add_child(bullet)
	var shoot_anim_candidates: Array = [
		"gun_shoot_" + _anim_dir_str(), "gun_shoot",
		"shoot_" + _anim_dir_str(), "shoot"
	]
	for a in shoot_anim_candidates:
		if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(a):
			_temp_anim_name = a
			_temp_anim_timer = shoot_anim_time
			if _current_anim != _temp_anim_name:
				_current_anim = _temp_anim_name
				animated_sprite.animation = _temp_anim_name
				animated_sprite.play()
			return

func _toggle_mode() -> void:
	mode = Mode.GUN if mode == Mode.NORMAL else Mode.NORMAL
	_select_muzzle_for_cardinal(cardinal_direction)
	_update_animation(true)

func _anim_dir_str() -> String:
	return "down" if cardinal_direction == Vector2.DOWN else "up" if cardinal_direction == Vector2.UP else "side"

func _choose_animation_candidates() -> Array:
	var dir_str: String = _anim_dir_str()
	var candidates: Array = []
	if state == State.PUNCH and mode == Mode.NORMAL:
		candidates += ["fist_punch_%s" % dir_str, "punch_%s" % dir_str, "fist_punch", "punch"]
	if mode == Mode.GUN:
		if (state == State.SNEAK or state == State.CRAWL) and direction == Vector2.ZERO:
			candidates += [
				"gun_%s_idle_%s" % [_state_to_string(state), dir_str],
				"gun_%s_idle" % _state_to_string(state),
				"gun_%s_%s" % [_state_to_string(state), dir_str],
				"gun_%s" % _state_to_string(state)
			]
		else:
			candidates += [
				"gun_%s_%s" % [_state_to_string(state), dir_str],
				"gun_%s" % _state_to_string(state),
				"gun_idle_%s" % dir_str,
				"gun_idle"
			]
		candidates += [
			"%s_%s" % [_state_to_string(state), dir_str],
			_state_to_string(state)
		]
	else:
		if (state == State.SNEAK or state == State.CRAWL) and direction == Vector2.ZERO:
			candidates += [
				"%s_idle_%s" % [_state_to_string(state), dir_str],
				"%s_%s" % [_state_to_string(state), dir_str],
				"%s_idle" % _state_to_string(state)
			]
		candidates += [
			"%s_%s" % [_state_to_string(state), dir_str],
			_state_to_string(state),
			"idle_%s" % dir_str,
			"idle"
		]
	candidates.append("gun_idle_%s" % dir_str if mode == Mode.GUN else "idle_%s" % dir_str)
	return candidates

func _update_animation(force: bool=false) -> void:
	if state != State.PUNCH and _temp_anim_name != "" and _temp_anim_timer > 0.0 and not force:
		if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(_temp_anim_name):
			if _current_anim != _temp_anim_name:
				_current_anim = _temp_anim_name
				animated_sprite.animation = _temp_anim_name
				animated_sprite.play()
		return
	var candidates: Array = _choose_animation_candidates()
	for name in candidates:
		if animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(name):
			if _current_anim != name or force:
				_current_anim = name
				animated_sprite.animation = name
				animated_sprite.play()
			return
	_current_anim = ""

func _on_animation_finished(anim_name: String) -> void:
	if state == State.PUNCH:
		var dir_str: String = _anim_dir_str()
		var punch_candidates: Array = ["fist_punch_%s" % dir_str, "punch_%s" % dir_str, "fist_punch", "punch"]
		if anim_name in punch_candidates:
			_end_punch()

func _state_to_string(s: int) -> String:
	match s:
		State.WALK: return "walk"
		State.RUN: return "run"
		State.SNEAK: return "sneak"
		State.CRAWL: return "crawl"
		State.IDLE: return "idle"
		_:
			return "idle"

func _get_speed_for_state() -> float:
	match state:
		State.WALK: return MAX_SPEED
		State.RUN: return run_speed
		State.SNEAK: return crouch_speed
		State.CRAWL: return crawl_speed
		State.IDLE: return 0.0
		_:
			return MAX_SPEED
