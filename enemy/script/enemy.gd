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
const LAYER_VENT: int = 128 << 7


@export var sight_distance: float = 300.0
@export var sight_fov_deg: float = 120.0
@export var sight_rays: int = 36
@export var sight_debug: bool = true
@export var sight_debug_color_clear: Color = Color(0, 1, 0, 0.18)
@export var sight_debug_color_alert: Color = Color(1, 0, 0, 0.25)

# Optional: allow specifying a NodePath in the inspector for the sight origin.
# If a child Node2D named "SightOrigin" exists, it will be used automatically.
@export var sight_origin_path: NodePath = NodePath("")
@onready var sight_origin: Marker2D = get_node_or_null("SightOrigin") as Marker2D

# Muzzle (ใหม่) - กำหนดตำแหน่งปากกระบอกปืนเป็น Marker2D
@export var muzzle_path: NodePath = NodePath("")   # ถ้าตั้ง path ไว้ จะใช้ node นั้นเป็น muzzle
var muzzle: Marker2D = null                        # ถูก resolved ใน _ready()

# การปรับแต่งพฤติกรรม COMBAT (เปลี่ยนจาก alert)
@export var combat_pause_duration: float = 0.6
@export var combat_search_duration: float = 10.0
@export var combat_sight_multiplier: float = 1.5
@export var combat_move_speed: float = 160.0

# -------- Stealth interaction (ใหม่) ----------
# เมื่อผู้เล่นอยู่ในสถานะ SNEAK หรือ CRAWL ให้ลดระยะการมองของศัตรูลง
@export var stealth_sneak_multiplier: float = 0.6
@export var stealth_crawl_multiplier: float = 0.3
# ถ้าเปิด จะลด polygon ที่แสดง (debug) ตาม stealth ด้วย มิฉะนั้น polygon แสดง sight_distance ปกติ
@export var apply_stealth_to_sight_visual: bool = true

# หมายเหตุ: player.gd กำหนด enum State ดังนี้: IDLE=0, WALK=1, RUN=2, SNEAK=3, CRAWL=4, PUNCH=5
const PLAYER_STATE_SNEAK: int = 3
const PLAYER_STATE_CRAWL: int = 4
# ----------------------------------------------

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
# เพิ่มการตอบสนองเสียง: หยุดชั่วคราว (stun-like), หันหน้าไปยังแหล่งกำเนิด แล้วค [...]
# -----------------------
@export var sound_reaction_pause: float = 0.35   # เวลาหยุดชั่วคราวเมื่อได้ยินเสียง (วินาที)
var _sound_reaction_timer: float = 0.0
var _sound_reaction_waiting: bool = false

# ---------- การยิง (ใหม่) ----------
# ถ้าใส่ projectile_scene จะ instance projectile เมื่อยิง
@export var attack_cooldown: float = 0.1   # วินาทีระหว่างการยิง
@export var projectile_scene: PackedScene
@export var muzzle_offset: Vector2 = Vector2.ZERO
@export var projectile_speed: float = 1000.0
var _attack_timer: float = 0.0
signal shoot_at(target_pos)

# -----------------------
# สถานะรันไทม์ / AI
# -----------------------
enum AIState { NORMAL, COMBAT, SEARCH, DETECT }
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
var is_hit: bool = false   # ใหม่: ถูกโจมตี (hit) ชั่วคราว (ต่างจาก stun)

var _original_sight_distance: float = 0.0
var _combat_pause_timer: float = 0.0
var _combat_search_timer: float = 0.0
var _last_known_player_pos: Vector2 = Vector2.ZERO
var _pause_on_reach: bool = true

var _scan_index: int = 0
var _scan_timer: float = 0.0
const _SCAN_DIRS: Array = [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]

var _last_player_visible: bool = false

# --- ใหม่: ตัวแปรสำหรับให้หันตามผู้เล่นขณะสตั้น ---
var _stun_track_player: bool = false
var _stun_track_node: Node = null

