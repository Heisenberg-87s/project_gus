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

# ===== Hurtbox node (ต้องเป็นลูกของ Player ตรงชื่อ "Hurtbox") =====
@onready var hurtbox_area: Area2D = get_node_or_null("Hurtbox") as Area2D
# ใน Hurtbox ควรมีลูกเป็น CollisionShape2D 3 ตัว ชื่อ:
# "CS_NORMAL", "CS_SNEAK", "CS_CRAWL"

# ===== Player's main body collision (optional) =====
# ถ้าต้นฉบับ node ชื่อ CollisionShape2D อยู่ในตัว player จะถูกใช้เป็น collision หลัก
@onready var body_collision: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

# ==== SOUND AREA ====
const SOUND_AREA_SCENE = preload("res://player/sound_area.tscn")
@export var sound_detect_radius: float = 300.0
@export var sound_detect_duration: float = 0.25
@export var sound_emit_sfx: AudioStream = preload("res://assets/audio/knock1.ogg")

# -- Sound emit cooldown (prevents spamming the sound area) --
@export var sound_emit_cooldown_time: float = 1.2
var _sound_emit_cooldown_timer: float = 0.0

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

# ===== HEALTH / DAMAGE =====
@export var max_health: int = 100
var health: int = 100
@export var invuln_time: float = 3.0
var _invuln_timer: float = 0.0

signal died

# ===== VISUAL DAMAGE FEEDBACK (ตัวอย่าง) =====
@export var flash_color: Color = Color(1.0, 0.502, 0.502, 0.0)
var _orig_modulate: Color = Color(1,1,1,1)

# ===== BLINK (invulnerability visual) =====
@export var blink_interval: float = 0.08
var _blink_accum: float = 0.0
var _blink_on: bool = false

# ===== Collision scale settings (ใหม่) =====
@export var crawl_collision_scale: float = 0.7   # scale applied while crawling
@export var sneak_collision_scale: float = 0.9   # scale applied while sneaking
# keep originals to avoid cumulative scaling
var _body_shape_original: Dictionary = {}
var _hurtbox_shapes_original: Dictionary = {}

func _ready() -> void:
	add_to_group("player")
	_select_muzzle_for_cardinal(cardinal_direction)
	if animated_sprite:
		animated_sprite.connect("animation_finished", Callable(self, "_on_animation_finished"))
	# init health
	health = max_health
	# store original modulate for flash
	if animated_sprite:
		_orig_modulate = animated_sprite.modulate
	# connect hurtbox signals (if hurtbox present)
	if hurtbox_area != null:
		# ใช้ Callable แบบ Godot 4 ใน is_connected
		if not hurtbox_area.is_connected("area_entered", Callable(self, "_on_hurtbox_area_entered")):
			hurtbox_area.connect("area_entered", Callable(self, "_on_hurtbox_area_entered"))
		if not hurtbox_area.is_connected("body_entered", Callable(self, "_on_hurtbox_body_entered")):
			hurtbox_area.connect("body_entered", Callable(self, "_on_hurtbox_body_entered"))
	# initial animation/hurtbox setup
	_capture_original_shapes()
	_update_animation(true)
	_update_hurtbox_shape(true)

func _capture_original_shapes() -> void:
	# capture main body collision shape original params if available
	if body_collision != null and body_collision.shape != null:
		_body_shape_original = _capture_shape_original(body_collision.shape)
	# capture hurtbox children's shapes originals
	if hurtbox_area != null:
		for name in ["CS_NORMAL", "CS_SNEAK", "CS_CRAWL"]:
			var cs = hurtbox_area.get_node_or_null(name) as CollisionShape2D
			if cs != null and cs.shape != null:
				_hurtbox_shapes_original[name] = _capture_shape_original(cs.shape)

func _capture_shape_original(s: Shape2D) -> Dictionary:
	# store a lightweight copy of important properties so we can scale from original later
	if s is RectangleShape2D:
		return {"type":"rect", "extents": (s as RectangleShape2D).extents}
	elif s is CircleShape2D:
		return {"type":"circle", "radius": (s as CircleShape2D).radius}
	elif s is CapsuleShape2D:
		return {"type":"capsule", "height": (s as CapsuleShape2D).height, "radius": (s as CapsuleShape2D).radius}
	else:
		# fallback: store a shallow reference - we will not scale unknown shapes
		return {"type":"unknown"}

func _apply_scaled_to_shape(s: Shape2D, original: Dictionary, scale: float) -> void:
	if original == null:
		return
	match original.get("type", ""):
		"rect":
			if s is RectangleShape2D:
				(s as RectangleShape2D).extents = original["extents"] * scale
		"circle":
			if s is CircleShape2D:
				(s as CircleShape2D).radius = original["radius"] * scale
		"capsule":
			if s is CapsuleShape2D:
				(s as CapsuleShape2D).height = original["height"] * scale
				(s as CapsuleShape2D).radius = original["radius"] * scale
		_:
			# unknown shape: do nothing
			pass

