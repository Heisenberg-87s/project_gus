extends CharacterBody2D
class_name Enemy

# การเคลื่อนที่ / ลาดตระเวน
@export var speed: float = 120.0
@export var acceleration: float = 1400.0
@export var arrival_distance: float = 8.0
@export var wait_time_at_point: float = 0.1

@export var patrol_root_path: NodePath = NodePath("")   # โหนดที่เก็บจุดลาดตระเวน
@export var loop_patrol: bool = true
@export var ping_patrol: bool = false

# Facing option for when reaching the latest patrol point
enum PatrolFinishFacing { AUTO = 0, UP = 1, DOWN = 2, LEFT = 3, RIGHT = 4 }
@export var patrol_finish_facing: PatrolFinishFacing = PatrolFinishFacing.AUTO

# ตัวช่วยสถานะ SEARCH (compat layer — เราใช้ EVASION แทน SEARCH)
var _search_scan_cooldown: float = 5.0
var _search_scan_timer: float = 0.0
var _search_scan_index: int = 0
const _SEARCH_SCAN_DIRS: Array = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
var _search_is_scanning: bool = false
var _search_scan_dir_timer: float = 0.45

# -----------------------
# การตั้งค่าการมอง/การตรวจจับ
# -----------------------
const LAYER_WALL: int = (1 << 0) | (1 << 7) | (1 << 11)

@export var sight_distance: float = 300.0
@export var sight_fov_deg: float = 120.0
@export var sight_rays: int = 36
@export var sight_debug: bool = true
@export var sight_debug_color_clear: Color = Color(0, 1, 0, 0.18)
@export var sight_debug_color_alert: Color = Color(1, 0, 0, 0.25)

@export var sight_origin_path: NodePath = NodePath("")
@onready var sight_origin: Marker2D = get_node_or_null("SightOrigin") as Marker2D

# Muzzle
@export var muzzle_path: NodePath = NodePath("")
var muzzle: Marker2D = null

# Combat tuning
@export var combat_pause_duration: float = 0.6
@export var combat_sight_multiplier: float = 1.5
@export var combat_move_speed: float = 220.0

# Stealth interaction
@export var stealth_sneak_multiplier: float = 0.6
@export var stealth_crawl_multiplier: float = 0.3
@export var stealth_grass_crawl_multiplier: float = 0.0333
@export var stealth_grass_crawl_override_distance: float = 10.0
@export var apply_stealth_to_sight_visual: bool = true

const PLAYER_STATE_SNEAK: int = 3
const PLAYER_STATE_CRAWL: int = 4

@export var combat_scan: bool = true
@export var combat_scan_interval: float = 0.45

# Stun/cooldown
@export var stun_duration: float = 1.0
@export var stun_cooldown_min: float = 8.0
@export var stun_cooldown_max: float = 10.0
var _stun_cooldown_timer: float = 0.0
var _can_stun: bool = true

# Sound reaction
@export var sound_reaction_pause: float = 0.35
var _sound_reaction_timer: float = 1.0
var _sound_reaction_waiting: bool = true

# Shooting
@export var attack_cooldown: float = 0.1
@export var projectile_scene: PackedScene
@export var muzzle_offset: Vector2 = Vector2.ZERO
@export var projectile_speed: float = 1000.0
var _attack_timer: float = 0.0
signal shoot_at(target_pos)

# -----------------------
# Runtime AI
# -----------------------
enum AIState { NORMAL, COMBAT, EVASION, DETECT } # SEARCH replaced by EVASION
var ai_state: int = AIState.NORMAL

var _patrol_points: Array = []
var _patrol_index: int = 0
var _forward: bool = true
var _wait_timer: float = 0.0

var _last_facing: Vector2 = Vector2.DOWN

@onready var agent: NavigationAgent2D = get_node_or_null("Agent") as NavigationAgent2D
@onready var _anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
var _current_anim: String = ""

@onready var _sight_polygon: Polygon2D = get_node_or_null("SightCone") as Polygon2D

var is_stunned: bool = false
var is_hit: bool = false

var _original_sight_distance: float = 0.0
var _combat_pause_timer: float = 0.0
# (legacy _combat_search_timer kept but not used for CAUTION countdown)
var _combat_search_timer: float = 0.0
var _last_known_player_pos: Vector2 = Vector2.ZERO
var _pause_on_reach: bool = true

var _scan_index: int = 0
var _scan_timer: float = 0.0
const _SCAN_DIRS: Array = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]

var _last_player_visible: bool = false

var _stun_track_player: bool = false
var _stun_track_node: Node = null

signal player_spotted(player)
signal player_lost()

# Signals to notify UI / other systems about CAUTION
signal caution_started(enemy)
signal caution_ended(enemy)

# ----------------------------------------------------------------
# EVASION (new)
# ----------------------------------------------------------------
@export var evasion_duration: float = 10.0        # changed to 10s as requested
@export var evasion_point_count: int = 5
@export var evasion_min_radius: float = 45.0
@export var evasion_max_radius: float = 60.0
@export var evasion_wait_at_point: float = 1.0
@export var evasion_move_speed: float = 140.0
@export var evasion_scan_interval: float = 0.45

