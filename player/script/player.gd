extends CharacterBody2D
class_name player

enum Mode { NORMAL, GUN }
enum State { IDLE, WALK, RUN, SNEAK, CRAWL, PUNCH, WALL_CLING } # เพิ่ม WALL_CLING

var input_enabled: bool = true

# ===== MOVEMENT CONFIG =====
const MAX_SPEED: float = 150.0
const ACCELERATION: float = 1400.0
const FRICTION: float = 1500.0

@export var run_speed := 250.0
@export var crouch_speed := 100.0
@export var crawl_speed := 70.0

# ===== SPRITE Y OFFSET (SNEAK/CRAWL) =====
@export var sneak_offset_y := 0.0
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

# ===== WALL CLING NODES (ต้องเพิ่มใน scene ของ Player ถ้าไม่มี) =====
# Add four RayCast2D nodes named: RC_WALL_UP, RC_WALL_DOWN, RC_WALL_LEFT, RC_WALL_RIGHT
# Each RayCast2D should have `enabled = true` and an appropriate target_position (e.g., (0,-16), (0,16), (-16,0), (16,0)).
@onready var rc_wall_up: RayCast2D = get_node_or_null("RC_WALL_UP") as RayCast2D
@onready var rc_wall_down: RayCast2D = get_node_or_null("RC_WALL_DOWN") as RayCast2D
@onready var rc_wall_left: RayCast2D = get_node_or_null("RC_WALL_LEFT") as RayCast2D
@onready var rc_wall_right: RayCast2D = get_node_or_null("RC_WALL_RIGHT") as RayCast2D

# ===== VENT RAYCASTS FOR STAND CHECK (required per request) =====
# Place 4 RayCast2D children on the Player node named:
# RC_VENT_UP, RC_VENT_DOWN, RC_VENT_LEFT, RC_VENT_RIGHT
# Each RayCast2D should be enabled and point outward from player's origin at a distance that samples clearance.
@onready var rc_vent_up: RayCast2D = get_node_or_null("RC_VENT_UP") as RayCast2D
@onready var rc_vent_down: RayCast2D = get_node_or_null("RC_VENT_DOWN") as RayCast2D
@onready var rc_vent_left: RayCast2D = get_node_or_null("RC_VENT_LEFT") as RayCast2D
@onready var rc_vent_right: RayCast2D = get_node_or_null("RC_VENT_RIGHT") as RayCast2D

# Camera2D used for peek. Prefer a Camera2D child of player named "Camera2D".
# Fallback: will try to use current viewport camera if not a child.
@onready var cam: Camera2D = get_node_or_null("Camera2D") as Camera2D

# ===== Hurtbox node (ต้องเป็นลูกของ Player ตรงชื่อ "Hurtbox") =====
@onready var hurtbox_area: Area2D = get_node_or_null("Hurtbox") as Area2D
# ใน Hurtbox ควรมีลูกเป็น CollisionShape2D 3 ตัว ชื่อ:
# "CS_NORMAL", "CS_SNEAK", "CS_CRAWL"

# ===== Player's main body collision (optional) =====
@onready var body_collision: CollisionShape2D = get_node_or_null("CollisionShape2D") as CollisionShape2D

# ==== SOUND AREA ====
const SOUND_AREA_SCENE = preload("res://player/sound_area.tscn")
@export var sound_detect_radius: float = 300.0
@export var sound_detect_duration: float = 0.25
@export var sound_emit_sfx: AudioStream = preload("res://assets/audio/knock1.ogg")

# -- Sound emit cooldown (prevents spamming the sound area) --
@export var sound_emit_cooldown_time: float = 1.2
var _sound_emit_cooldown_timer: float = 0.0

# ==== SHOOT SOUND AREA =====
const SHOOT_AREA_SCENE = preload("res://player/player_shoot_area.tscn")

@export var gunshot_sound_radius: float = 500.0
@export var gunshot_sound_duration: float = 0.25
@export var gunshot_sound_sfx: AudioStream = null  # ถ้าไม่มีจะ fallback ไปใช้ sound_emit_sfx


# ===== Footstep sound detect (auto) =====
@export var footstep_enabled: bool = true
@export var footstep_radius_walk: float = 100.0
@export var footstep_radius_run: float = 300.0
@export var footstep_interval_walk: float = 0.45
@export var footstep_interval_run: float = 0.28
@export var footstep_sfx: AudioStream = sound_emit_sfx
var _footstep_timer: float = 0.0

# Suppress footstep briefly after exiting wall_cling (so push-off doesn't create a footstep)
@export var footstep_exit_suppress_time: float = 0.28
var _suppress_footstep_after_exit_timer: float = 0.0

# ===== MODE/STATE/INPUT VARS =====
var mode: int = Mode.NORMAL
var state: int = State.IDLE
var direction: Vector2 = Vector2.ZERO
var cardinal_direction: Vector2 = Vector2.DOWN
var facing: Vector2 = Vector2.DOWN

# ===== WALL CLING CONFIG (exported so editable in Inspector) =====
@export var wall_cling_enabled: bool = true
@export var wall_cling_push_distance: float = 1.0
@export var wall_cling_peek_offset: float = 200.0
@export var wall_cling_push_speed: float = 1.0
@export var wall_cling_camera_time: float = 0.18
# default allowed states (but we'll also require mode == Mode.NORMAL)
@export var wall_cling_allowed_states: Array = [State.IDLE, State.WALK, State.RUN, State.SNEAK]

# internal wall cling trackers
var _is_wall_clinging: bool = false
var _wall_cling_dir: Vector2 = Vector2.ZERO
var _saved_footstep_enabled: bool = true
var _peek_tween: Tween = null

# ===== PUNCH (melee) =====
@export var punch_duration: float = 0.5
@export var punch_cooldown: float = 0.0
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
@export var shoot_anim_time: float = 0.4
var _current_anim: String = ""

# ===== Crouch / Sit stand-delay (new) =====
@export var stand_from_crouch_delay_min: float = 0.1
@export var stand_from_crouch_delay_max: float = 0.2
var _crouch_pending_stand: bool = false
var _crouch_delay_timer: float = 0.0

