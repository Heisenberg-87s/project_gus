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


# ตัวช่วยสถานะ SEARCH (จำเป็นสำหรับ _enter_search_state และ _handle_search_state)
var _search_scan_cooldown: float = 5.0   # ทุก 5 วินาที เริ่มสแกน
var _search_scan_timer: float = 0.0
var _search_scan_index: int = 0
const _SEARCH_SCAN_DIRS: Array = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
var _search_is_scanning: bool = false
var _search_scan_dir_timer: float = 0.45

# -----------------------
# การตั้งค่าการมอง/การตรวจจับ
# -----------------------
const LAYER_WALL: int = 1 << 0  # เปลี่ยนบิตหากเลเยอร์ผนังต่างออกไป

@export var sight_distance: float = 220.0
@export var sight_fov_deg: float = 90.0
@export var sight_rays: int = 36
@export var sight_debug: bool = true
@export var sight_debug_color_clear: Color = Color(0, 1, 0, 0.18)
@export var sight_debug_color_alert: Color = Color(1, 0, 0, 0.25)

# การปรับแต่งพฤติกรรม COMBAT (เปลี่ยนจาก alert)
@export var combat_pause_duration: float = 1.0
@export var combat_search_duration: float = 10.0
@export var combat_sight_multiplier: float = 1.5
@export var combat_move_speed: float = 160.0

# สแกน (มองรอบๆ) ขณะหยุด/ค้นหา 
@export var combat_scan: bool = true
@export var combat_scan_interval: float = 0.45

# การปรับแต่ง STUN / คูลดาวน์
@export var stun_duration: float = 1.0                     # เวลาโดนสตั้นเมื่อตรวจเจอ (หยุด 1 วินาที)
@export var stun_cooldown_min: float = 8.0                 # คูลดาวน์ของเอฟเฟคสตั้นขั้นต่ำ (วินาที)
@export var stun_cooldown_max: float = 10.0                # คูลดาวน์ของเอฟเฟคสตั้นสูงสุด (วินาที)
var _stun_cooldown_timer: float = 0.0
var _can_stun: bool = true

# -----------------------
# สถานะรันไทม์ / AI
# -----------------------
enum AIState { NORMAL, COMBAT, SEARCH }
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

var _original_sight_distance: float = 0.0
var _combat_pause_timer: float = 0.0
var _combat_search_timer: float = 0.0
var _last_known_player_pos: Vector2 = Vector2.ZERO
var _pause_on_reach: bool = true

var _scan_index: int = 0
var _scan_timer: float = 0.0
const _SCAN_DIRS: Array = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]

var _last_player_visible: bool = false

signal player_spotted(player)
signal player_lost()

func _ready() -> void:
	_original_sight_distance = sight_distance
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

func _physics_process(delta: float) -> void:
	# นับลดตัวจับเวลา stun/cooldown
	if _stun_cooldown_timer > 0.0:
		_stun_cooldown_timer = max(_stun_cooldown_timer - delta, 0.0)
		if _stun_cooldown_timer <= 0.0:
			_can_stun = true

	_update_sight_visual_and_detection()
	if is_stunned:
		velocity = Vector2.ZERO
		move_and_slide()
		_update_animation()
		return
	match ai_state:
		AIState.NORMAL:
			_patrol_state_process(delta)
		AIState.COMBAT:
			_handle_combat_state(delta)
		AIState.SEARCH:
			_handle_search_state(delta)
	_update_animation()

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

func _patrol_state_process(delta: float) -> void:
	if _patrol_points.size() == 0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return
	var target_pos: Vector2 = _patrol_points[_patrol_index]
	if agent != null:
		_set_agent_target(target_pos)
	var next_pos = _get_agent_next_position()
	var move_target: Vector2 = (next_pos as Vector2) if next_pos != null else target_pos
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
	elif "target_position" in agent:
		agent.target_position = target_pos
	elif agent.has_method("set_target_location"):
		agent.set_target_location(target_pos)

func _get_agent_next_position():
	if agent == null:
		return null
	if agent.has_method("get_next_path_position"):
		return agent.get_next_path_position()
	elif "next_path_position" in agent:
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

func _update_sight_visual_and_detection() -> void:
	if not sight_debug and sight_rays <= 0:
		return
	var forward = _last_facing
	if forward.length() == 0:
		forward = Vector2.DOWN
	var pts: PackedVector2Array = PackedVector2Array()
	pts.append(Vector2.ZERO)
	var half_fov = deg_to_rad(sight_fov_deg * 0.5)
	var global_points: Array = []
	for i in range(sight_rays + 1):
		var t = float(i) / float(sight_rays)
		var angle = lerp(-half_fov, half_fov, t)
		var dir = forward.rotated(angle).normalized()
		var target_global = global_position + dir * sight_distance
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
	var player_visible: bool = false
	var player_node := _get_player_node()
	if player_node != null:
		var player_pos: Vector2 = (player_node as Node2D).global_position
		var v = player_pos - global_position
		var dist = v.length()
		if dist <= sight_distance:
			var angle_to_player = abs(forward.angle_to(v.normalized()))
			if angle_to_player <= half_fov:
				var params2 := PhysicsRayQueryParameters2D.new()
				params2.from = global_position
				params2.to = player_pos
				params2.exclude = [self]
				params2.collision_mask = LAYER_WALL
				var res2 = get_world_2d().direct_space_state.intersect_ray(params2)
				if not res2:
					player_visible = true
	if _sight_polygon != null:
		_sight_polygon.polygon = pts
		_sight_polygon.color = sight_debug_color_alert if player_visible else sight_debug_color_clear
		_sight_polygon.visible = sight_debug
	if player_visible and not _last_player_visible:
		emit_signal("player_spotted", player_node)
		_on_player_spotted(player_node)
	elif not player_visible and _last_player_visible:
		emit_signal("player_lost")
		_on_player_lost()
	_last_player_visible = player_visible