var _evasion_points: Array = []
var _evasion_index: int = 0
var _evasion_time_left: float = 0.0
var _evasion_wait_timer: float = 0.0
var _evasion_waiting: bool = false

# CAUTION state flag:
# Show "CAUTION" during COMBAT but do not start the countdown here.
# Countdown starts only when entering EVASION (so Combat acts as caution phase).
var _caution_active: bool = false

# ----------------------------------------------------------------
# New option: disable hearing while 'hit'
@export var disable_hearing_while_hit: bool = true

# ----------------------------------------------------------------
# Helper: safe agent next position (returns null if agent has no path)
func _get_agent_next_position_safe():
	if agent == null:
		return null
	if agent.has_method("get_next_path_position"):
		var np = agent.get_next_path_position()
		if np == Vector2.ZERO:
			return null
		return np
	elif "next_path_position" in agent:
		var np2 = agent.next_path_position
		if np2 == Vector2.ZERO:
			return null
		return np2
	return null

# ----------------------------------------------------------------
func _ready() -> void:
	_original_sight_distance = sight_distance
	add_to_group("enemies")

	if sight_origin == null and sight_origin_path != NodePath("") and has_node(sight_origin_path):
		sight_origin = get_node_or_null(sight_origin_path) as Marker2D

	if has_node("Muzzle"):
		muzzle = get_node_or_null("Muzzle") as Marker2D
	elif muzzle_path != NodePath("") and has_node(muzzle_path):
		muzzle = get_node_or_null(muzzle_path) as Marker2D

	if sight_debug and _sight_polygon == null:
		_sight_polygon = Polygon2D.new()
		_sight_polygon.name = "SightCone"
		_sight_polygon.z_index = 100
		add_child(_sight_polygon)
	if _sight_polygon:
		_sight_polygon.polygon = PackedVector2Array()
	_reload_patrol_points()
	if _patrol_points.size() > 0:
		_patrol_index = 0
		_forward = true
		_wait_timer = 0.0
	if agent:
		if "target_desired_distance" in agent:
			agent.target_desired_distance = arrival_distance
		if "navigation_layers" in agent:
			print("Enemy: Agent navigation_layers =", agent.navigation_layers)
		else:
			print("Enemy: Agent available but 'navigation_layers' property not found (check Godot version).")

