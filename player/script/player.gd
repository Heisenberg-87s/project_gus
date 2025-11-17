extends CharacterBody2D
class_name player

# Two-level system:
# - Mode: NORMAL (melee) or GUN (hold gun & shoot)
# - State: movement states + PUNCH (used only in NORMAL mode)
enum Mode { NORMAL, GUN }
enum State { IDLE, WALK, RUN, SNEAK, CRAWL, PUNCH }

# ===== MOVEMENT CONFIG =====
const MAX_SPEED: float = 150.0
const ACCELERATION: float = 1400.0
const FRICTION: float = 1500.0

@export var run_speed: float = 250.0
@export var crouch_speed: float = 100.0
@export var crawl_speed: float = 70.0

# ===== VISUAL OFFSET FOR SNEAK/CRAWL =====
@export var sneak_offset_y: float = 5.0
@export var crawl_offset_y: float = 9.0
@export var offset_lerp_speed: float = 15.0   # higher = faster snap
var _base_sprite_pos: Vector2 = Vector2.ZERO
var _target_offset_y: float = 0.0
var _current_offset_y: float = 0.0

# ===== NODES =====
@onready var animated_sprite: AnimatedSprite2D = $AnimatedSprite2D
# Keep a default muzzle if you have one named "Muzzle"
@onready var muzzle_default: Marker2D = get_node_or_null("Muzzle") as Marker2D
var _active_muzzle: Marker2D = null

# ===== PUNCH POINT MARKERS (method 2) =====
# Place these Marker2D nodes as children of the Player scene for precise punch placement:
#  - PunchPoint_up
#  - PunchPoint_down
#  - PunchPoint_left
#  - PunchPoint_right
#
# If any are missing, code will fallback to a position in front of the player.
@onready var _punch_point_up: Node2D = get_node_or_null("PunchPoint_up") as Node2D
@onready var _punch_point_down: Node2D = get_node_or_null("PunchPoint_down") as Node2D
@onready var _punch_point_left: Node2D = get_node_or_null("PunchPoint_left") as Node2D
@onready var _punch_point_right: Node2D = get_node_or_null("PunchPoint_right") as Node2D

# ===== MODE / STATE / INPUT =====
var mode: int = Mode.NORMAL    # start in NORMAL (melee) mode
var state: int = State.IDLE
var direction: Vector2 = Vector2.ZERO
var cardinal_direction: Vector2 = Vector2.DOWN
var facing: Vector2 = Vector2.DOWN    # analog facing for bullets

# ===== PUNCH (melee) =====
@export var punch_duration: float = 0.20
@export var punch_cooldown: float = 0.4
@export var punch_move_multiplier: float = 0.4   # fraction of speed allowed while punching
@export var punch_reach: float = 28.0            # how far the punch reaches (world units)
@export var punch_radius: float = 18.0           # hit radius of the punch area
# optional small up-offset for side punches if you prefer (kept for fallback)
@export var punch_side_offset_y: float = 6.0

var _punch_timer: float = 0.0
var _punch_cooldown_timer: float = 0.0
# When true we rely on the AnimatedSprite finishing the punch animation to end the punch state.
var _punch_auto_end_by_anim: bool = false

# ===== GUN (shooting) =====
const BULLET = preload("res://bullet.tscn")
const PUNCH_AREA_SCENE = preload("res://player/punch_area.tscn")
@export var gun_cooldown_time: float = 0.25
var _gun_cooldown: float = 0.0

# temporary shoot animation (so shooting doesn't lock state)
var _temp_anim_name: String = ""
var _temp_anim_timer: float = 0.0
@export var shoot_anim_time: float = 0.12

# currently-playing animation name (avoid restarting same anim every frame)
var _current_anim: String = ""

# ===== PROCESS =====
func _ready() -> void:
	add_to_group("player")
	# pick an initial active muzzle (prefer direction/state-specific ones if present)
	_select_muzzle_for_cardinal(cardinal_direction)
	# connect AnimatedSprite2D finished signal to handle end of punch animation
	if animated_sprite:
		animated_sprite.connect("animation_finished", Callable(self, "_on_animation_finished"))
	_update_animation(true)
	