func _process(delta: float) -> void:
	# ---- Visual Y offset for sneak/crawl ----
	var desired_offset: float = (sneak_offset_y if state == State.SNEAK else crawl_offset_y if state == State.CRAWL else 0.0)
	var t: float = clamp(delta * offset_lerp_speed, 0.0, 1.0)
	_current_offset_y = lerp(_current_offset_y, desired_offset, t)
	animated_sprite.position = _base_sprite_pos + Vector2(0.0, _current_offset_y)
	# update hurtbox position to follow sprite offset
	_update_hurtbox_position()

	# ---- Timers ----
	_gun_cooldown = max(_gun_cooldown - delta, 0.0) if _gun_cooldown > 0.0 else 0.0
	_punch_timer = max(_punch_timer - delta, 0.0) if _punch_timer > 0.0 else 0.0
	_punch_cooldown_timer = max(_punch_cooldown_timer - delta, 0.0) if _punch_cooldown_timer > 0.0 else 0.0
	# decrement sound emit cooldown
	if _sound_emit_cooldown_timer > 0.0:
		_sound_emit_cooldown_timer = max(_sound_emit_cooldown_timer - delta, 0.0)
	if _temp_anim_timer > 0.0:
		_temp_anim_timer = max(_temp_anim_timer - delta, 0.0)
		if _temp_anim_timer <= 0.0:
			_temp_anim_name = ""
			_update_animation(true)

	# decrement invuln timer and handle blinking
	if _invuln_timer > 0.0:
		_invuln_timer = max(_invuln_timer - delta, 0.0)
		# blinking logic while invulnerable
		_blink_accum += delta
		if _blink_accum >= blink_interval:
			_blink_accum = 0.0
			_blink_on = not _blink_on
			if animated_sprite:
				animated_sprite.modulate = (flash_color if _blink_on else _orig_modulate)
		if _invuln_timer <= 0.0:
			# ensure restored
			if animated_sprite:
				animated_sprite.modulate = _orig_modulate
			_blink_accum = 0.0
			_blink_on = false

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
				_update_hurtbox_shape(true)

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
			
	if Input.is_action_just_pressed("sound_detect"):
		# check emit cooldown before creating a sound area
		if _sound_emit_cooldown_timer <= 0.0:
			var sa = SOUND_AREA_SCENE.instantiate()
			sa.global_position = global_position    # หรือใช้ muzzle position ถ้าต้องการ
			sa.radius = sound_detect_radius
			sa.duration = sound_detect_duration
			sa.source_player = self
			get_tree().current_scene.add_child(sa)
			_sound_emit_cooldown_timer = sound_emit_cooldown_time
		else:
			pass

	# ---- State updates ----
	# Note: _set_state() now respects _crouch_pending_stand (won't leave crouch/crawl while pending)
	if state != State.PUNCH:
		if _set_state():
			_select_muzzle_for_cardinal(cardinal_direction)
			_update_animation(true)
			_update_hurtbox_shape(true)

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
	# pa อาจมี export var damage (ตัวอย่าง)
	if pa.has_method("set") and pa.has_method("get"):
		# ถ้ามี property damage อยู่ ให้ตั้งเป็น 10
		var v = pa.get("damage") if pa.has_method("get") else null
		if v != null:
			pa.set("damage", 10)
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

# ========== HURT / DAMAGE HANDLING ==========

func _on_hurtbox_area_entered(area: Area2D) -> void:
	# ถ้าต่อสัญญาณจาก Hurtbox เข้ามา (ทางเลือก) ให้เรียก take_damage
	if not is_instance_valid(area):
		return
	var dmg = 0
	if area.has_method("get_damage_amount"):
		dmg = int(area.get_damage_amount())
	elif area.has_meta("damage"):
		dmg = int(area.get_meta("damage"))
	else:
		var v = area.get("damage")
		if v != null:
			dmg = int(v)
	if dmg > 0:
		var src = null
		if area.has_meta("source"):
			src = area.get_meta("source")
		else:
			var sv = area.get("source")
			if sv != null:
				src = sv
		take_damage(dmg, src)

func _on_hurtbox_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	var dmg = 0
	if body.has_method("get_damage_amount"):
		dmg = int(body.get_damage_amount())
	elif body.has_meta("damage"):
		dmg = int(body.get_meta("damage"))
	else:
		var v = body.get("damage")
		if v != null:
			dmg = int(v)
	if dmg > 0:
		var src = null
		if body.has_meta("source"):
			src = body.get_meta("source")
		else:
			var sv = body.get("source")
			if sv != null:
				src = sv
		take_damage(dmg, src)

func take_damage(amount: int, source: Node = null) -> void:
	# ถ้าอยู่ในช่วงอมตะ ให้ข้าม
	if _invuln_timer > 0.0:
		return

	# Apply damage
	health = max(health - amount, 0)

	# เริ่มตัวจับเวลาอมตะและ visual blink
	_invuln_timer = invuln_time
	if animated_sprite:
		_blink_accum = 0.0
		_blink_on = true
		animated_sprite.modulate = flash_color

	# (Optional) เล่นเสียงโดน ถ้าคุณมี node ชื่อ "HurtSound"
	if has_node("HurtSound"):
		var hs = get_node("HurtSound")
		if hs != null and hs.has_method("play"):
			hs.play()

	# ถ้า HP ถึง 0 -> ตาย
	if health <= 0:
		_die()