# ===== HEALTH / DAMAGE =====
@export var max_health: int = 100
var health: int = 100
@export var invuln_time: float = 2.0
var _invuln_timer: float = 0.0

signal player_spawned(player)

@onready var anim: AnimationPlayer = $AnimationPlayer

signal died

signal weapon_mode_changed(new_mode: int)

# Wall cling signals
signal wall_cling_started(direction: Vector2)
signal wall_cling_ended()

# ===== VISUAL DAMAGE FEEDBACK =====
@export var flash_color: Color = Color(0.727, 0.0, 0.163, 0.0)
var _orig_modulate: Color = Color(1,1,1,1)

# ===== BLINK (invulnerability visual) =====
@export var blink_interval: float = 0.08
var _blink_accum: float = 0.0
var _blink_on: bool = false

# current base modulate (used as the "normal" color; we adjust its alpha for grass)
var _current_base_modulate: Color = Color(1,1,1,1)

# ===== Collision scale settings =====
@export var crawl_collision_scale: float = 0.7
@export var sneak_collision_scale: float = 0.9
var _body_shape_original: Dictionary = {}
var _hurtbox_shapes_original: Dictionary = {}

# ========== GRASS AREA DETECTION ==========
var _grass_areas: Array = []
var _was_grass_crawl := false
var _player_alpha_in_grass_crawl := 0.5
var _player_zindex_in_grass_crawl := 1
var _player_zindex_normal := 0

# -------------------------------------------------------------------------
# MGS-style single-button posture control variables
# -------------------------------------------------------------------------
@export var sneak_hold_threshold: float = 0.3
var _sneak_hold_timer: float = 0.0
var _sneak_hold_triggered: bool = false
var _posture_toggle_request: int = 0    # 0=none,1=SNEAK,2=CRAWL,-1=STAND

var _want_sneak: bool = false
var _want_crawl: bool = false
# -------------------------------------------------------------------------

# Hurtbox editor-preserved position + fine-tune export
@export var hurtbox_base_offset: Vector2 = Vector2.ZERO
var _hurtbox_original_pos: Vector2 = Vector2.ZERO

# ====== NEW: Stand-check configuration (kept for compatibility but not required with rays) ======
@export var stand_height: float = 0.0
@export var crawl_height: float = 0.0
@export var stand_check_width: float = 24.0
@export var stand_check_margin: float = 2.0

# optional sound to play when stand is blocked (add an AudioStreamPlayer2D named "StandBlockedSound" as child, or set this AudioStream and it will be played fallback)
@export var stand_blocked_sfx: AudioStream = null

var _stand_blocked_player: AudioStreamPlayer2D = null

func _ready() -> void:
	emit_signal("player_spawned", self)
	print("[Player] _ready called in scene:", get_tree().current_scene.name)
	call_deferred("_apply_scene_manager_spawn")
	add_to_group("player")
	# If Camera2D wasn't set as a child named Camera2D, try to find current viewport camera
	if cam == null:
		# try to find a Camera2D in children
		for c in get_children():
			if c is Camera2D:
				cam = c
				break
	# fallback to viewport camera (may be null)
	if cam == null:
		var vp_cam = get_viewport().get_camera_2d()
		if vp_cam != null:
			cam = vp_cam

	_select_muzzle_for_cardinal(cardinal_direction)
	if animated_sprite:
		animated_sprite.connect("animation_finished", Callable(self, "_on_animation_finished"))
	# init health
	health = max_health
	# store original modulate for flash
	if animated_sprite:
		_orig_modulate = animated_sprite.modulate
		_current_base_modulate = _orig_modulate  # base follows orig initially

	# capture hurtbox editor position BEFORE any runtime adjustments
	if hurtbox_area != null:
		_hurtbox_original_pos = hurtbox_area.position

	# connect hurtbox signals (if hurtbox present)
	if hurtbox_area != null:
		if not hurtbox_area.is_connected("area_entered", Callable(self, "_on_hurtbox_area_entered")):
			hurtbox_area.connect("area_entered", Callable(self, "_on_hurtbox_area_entered"))
		if not hurtbox_area.is_connected("body_entered", Callable(self, "_on_hurtbox_body_entered")):
			hurtbox_area.connect("body_entered", Callable(self, "_on_hurtbox_body_entered"))
		if not hurtbox_area.is_connected("area_entered", Callable(self, "_on_area_entered_any")):
			hurtbox_area.connect("area_entered", Callable(self, "_on_area_entered_any"))
		if not hurtbox_area.is_connected("area_exited", Callable(self, "_on_area_exited_any")):
			hurtbox_area.connect("area_exited", Callable(self, "_on_area_exited_any"))

	# capture shapes and initial visuals/collisions
	_capture_original_shapes()
	_update_animation(true)
	_update_hurtbox_shape(true)

	# Prepare optional stand-blocked player (fallback if no node named StandBlockedSound)
	if has_node("StandBlockedSound"):
		_stand_blocked_player = get_node("StandBlockedSound") as AudioStreamPlayer2D
	else:
		_stand_blocked_player = AudioStreamPlayer2D.new()
		_stand_blocked_player.bus = "Master"
		if stand_blocked_sfx != null:
			_stand_blocked_player.stream = stand_blocked_sfx
		add_child(_stand_blocked_player)
		

# -------------------------
# Helper: apply modulate with blink + base alpha preserved
# -------------------------
func _apply_modulate() -> void:
	if animated_sprite == null:
		return
	# If blinking, use flash color but preserve base alpha
	if _blink_on:
		var blink_col = flash_color
		blink_col.a = _current_base_modulate.a
		animated_sprite.modulate = blink_col
	else:
		animated_sprite.modulate = _current_base_modulate

func _capture_original_shapes() -> void:
	if body_collision != null and body_collision.shape != null:
		_body_shape_original = _capture_shape_original(body_collision.shape)
	if hurtbox_area != null:
		for name in ["CS_NORMAL", "CS_SNEAK", "CS_CRAWL"]:
			var cs = hurtbox_area.get_node_or_null(name) as CollisionShape2D
			if cs != null and cs.shape != null:
				_hurtbox_shapes_original[name] = _capture_shape_original(cs.shape)