func _process(delta: float) -> void:
	# --- VISUAL OFFSET HANDLING (sneak / crawl) ---
	var desired_offset: float = 0.0
	if state == State.SNEAK:
		desired_offset = sneak_offset_y
	elif state == State.CRAWL:
		desired_offset = crawl_offset_y
	else:
		desired_offset = 0.0
	_target_offset_y = desired_offset
	# smooth towards target
	var t = clamp(delta * offset_lerp_speed, 0.0, 1.0)
	_current_offset_y = lerp(_current_offset_y, _target_offset_y, t)
	animated_sprite.position = _base_sprite_pos + Vector2(0.0, _current_offset_y)
	# --- end offset handling ---

	# update animation once per frame (avoid restarting same anim)
	_update_animation()
	
	# timers
	if _gun_cooldown > 0.0:
		_gun_cooldown = max(_gun_cooldown - delta, 0.0)
	if _punch_timer > 0.0:
		_punch_timer = max(_punch_timer - delta, 0.0)
	if _punch_cooldown_timer > 0.0:
		_punch_cooldown_timer = max(_punch_cooldown_timer - delta, 0.0)

	# temp anim timer
	if _temp_anim_timer > 0.0:
		_temp_anim_timer = max(_temp_anim_timer - delta, 0.0)
		if _temp_anim_timer <= 0.0:
			_temp_anim_name = ""
			_update_animation(true)

	# read movement input
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	# update facing and immediate cardinal when there's input (so crouch/crawl shows immediately)
	if direction != Vector2.ZERO:
		facing = direction.normalized()
		_set_direction_immediate()

	# toggle mode with "weapon_swap" (map key "1")
	if Input.is_action_just_pressed("weapon_swap"):
		_toggle_mode()

	# single attack button "attack" controls both punch and shoot depending on mode
	if Input.is_action_just_pressed("attack"):
		if mode == Mode.GUN:
			_try_shoot()
		else:
			# NORMAL mode -> punch (if not cooling down)
			if _punch_cooldown_timer <= 0.0 and state != State.PUNCH:
				_start_punch()

	# update movement state and direction unless punching (punch locks its state)
	if state != State.PUNCH:
		var changed_state: bool = _set_state()
		if changed_state:
			# state change (including entering/exiting sneak/crawl) may need muzzle update
			_select_muzzle_for_cardinal(cardinal_direction)
			_update_animation(true)

	# finish punch when timer expired ONLY if we're not using animation to end punch
	if state == State.PUNCH and not _punch_auto_end_by_anim and _punch_timer <= 0.0:
		_end_punch()

	# update animation once per frame (avoid restarting same anim)
	_update_animation()

func _physics_process(delta: float) -> void:
	var target_speed = _get_speed_for_state()
	var input_dir = direction.normalized()

	# movement multiplier during punch (0.0 = freeze, 1.0 = full speed)
	var speed_mult: float = 1.0
	if state == State.PUNCH:
		speed_mult = clamp(punch_move_multiplier, 0.0, 1.0)

	# compute desired target velocity and smoothly move towards it
	var target_vel = Vector2.ZERO
	if direction != Vector2.ZERO:
		target_vel = input_dir * target_speed * speed_mult

	velocity = velocity.move_toward(target_vel, ACCELERATION * delta)

	move_and_slide()

# ===== DIRECTION / MUZZLE helpers =====
func _set_direction_immediate() -> void:
	# update cardinal_direction immediately based on current facing direction if axis-aligned
	if direction == Vector2.ZERO:
		return
	var new_dir: Vector2 = cardinal_direction
	if direction.y == 0:
		new_dir = Vector2.LEFT if direction.x < 0 else Vector2.RIGHT
	elif direction.x == 0:
		new_dir = Vector2.UP if direction.y < 0 else Vector2.DOWN
	if new_dir != cardinal_direction:
		cardinal_direction = new_dir
		animated_sprite.scale.x = -1 if cardinal_direction == Vector2.LEFT else 1
		_select_muzzle_for_cardinal(cardinal_direction)

func _set_direction() -> bool:
	if direction == Vector2.ZERO:
		return false
	_set_direction_immediate()
	return true

# Helper: try to find the first existing muzzle node from a list of names.
# Names are looked up as direct children of this node (e.g. "Muzzle_crawl_up"), adjust if your structure differs.
func _get_muzzle_from_names(names: Array) -> Marker2D:
	for name in names:
		var n = get_node_or_null(name)
		if n != null and n is Marker2D:
			return n as Marker2D
	return null