signal player_spotted(player)
signal player_lost()

# ----------------------------------------------------------------
# Helper: safe agent next position (returns null if agent has no path)
func _get_agent_next_position_safe():
	if agent == null:
		return null
	# Prefer method calls if available (handles API differences)
	if agent.has_method("get_next_path_position"):
		var np = agent.get_next_path_position()
		# Some implementations return Vector2.ZERO when no next - treat as none
		if np == Vector2.ZERO:
			return null
		return np
	elif "next_path_position" in agent:
		var np2 = agent.next_path_position
		if np2 == Vector2.ZERO:
			return null
		return np2
	return null

func _ready() -> void:
	_original_sight_distance = sight_distance
	# try to resolve sight_origin from exported path if not found by name
	if sight_origin == null and sight_origin_path != NodePath("") and has_node(sight_origin_path):
		sight_origin = get_node_or_null(sight_origin_path) as Node2D

	# Resolve muzzle: ถ้ามี child ชื่อ "Muzzle" ใช้เลย ถ้าไม่มีก็ลองใช้ muzzle_path
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
		# debug print about agent navigation layers (helpful if agent can't build path)
		if "navigation_layers" in agent:
			print("Enemy: Agent navigation_layers =", agent.navigation_layers)
		else:
			print("Enemy: Agent available but 'navigation_layers' property not found (check Godot version).")

func _physics_process(delta: float) -> void:
	# นับลดตัวจับเวลา stun/cooldown
	if _stun_cooldown_timer > 0.0:
		_stun_cooldown_timer = max(_stun_cooldown_timer - delta, 0.0)
		if _stun_cooldown_timer <= 0.0:
			_can_stun = true

	_update_sight_visual_and_detection()

	# หากกำลังรอการตอบสนองจากเสียง (face -> pause) ให้นับถอยหลัง และยังไม่ให้ AI หลุดไ [...]
	if _sound_reaction_waiting:
		_sound_reaction_timer = max(_sound_reaction_timer - delta, 0.0)
		velocity = Vector2.ZERO
		move_and_slide()
		# แสดงอนิเมชัน "stun" (ถ้ามี) ระหว่างรอ
		_update_animation()
		if _sound_reaction_timer <= 0.0:
			_sound_reaction_waiting = false
			# หลังจากรอเสร็จ ให้สั่ง agent ให้ตั้งเป้าตำแหน่งเสียง (ถ้ามี) เพื่อเริ่มเด[...]
			if agent:
				if agent.has_method("set_target_position"):
					agent.set_target_position(_last_known_player_pos)
				elif "target_position" in agent:
					agent.target_position = _last_known_player_pos
		return

	# ถ้าอยู่ในสถานะ stunned หรือ ถูก hit (is_hit) ให้หยุดทำงานชั่วคราว
	if is_stunned or is_hit:
		# ถ้าเป็นสตั้นและเปิดโหมดติดตามผู้เล่น ให้หันไปหาผู้เล่นทุกเฟรมจนกว่[...]
		if is_stunned and _stun_track_player:
			var player_node := (_stun_track_node if is_instance_valid(_stun_track_node) else _get_player_node())
			if player_node != null and _last_player_visible:
				_set_facing_toward_point_continuous((player_node as Node2D).global_position)
			else:
				# ถ้าผู้เล่นไม่อยู่ในสายตาแล้ว ให้ยกเลิกการติดตาม
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
		AIState.SEARCH:
			_handle_search_state(delta)
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
# Patrol: use agent path when available. If agent exists but has no path, stop (avoid running through walls).
func _patrol_state_process(delta: float) -> void:
	if _patrol_points.size() == 0:
		velocity = velocity.move_toward(Vector2.ZERO, acceleration * delta)
		move_and_slide()
		return
	var target_pos: Vector2 = _patrol_points[_patrol_index]
	if agent != null:
		_set_agent_target(target_pos)
	var next_pos = _get_agent_next_position_safe()
	# If agent exists, require a next_path_position before moving; otherwise stop and wait for path
	var move_target: Vector2
	if agent != null:
		if next_pos != null:
			move_target = next_pos
		else:
			# No path yet — don't move straight to target_pos (would go through obstacles).
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
	# ถ้ากำลังรอการตอบสนองจากเสียง ให้แสดงอนิเมชัน "stun" หากมี (และให้หันตาม _last[...]
	if _sound_reaction_waiting:
		# ใช้ logic เดียวกับการเลือก animation ปกติ แต่พยายามหา stun_{dir} ก่อน
		var dir_vec: Vector2 = _last_facing
		if velocity.length() > 5.0:
			dir_vec = velocity.normalized()
		var dir_str: String = "side"
		if abs(dir_vec.y) > abs(dir_vec.x):
			dir_str = "up" if dir_vec.y < 0.0 else "down"
		else:
			dir_str = "side"
		# directional stun animation first
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
	# ถ้ามี animation "hit" หรือ "stun" ให้แสดงตามสถานะ
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
# Returns multiplier to apply to sight distance based on player's stealth state.
# Default is 1.0 (no reduction). Uses the player's `state` property (player.gd State enum).
func _get_player_stealth_multiplier(player_node: Node) -> float:
	if player_node == null or not is_instance_valid(player_node):
		return 1.0
	var p_state = null
	# Use generic get() so this is tolerant if the player node is a different script/class.
	# get() returns null if property not present.
	p_state = player_node.get("state")
	if p_state == null:
		return 1.0
	if int(p_state) == PLAYER_STATE_SNEAK:
		return stealth_sneak_multiplier
	elif int(p_state) == PLAYER_STATE_CRAWL:
		return stealth_crawl_multiplier
	return 1.0