# ----------------------------------------------------------------
func _physics_process(delta: float) -> void:
	if _stun_cooldown_timer > 0.0:
		_stun_cooldown_timer = max(_stun_cooldown_timer - delta, 0.0)
		if _stun_cooldown_timer <= 0.0:
			_can_stun = true

	_update_sight_visual_and_detection()

	if _sound_reaction_waiting:
		_sound_reaction_timer = max(_sound_reaction_timer - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation()
		if _sound_reaction_timer <= 0.0:
			_sound_reaction_waiting = false
			if agent:
				if agent.has_method("set_target_position"):
					agent.set_target_position(_last_known_player_pos)
				elif "target_position" in agent:
					agent.target_position = _last_known_player_pos
		return

	if is_stunned or is_hit:
		if is_stunned and _stun_track_player:
			var player_node := (_stun_track_node if is_instance_valid(_stun_track_node) else _get_player_node())
			if player_node != null and _last_player_visible:
				_set_facing_toward_point_continuous((player_node as Node2D).global_position)
			else:
				_stun_track_player = false
				_stun_track_node = null
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation()
		return

	match ai_state:
		AIState.NORMAL:
			_patrol_state_process(delta)
		AIState.COMBAT:
			_handle_combat_state(delta)
		AIState.EVASION:
			_handle_evasion_state(delta)
		AIState.DETECT:
			_handle_detect_state(delta)
	_update_animation()

# ----------------------------------------------------------------
func _reload_patrol_points() -> void:
	_patrol_points.clear()
	if patrol_root_path == NodePath("") or not has_node(patrol_root_path):
		return
	var root = get_node_or_null(patrol_root_path)
	if root == null:
		return
	var numbered := {}
	var numbers := []
	for child in root.get_children():
		if child is Node2D:
			var nm: String = child.name
			if nm.length() > 1 and nm.begins_with("p"):
				var suffix := nm.substr(1)
				if suffix.is_valid_int():
					var idx = suffix.to_int()
					numbered[idx] = child.global_position
					numbers.append(idx)
	if numbers.size() > 0:
		numbers.sort()
		for i in numbers:
			_patrol_points.append(numbered[i])
		return
	for child in root.get_children():
		if child is Node2D:
			_patrol_points.append(child.global_position)

# ----------------------------------------------------------------
func _patrol_state_process(delta: float) -> void:
	if _patrol_points.size() == 0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return
	var target_pos: Vector2 = _patrol_points[_patrol_index]
	if agent != null:
		_set_agent_target(target_pos)
	var next_pos = _get_agent_next_position_safe()
	var move_target: Vector2
	if agent != null:
		if next_pos != null:
			move_target = next_pos
		else:
			print("Enemy: agent has no path (patrol). Check NavigationRegion / agent navigation_layers.")
			velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
			move_and_slide()
			return
	else:
		move_target = target_pos

	if global_position.distance_to(target_pos) <= arrival_distance:
		global_position = target_pos
		velocity = Vector2.ZERO
		move_and_slide()

		# If we've reached the latest patrol point (last index), optionally set facing
		var is_last_point: bool = (_patrol_index == max(0, _patrol_points.size() - 1))
		if is_last_point:
			var facing_vec: Vector2 = Vector2.DOWN # default fallback
			match patrol_finish_facing:
				PatrolFinishFacing.AUTO:
					facing_vec = Vector2.DOWN
				PatrolFinishFacing.UP:
					facing_vec = Vector2.UP
				PatrolFinishFacing.DOWN:
					facing_vec = Vector2.DOWN
				PatrolFinishFacing.LEFT:
					facing_vec = Vector2.LEFT
				PatrolFinishFacing.RIGHT:
					facing_vec = Vector2.RIGHT
			_last_facing = facing_vec
			_update_animation()

		if _wait_timer <= 0.0:
			_wait_timer = wait_time_at_point
		_wait_timer -= delta
		if _wait_timer <= 0.0:
			_advance_patrol_index()
		return
	var dir = move_target - global_position
	if dir.length() > 0.1:
		_last_facing = dir.normalized()
	_move_toward_target(move_target, speed, delta)

# ----------------------------------------------------------------
func _move_toward_target(world_pos: Vector2, move_speed: float, delta: float) -> void:
	var dir = world_pos - global_position
	if dir.length() <= 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
	else:
		var desired = dir.normalized() * move_speed
		velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()

# ----------------------------------------------------------------
func _set_agent_target(target_pos: Vector2) -> void:
	if agent == null:
		return
	if agent.has_method("set_target_position"):
		agent.set_target_position(target_pos)
	elif "target_position" in agent:
		agent.target_position = target_pos
	elif agent.has_method("set_target_location"):
		agent.set_target_location(target_pos)

# ----------------------------------------------------------------
func _get_agent_next_position():
	if agent == null:
		return null
	if agent.has_method("get_next_path_position"):
		return agent.get_next_path_position()
	elif "next_path_position" in agent:
		return agent.next_path_position
	return null

# ----------------------------------------------------------------
func _advance_patrol_index() -> void:
	_wait_timer = 0.0
	if ping_patrol:
		if _forward:
			_patrol_index += 1
			if _patrol_index >= _patrol_points.size():
				_patrol_index = max(0, _patrol_points.size() - 2)
				_forward = false
		else:
			_patrol_index -= 1
			if _patrol_index < 0:
				_patrol_index = min(1, _patrol_points.size() - 1)
				_forward = true
	else:
		_patrol_index += 1
		if _patrol_index >= _patrol_points.size():
			if loop_patrol:
				_patrol_index = 0
			else:
				_patrol_index = _patrol_points.size() - 1

# ----------------------------------------------------------------
func _update_animation() -> void:
	if _sound_reaction_waiting:
		var dir_vec: Vector2 = _last_facing
		if velocity.length() > 5.0:
			dir_vec = velocity.normalized()
		var dir_str: String = "side"
		if abs(dir_vec.y) > abs(dir_vec.x):
			dir_str = "up" if dir_vec.y < 0.0 else "down"
		else:
			dir_str = "side"
		var stun_candidates: Array = ["stun_%s" % dir_str, "stun"]
		for s in stun_candidates:
			if _anim != null and _anim.sprite_frames != null and _anim.sprite_frames.has_animation(s):
				if _current_anim != s:
					_current_anim = s
					_anim.animation = s
					_anim.play()
				if dir_str == "side":
					_anim.flip_h = (dir_vec.x > 0.0)
				else:
					_anim.flip_h = false
				return

	if _anim == null:
		return
	if _anim.sprite_frames == null:
		return
	var dir_vec: Vector2 = _last_facing
	if velocity.length() > 5.0:
		dir_vec = velocity.normalized()
	var dir_str: String = "side"
	if abs(dir_vec.y) > abs(dir_vec.x):
		dir_str = "up" if dir_vec.y < 0.0 else "down"
	else:
		dir_str = "side"
	var state_str: String = "idle" if velocity.length() <= 5.0 else "walk"
	var anim_name: String = state_str + "_" + dir_str
	if is_stunned and _anim.sprite_frames.has_animation("stun"):
		if _current_anim != "stun":
			_current_anim = "stun"
			_anim.animation = "stun"
			_anim.play()
		return
	if is_hit and _anim.sprite_frames.has_animation("hit"):
		if _current_anim != "hit":
			_current_anim = "hit"
			_anim.animation = "hit"
			_anim.play()
		return
	if _anim.sprite_frames.has_animation(anim_name):
		if _current_anim != anim_name:
			_current_anim = anim_name
			_anim.animation = anim_name
			_anim.play()
	elif _anim.sprite_frames.has_animation(state_str):
		if _current_anim != state_str:
			_current_anim = state_str
			_anim.animation = state_str
			_anim.play()
	elif _anim.sprite_frames.has_animation("idle_side"):
		if _current_anim != "idle_side":
			_current_anim = "idle_side"
			_anim.animation = "idle_side"
			_anim.play()
	else:
		_current_anim = ""
	if dir_str == "side":
		_anim.flip_h = (dir_vec.x > 0.0)
	else:
		_anim.flip_h = false

# ----------------------------------------------------------------
func _get_player_stealth_multiplier(player_node: Node) -> float:
	if player_node == null or not is_instance_valid(player_node):
		return 1.0
	var p_state = null
	p_state = player_node.get("state")
	if p_state == null:
		return 1.0
	if int(p_state) == PLAYER_STATE_CRAWL:
		if player_node.has_method("is_in_grass") and player_node.is_in_grass():
			if stealth_grass_crawl_override_distance > 0.0 and sight_distance > 0.0:
				return stealth_grass_crawl_override_distance / sight_distance
			return stealth_grass_crawl_multiplier
	if int(p_state) == PLAYER_STATE_SNEAK:
		return stealth_sneak_multiplier
	if int(p_state) == PLAYER_STATE_CRAWL:
		return stealth_crawl_multiplier
	return 1.0

# ----------------------------------------------------------------
func _update_sight_visual_and_detection() -> void:
	if not sight_debug and sight_rays <= 0:
		return
	var origin_global: Vector2 = global_position
	if sight_origin != null and is_instance_valid(sight_origin):
		origin_global = sight_origin.global_position

	var forward = _last_facing
	if forward.length() == 0:
		forward = Vector2.DOWN
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(to_local(origin_global))
	var half_fov = deg_to_rad(sight_fov_deg * 0.5)

	var player_node := _get_player_node()
	var stealth_mult: float = _get_player_stealth_multiplier(player_node)
	var visual_mult: float = stealth_mult if apply_stealth_to_sight_visual else 1.0

	# If currently "hit", reduce effective sight to zero so the enemy cannot see the player.
	# We do this locally (don't mutate sight_distance).
	var effective_sight: float = 0.0
	if is_hit:
		effective_sight = 0.0
	else:
		effective_sight = sight_distance * visual_mult

	# Build sight polygon using effective_sight (will be degenerate if effective_sight == 0)
	for i in range(sight_rays + 1):
		var t = float(i) / float(sight_rays)
		var angle = lerp(-half_fov, half_fov, t)
		var dir = forward.rotated(angle).normalized()
		var target_global = origin_global + dir * effective_sight
		var params := PhysicsRayQueryParameters2D.new()
		params.from = origin_global
		params.to = target_global
		params.exclude = [self.get_rid()]
		params.collision_mask = LAYER_WALL
		var res = get_world_2d().direct_space_state.intersect_ray(params)
		var hit_point: Vector2 = target_global
		if res:
			hit_point = res.position
		pts.append(to_local(hit_point))

	# If hit, we explicitly prevent detection regardless of ray results
	var player_visible: bool = false
	if not is_hit and player_node != null:
		var player_pos: Vector2 = (player_node as Node2D).global_position
		var v = player_pos - origin_global
		var dist = v.length()
		var invisible_by_grass := false
		if player_node != null and player_node.has_method("is_crawling_in_grass"):
			invisible_by_grass = player_node.is_crawling_in_grass()
		if dist <= effective_sight and not invisible_by_grass:
			var angle_to_player = abs(forward.angle_to(v.normalized()))
			if angle_to_player <= half_fov:
				var params2 := PhysicsRayQueryParameters2D.new()
				params2.from = origin_global
				params2.to = player_pos
				params2.exclude = [self.get_rid()]
				params2.collision_mask = LAYER_WALL
				var res2 = get_world_2d().direct_space_state.intersect_ray(params2)
				if not res2:
					player_visible = true

	# Update sight polygon visual
	if _sight_polygon != null:
		_sight_polygon.polygon = pts
		_sight_polygon.color = sight_debug_color_alert if player_visible else sight_debug_color_clear
		_sight_polygon.visible = sight_debug

	# Handle player spotted/lost transitions as before
	if player_visible and not _last_player_visible:
		emit_signal("player_spotted", player_node)
		_on_player_spotted(player_node)
	elif not player_visible and _last_player_visible:
		emit_signal("player_lost")
		_on_player_lost()
	_last_player_visible = player_visible

# ----------------------------------------------------------------
# Helper to manage caution flag and emit UI signals (prevents repeated emits)
func _set_caution_active(active: bool) -> void:
	if active and not _caution_active:
		_caution_active = true
		print("caution start")
		# Emit caution started for UI / listeners; send self so UI knows which enemy triggered (or listen to group)
		emit_signal("caution_started", self)
	elif not active and _caution_active:
		_caution_active = false
		emit_signal("caution_ended", self)

# ----------------------------------------------------------------
func _on_player_spotted(player: Node) -> void:
	_last_known_player_pos = (player as Node2D).global_position
	_set_facing_toward_point_continuous(_last_known_player_pos)
	_update_animation()

	# Enter COMBAT (acts as CAUTION phase). Do not start countdown here.
	ai_state = AIState.COMBAT
	_pause_on_reach = true
	# mark caution active so UI/other systems can show CAUTION without countdown
	_set_caution_active(true)

	# boost sight immediately
	sight_distance = _original_sight_distance * combat_sight_multiplier

	# stop movement and set agent target
	velocity = Vector2.ZERO
	move_and_slide()
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)

	_set_facing_toward_point_continuous(_last_known_player_pos)

	# start stun/tracking as before
	_stun_track_player = true
	_stun_track_node = player

	# notify other enemies (they will enter COMBAT/caution as well)
	if get_tree() != null:
		get_tree().call_group("enemies", "_on_alert_received", _last_known_player_pos, self)

	# optional immediate stun of this enemy (respecting cooldown)
	stun(stun_duration)