func _capture_shape_original(s: Shape2D) -> Dictionary:
	if s is RectangleShape2D:
		return {"type":"rect", "extents": (s as RectangleShape2D).extents}
	elif s is CircleShape2D:
		return {"type":"circle", "radius": (s as CircleShape2D).radius}
	elif s is CapsuleShape2D:
		return {"type":"capsule", "height": (s as CapsuleShape2D).height, "radius": (s as CapsuleShape2D).radius}
	else:
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
			pass

func _process(delta: float) -> void:
	# sprite offset lerp
	var desired_offset: float = (sneak_offset_y if state == State.SNEAK else crawl_offset_y if state == State.CRAWL else 0.0)
	var t: float = clamp(delta * offset_lerp_speed, 0.0, 1.0)
	_current_offset_y = lerp(_current_offset_y, desired_offset, t)
	animated_sprite.position = _base_sprite_pos + Vector2(0.0, _current_offset_y)
	_update_hurtbox_position()

	# if wall cling active but wall lost or player got punched/stunned -> exit cling
	if _is_wall_clinging:
		# exit if no longer touching wall
		if _get_wall_cling_direction() == Vector2.ZERO:
			_exit_wall_cling(false)
		# exit if punched/stunned (state==PUNCH)
		if state == State.PUNCH:
			_exit_wall_cling(false)

	# grass crawl visuals: update base modulate (do not overwrite actual modulate directly)
	var crawl_grass_now := is_in_grass() and state == State.CRAWL
	if crawl_grass_now != _was_grass_crawl:
		_was_grass_crawl = crawl_grass_now
		if animated_sprite:
			if crawl_grass_now:
				# use original base modulate but with reduced alpha
				var base = _orig_modulate
				base.a = _player_alpha_in_grass_crawl
				_current_base_modulate = base
				# set z_index for both player node and sprite so player renders above foliage as requested
				self.z_index = _player_zindex_in_grass_crawl
				animated_sprite.z_index = _player_zindex_in_grass_crawl
			else:
				var base = _orig_modulate
				base.a = 1.0
				_current_base_modulate = base
				# restore z_index
				self.z_index = _player_zindex_normal
				animated_sprite.z_index = _player_zindex_normal
		# apply modulate respecting blink state
		_apply_modulate()

	# timers
	_gun_cooldown = max(_gun_cooldown - delta, 0.0) if _gun_cooldown > 0.0 else 0.0
	_punch_timer = max(_punch_timer - delta, 0.0) if _punch_timer > 0.0 else 0.0
	_punch_cooldown_timer = max(_punch_cooldown_timer - delta, 0.0) if _punch_cooldown_timer > 0.0 else 0.0
	if _sound_emit_cooldown_timer > 0.0:
		_sound_emit_cooldown_timer = max(_sound_emit_cooldown_timer - delta, 0.0)
	if _temp_anim_timer > 0.0:
		_temp_anim_timer = max(_temp_anim_timer - delta, 0.0)
		if _temp_anim_timer <= 0.0:
			_temp_anim_name = ""
			_update_animation(true)

	# invuln blinking: toggle _blink_on and apply modulate through helper
	if _invuln_timer > 0.0:
		_invuln_timer = max(_invuln_timer - delta, 0.0)
		_blink_accum += delta
		if _blink_accum >= blink_interval:
			_blink_accum = 0.0
			_blink_on = not _blink_on
			_apply_modulate()
		if _invuln_timer <= 0.0:
			# ensure restored to base
			_blink_accum = 0.0
			_blink_on = false
			_apply_modulate()

	# MGS single-button crouch/sneak handling
	if Input.is_action_just_pressed("sneak"):
		_sneak_hold_timer = 0.0
		_sneak_hold_triggered = false
		_posture_toggle_request = 0
	elif Input.is_action_pressed("sneak"):
		_sneak_hold_timer += delta
		if not _sneak_hold_triggered and _sneak_hold_timer >= sneak_hold_threshold:
			_sneak_hold_triggered = true
			_posture_toggle_request = 2
			_apply_posture_toggle_request()
	elif Input.is_action_just_released("sneak"):
		if not _sneak_hold_triggered:
			_posture_toggle_request = 1
			_apply_posture_toggle_request()
		_sneak_hold_timer = 0.0
		_sneak_hold_triggered = false
		_posture_toggle_request = 0

	# pending-stand logic based on virtual desires
	if state == State.SNEAK:
		if _want_sneak:
			if _crouch_pending_stand:
				_crouch_pending_stand = false
				_crouch_delay_timer = 0.0
		else:
			if not _crouch_pending_stand:
				_crouch_pending_stand = true
				_crouch_delay_timer = lerp(stand_from_crouch_delay_min, stand_from_crouch_delay_max, randf())
	elif state == State.CRAWL:
		if _want_crawl:
			if _crouch_pending_stand:
				_crouch_pending_stand = false
				_crouch_delay_timer = 0.0
		else:
			if not _crouch_pending_stand:
				_crouch_pending_stand = true
				_crouch_delay_timer = lerp(stand_from_crouch_delay_min, stand_from_crouch_delay_max, randf())