# ----------------------------------------------------------------
func _update_sight_visual_and_detection() -> void:
	if not sight_debug and sight_rays <= 0:
		return
	# Use sight origin if provided (child Node2D "SightOrigin" or via sight_origin_path), otherwise use enemy center
	var origin_global: Vector2 = global_position
	if sight_origin != null and is_instance_valid(sight_origin):
		origin_global = sight_origin.global_position

	var forward = _last_facing
	if forward.length() == 0:
		forward = Vector2.DOWN
	var pts: PackedVector2Array = PackedVector2Array()
	# polygon first point should be the origin (in enemy-local coordinates)
	pts.append(to_local(origin_global))
	var half_fov = deg_to_rad(sight_fov_deg * 0.5)

	# Determine player-based stealth multiplier (only for detection)
	var player_node := _get_player_node()
	var stealth_mult: float = _get_player_stealth_multiplier(player_node)
	# if apply_stealth_to_sight_visual is true, shrink the debug polygon as well
	var visual_mult: float = stealth_mult if apply_stealth_to_sight_visual else 1.0
	var visual_range: float = sight_distance * visual_mult

	# build polygon using visual_range (so polygon reflects stealth optionally)
	var global_points: Array = []
	for i in range(sight_rays + 1):
		var t = float(i) / float(sight_rays)
		var angle = lerp(-half_fov, half_fov, t)
		var dir = forward.rotated(angle).normalized()
		var target_global = origin_global + dir * visual_range
		var params := PhysicsRayQueryParameters2D.new()
		params.from = origin_global
		params.to = target_global
		# use RID exclude in Godot 4
		params.exclude = [self.get_rid()]
		params.collision_mask = LAYER_WALL
		var res = get_world_2d().direct_space_state.intersect_ray(params)
		var hit_point: Vector2 = target_global
		if res:
			hit_point = res.position
		global_points.append(hit_point)
		pts.append(to_local(hit_point))

	# Detection: use effective sight (sight_distance * stealth_mult)
	var effective_sight: float = sight_distance * stealth_mult

	var player_visible: bool = false
	if player_node != null:
		var player_pos: Vector2 = (player_node as Node2D).global_position
		var v = player_pos - origin_global
		var dist = v.length()
		if dist <= effective_sight:
			var angle_to_player = abs(forward.angle_to(v.normalized()))
			if angle_to_player <= half_fov:
				var params2 := PhysicsRayQueryParameters2D.new()
				params2.from = origin_global
				# Raycast to player's position (we already limited by effective_sight)
				params2.to = player_pos
				# use RID exclude
				params2.exclude = [self.get_rid()]
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