# When player is lost from sight, transition from CAUTION/COMBAT to EVASION (countdown begins)
func _on_player_lost() -> void:
	# start EVASION countdown (do not turn off caution here; UI will remain until EVASION ends)
	_enter_evasion_state()

# ----------------------------------------------------------------
func _handle_combat_state(delta: float) -> void:
	# shooting cooldown
	_attack_timer = max(_attack_timer - delta, 0.0)

	var player_node := _get_player_node()
	# if player visible -> shoot / face
	if player_node != null and _last_player_visible:
		_last_known_player_pos = (player_node as Node2D).global_position
		# Keep CAUTION active while seeing player (UI can use _caution_active)
		_set_caution_active(true)
		_set_facing_toward_point_continuous(_last_known_player_pos)
		velocity = Vector2.ZERO
		move_and_slide()
		if _attack_timer <= 0.0:
			_shoot_at_player(player_node)
			_attack_timer = attack_cooldown
		return

	# Not currently seeing player, move to last known pos. When reached, pause then transition to EVASION.
	if global_position.distance_to(_last_known_player_pos) > arrival_distance:
		if agent != null:
			_set_agent_target(_last_known_player_pos)
			var np = _get_agent_next_position_safe()
			if np != null:
				_set_facing_toward_point_continuous(np)
				_move_toward_target(np, combat_move_speed, delta)
				return
			else:
				print("Enemy: agent has no path (combat follow).")
				velocity = Vector2.ZERO
				move_and_slide()
				return
		else:
			_set_facing_toward_point_continuous(_last_known_player_pos)
			_move_toward_target(_last_known_player_pos, combat_move_speed, delta)
			return

	# reached last known pos -> enter short pause (scan) then go to EVASION
	if _pause_on_reach:
		_pause_on_reach = false
		_combat_pause_timer = combat_pause_duration
		_scan_index = _closest_scan_index_to_vector(_last_facing)
		_scan_timer = combat_scan_interval
		velocity = Vector2.ZERO
		move_and_slide()
		_face_toward_point(_last_known_player_pos)
		return

	# during pause show scan animation; when pause ends -> start EVASION
	if _combat_pause_timer > 0.0:
		_combat_pause_timer = max(_combat_pause_timer - delta, 0.0)
		if combat_scan:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = combat_scan_interval
				_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
				_last_facing = _SCAN_DIRS[_scan_index]
				_update_animation()
		# if still in combat pause, do not start evasion yet
		if _combat_pause_timer > 0.0:
			return
	# pause finished -> transition to EVASION (start countdown there)
	_enter_evasion_state()