# แทนบล็อกเดิมที่คุณมีใน _process
	if _crouch_pending_stand and _crouch_delay_timer > 0.0:
		_crouch_delay_timer = max(_crouch_delay_timer - delta, 0.0)
		if _crouch_delay_timer <= 0.0:
			_crouch_pending_stand = false
			# If player was crawling and we attempt to auto-stand, ensure clearance first
			if state == State.CRAWL:
				if not can_stand():
					# blocked: play feedback and remain crawling
					_play_stand_blocked_feedback()
					_want_crawl = true
					_want_sneak = false
					_crouch_pending_stand = false
					_crouch_delay_timer = 0.0
					_posture_toggle_request = 0
				else:
					if _set_state(true):
						_select_muzzle_for_cardinal(cardinal_direction)
						_update_animation(true)
						_update_hurtbox_shape(true)
			else:
				# not crawling (e.g., coming from SNEAK) — proceed normally
				if _set_state(true):
					_select_muzzle_for_cardinal(cardinal_direction)
					_update_animation(true)
					_update_hurtbox_shape(true)

	# Reduce suppression timer for footsteps after exiting cling
	if _suppress_footstep_after_exit_timer > 0.0:
		_suppress_footstep_after_exit_timer = max(_suppress_footstep_after_exit_timer - delta, 0.0)

	# footstep auto sound (suppressed while wall-cling or during short post-exit suppression)
	if footstep_enabled and not _is_wall_clinging and _suppress_footstep_after_exit_timer <= 0.0:
		if _footstep_timer > 0.0:
			_footstep_timer = max(_footstep_timer - delta, 0.0)
		if (state == State.WALK or state == State.RUN) and direction != Vector2.ZERO:
			if _footstep_timer <= 0.0:
				var radius: float = footstep_radius_walk if state == State.WALK else footstep_radius_run
				var interval: float = footstep_interval_walk if state == State.WALK else footstep_interval_run
				var sa = SOUND_AREA_SCENE.instantiate()
				sa.global_position = global_position
				sa.radius = radius
				sa.duration = clamp(sound_detect_duration, 0.05, 0.6)
				sa.source_player = self
				sa.sound_sfx = footstep_sfx
				get_tree().current_scene.add_child(sa)
				_footstep_timer = interval
		else:
			_footstep_timer = 0.0
	else:
		# while suppressed, keep timer zero so no footsteps appear when leaving state quickly
		_footstep_timer = 0.0

	# input update
	direction.x = Input.get_action_strength("right") - Input.get_action_strength("left")
	direction.y = Input.get_action_strength("down") - Input.get_action_strength("up")
	if direction != Vector2.ZERO:
		facing = direction.normalized()
		_set_direction_immediate()

	# wall cling input: try enter when pressing action
	if Input.is_action_just_pressed("wall_cling"):
		# only enter if _can_wall_cling
		if _can_wall_cling():
			var dir = _get_wall_cling_direction()
			if dir != Vector2.ZERO:
				_enter_wall_cling(dir)

	if Input.is_action_just_pressed("weapon_swap"):
		_toggle_mode()
	if Input.is_action_just_pressed("attack"):
		if mode == Mode.GUN:
			_try_shoot()
		elif _punch_cooldown_timer <= 0.0 and state != State.PUNCH:
			_start_punch()

	if Input.is_action_just_pressed("sound_detect"):
		if not _is_wall_clinging:
			return
		elif _sound_emit_cooldown_timer <= 0.0 and _is_wall_clinging:
			var sa = SOUND_AREA_SCENE.instantiate()
			sa.global_position = global_position
			sa.radius = sound_detect_radius
			sa.duration = sound_detect_duration
			sa.source_player = self
			sa.sound_sfx = sound_emit_sfx
			get_tree().current_scene.add_child(sa)
			_sound_emit_cooldown_timer = sound_emit_cooldown_time
			

	# state updates (don't change during punch or while wall clinging)
	if state != State.PUNCH and not _is_wall_clinging:
		if _set_state():
			_select_muzzle_for_cardinal(cardinal_direction)
			_update_animation(true)
			_update_hurtbox_shape(true)

	# if wall-clinging, handle cling-specific input & behavior
	if _is_wall_clinging:
		_handle_wall_cling_input()

	# end punch
	if state == State.PUNCH and not _punch_auto_end_by_anim and _punch_timer <= 0.0:
		_end_punch()
	_update_animation()

func _physics_process(delta: float) -> void:
	if not input_enabled:
		velocity = Vector2.ZERO
		return
	# ถ้า wall-clinging: อนุญาตให้เคลื่อนที่เฉพาะแนวที่ขนานกับผนัง (tangent)
	if _is_wall_clinging:
		# ความเร็วเป้าหมายตาม state (walk/run/crouch ฯลฯ)
		var target_speed: float = _get_speed_for_state()
		var input_dir: Vector2 = direction.normalized() if direction != Vector2.ZERO else Vector2.ZERO

		# กำหนด tangent ของผนัง (ทิศทางที่อนุญาตให้เดินขณะ cling)
		# ถ้า wall_dir = LEFT/RIGHT => tangent = UP/DOWN (เคลื่อนในแกน Y)
		# ถ้า wall_dir = UP/DOWN => tangent = LEFT/RIGHT (เคลื่อนในแกน X)
		var tangent: Vector2 = Vector2.ZERO
		if _wall_cling_dir != Vector2.ZERO:
			tangent = Vector2(-_wall_cling_dir.y, _wall_cling_dir.x) # rotate 90deg

		# โปรเจ็กต์ input ไปตาม tangent เพื่อรู้ทิศและขนาดการเคลื่อนที่ที่ต้องการ
		var proj: float = 0.0
		if tangent != Vector2.ZERO and input_dir != Vector2.ZERO:
			proj = input_dir.dot(tangent) # ค่า -1..1 (ลบ=ทิศหนึ่ง บวก=อีกทิศ)

		# ตั้งความเร็วเป้าหมายเฉพาะแนว tangent
		var target_vel: Vector2 = tangent * proj * target_speed

		# ใช้การเร่งแบบเดิมเพื่อความนุ่มนวล
		velocity = velocity.move_toward(target_vel, ACCELERATION * delta)
		move_and_slide()
		return

	# ปกติ (ไม่ cling) -> พฤติกรรมเดิม
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
		# ไม่ให้ flip sprite ขณะ wall_cling (ป้องกันการพลิกเมื่อเพิ่งเข้า cling)
		if not _is_wall_clinging:
			animated_sprite.scale.x = -1 if cardinal_direction == Vector2.LEFT else 1
		_select_muzzle_for_cardinal(cardinal_direction)

func _set_direction() -> bool:
	if direction == Vector2.ZERO: return false
	_set_direction_immediate()
	return true