# Select muzzle based on cardinal direction AND current state (sneak/crawl)
# Order of lookup (first match is used):
# 1) Muzzle_<state>_<dir> (e.g. Muzzle_crawl_down)
# 2) Muzzle_<state> (e.g. Muzzle_crawl)
# 3) Muzzle_<dir> (e.g. Muzzle_down or Muzzle_side)
# 4) Muzzle (default)
func _select_muzzle_for_cardinal(card: Vector2) -> void:
	var dir_str: String = "side"
	if card == Vector2.UP:
		dir_str = "up"
	elif card == Vector2.DOWN:
		dir_str = "down"

	var state_str: String = _state_to_string(state)  # "crawl", "sneak", etc.

	var candidates: Array = []
	# If in sneak/crawl, prefer state-specific muzzles so bullets spawn at correct low height
	if state == State.SNEAK or state == State.CRAWL:
		candidates.append("Muzzle_" + state_str + "_" + dir_str)  # e.g. Muzzle_crawl_down
		candidates.append("Muzzle_" + state_str)                  # e.g. Muzzle_crawl

	# Then try direction-specific
	candidates.append("Muzzle_" + dir_str)                        # e.g. Muzzle_down / Muzzle_side
	# Finally default
	candidates.append("Muzzle")

	# find first node that exists
	var m = _get_muzzle_from_names(candidates)
	if m != null:
		_active_muzzle = m
	else:
		_active_muzzle = muzzle_default  # may be null if none exists

# ===== STATE helpers =====
# 'force' flag so callers (like _end_punch) can force leaving PUNCH state.
func _set_state(force: bool=false) -> bool:
	var new_state: int = State.IDLE

	# Priority: if crawl/sneak keys pressed, honor them (even when not moving)
	if Input.is_action_pressed("crawl"):
		new_state = State.CRAWL
	elif Input.is_action_pressed("sneak"):
		new_state = State.SNEAK
	elif Input.is_action_pressed("run") and direction != Vector2.ZERO:
		new_state = State.RUN
	elif direction == Vector2.ZERO:
		new_state = State.IDLE
	else:
		new_state = State.WALK

	# don't override active punch state unless forced
	if state == State.PUNCH and not force:
		return false

	if new_state == state:
		return false

	state = new_state
	return true