# ----------------------------------------------------------------
func _enter_evasion_state() -> void:
	_evasion_points.clear()
	_evasion_index = 0
	_evasion_time_left = evasion_duration
	_evasion_wait_timer = 0.0
	_evasion_waiting = false

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()

	var made_points: int = 0
	var attempts: int = 0
	var global_attempt_limit: int = max(12, evasion_point_count * 12)

	while made_points < evasion_point_count and attempts < global_attempt_limit:
		attempts += 1
		var ang: float = rng.randf() * TAU
		var r: float = lerp(evasion_min_radius, evasion_max_radius, rng.randf())
		var cand: Vector2 = _last_known_player_pos + Vector2(cos(ang), sin(ang)) * r
		if agent != null:
			# test path availability using agent
			_set_agent_target(cand)
			var np = _get_agent_next_position_safe()
			if np != null:
				_evasion_points.append(cand)
				made_points += 1
			else:
				# try few smaller radii before skipping
				var inner_try: int = 0
				var shr_r: float = r
				var found: bool = false
				while inner_try < 3 and not found:
					inner_try += 1
					shr_r *= 0.66
					cand = _last_known_player_pos + Vector2(cos(ang), sin(ang)) * shr_r
					_set_agent_target(cand)
					var np2 = _get_agent_next_position_safe()
					if np2 != null:
						_evasion_points.append(cand)
						made_points += 1
						found = true
						break
				if not found:
					print("Enemy: skipped evasion candidate (no path) attempt=", attempts)
		else:
			# fallback: accept point if no agent (may go outside nav)
			_evasion_points.append(cand)
			made_points += 1

	if _evasion_points.size() == 0:
		print("Enemy: failed to find evasion points -> returning to NORMAL")
		ai_state = AIState.NORMAL
		sight_distance = _original_sight_distance
		_set_caution_active(false)
		return

	_evasion_points.shuffle()

	# Now switch to EVASION and start counting down
	ai_state = AIState.EVASION
	# NOTE: keep caution active until evasion actually ends (UI requirement)
	# Do NOT call _set_caution_active(false) here.

	_set_facing_toward_point_continuous(_evasion_points[0])
	_update_animation()
	print("Enemy: entered EVASION (countdown started), points=", _evasion_points.size(), " duration=", _evasion_time_left)