# ----------------------------------------------------------------
func _on_player_spotted(player: Node) -> void:
	_last_known_player_pos = (player as Node2D).global_position
	_set_facing_toward_point_continuous(_last_known_player_pos)
	_update_animation()
	ai_state = AIState.COMBAT
	_pause_on_reach = true
	_combat_search_timer = combat_search_duration
	# note: sight_distance may be modified in combat; we keep effective detection logic
	sight_distance = _original_sight_distance * combat_sight_multiplier
	velocity = Vector2.ZERO
	move_and_slide()
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)
	_set_facing_toward_point_continuous(_last_known_player_pos)
	# เรียกสตั้น แต่เฉพาะเมื่อคูลดาว์นอนุญาต
	# เริ่มติดตามผู้เล่นขณะสตั้น
	_stun_track_player = true
	_stun_track_node = player
	stun(stun_duration)

func _on_player_lost() -> void:
	pass

# ----------------------------------------------------------------
# Combat: use agent's next path positions. If agent exists but has no path, stop and print debug.
func _handle_combat_state(delta: float) -> void:
	# ลดตัวจับเวลาการยิง
	_attack_timer = max(_attack_timer - delta, 0.0)

	var player_node := _get_player_node()
	# If player visible -> shoot (don't immediately path toward them; instead fire while visible).
	if player_node != null and _last_player_visible:
		_last_known_player_pos = (player_node as Node2D).global_position
		_combat_search_timer = combat_search_duration
		# face player and stop moving; shoot on cooldown
		_set_facing_toward_point_continuous(_last_known_player_pos)
		velocity = Vector2.ZERO
		move_and_slide()
		# attack when ready
		if _attack_timer <= 0.0:
			_shoot_at_player(player_node)
			_attack_timer = attack_cooldown
		return

	# Not currently seeing player, move toward last known pos using path if available
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

	# reached last known pos -> enter pause/search
	if _pause_on_reach:
		_pause_on_reach = false
		_combat_pause_timer = combat_pause_duration
		_scan_index = _closest_scan_index_to_vector(_last_facing)
		_scan_timer = combat_scan_interval
		velocity = Vector2.ZERO
		move_and_slide()
		_face_toward_point(_last_known_player_pos)
		return

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
	# ตั้งค่าเหมือน COMBAT เพื่อให้ sprite หัน/แสดงผลเหมือนกัน
	_combat_search_timer = combat_search_duration
	_scan_timer = combat_scan_interval
	_scan_index = _closest_scan_index_to_vector(_last_facing)
	_search_is_scanning = false
	ai_state = AIState.SEARCH
	# อัพเดตอนิเมชันทันทีเพื่อให้ sprite หันตามทิศเริ่มต้นของการค้นหา
	_update_animation()