# --------------------------------------------------------------------
# _set_state using virtual posture flags; updates visuals/collisions
# --------------------------------------------------------------------
func _apply_posture_toggle_request() -> void:
	# ถ้าอยู่ใน wall cling ห้ามเปลี่ยน posture ใด ๆ
	if _is_wall_clinging:
		_posture_toggle_request = 0
		return

	if state == State.PUNCH:
		_posture_toggle_request = 0
		return

	# NOTE:
	# We intercept the case where player is in CRAWL and requests to stand.
	# In that case we run can_stand(). If can_stand() == false -> block and play feedback.
	#
	# Ensure both short-press (1) and the "already-crawling long-hold" (2 while state==CRAWL)
	# check clearance, otherwise long-hold could bypass check.

	match _posture_toggle_request:
		1:
			# Short press
			# Behavior:
			# - If currently crawling: short press -> SNEAK (but only if standing/clearance allows)
			# - If currently sneak: short-press -> stand
			# - Otherwise (standing): short-press -> sneak
			if state == State.CRAWL:
				# From CRAWL: short press -> SNEAK, but only if there's vertical clearance.
				# If can_stand() is false, block (don't allow sneak) so player remains crawling.
				if not can_stand():
					_play_stand_blocked_feedback()
					# keep crawling
					_want_crawl = true
					_want_sneak = false
					_crouch_pending_stand = false
					_crouch_delay_timer = 0.0
					_posture_toggle_request = 0
					return
				# space available -> go to sneak
				_want_crawl = false
				_want_sneak = true
				# cancel any pending automatic stand
				_crouch_pending_stand = false
				_crouch_delay_timer = 0.0
			elif state == State.SNEAK:
				# From SNEAK: short press -> STAND (normal behavior)
				_want_sneak = false
				_want_crawl = false
			else:
				# From STAND/WALK/RUN: short press -> SNEAK
				_want_sneak = true
				_want_crawl = false
		2:
			# Long hold
			# Behavior:
			# - If currently crawling: long-hold -> attempt to STAND (check clearance)
			# - If currently sneak: long-hold -> go to CRAWL
			# - Otherwise (standing): long-hold -> CRAWL
			if state == State.CRAWL:
				# Attempt to stand: check with vent rays
				if not can_stand():
					# Block standing: keep crawling and play feedback (sound/effect)
					_play_stand_blocked_feedback()
					# ensure we remain wanting crawl
					_want_crawl = true
					_want_sneak = false
					_crouch_pending_stand = false
					_crouch_delay_timer = 0.0
					_posture_toggle_request = 0
					return
				else:
					# space available -> go to stand
					_want_sneak = false
					_want_crawl = false
			elif state == State.SNEAK:
				# From SNEAK: long-hold -> go to CRAWL
				_want_crawl = true
				_want_sneak = false
			else:
				# From STAND/WALK/RUN: long-hold -> go to CRAWL
				_want_crawl = true
				_want_sneak = false
		-1:
			_want_sneak = false
			_want_crawl = false
		_:
			pass

	_set_state()
	_posture_toggle_request = 0

# New helper: play feedback when standing is blocked (sound/optional effect)
func _play_stand_blocked_feedback() -> void:
	# Play node "StandBlockedSound" if exists (AudioStreamPlayer2D),
	# otherwise use fallback _stand_blocked_player prepared in _ready().
	if _stand_blocked_player != null:
		if stand_blocked_sfx != null:
			_stand_blocked_player.stream = stand_blocked_sfx
		if _stand_blocked_player.stream != null:
			_stand_blocked_player.play()
	# small visual feedback: flash sprite quickly (non-destructive)
	if animated_sprite != null:
		var old = animated_sprite.modulate
		animated_sprite.modulate = Color(1.0, 0.6, 0.6, old.a)
		var timer = get_tree().create_timer(0.12)
		timer.connect("timeout", Callable(self, "_on_stand_block_flash_timeout"))

func _on_stand_block_flash_timeout() -> void:
	_apply_modulate()

func _set_state(force: bool=false) -> bool:
	# ถ้า wall-clinging ห้ามเปลี่ยน state ยกเว้นถูกบังคับด้วย force
	if _is_wall_clinging and not force:
		return false

	if _crouch_pending_stand and not force and (state == State.SNEAK or state == State.CRAWL):
		return false
	if state == State.PUNCH and not force:
		return false

	var new_state: int
	if _want_crawl:
		new_state = State.CRAWL
	elif _want_sneak:
		new_state = State.SNEAK
	else:
		new_state = (
			State.RUN if Input.is_action_pressed("run") and direction != Vector2.ZERO else
			State.IDLE if direction == Vector2.ZERO else State.WALK
		)

	if new_state == state:
		return false

	state = new_state

	_select_muzzle_for_cardinal(cardinal_direction)
	_update_animation(true)
	_update_hurtbox_shape(true)

	return true

# -------------------------------------------------------------

func _start_punch() -> void:
	if state == State.CRAWL or _is_wall_clinging:
		return
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
	if pa.has_method("set") and pa.has_method("get"):
		var v = pa.get("damage") if pa.has_method("get") else null
		if v != null:
			pa.set("damage", 10)
	get_tree().current_scene.add_child(pa)

func _try_shoot() -> void:
	if state == State.CRAWL or _is_wall_clinging:
		return
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

	# spawn shoot-area so nearby enemies hear the gunshot (like SoundArea)
	var sa = null
	if SHOOT_AREA_SCENE != null:
		sa = SHOOT_AREA_SCENE.instantiate()
	else:
		# fallback to the existing sound_area scene used for footsteps
		sa = SOUND_AREA_SCENE.instantiate()
	sa.global_position = pos
	# ใช้ค่าที่ export ไว้ (ปรับได้ใน Inspector)
	sa.radius = gunshot_sound_radius
	sa.duration = gunshot_sound_duration
	sa.source_player = self
	sa.sound_sfx = gunshot_sound_sfx if gunshot_sound_sfx != null else sound_emit_sfx
	get_tree().current_scene.add_child(sa)

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
	# Notify HUD / listeners about mode change
	emit_signal("weapon_mode_changed", mode)
	# If you have an ammo variable, emit ammo update too:
	# if has_method("get_ammo_count"):
	#     emit_signal("ammo_changed", get_ammo_count())

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
	# If wall-clinging, prefer wall animations (explicit left/right/up/down)
	if _is_wall_clinging:
		var anim_name = ""
		if _wall_cling_dir == Vector2.LEFT:
			anim_name = "wall_left"
		elif _wall_cling_dir == Vector2.RIGHT:
			anim_name = "wall_right"
		elif _wall_cling_dir == Vector2.UP:
			anim_name = "wall_up"
		elif _wall_cling_dir == Vector2.DOWN:
			anim_name = "wall_down"
		if anim_name != "" and animated_sprite.sprite_frames != null and animated_sprite.sprite_frames.has_animation(anim_name):
			if _current_anim != anim_name or force:
				_current_anim = anim_name
				animated_sprite.animation = anim_name
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