# ----------------------------------------------------------------
func _handle_evasion_state(delta: float) -> void:
	# Countdown evasion timer
	_evasion_time_left = max(_evasion_time_left - delta, 0.0)

	# If player seen mid-evasion -> COMBAT (handled in _on_player_spotted)
	if _last_player_visible:
		return

	if _evasion_points.size() == 0:
		ai_state = AIState.NORMAL
		sight_distance = _original_sight_distance
		_set_caution_active(false)
		print("Enemy: evasion points empty -> NORMAL")
		return

	if _evasion_time_left <= 0.0:
		ai_state = AIState.NORMAL
		sight_distance = _original_sight_distance
		_set_caution_active(false)
		print("Enemy: evasion time expired -> NORMAL")
		return

	if _evasion_index >= _evasion_points.size():
		ai_state = AIState.NORMAL
		sight_distance = _original_sight_distance
		_set_caution_active(false)
		print("Enemy: completed evasion points -> NORMAL")
		return

	var target_point: Vector2 = _evasion_points[_evasion_index]

	# waiting at current point
	if _evasion_waiting:
		_evasion_wait_timer = max(_evasion_wait_timer - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation()
		if evasion_scan_interval > 0.0:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = evasion_scan_interval
				_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
				_last_facing = _SCAN_DIRS[_scan_index]
				_update_animation()
		if _evasion_wait_timer <= 0.0:
			_evasion_waiting = false
			_evasion_index += 1
		return

	# move using agent if possible
	if agent != null:
		_set_agent_target(target_point)
		var np = _get_agent_next_position_safe()
		if np != null:
			_set_facing_toward_point_continuous(np)
			_move_toward_target(np, evasion_move_speed, delta)
			# when close to actual evasion point
			if global_position.distance_to(target_point) <= arrival_distance:
				global_position = target_point
				velocity = Vector2.ZERO
				move_and_slide()
				_evasion_waiting = true
				_evasion_wait_timer = evasion_wait_at_point
				_scan_timer = evasion_scan_interval
				_scan_index = _closest_scan_index_to_vector(_last_facing)
				_update_animation()
			return
		else:
			# no path -> skip to avoid stuck
			print("Enemy: no agent path to evasion point, skipping index=", _evasion_index)
			_evasion_index += 1
			return
	else:
		# fallback direct movement when no agent
		var dir = target_point - global_position
		if dir.length() <= arrival_distance:
			global_position = target_point
			velocity = Vector2.ZERO
			move_and_slide()
			_evasion_waiting = true
			_evasion_wait_timer = evasion_wait_at_point
			_scan_timer = evasion_scan_interval
			_scan_index = _closest_scan_index_to_vector(_last_facing)
			_update_animation()
			return
		_last_facing = dir.normalized()
		_move_toward_target(target_point, evasion_move_speed, delta)
		return

# compatibility wrappers
func _enter_search_state() -> void:
	_enter_evasion_state()

func _handle_search_state(delta: float) -> void:
	_handle_evasion_state(delta)

# ----------------------------------------------------------------
func _on_alert_received(player_position: Vector2, instigator: Node = null) -> void:
	if ai_state == AIState.COMBAT:
		return
	if instigator == self:
		return

	_last_known_player_pos = player_position
	# go to COMBAT (CAUTION) but do not start countdown here
	ai_state = AIState.COMBAT
	_pause_on_reach = true
	_set_caution_active(true)
	sight_distance = _original_sight_distance * combat_sight_multiplier
	velocity = Vector2.ZERO
	move_and_slide()
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)
		elif "target_position" in agent:
			agent.target_position = _last_known_player_pos
	_set_facing_toward_point_continuous(_last_known_player_pos)
	_update_animation()