func _handle_search_state(delta: float) -> void:
	# ถ้าผู้เล่นกลับมา ให้กลับไปสถานะ COMBAT
	var player_node := _get_player_node()
	if player_node != null and _last_player_visible:
		ai_state = AIState.COMBAT
		_combat_search_timer = combat_search_duration
		return

	# นับถอยหลังตัวจับเวลา search และสแกนแบบเดียวกับ COMBAT (หมุนเป็นช่วงๆ)
	_combat_search_timer = max(_combat_search_timer - delta, 0.0)
	if combat_scan:
		_scan_timer -= delta
		if _scan_timer <= 0.0:
			_scan_timer = combat_scan_interval
			_scan_index = (_scan_index + 1) % _SCAN_DIRS.size()
			# เปลี่ยน _last_facing เป็นทิศที่จะสแกน (cardinal) เพื่อให้ animation/flip ถูกต้อง
			_last_facing = _SCAN_DIRS[_scan_index]
			_update_animation()

	# ถ้าเวลาค้นหาหมด ให้กลับไปลาดตระเวน (เหมือน COMBAT)
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
	# อนุญาตให้สตั้นเฉพาะเมื่อคูลดาว์นอนุญาต
	if not _can_stun:
		return
	if is_stunned:
		return
	is_stunned = true
	# ป้องกันการสตั้นซ้ำจนกว่าจะตั้งคูลดาว์นหลังสตั้นจบ
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
	# ยกเลิกการติดตามผู้เล่นเมื่อสตั้นจบ
	_stun_track_player = false
	_stun_track_node = null
	_update_animation()
	# ตั้งตัวจับเวลาคูลดาว์น (สุ่มระหว่างค่าน้อยสุด/มากสุด)
	var cd = lerp(stun_cooldown_min, stun_cooldown_max, randf())
	_stun_cooldown_timer = cd
	# _can_stun จะถูกเปิดอีกครั้งใน _physics_process เมื่อ timer เป็น 0

# ใหม่: ถูกโจมตี (hit) ชั่วคราว — หยุดการเคลื่อนที่/AI ชั่วคราว แต่ไม่เกี่ยวกั  [...]
func hit(duration: float) -> void:
	# หากกำลัง stun อยู่หรือกำลังถูก hit อยู่ ให้ข้าม
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
	await get_tree().create_timer(duration).timeout
	if is_hit:
		_end_hit()

func _end_hit() -> void:
	is_hit = false
	_update_animation()

# ---------- การตอบสนองต่อ "เสียง" (sound detection) ----------
# ฟังก์ชันที่ SoundArea จะเรียก: on_sound_detected(player, sound_position)
# และสำรองชื่ออื่น ๆ: investigate_sound(sound_pos, player), set_investigate_target(player), set_target(player)
func on_sound_detected(player: Node, sound_position: Vector2) -> void:
	# ถ้าโดนสตั้นจริง ๆ ให้ไม่ตอบสนองเสียง
	if is_stunned:
		return
	# บันทึกตำแหน่งเสียงหรือใช้ตำแหน่งผู้เล่นถ้าไม่มี
	if sound_position != Vector2.ZERO:
		_last_known_player_pos = sound_position
	elif player != null and is_instance_valid(player):
		_last_known_player_pos = (player as Node2D).global_position
	else:
		_last_known_player_pos = global_position

	# เปลี่ยนเป็น COMBAT ทันทีตามที่ขอ
	# ตั้งค่าเหมือน _on_player_spotted เพื่อให้พฤติกรรมการไล่/หันหน้าเหมือนการเห็นผู้  [...]
	ai_state = AIState.COMBAT
	_pause_on_reach = true
	_combat_search_timer = combat_search_duration
	sight_distance = _original_sight_distance * combat_sight_multiplier
	velocity = Vector2.ZERO
	move_and_slide()
	# ถ้ามี NavigationAgent ให้ตั้งเป้าตำแหน่งเสียงเลย
	if agent:
		if agent.has_method("set_target_position"):
			agent.set_target_position(_last_known_player_pos)
		elif "target_position" in agent:
			agent.target_position = _last_known_player_pos
	# หันหน้าตามตำแหน่งเสียง (continuous) และอัพเดตอนิเมชันทันที
	_set_facing_toward_point_continuous(_last_known_player_pos)
	_update_animation()
	# (ไม่เรียก stun โดยอัตโนมัติ — ถ้าต้องการให้สตั้นก่อน คอล์ฟังก์ชัน stun(stun_duration)  [... ]
	emit_signal("player_spotted", player)  # คงสัญญาณไว้ในกรณีระบบอื่นฟังอยู่