# ===== PUNCH (NORMAL mode only) =====
func _start_punch() -> void:
	if mode != Mode.NORMAL:
		return
	_punch_timer = punch_duration
	_punch_cooldown_timer = punch_cooldown
	state = State.PUNCH

	# clear any temporary shoot anim so punch wins
	_temp_anim_name = ""
	_temp_anim_timer = 0.0

	# pick and play a punch animation immediately (don't rely on fallback ordering)
	var dir_str: String
	if abs(facing.x) > 0.5:
		dir_str = "side"
	else:
		dir_str = "up" if facing.y < 0 else "down"

	var punch_candidates: Array = [
		"fist_punch_" + dir_str,
		"punch_" + dir_str,
		"fist_punch",
		"punch"
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

	# fallback to the generic update if none matched
	if not played:
		_update_animation(true)

	# perform hit by spawning a short-lived PunchArea (Area2D)
	_do_punch_hit()

func _end_punch() -> void:
	_set_state(true)
	_set_direction()
	_select_muzzle_for_cardinal(cardinal_direction)
	_update_animation(true)

# Spawn PunchArea in front of player (prefers marker positions for accuracy)
func _do_punch_hit() -> void:
	var dir_vec: Vector2 = cardinal_direction
	if dir_vec == Vector2.ZERO:
		dir_vec = (facing.normalized() if facing != Vector2.ZERO else Vector2.DOWN)

	var reach = max(50.0, punch_reach)
	var radius = max(1.0, punch_radius)

	# If markers exist, use them so hit area aligns with sprite hands
	var hit_pos: Vector2 = Vector2.ZERO
	if dir_vec == Vector2.UP and _punch_point_up:
		hit_pos = _punch_point_up.global_position
	elif dir_vec == Vector2.DOWN and _punch_point_down:
		hit_pos = _punch_point_down.global_position
	elif dir_vec.x < 0 and _punch_point_left:
		hit_pos = _punch_point_left.global_position
	elif dir_vec.x > 0 and _punch_point_right:
		hit_pos = _punch_point_right.global_position
	else:
		# fallback: position in front calculation
		hit_pos = global_position + (dir_vec * (reach * 0.5 + radius * 0.2))
		# small optional side offset when not using markers
		if abs(dir_vec.x) > 0.5:
			hit_pos.y -= punch_side_offset_y

	var pa = PUNCH_AREA_SCENE.instantiate()
	pa.global_position = hit_pos
	pa.radius = radius
	pa.duration = clamp(punch_duration * 0.9, 0.06, punch_duration + 0.05)
	pa.stun_duration = 10.0
	get_tree().current_scene.add_child(pa)

	# Optionally play VFX / SFX here

# ===== SHOOT (GUN mode only) =====
func _try_shoot() -> void:
	if mode != Mode.GUN:
		return
	if _gun_cooldown > 0.0:
		return

	_gun_cooldown = gun_cooldown_time

	# spawn bullet from active muzzle if one exists else player's global_position
	var pos: Vector2 = global_position
	if _active_muzzle != null and is_instance_valid(_active_muzzle):
		pos = _active_muzzle.global_position
	elif muzzle_default != null and is_instance_valid(muzzle_default):
		pos = muzzle_default.global_position

	var dir: Vector2 = facing.normalized()

	var bullet = BULLET.instantiate()
	bullet.global_position = pos
	if bullet.has_method("set_direction"):
		bullet.set_direction(dir)
	else:
		bullet.rotation = dir.angle()
	get_tree().current_scene.add_child(bullet)

	# short temporary shoot animation candidates (won't lock state)
	var shoot_anim_candidates: Array = [
		"gun_shoot_" + _anim_dir_str(),
		"gun_shoot",
		"shoot_" + _anim_dir_str(),
		"shoot"
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

# ===== MODE toggle =====
func _toggle_mode() -> void:
	mode = Mode.GUN if mode == Mode.NORMAL else Mode.NORMAL
	# when switching to GUN, pick muzzle that matches current cardinal/state; when switching back, keep default
	_select_muzzle_for_cardinal(cardinal_direction)
	_update_animation(true)

# ===== ANIMATION selection =====
func _anim_dir_str() -> String:
	if cardinal_direction == Vector2.DOWN:
		return "down"
	elif cardinal_direction == Vector2.UP:
		return "up"
	else:
		return "side"

func _choose_animation_candidates() -> Array:
	var dir_str: String = _anim_dir_str()
	var candidates: Array = []

	# punch (NORMAL mode)
	if state == State.PUNCH and mode == Mode.NORMAL:
		candidates.append("fist_punch_" + dir_str)
		candidates.append("punch_" + dir_str)
		candidates.append("fist_punch")
		candidates.append("punch")

	# gun-mode preferred names (handle idle-vs-move for sneak/crawl)
	if mode == Mode.GUN:
		# If sneak/crawl and idle, prefer "gun_<state>_idle_<dir>" first
		if (state == State.SNEAK or state == State.CRAWL) and direction == Vector2.ZERO:
			candidates.append("gun_" + _state_to_string(state) + "_idle_" + dir_str)
			candidates.append("gun_" + _state_to_string(state) + "_idle")
			# then try the movement name as fallback
			candidates.append("gun_" + _state_to_string(state) + "_" + dir_str)
			candidates.append("gun_" + _state_to_string(state))
		else:
			# moving or other states: prefer movement-style "gun_<state>_<dir>"
			candidates.append("gun_" + _state_to_string(state) + "_" + dir_str)
			candidates.append("gun_" + _state_to_string(state))
			# also try a gun-specific idle as a fallback
			candidates.append("gun_idle_" + dir_str)
			candidates.append("gun_idle")
		# allow fallback to generic movement names
		candidates.append(_state_to_string(state) + "_" + dir_str)
		candidates.append(_state_to_string(state))
	else:
		# NORMAL mode: if sneak/crawl and idle, prefer "<state>_idle_<dir>"
		if (state == State.SNEAK or state == State.CRAWL) and direction == Vector2.ZERO:
			# try both common orderings to match different naming conventions
			candidates.append(_state_to_string(state) + "_idle_" + dir_str)
			candidates.append(_state_to_string(state) + "_" + dir_str)
			candidates.append(_state_to_string(state) + "_idle")
		candidates.append(_state_to_string(state) + "_" + dir_str)
		candidates.append(_state_to_string(state))
		candidates.append("idle_" + dir_str)
		candidates.append("idle")

	# last resort generic idle for mode
	var last_idle: String = "gun_idle_" + dir_str if mode == Mode.GUN else "idle_" + dir_str
	candidates.append(last_idle)
	return candidates

func _update_animation(force: bool=false) -> void:
	# keep temp anim unless forced to change
	# NOTE: allow punch to override temp animation so punch visuals always show
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

	# none found -> clear current (prevents constant reassign)
	_current_anim = ""

func _on_animation_finished(anim_name: String) -> void:
	# if punch animation finished and we're using animation to end punch, end punch
	if state == State.PUNCH:
		# if the finished animation is one of our punch candidates, end punch
		var dir_str: String = _anim_dir_str()
		var punch_candidates = [
			"fist_punch_" + dir_str,
			"punch_" + dir_str,
			"fist_punch",
			"punch"
		]
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

# ===== SPEED handler =====
func _get_speed_for_state() -> float:
	match state:
		State.WALK: return MAX_SPEED
		State.RUN: return run_speed
		State.SNEAK: return crouch_speed
		State.CRAWL: return crawl_speed
		State.IDLE: return 0.0
		_:
			return MAX_SPEED