# ----------------------------------------------------------------
func stun(duration: float) -> void:
	if not _can_stun:
		return
	if is_stunned:
		return
	is_stunned = true
	_can_stun = false
	velocity = Vector2.ZERO
	move_and_slide()
	if agent != null:
		if agent.has_method("set_target_position"):
			agent.set_target_position(global_position)
		elif "target_position" in agent:
			agent.target_position = global_position
	if _anim != null and _anim.sprite_frames != null and _anim.sprite_frames.has_animation("stun"):
		_current_anim = "stun"
		_anim.animation = "stun"
		_anim.play()
	else:
		_update_animation()
	await get_tree().create_timer(duration).timeout
	if is_stunned:
		_end_stun()

func _end_stun() -> void:
	is_stunned = false
	_stun_track_player = false
	_stun_track_node = null
	_update_animation()
	var cd = lerp(stun_cooldown_min, stun_cooldown_max, randf())
	_stun_cooldown_timer = cd

func hit(duration: float) -> void:
	if is_stunned or is_hit:
		return
	is_hit = true
	velocity = Vector2.ZERO
	move_and_slide()
	if agent != null:
		if agent.has_method("set_target_position"):
			agent.set_target_position(global_position)
		elif "target_position" in agent:
			agent.target_position = global_position
	# เล่นอนิเมชัน "hit" หากมี มิฉะนั้นให้เรียกอัพเดตอนิเมชันปกติ
	if _anim != null and _anim.sprite_frames != null and _anim.sprite_frames.has_animation("hit"):
		_current_anim = "hit"
		_anim.animation = "hit"
		_anim.play()
	else:
		_update_animation()

	# Debug/info: when hit, hearing can be disabled (controlled by disable_hearing_while_hit)
	if disable_hearing_while_hit:
		print("Enemy:", name, "is hit -> hearing disabled for duration", duration)

	await get_tree().create_timer(duration).timeout
	if is_hit:
		_end_hit()

func _end_hit() -> void:
	is_hit = false
	_update_animation()
	if disable_hearing_while_hit:
		print("Enemy:", name, "hit ended -> hearing restored")

# ---------- Sound reaction ----------
func on_sound_detected(player: Node, sound_position: Vector2) -> void:
	# If stunned or currently in 'hit' state (and feature enabled), ignore sound detection.
	if is_stunned or (is_hit and disable_hearing_while_hit):
		# debug optional
		# print("Enemy:", name, "ignored sound (stunned/hit)")
		return
	if sound_position != Vector2.ZERO:
		_last_known_player_pos = sound_position
	elif player != null and is_instance_valid(player):
		_last_known_player_pos = (player as Node2D).global_position
	else:
		_last_known_player_pos = global_position

	# immediate CAUTION/COMBAT (no countdown)
	ai_state = AIState.COMBAT
	_pause_on_reach = true
	_set_caution_active(true)
	sight_distance = _original_sight_distance * combat_sight_multiplier
	velocity = Vector2.ZERO
	move_and_slide()
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)
		elif "target_position" in agent:
			agent.target_position = _last_known_player_pos
	_set_facing_toward_point_continuous(_last_known_player_pos)
	_update_animation()
	emit_signal("player_spotted", player)
	if get_tree() != null:
		get_tree().call_group("enemies", "_on_alert_received", _last_known_player_pos, self)

# ----------------------------------------------------------------
func _handle_detect_state(delta: float) -> void:
	if agent != null:
		_set_agent_target(_last_known_player_pos)
		var np = _get_agent_next_position_safe()
		if np != null:
			_set_facing_toward_point_continuous(np)
			_move_toward_target(np, speed, delta)
			if global_position.distance_to(_last_known_player_pos) <= arrival_distance:
				_enter_evasion_state()
				_update_animation()
			return
		else:
			print("Enemy: agent has no path (detect).")
			velocity = Vector2.ZERO
			move_and_slide()
			return

	if global_position.distance_to(_last_known_player_pos) > arrival_distance:
		_set_facing_toward_point_continuous(_last_known_player_pos)
		_move_toward_target(_last_known_player_pos, speed, delta)
		return
	_enter_evasion_state()
	_update_animation()

func _get_player_node() -> Node:
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		return arr[0]
	return null

# ---------- Shooting helpers ----------
func _shoot_at_player(player_node: Node) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	var target_pos = _get_player_aim_position(player_node)
	_shoot_at_position(target_pos)