# ---------- จบการตอบสนองต่อ "เสียง" ----------
func _handle_detect_state(delta: float) -> void:
	# หากยังอยู่ในช่วงรอการตอบสนอง (handled earlier in _physics_process) จะไม่มาถึงที่นี่
	# เคลื่อนที่ไปยังตำแหน่งเสียง (_last_known_player_pos) ด้วยความเร็วปกติ
	if agent != null:
		_set_agent_target(_last_known_player_pos)
		var np = _get_agent_next_position_safe()
		if np != null:
			_set_facing_toward_point_continuous(np)
			_move_toward_target(np, speed, delta)
			# ถ้ามาถึงเป้าหมายจริง ๆ แล้วเปลี่ยนเป็น SEARCH
			if global_position.distance_to(_last_known_player_pos) <= arrival_distance:
				ai_state = AIState.SEARCH
				_enter_search_state()
				_update_animation()
			return
		else:
			print("Enemy: agent has no path (detect).")
			velocity = Vector2.ZERO
			move_and_slide()
			return

	# fallback if no agent
	if global_position.distance_to(_last_known_player_pos) > arrival_distance:
		_set_facing_toward_point_continuous(_last_known_player_pos)
		_move_toward_target(_last_known_player_pos, speed, delta)
		return
	ai_state = AIState.SEARCH
	_enter_search_state()
	_update_animation()

func _get_player_node() -> Node:
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		return arr[0]
	return null

# ---------- ฟังก์ชันยิง (แก้ให้ใช้ muzzle หากมี) ----------
func _shoot_at_player(player_node: Node) -> void:
	if player_node == null or not is_instance_valid(player_node):
		return
	var target_pos = _get_player_aim_position(player_node)
	_shoot_at_position(target_pos)

func _shoot_at_position(target_pos: Vector2) -> void:
	# origin: ถ้ามี muzzle ให้ใช้ muzzle.global_position, ถ้าไม่มีก็กลับไปใช้ sight_origin หรือ global_position
	var origin = global_position
	var muzzle_rot = 0.0
	if muzzle != null and is_instance_valid(muzzle):
		origin = muzzle.global_position
		muzzle_rot = muzzle.global_rotation
	elif sight_origin != null and is_instance_valid(sight_origin):
		origin = sight_origin.global_position

	# คำนวณตำแหน่ง spawn โดยใช้ muzzle_offset หมุนตาม muzzle (ถ้ามี)
	var spawn_pos = origin
	if muzzle != null and is_instance_valid(muzzle):
		spawn_pos = origin + muzzle_offset.rotated(muzzle_rot)
	else:
		# ถ้าไม่มี muzzle ให้หมุนตาม _last_facing เหมือนเดิม
		spawn_pos = origin + muzzle_offset.rotated(_last_facing.angle() if _last_facing.length() > 0 else 0.0)

	# สร้าง projectile
	if projectile_scene == null:
		emit_signal("shoot_at", target_pos)
		return

	var inst = projectile_scene.instantiate()
	inst.global_position = spawn_pos

	# มุ่งไปยัง target จากตำแหน่ง spawn
	var dir = (target_pos - spawn_pos)
	if dir.length() == 0:
		dir = Vector2.RIGHT
	dir = dir.normalized()

	# พยายามเรียกเมธอด launch ถ้ามี (จะตั้ง _shooter ใน projectile ได้)
	if inst.has_method("launch"):
		inst.launch(dir, projectile_speed, self)
	else:
		# fallback: ตั้งความเร็ว/linear_velocity ตามชื่อ property/เมธอดยอดนิยม
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
		# พยายามตั้ง shooter ถ้ามี property / setter
		if "shooter" in inst:
			inst.set("shooter", self)
		elif inst.has_method("set_shooter"):
			inst.set_shooter(self)
		else:
			# หาก projectile มีตัวแปรภายในชื่อ _shooter (เช่นตัวอย่าง enemy_bullet.gd) เราตั้งตรง ๆ ได้ (ไม่แนะนำแต่ใช้ได้)
			if "_shooter" in inst:
				inst._shooter = self

	# เพิ่มลงใน scene tree (current scene หรือ root)
	var root = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	root.add_child(inst)

	# ส่งสัญญาณเพื่อให้ระบบอื่น ๆ ฟังได้ด้วย
	emit_signal("shoot_at", target_pos)