func _on_animation_finished() -> void:
	# AnimatedSprite2D.animation_finished in Godot 4 emits no arguments.
	# Read the animation name directly from the AnimatedSprite2D node (or use _current_anim if you track it).
	if animated_sprite == null:
		return
	var anim_name: String = animated_sprite.animation if animated_sprite.animation != "" else _current_anim

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

# ========== WALL CLING: detection & behavior functions ==========
# Return true if wall cling is allowed in current context (mode, state, etc.)
func _can_wall_cling() -> bool:
	if not wall_cling_enabled:
		return false
	# allow both NORMAL and GUN modes (previously required NORMAL only)
	if not (mode == Mode.NORMAL or mode == Mode.GUN):
		return false
	# don't allow when punching
	if state == State.PUNCH:
		return false
	# require that current state is in allowed list (editor configurable)
	var ok_state: bool = false
	for s in wall_cling_allowed_states:
		if s == state:
			ok_state = true
			break
	if not ok_state:
		return false
	# must be touching a wall via raycasts
	if _get_wall_cling_direction() == Vector2.ZERO:
		return false
	return true

# Return a cardinal Vector2 indicating wall normal direction (LEFT/RIGHT/UP/DOWN) when touching; Vector2.ZERO otherwise.
func _get_wall_cling_direction() -> Vector2:
	# prefer the direction the player is facing if multiple raycasts hit
	var hits: Array = []
	if rc_wall_left != null and rc_wall_left.is_colliding():
		hits.append(Vector2.LEFT)
	if rc_wall_right != null and rc_wall_right.is_colliding():
		hits.append(Vector2.RIGHT)
	if rc_wall_up != null and rc_wall_up.is_colliding():
		hits.append(Vector2.UP)
	if rc_wall_down != null and rc_wall_down.is_colliding():
		hits.append(Vector2.DOWN)
	if hits.size() == 0:
		return Vector2.ZERO
	# if only one hit, return that
	if hits.size() == 1:
		return hits[0]
	# if multiple, choose hit most aligned with facing; fallback to first
	var best = hits[0]
	var best_dot = facing.dot(best)
	for h in hits:
		var d = facing.dot(h)
		if d > best_dot:
			best_dot = d
			best = h
	return best

# Enter wall cling state. dir must be a cardinal Vector2 (LEFT/RIGHT/UP/DOWN)
func _enter_wall_cling(dir: Vector2) -> void:
	# เข้าสู่ wall cling: ป้องกัน redundant calls
	if _is_wall_clinging:
		return
	if dir == Vector2.ZERO:
		return

	# ยกเลิกการเปลี่ยน posture ทั้งหมดยาม cling
	_posture_toggle_request = 0
	_want_sneak = false
	_want_crawl = false
	_crouch_pending_stand = false
	_crouch_delay_timer = 0.0

	_is_wall_clinging = true
	_wall_cling_dir = dir
	# ตั้ง state เพื่อให้ animation/system รู้ว่าเรา cling
	state = State.WALL_CLING
	# freeze velocity
	velocity = Vector2.ZERO
	# suppress footsteps (store previous value to restore later)
	_saved_footstep_enabled = footstep_enabled
	footstep_enabled = false

	# ตั้งค่า scale ให้เป็นค่า default (ไม่ flip) เพื่อหลีกเลี่ยงการพลิก sprite เมื่อเพิ่งเข้า cling
	# เราใช้อนิเมชันแยกเป็น "wall_left"/"wall_right" ดังนั้นไม่ต้อง flip
	if animated_sprite != null:
		animated_sprite.scale.x = 1

	# play wall animation immediately
	_update_animation(true)
	# emit signal
	emit_signal("wall_cling_started", dir)
	# cancel any existing peek tween
	if _peek_tween != null and is_instance_valid(_peek_tween):
		_peek_tween.kill()
		_peek_tween = null

# Handle input while wall clinging: peek toward wall or push-off
func _handle_wall_cling_input() -> void:
	# read directional intent from input/action strengths (same way as movement)
	var input_vec = Vector2(
		Input.get_action_strength("right") - Input.get_action_strength("left"),
		Input.get_action_strength("down") - Input.get_action_strength("up")
	)
	if input_vec == Vector2.ZERO:
		# no input -> stop peek if active
		_stop_peek()
		return

	# normalize to get direction intent
	var intent = input_vec.normalized()
	# dot with wall dir: positive => pressing toward wall, negative => pressing away
	var d = intent.dot(_wall_cling_dir)
	# threshold: when pressing sufficiently toward or away
	var threshold = 0.5
	if d < -threshold:
		# pressing away from wall -> exit with push
		_exit_wall_cling(true)
	elif d > threshold:
		# pressing toward wall -> start peek (camera shift)
		_start_peek(_wall_cling_dir)
	else:
		_stop_peek()

