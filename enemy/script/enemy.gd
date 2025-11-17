extends CharacterBody2D
class_name Enemy

# Movement / patrol config
@export var speed: float = 120.0
@export var acceleration: float = 1400.0
@export var arrival_distance: float = 8.0
@export var wait_time_at_point: float = 0.1

@export var patrol_root_path: NodePath = NodePath("")   # Node that contains patrol points
@export var loop_patrol: bool = true
@export var ping_patrol: bool = false

# -----------------------
# SIGHT / DETECTION CONFIG
# -----------------------
# Set this constant to the bit for your "walls" physics layer (Project Settings -> Physics 2D -> Layer Names)
const LAYER_WALL: int = 1 << 0  # change bit if "walls" is on another layer

@export var sight_distance: float = 220.0
@export var sight_fov_deg: float = 90.0      # cone total angle (degrees)
@export var sight_rays: int = 36            # resolution of cone (more = smoother polygon)
@export var sight_debug: bool = true        # show debug polygon
@export var sight_debug_color_clear: Color = Color(0, 1, 0, 0.18)   # green when nothing seen
@export var sight_debug_color_alert: Color = Color(1, 0, 0, 0.25)   # red when player visible

# ALERT behavior tuning
@export var alert_pause_duration: float = 1.0      # pause time when reached last seen pos
@export var alert_search_duration: float = 10.0    # time to keep searching before returning to normal
@export var alert_sight_multiplier: float = 1.5    # multiply sight_distance while in Alert
@export var alert_move_speed: float = 160.0        # speed when moving toward last seen pos

# Scan (look-around) while paused / searching
@export var alert_scan: bool = true                # enable look-around during pause & search
@export var alert_scan_interval: float = 0.45      # seconds between cardinal direction switches while scanning

# -----------------------
# runtime state / AI
# -----------------------
enum AIState { NORMAL, ALERT }
var ai_state: int = AIState.NORMAL

var _patrol_points: Array = []
var _patrol_index: int = 0
var _forward: bool = true
var _wait_timer: float = 0.0

# last facing used for animation; while moving it can be a normalized vector,
# when paused/reached it will be snapped to cardinal directions by _face_toward_point()
var _last_facing: Vector2 = Vector2.DOWN

# optional navigation agent (child node "Agent")
@onready var agent: NavigationAgent2D = get_node_or_null("Agent") as NavigationAgent2D
# optional AnimatedSprite2D (child node "AnimatedSprite2D")
@onready var _anim: AnimatedSprite2D = get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
var _current_anim: String = ""

# Sight debug polygon child (Polygon2D). If not present we create one at runtime (child named "SightCone").
@onready var _sight_polygon: Polygon2D = get_node_or_null("SightCone") as Polygon2D

# STUN / HURT state
var is_stunned: bool = false

# alert runtime vars
var _original_sight_distance: float = 0.0
var _alert_pause_timer: float = 0.0      # used when pausing after reaching last seen pos
var _alert_search_timer: float = 0.0
var _last_known_player_pos: Vector2 = Vector2.ZERO
var _pause_on_reach: bool = true          # when true, begin pause + scan only after reaching last_known_player_pos

# scanning state
var _scan_index: int = 0
var _scan_timer: float = 0.0
const _SCAN_DIRS: Array = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]  # order of scanning

# Sight detection cache
var _last_player_visible: bool = false

# Signals to react externally
signal player_spotted(player)
signal player_lost()

func _ready() -> void:
	_original_sight_distance = sight_distance
	# create SightCone Polygon2D if requested and not present
	if sight_debug and _sight_polygon == null:
		_sight_polygon = Polygon2D.new()
		_sight_polygon.name = "SightCone"
		_sight_polygon.z_index = 100
		add_child(_sight_polygon)
	# default polygon empty
	if _sight_polygon:
		_sight_polygon.polygon = PackedVector2Array()

	_reload_patrol_points()
	# start at first point if any
	if _patrol_points.size() > 0:
		_patrol_index = 0
		_forward = true
		_wait_timer = 0.0

	# configure agent desired distance if agent exists
	if agent:
		if "target_desired_distance" in agent:
			agent.target_desired_distance = arrival_distance

func _physics_process(delta: float) -> void:
	# update sight -> draws cone and determines if player is visible (blocks by walls)
	_update_sight_visual_and_detection()

	# When stunned, remain stopped and show idle using last facing
	if is_stunned:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation()
		return

	# AI state handling
	match ai_state:
		AIState.NORMAL:
			_patrol_state_process(delta)
		AIState.ALERT:
			_handle_alert_state(delta)

	_update_animation()