func _on_player_spotted(player: Node) -> void:
	_last_known_player_pos = (player as Node2D).global_position
	_set_facing_toward_point_continuous(_last_known_player_pos)
	_update_animation()
	ai_state = AIState.COMBAT
	_pause_on_reach = true
	_combat_search_timer = combat_search_duration
	sight_distance = _original_sight_distance * combat_sight_multiplier
	velocity = Vector2.ZERO
	move_and_slide()
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)
	_set_facing_toward_point_continuous(_last_known_player_pos)
	# เรียกสตั้น แต่เฉพาะเมื่อคูลดาวน์อนุญาต
	stun(stun_duration)

func _on_player_lost() -> void:
	pass

func _handle_combat_state(delta: float) -> void:
	var player_node := _get_player_node()
	if player_node != null and _last_player_visible:
		_last_known_player_pos = (player_node as Node2D).global_position
		_combat_search_timer = combat_search_duration
		_set_facing_toward_point_continuous(_last_known_player_pos)
		_move_toward_target(_last_known_player_pos, combat_move_speed, delta)
		return
	if global_position.distance_to(_last_known_player_pos) > arrival_distance:
		_set_facing_toward_point_continuous(_last_known_player_pos)
		_move_toward_target(_last_known_player_pos, combat_move_speed, delta)
		return
	if _pause_on_reach:
		_pause_on_reach = false
		_combat_pause_timer = combat_pause_duration
		_scan_index = _closest_scan_index_to_vector(_last_facing)
		_scan_timer = combat_scan_interval
		velocity = Vector2.ZERO
		move_and_slide()
		_face_toward_point(_last_known_player_pos)
	if _combat_pause_timer > 0.0:
		_combat_pause_timer = max(_combat_pause_timer - delta, 0.0)
		if combat_scan:
			_scan_timer -= delta
			if _scan_timer <= 0.0:
				_scan_timer = combat_scan_interval
				_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
				_last_facing = _SCAN_DIRS[_scan_index]
				_update_animation()
		return
	_combat_search_timer = max(_combat_search_timer - delta, 0.0)
	if combat_scan:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = combat_scan_interval
			_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
			_last_facing = _SCAN_DIRS[_scan_index]
			_update_animation()
	if _combat_search_timer <= 0.0:
		ai_state = AIState.NORMAL
		sight_distance = _original_sight_distance
		return

# ---------- ตัวจัดการสถานะ SEARCH ----------
func _enter_search_state() -> void:
	# เริ่มการค้นหา: ใช้ combat_search_duration และเริ่มสแกน
	_combat_search_timer = combat_search_duration
	_scan_timer = combat_scan_interval
	_scan_index = _closest_scan_index_to_vector(_last_facing)
	_search_is_scanning = false
	ai_state = AIState.SEARCH

func _handle_search_state(delta: float) -> void:
	# ถ้าผู้เล่นกลับมา ให้กลับไปสถานะ COMBAT
	var player_node := _get_player_node()
	if player_node != null and _last_player_visible:
		ai_state = AIState.COMBAT
		_combat_search_timer = combat_search_duration
		return

	# นับถอยหลังตัวจับเวลา search และสแกนแบบง่าย (หมุนทิศทาง)
	_combat_search_timer = max(_combat_search_timer - delta, 0.0)
	if combat_scan:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = combat_scan_interval
			_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
			_last_facing = _SCAN_DIRS[_scan_index]
			_update_animation()

	# ถ้าเวลาค้นหาหมด ให้กลับไปลาดตระเวน
	if _combat_search_timer <= 0.0:
		ai_state = AIState.NORMAL
		sight_distance = _original_sight_distance
# ---------- จบตัวจัดการ SEARCH ----------
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

func stun(duration: float) -> void:
	# อนุญาตให้สตั้นเฉพาะเมื่อคูลดาวน์อนุญาต
	if not _can_stun:
		return
	if is_stunned:
		return
	is_stunned = true
	# ป้องกันการสตั้นซ้ำจนกว่าจะตั้งคูลดาวน์หลังสตั้นจบ
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
	_update_animation()
	# ตั้งตัวจับเวลาคูลดาวน์ (สุ่มระหว่างค่าน้อยสุด/มากสุด)
	var cd = lerp(stun_cooldown_min, stun_cooldown_max, randf())
	_stun_cooldown_timer = cd
	# _can_stun จะถูกเปิดอีกครั้งใน _physics_process เมื่อ timer เป็น 0

func _get_player_node() -> Node:
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		return arr[0]
	return null