# Exit wall cling. If push==true, apply velocity away from wall to "step off".
func _exit_wall_cling(push: bool=false) -> void:
	if not _is_wall_clinging:
		return
	_is_wall_clinging = false

	# restore footstep setting (will be used after we optionally suppress immediate footstep)
	footstep_enabled = _saved_footstep_enabled

	# stop peek and tween
	_stop_peek()

	# set state back to a normal state (try set_state)
	_set_state(true)

	# on push: apply a small instantaneous velocity away from the wall
	if push:
		# set a velocity that pushes player away
		velocity = _wall_cling_dir * -wall_cling_push_speed
		# small position offset to avoid re-detecting wall in same frame (optional)
		var push_offset = _wall_cling_dir * -wall_cling_push_distance
		global_position += push_offset

		# set facing/cardinal to match the push direction (away from wall) so animation faces forward
		var move_dir = velocity.normalized() if velocity.length() > 0.0 else -_wall_cling_dir
		if move_dir.x != 0 and abs(move_dir.x) >= abs(move_dir.y):
			cardinal_direction = Vector2.LEFT if move_dir.x < 0 else Vector2.RIGHT
		else:
			cardinal_direction = Vector2.UP if move_dir.y < 0 else Vector2.DOWN

		# allow sprite flipping now (ensure scale matches cardinal)
		if animated_sprite != null:
			animated_sprite.scale.x = -1 if cardinal_direction == Vector2.LEFT else 1

		# suppress footstep spawn for a short duration so push-off doesn't emit sound
		_suppress_footstep_after_exit_timer = footstep_exit_suppress_time
		# also set _footstep_timer so immediate generation is blocked
		_footstep_timer = max(footstep_interval_walk, footstep_interval_run)
	else:
		# no push: try to preserve facing based on input if any
		if direction != Vector2.ZERO:
			facing = direction.normalized()
			_set_direction_immediate()

	# reset wall dir
	_wall_cling_dir = Vector2.ZERO

	# update animation and hurtbox as we left WALL_CLING
	_select_muzzle_for_cardinal(cardinal_direction)
	_update_animation(true)
	_update_hurtbox_shape(true)
	emit_signal("wall_cling_ended")