# -----------------------
# Patrol movement
# -----------------------
func _reload_patrol_points() -> void:
	_patrol_points.clear()
	if patrol_root_path == NodePath(""):
		return
	if not has_node(patrol_root_path):
		return
	var root = get_node_or_null(patrol_root_path)
	if root == null:
		return

	var numbered := {}
	var numbers := []
	for child in root.get_children():
		if child is Node2D:
			var nm: String = (child as Node2D).name
			if nm.length() > 1 and nm.begins_with("p"):
				var suffix := nm.substr(1)
				if suffix.is_valid_int():
					var idx = suffix.to_int()
					numbered[idx] = (child as Node2D).global_position
					numbers.append(idx)

	if numbers.size() > 0:
		numbers.sort()
		for i in numbers:
			_patrol_points.append(numbered[i])
		return

	for child in root.get_children():
		if child is Node2D:
			_patrol_points.append((child as Node2D).global_position)

func _patrol_state_process(delta: float) -> void:
	if _patrol_points.size() == 0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return

	var target_pos: Vector2 = _patrol_points[_patrol_index]

	if agent != null:
		_set_agent_target(target_pos)

	var move_target: Vector2 = target_pos
	var next_pos = _get_agent_next_position()
	if next_pos != null:
		move_target = next_pos

	if global_position.distance_to(target_pos) <= arrival_distance:
		global_position = target_pos
		velocity = Vector2.ZERO
		move_and_slide()
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

func _move_toward_target(world_pos: Vector2, move_speed: float, delta: float) -> void:
	var dir = world_pos - global_position
	if dir.length() <= 1.0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
	else:
		var desired = dir.normalized() * move_speed
		velocity = velocity.move_toward(desired, acceleration * delta)
	move_and_slide()

func _set_agent_target(target_pos: Vector2) -> void:
	if agent == null:
		return
	if agent.has_method("set_target_position"):
		agent.set_target_position(target_pos)
	else:
		if "target_position" in agent:
			agent.target_position = target_pos
		else:
			if agent.has_method("set_target_location"):
				agent.set_target_location(target_pos)

func _get_agent_next_position():
	if agent == null:
		return null
	if agent.has_method("get_next_path_position"):
		return agent.get_next_path_position()
	if "next_path_position" in agent:
		return agent.next_path_position
	return null

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

# -------------------
# Animation helper
# -------------------
func _update_animation() -> void:
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

	if _anim.sprite_frames.has_animation(anim_name):
		if _current_anim != anim_name:
			_current_anim = anim_name
			_anim.animation = anim_name
			_anim.play()
	else:
		if _anim.sprite_frames.has_animation(state_str):
			if _current_anim != state_str:
				_current_anim = state_str
				_anim.animation = state_str
				_anim.play()
		else:
			var fallback = "idle_side"
			if _anim.sprite_frames.has_animation(fallback):
				if _current_anim != fallback:
					_current_anim = fallback
					_anim.animation = fallback
					_anim.play()
			else:
				_current_anim = ""

	if dir_str == "side":
		_anim.flip_h = (dir_vec.x > 0.0)
	else:
		_anim.flip_h = false

# -------------------
# SIGHT / DEBUG: build cone polygon using raycasts and test player visibility
# -------------------
func _update_sight_visual_and_detection() -> void:
	# if debug disabled and we don't need detection, skip
	if not sight_debug and sight_rays <= 0:
		return

	# use last facing (so standing still retains a direction)
	var forward = _last_facing
	if forward.length() == 0:
		forward = Vector2.DOWN

	# build polygon points; first point is local origin
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)

	# compute half fov
	var half_fov = deg_to_rad(sight_fov_deg * 0.5)

	# gather endpoints clipped by walls
	var global_points: Array = []
	for i in range(sight_rays + 1):
		var t = float(i) / float(sight_rays)
		var angle = lerp(-half_fov, half_fov, t)
		var dir = forward.rotated(angle).normalized()
		var target_global = global_position + dir * sight_distance

		# raycast for walls only
		var params := PhysicsRayQueryParameters2D.new()
		params.from = global_position
		params.to = target_global
		params.exclude = [self]
		params.collision_mask = LAYER_WALL
		var res = get_world_2d().direct_space_state.intersect_ray(params)
		var hit_point: Vector2 = target_global
		if res:
			hit_point = res.position
		global_points.append(hit_point)
		pts.append(to_local(hit_point))

	# check player visibility: angle + distance + unobstructed by walls
	var player_visible: bool = false
	var player_node := _get_player_node()
	if player_node != null:
		var player_pos: Vector2 = (player_node as Node2D).global_position
		var v = player_pos - global_position
		var dist = v.length()
		if dist <= sight_distance:
			# check angle using angle_to (signed) and absolute
			var angle_to_player = abs(forward.angle_to(v.normalized()))
			if angle_to_player <= half_fov:
				# check walls between enemy and player
				var params2 := PhysicsRayQueryParameters2D.new()
				params2.from = global_position
				params2.to = player_pos
				params2.exclude = [self]
				params2.collision_mask = LAYER_WALL
				var res2 = get_world_2d().direct_space_state.intersect_ray(params2)
				# if no wall hit -> player visible
				if not res2:
					player_visible = true

	# update polygon debug visual
	if _sight_polygon != null:
		_sight_polygon.polygon = pts
		_sight_polygon.color = sight_debug_color_alert if player_visible else sight_debug_color_clear
		_sight_polygon.visible = sight_debug

	# emit signals when visibility changes
	if player_visible and not _last_player_visible:
		emit_signal("player_spotted", player_node)
		_on_player_spotted(player_node)
	elif not player_visible and _last_player_visible:
		emit_signal("player_lost")
		_on_player_lost()
	_last_player_visible = player_visible