func _die() -> void:
	# หยุดการประมวลผลของ player (ป้องกัน input/physics ต่อ)
	set_process(false)
	set_physics_process(false)

	# หยุดการเคลื่อนที่ทันที
	if "velocity" in self:
		velocity = Vector2.ZERO

	# เล่นเสียงตาย ถ้ามี node ชื่อ "DeathSound" (AudioStreamPlayer / AudioStreamPlayer2D)
	if has_node("DeathSound"):
		var ds = get_node("DeathSound")
		if ds != null and ds.has_method("play"):
			ds.play()

	# เล่นอนิเมชันตายถ้ามี (เช็คชื่อยอดนิยม)
	if animated_sprite != null and animated_sprite.sprite_frames != null:
		var death_candidates: Array = ["death", "die", "dead"]
		for a in death_candidates:
			if animated_sprite.sprite_frames.has_animation(a):
				animated_sprite.animation = a
				animated_sprite.play()
				break
				
				

	# ปิดการชน/ตรวจจับเพิ่มเติม เพื่อไม่ให้ถูกกระทบซ้ำ
	if body_collision != null:
		body_collision.disabled = true
	if hurtbox_area != null:
		# ปิด monitoring ทันที และกำหนดแบบ deferred เผื่ออยู่ใน callback ของ physics
		hurtbox_area.monitoring = false
		hurtbox_area.set_deferred("monitoring", false)

	# ส่งสัญญาณว่าตาย — DeathUI ควรฟังสัญญาณนี้แล้วเริ่ม sequence fade / video / restart
	emit_signal("died")

# ========== HURTBOX SHAPE SWITCHING ==========

func _update_hurtbox_shape(force: bool=false) -> void:
	# เปิด shape ให้ตรงกับ state (CS_NORMAL, CS_SNEAK, CS_CRAWL)
	if hurtbox_area == null:
		return
	var cs_normal = hurtbox_area.get_node_or_null("CS_NORMAL") as CollisionShape2D
	var cs_sneak = hurtbox_area.get_node_or_null("CS_SNEAK") as CollisionShape2D
	var cs_crawl = hurtbox_area.get_node_or_null("CS_CRAWL") as CollisionShape2D
	# ปิด/เปิดตาม state
	if cs_normal:
		cs_normal.disabled = not (state == State.IDLE or state == State.WALK or state == State.RUN)
	if cs_sneak:
		cs_sneak.disabled = not (state == State.SNEAK)
	if cs_crawl:
		cs_crawl.disabled = not (state == State.CRAWL)

	# ถ้าต้องการ ลด/เพิ่มขนาด collision ของ body หรือ hurtbox ให้ใช้ค่า scale ที่ตั้งได้
	var scale: float = 1.0
	if state == State.CRAWL:
		scale = clamp(crawl_collision_scale, 0.01, 2.0)
	elif state == State.SNEAK:
		scale = clamp(sneak_collision_scale, 0.01, 2.0)
	else:
		scale = 1.0

	# Apply scale to main body collision (ถ้ามี)
	if body_collision != null and body_collision.shape != null and _body_shape_original != null:
		_apply_scaled_to_shape(body_collision.shape, _body_shape_original, scale)

	# Optionally apply scale to the active hurtbox shape(s) so damage area also shrinks
	# We only scale shapes that we captured originally to avoid unexpected mutation
	for name in _hurtbox_shapes_original.keys():
		var cs = hurtbox_area.get_node_or_null(name) as CollisionShape2D
		if cs != null and cs.shape != null:
			# scale only when the shape is enabled (active) so inactive shapes keep original sizes
			if not cs.disabled:
				_apply_scaled_to_shape(cs.shape, _hurtbox_shapes_original[name], scale)
			else:
				# restore original if disabled (prevents leftover scaled values)
				_apply_scaled_to_shape(cs.shape, _hurtbox_shapes_original[name], 1.0)

	# ถ้าต้องการ เปลี่ยนตำแหน่งหรือขนาดเพิ่มเติม ให้ปรับที่นี่
	_update_hurtbox_position()

func _update_hurtbox_position() -> void:
	# ให้ Hurtbox ย้ายตาม sprite offset (y) และคำนึงการ flip x ถ้าจำเป็น
	if hurtbox_area == null:
		return
	var pos = Vector2.ZERO
	pos.y = _current_offset_y
	hurtbox_area.position = pos
	# สำหรับ flip แนวนอน: ถ้าคุณมี shape ที่ offset ทาง x ให้ตรวจเช็ค scale.x
	# (ถ้าจำเป็น สามารถ loop ผ่าน children ของ hurtbox และ multiply x offset ด้วย sign of animated_sprite.scale.x)


func _on_nav_timer_timeout() -> void:
	pass # Replace with function body.