# Start camera peek toward wall_dir (cardinal). Uses Tween for smooth motion.
func _start_peek(wall_dir: Vector2) -> void:
	if cam == null:
		return
	# compute target offset relative to camera's parent
	var peek_vector = wall_dir * wall_cling_peek_offset
	# if camera is direct child of player, tween its local position
	if cam.get_parent() == self:
		# kill existing tween
		if _peek_tween != null and is_instance_valid(_peek_tween):
			_peek_tween.kill()
		_peek_tween = get_tree().create_tween()
		_peek_tween.tween_property(cam, "position", peek_vector, wall_cling_camera_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		# camera is elsewhere: tween global position
		if _peek_tween != null and is_instance_valid(_peek_tween):
			_peek_tween.kill()
		_peek_tween = get_tree().create_tween()
		var target_global = cam.global_position + peek_vector
		_peek_tween.tween_property(cam, "global_position", target_global, wall_cling_camera_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# Stop peek and return camera to neutral
func _stop_peek() -> void:
	if cam == null:
		return
	if _peek_tween != null and is_instance_valid(_peek_tween):
		_peek_tween.kill()
		_peek_tween = null
	# tween back to origin
	if cam.get_parent() == self:
		_peek_tween = get_tree().create_tween()
		_peek_tween.tween_property(cam, "position", Vector2.ZERO, wall_cling_camera_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	else:
		_peek_tween = get_tree().create_tween()
		_peek_tween.tween_property(cam, "global_position", get_viewport().get_camera_2d().global_position, wall_cling_camera_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

# ========== HURT / DAMAGE HANDLING ==========
func _on_hurtbox_area_entered(area: Area2D) -> void:
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
	if _invuln_timer > 0.0:
		return
	health = max(health - amount, 0)
	_invuln_timer = invuln_time
	# start blink: set trackers and apply modulate via helper so alpha is preserved
	_blink_accum = 0.0
	_blink_on = true
	_apply_modulate()
	# leaving wall cling when hurt
	if _is_wall_clinging:
		_exit_wall_cling(false)
	if has_node("HurtSound"):
		var hs = get_node("HurtSound")
		if hs != null and hs.has_method("play"):
			hs.play()
	if health <= 0:
		_die()

func _die() -> void:
	set_process(false)
	set_physics_process(false)

	if "velocity" in self:
		velocity = Vector2.ZERO

	if has_node("DeathSound"):
		var ds = get_node("DeathSound")
		if ds != null and ds.has_method("play"):
			ds.play()

	if anim != null:
		if anim.has_animation("die"):
			if not anim.animation_finished.is_connected(_on_die_animation_finished):
				anim.animation_finished.connect(_on_die_animation_finished)
			anim.play("die")
		else:
			# fallback ถ้าไม่มี animation
			emit_signal("died")
	else:
		emit_signal("died")

	if body_collision != null:
		body_collision.disabled = true

	if hurtbox_area != null:
		hurtbox_area.set_deferred("monitoring", false)
		
func _on_die_animation_finished(anim_name: StringName) -> void:
	if anim_name == "die":
		emit_signal("died")

#-- Healing --
func heal(amount: int, source: Node = null) -> bool:
	if amount <= 0:
		return false
	if health >= max_health:
		return false
	var prev_health: int = health
	health = min(health + amount, max_health)
	if has_node("HealSound"):
		var hs = get_node("HealSound")
		if hs != null and hs.has_method("play"):
			hs.play()
	# show temp heal tint then restore via _apply_modulate
	if animated_sprite:
		animated_sprite.modulate = Color(0.6, 1.0, 0.6, 1.0)
		var st = get_tree().create_timer(0.15)
		st.connect("timeout", Callable(self, "_on_heal_flash_timeout"))
	return health > prev_health

func _on_heal_flash_timeout() -> void:
	# restore using _apply_modulate so we respect grass + blink state
	_apply_modulate()

# ========== HURTBOX SHAPE SWITCHING ==========
func _update_hurtbox_shape(force: bool=false) -> void:
	if hurtbox_area == null:
		return
	var cs_normal = hurtbox_area.get_node_or_null("CS_NORMAL") as CollisionShape2D
	var cs_sneak = hurtbox_area.get_node_or_null("CS_SNEAK") as CollisionShape2D
	var cs_crawl = hurtbox_area.get_node_or_null("CS_CRAWL") as CollisionShape2D
	if cs_normal == null and cs_sneak == null and cs_crawl == null:
		push_warning("Hurtbox shapes not found: expected children CS_NORMAL, CS_SNEAK, CS_CRAWL under Hurtbox")
		return
	if cs_normal:
		cs_normal.disabled = not (state == State.IDLE or state == State.WALK or state == State.RUN)
	if cs_sneak:
		cs_sneak.disabled = not (state == State.SNEAK)
	if cs_crawl:
		cs_crawl.disabled = not (state == State.CRAWL)

	var scale: float = 1.0
	if state == State.CRAWL:
		scale = clamp(crawl_collision_scale, 0.01, 2.0)
	elif state == State.SNEAK:
		scale = clamp(sneak_collision_scale, 0.01, 2.0)
	else:
		scale = 1.0

	if body_collision != null and body_collision.shape != null and _body_shape_original != null:
		_apply_scaled_to_shape(body_collision.shape, _body_shape_original, scale)

	for name in _hurtbox_shapes_original.keys():
		var cs = hurtbox_area.get_node_or_null(name) as CollisionShape2D
		if cs != null and cs.shape != null:
			if not cs.disabled:
				_apply_scaled_to_shape(cs.shape, _hurtbox_shapes_original[name], scale)
			else:
				_apply_scaled_to_shape(cs.shape, _hurtbox_shapes_original[name], 1.0)

	_update_hurtbox_position()

func _update_hurtbox_position() -> void:
	if hurtbox_area == null:
		return
	var pos: Vector2 = _hurtbox_original_pos
	pos.y += _current_offset_y
	pos += hurtbox_base_offset
	hurtbox_area.position = pos

func _on_nav_timer_timeout() -> void:
	pass

# ========== GRASS / AREA helpers ==========
func _on_area_entered_any(area: Area2D) -> void:
	if is_instance_valid(area) and area.is_in_group("grass_area"):
		if not _grass_areas.has(area):
			_grass_areas.append(area)

func _on_area_exited_any(area: Area2D) -> void:
	if is_instance_valid(area) and area.is_in_group("grass_area"):
		_grass_areas.erase(area)

func is_in_grass() -> bool:
	return _grass_areas.size() > 0


# Return Vector2 facing
func get_facing() -> Vector2:
	return facing

# Accept Vector2, apply facing, update sprite/animation
func set_facing(dir: Vector2) -> void:
	if dir == Vector2.ZERO:
		return
	facing = dir.normalized()
	# Update sprite/animation accordingly (left/right flip, up/down animation state)
	if has_node("Sprite"):
		var s = $Sprite
		# horizontal flip logic
		if facing.x < 0:
			s.flip_h = true
		elif facing.x > 0:
			s.flip_h = false
	# handle up/down animation via AnimationPlayer or animator if present
	if has_node("AnimationPlayer"):
		var ap = $AnimationPlayer
		# decide animation based on predominant axis
		if abs(facing.x) >= abs(facing.y):
			if facing.x < 0:
				ap.play("walk_left")
			else:
				ap.play("walk_right")
		else:
			if facing.y < 0:
				ap.play("walk_up")
			else:
				ap.play("walk_down")


# ===== For Scene Manager ========
# Utility method to allow Gameplay/Level to ask player to spawn at position directly
func spawn_at(global_pos: Vector2, facing_dir: Vector2 = Vector2.ZERO) -> void:
	global_position = global_pos
	if facing_dir != Vector2.ZERO:
		set_facing(facing_dir)

# Optionally save/load state if you chose to instantiate player per-level
func save_state() -> Dictionary:
	return {
		"facing": facing,
		# add hp, inventory, etc.
		}

func load_state(data: Dictionary) -> void:
		if data.has("facing"):
			var f = data["facing"]
			if f is Vector2:
				set_facing(f)
	# load other fields as needed

# =============================
# NEW: Clearance check - can_stand() using RayCast2D vents
# =============================
# Logic per your request:
# - If top blocked but bottom still free -> allow stand (only up colliding)
# - If top blocked and bottom blocked -> cannot stand (both vertical rays hit)
# - If left blocked but right free -> allow stand
# - If left blocked and right blocked -> cannot stand
# Ray names required on Player:
#   RC_VENT_UP, RC_VENT_DOWN, RC_VENT_LEFT, RC_VENT_RIGHT
# If a RayCast2D node is missing we treat it as "not colliding" (safe). You can change to strict mode if desired.
func can_stand() -> bool:
	# Safety: ensure raycasts exist and are enabled
	var up_hit: bool = false
	var down_hit: bool = false
	var left_hit: bool = false
	var right_hit: bool = false

	if rc_vent_up != null:
		if not rc_vent_up.enabled:
			rc_vent_up.enabled = true
			if rc_vent_up.has_method("force_raycast_update"):
				rc_vent_up.force_raycast_update()
		up_hit = rc_vent_up.is_colliding()
	if rc_vent_down != null:
		if not rc_vent_down.enabled:
			rc_vent_down.enabled = true
			if rc_vent_down.has_method("force_raycast_update"):
				rc_vent_down.force_raycast_update()
		down_hit = rc_vent_down.is_colliding()
	if rc_vent_left != null:
		if not rc_vent_left.enabled:
			rc_vent_left.enabled = true
			if rc_vent_left.has_method("force_raycast_update"):
				rc_vent_left.force_raycast_update()
		left_hit = rc_vent_left.is_colliding()
	if rc_vent_right != null:
		if not rc_vent_right.enabled:
			rc_vent_right.enabled = true
			if rc_vent_right.has_method("force_raycast_update"):
				rc_vent_right.force_raycast_update()
		right_hit = rc_vent_right.is_colliding()

	# debug (ชั่วคราว ถ้าต้องการ)
	# print("can_stand: up=", up_hit, " down=", down_hit, " left=", left_hit, " right=", right_hit)

	# Block if both vertical blocked OR both horizontal blocked (ตามนโยบายของคุณ)
	if up_hit and down_hit:
		return false
	if left_hit and right_hit:
		return false
	return true