func _on_player_spotted(player: Node) -> void:
	# Transition into ALERT state and set to move to last known pos first
	var player_pos = (player as Node2D).global_position
	_last_known_player_pos = player_pos

	# Immediately look toward the player (continuous facing) so the enemy "looks at" player on detection
	_set_facing_toward_point_continuous(player_pos)
	_update_animation()

	# enter ALERT state and prepare to move to last_known_player_pos first
	ai_state = AIState.ALERT
	# do NOT start the pause now; set pause to occur only after reaching the last known pos
	_pause_on_reach = true
	_alert_search_timer = alert_search_duration
	# extend sight range while alert
	sight_distance = _original_sight_distance * alert_sight_multiplier
	# stop current motion briefly then set agent target / move toward last known pos
	velocity = Vector2.ZERO
	move_and_slide()
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)
	# set facing while moving toward target
	_set_facing_toward_point_continuous(_last_known_player_pos)

func _on_player_lost() -> void:
	# nothing special — search timer will count down in alert state
	pass

# Alert-state behavior handler
func _handle_alert_state(delta: float) -> void:
	# If player becomes visible again (seen by sight update), update last_known position and reset search timer
	var player_node := _get_player_node()
	if player_node != null and _last_player_visible:
		var player_pos = (player_node as Node2D).global_position
		_last_known_player_pos = player_pos
		_alert_search_timer = alert_search_duration
		# set facing toward player continuously while moving
		_set_facing_toward_point_continuous(player_pos)
		# move toward current player pos quickly
		_move_toward_target(_last_known_player_pos, alert_move_speed, delta)
		return

	# If we have not reached last known pos yet, move toward it (this is the change: go there first)
	if global_position.distance_to(_last_known_player_pos) > arrival_distance:
		# update facing to point toward target while moving
		_set_facing_toward_point_continuous(_last_known_player_pos)
		_move_toward_target(_last_known_player_pos, alert_move_speed, delta)
		return
	else:
		# reached last known position
		# If we should pause/scan on reach, initialize pause/scanning
		if _pause_on_reach:
			_pause_on_reach = false
			_alert_pause_timer = alert_pause_duration
			# prepare scanning start index close to current facing
			_scan_index = _closest_scan_index_to_vector(_last_facing)
			_scan_timer = alert_scan_interval
			# stop moving and snap to a cardinal immediately (so animation shows)
			velocity = Vector2.ZERO
			move_and_slide()
			_face_toward_point(_last_known_player_pos)
			# now fall through to scanning / pause logic
		# If currently in pause (scanning) phase
		if _alert_pause_timer > 0.0:
			_alert_pause_timer = max(_alert_pause_timer - delta, 0.0)
			# scanning while paused
			if alert_scan:
				_scan_timer -= delta
				if _scan_timer <= 0.0:
					_scan_timer = alert_scan_interval
					_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
					_last_facing = _SCAN_DIRS[_scan_index]
					_update_animation()
			return

		# After pause/scanning finished, countdown overall search timer
		_alert_search_timer = max(_alert_search_timer - delta, 0.0)

		# Continue scanning during the entire search timer if enabled
		if alert_scan:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = alert_scan_interval
				_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
				_last_facing = _SCAN_DIRS[_scan_index]
				_update_animation()

		if _alert_search_timer <= 0.0:
			# search expired -> return to NORMAL
			ai_state = AIState.NORMAL
			# restore sight distance
			sight_distance = _original_sight_distance
			return
		# If still searching but not seeing player, remain at last known pos (facing is cardinal / scanning)
		return

# Face enemy in one of the 4 cardinal directions (up/down/left/right) toward a world point
func _face_toward_point(world_point: Vector2) -> void:
	var v = world_point - global_position
	if v.length() == 0:
		return
	# choose dominant axis and snap to cardinal
	if abs(v.x) > abs(v.y):
		_last_facing = Vector2.LEFT if v.x < 0 else Vector2.RIGHT
	else:
		_last_facing = Vector2.UP if v.y < 0 else Vector2.DOWN
	_update_animation()

# Set continuous facing vector toward a world point (used while moving)
func _set_facing_toward_point_continuous(world_point: Vector2) -> void:
	var v = world_point - global_position
	if v.length() == 0:
		return
	_last_facing = v.normalized()
	# animation will be refreshed in the main loop; do not force cardinal here

# return index in _SCAN_DIRS closest to given vector
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

# -------------------
# STUN / HURT API (updated)
# -------------------
func stun(duration: float) -> void:
	if is_stunned:
		return

	is_stunned = true
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
	_update_animation()

# -------------------
# Helpers
# -------------------
func _get_player_node() -> Node:
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		return arr[0]
	return null