func _shoot_at_position(target_pos: Vector2) -> void:
	var origin = global_position
	var muzzle_rot = 0.0
	if muzzle != null and is_instance_valid(muzzle):
		origin = muzzle.global_position
		muzzle_rot = muzzle.global_rotation
	elif sight_origin != null and is_instance_valid(sight_origin):
		origin = sight_origin.global_position

	var spawn_pos = origin
	if muzzle != null and is_instance_valid(muzzle):
		spawn_pos = origin + muzzle_offset.rotated(muzzle_rot)
	else:
		spawn_pos = origin + muzzle_offset.rotated(_last_facing.angle() if _last_facing.length() > 0 else 0.0)

	if projectile_scene == null:
		emit_signal("shoot_at", target_pos)
		return

	var inst = projectile_scene.instantiate()
	inst.global_position = spawn_pos
	var dir = (target_pos - spawn_pos)
	if dir.length() == 0:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	if inst.has_method("launch"):
		inst.launch(dir, projectile_speed, self)
	else:
		if inst.has_method("set_linear_velocity"):
			inst.set_linear_velocity(dir * projectile_speed)
		elif "linear_velocity" in inst:
			inst.linear_velocity = dir * projectile_speed
		elif "velocity" in inst:
			inst.velocity = dir * projectile_speed
		elif inst.has_method("set_velocity"):
			inst.set_velocity(dir * projectile_speed)
		elif inst.has_method("set_direction"):
			inst.set_direction(dir)
		if "shooter" in inst:
			inst.set("shooter", self)
		elif inst.has_method("set_shooter"):
			inst.set_shooter(self)
		elif "_shooter" in inst:
			inst._shooter = self

	var root = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	root.add_child(inst)
	emit_signal("shoot_at", target_pos)

# ---------- Player aim helpers ----------
func _get_player_hurtbox_center(player_node: Node) -> Vector2:
	if player_node == null or not is_instance_valid(player_node):
		return Vector2.ZERO
	if player_node.has_method("get_hurtbox_center"):
		var v = player_node.get_hurtbox_center()
		if typeof(v) == TYPE_VECTOR2:
			return v
	if player_node.has_node("Hurtbox"):
		var hb = player_node.get_node("Hurtbox")
		var active_shapes: Array = []
		for ch in hb.get_children():
			if ch is CollisionShape2D:
				if not ch.disabled:
					active_shapes.append(ch)
		if active_shapes.size() > 0:
			if active_shapes.size() == 1:
				return (active_shapes[0] as CollisionShape2D).global_position
			var sum = Vector2.ZERO
			for s in active_shapes:
				sum += (s as CollisionShape2D).global_position
			return sum / float(active_shapes.size())
		var found = _find_collisionshape_in_children(hb)
		if found != null:
			return found.global_position
	var found_any = _find_collisionshape_in_children(player_node)
	if found_any != null:
		return found_any.global_position
	if player_node.has_node("Aim"):
		return (player_node.get_node("Aim") as Node2D).global_position
	if player_node.has_node("AimPoint"):
		return (player_node.get_node("AimPoint") as Node2D).global_position
	if player_node.has_method("get_aim_point"):
		var ap = player_node.get_aim_point()
		if typeof(ap) == TYPE_VECTOR2:
			return ap
	if player_node is Node2D:
		return (player_node as Node2D).global_position
	return Vector2.ZERO

func _find_collisionshape_in_children(root: Node) -> CollisionShape2D:
	if root == null or not is_instance_valid(root):
		return null
	for child in root.get_children():
		if not is_instance_valid(child):
			continue
		if child is CollisionShape2D:
			return child as CollisionShape2D
		var sub = _find_collisionshape_in_children(child)
		if sub != null:
			return sub
	return null

func _get_player_aim_position(player_node: Node) -> Vector2:
	var hb = _get_player_hurtbox_center(player_node)
	if hb != Vector2.ZERO:
		return hb
	if player_node == null or not is_instance_valid(player_node):
		return Vector2.ZERO
	if player_node.has_node("Aim"):
		return (player_node.get_node("Aim") as Node2D).global_position
	if player_node.has_node("AimPoint"):
		return (player_node.get_node("AimPoint") as Node2D).global_position
	if player_node.has_method("get_aim_point"):
		var ap = player_node.get_aim_point()
		if typeof(ap) == TYPE_VECTOR2:
			return ap
	if player_node is Node2D:
		return (player_node as Node2D).global_position
	return Vector2.ZERO

# ----------------------------------------------------------------
func _on_nav_timer_timeout() -> void:
	pass

# ----------------------------------------------------------------
# Utility facing helpers
func _face_toward_point(world_point: Vector2) -> void:
	var v = world_point - global_position
	if v.length() == 0:
		return
	if abs(v.x) > abs(v.y):
		_last_facing = Vector2.LEFT if v.x < 0 else Vector2.RIGHT
	else:
		_last_facing = Vector2.UP if v.y < 0 else Vector2.DOWN
	_update_animation()

func _set_facing_toward_point_continuous(world_point: Vector2) -> void:
	var v = world_point - global_position
	if v.length() == 0:
		return
	_last_facing = v.normalized()

func _closest_scan_index_to_vector(vec: Vector2) -> int:
	if vec.length() == 0:
		return 0
	var best = 0
	var bestdot = -2.0
	for i in range(_SCAN_DIRS.size()):
		var d = _SCAN_DIRS[i].dot(vec.normalized())
		if d > bestdot:
			bestdot = d
			best = i
	return best

# End of file