# ---------- ฟังก์ชันหา aim/hurtbox ของ player ----------
# Helper: หา center ของ hurtbox ใน node ของ player (fallbacks: child Aim -> get_aim_point() -> global_position)
func _get_player_hurtbox_center(player_node: Node) -> Vector2:
	if player_node == null or not is_instance_valid(player_node):
		return Vector2.ZERO

	# 1) ถ้าผู้เล่นมีเมธอดเฉพาะ ให้เรียกใช้เลย (รองรับ API ฝั่ง player)
	if player_node.has_method("get_hurtbox_center"):
		var v = player_node.get_hurtbox_center()
		if typeof(v) == TYPE_VECTOR2:
			return v

	# 2) ถ้ามี child ชื่อ "Hurtbox" ให้ค้นหา CollisionShape2D ภายใน (เลือกอันที่ enabled)
	if player_node.has_node("Hurtbox"):
		var hb = player_node.get_node("Hurtbox")
		# เก็บ CollisionShape2D ที่ไม่ถูก disabled
		var active_shapes: Array = []
		for ch in hb.get_children():
			if ch is CollisionShape2D:
				# CollisionShape2D มี property `disabled` (Godot 4) — ตรวจว่าถูก enable อยู่
				if not ch.disabled:
					active_shapes.append(ch)
		# ถ้ามี shape ที่ active ให้คืน global_position ของ shape (หรือ average ถ้ามากกว่า 1)
		if active_shapes.size() > 0:
			if active_shapes.size() == 1:
				return (active_shapes[0] as CollisionShape2D).global_position
			var sum = Vector2.ZERO
			for s in active_shapes:
				sum += (s as CollisionShape2D).global_position
			return sum / float(active_shapes.size())
		# ถ้าไม่มี active shapes ให้ค้นหา collisionshape ทั่ว subtree เป็น fallback
		var found = _find_collisionshape_in_children(hb)
		if found != null:
			return found.global_position

	# 3) ถ้าไม่มี node "Hurtbox" หรือไม่พบ shape ข้างต้น ให้ลองค้นหาแบบ recursive ทั่ว player
	var found_any = _find_collisionshape_in_children(player_node)
	if found_any != null:
		return found_any.global_position

	# 4) ถ้ามี child "Aim" หรือ "AimPoint" ให้ใช้ (fallback)
	if player_node.has_node("Aim"):
		return (player_node.get_node("Aim") as Node2D).global_position
	if player_node.has_node("AimPoint"):
		return (player_node.get_node("AimPoint") as Node2D).global_position
	if player_node.has_method("get_aim_point"):
		var ap = player_node.get_aim_point()
		if typeof(ap) == TYPE_VECTOR2:
			return ap

	# 5) สุดท้าย fallback เป็นตำแหน่ง global ของ player (ถ้าเป็น Node2D)
	if player_node is Node2D:
		return (player_node as Node2D).global_position

	return Vector2.ZERO

# recursive search helper: หา CollisionShape2D ใน subtree
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

# เลือกตำแหน่ง aim ของ player: พยายามใช้ hurtbox center ก่อน แล้ว fallback เป็น Aim / global_position
func _get_player_aim_position(player_node: Node) -> Vector2:
	var hb = _get_player_hurtbox_center(player_node)
	if hb != Vector2.ZERO:
		return hb
	# fallback: Aim node or get_aim_point or global_position
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
