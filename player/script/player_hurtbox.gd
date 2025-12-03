extends Area2D

@export var source_player: Node = null         # ถ้าตั้งมาแล้ว จะใช้ในการอ้างอิงผู้เล่น (preferred)
@export var hurtbox_layer: int = 1 << 6        # ค่าเริ่มต้น: layer index 7 (1<<6)
@export var add_group_name: String = "player_hurtbox"
@export var auto_name_hurtbox: bool = true
@export var debug: bool = false

func _ready() -> void:
	# ตั้งชื่อ / กลุ่ม / layer ให้พร้อมใช้สำหรับ enemy raycasts
	if auto_name_hurtbox:
		name = "Hurtbox"
	# ถ้ายังไม่ระบุ source_player ให้พยายามหาอัตโนมัติ
	if source_player == null:
		if owner != null and owner.is_in_group("player"):
			source_player = owner
		elif get_parent() != null and get_parent().is_in_group("player"):
			source_player = get_parent()
	# ตั้ง collision layer ให้ตรงกับที่ enemy คาดหวัง (ถ้าต้องการเปลี่ยน ให้แก้ค่า hurtbox_layer)
	collision_layer = hurtbox_layer
	# ใส่กลุ่มช่วยในการค้นหา
	if add_group_name != "":
		add_to_group(add_group_name)

	# เช็ค/เชื่อมสัญญาณด้วย Callable (Godot 4 expects 2 args)
	if not is_connected("area_entered", Callable(self, "_on_area_entered")):
		connect("area_entered", Callable(self, "_on_area_entered"))
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))

	if debug:
		print("Hurtbox ready — source_player:", source_player, " layer:", hurtbox_layer)

# helper: safe read property-like (checks meta first, then tries get())
func _safe_read(obj: Object, key: String):
	if obj == null:
		return null
	if obj.has_meta(key):
		return obj.get_meta(key)
	# calling get() on an object that doesn't have the property usually returns null
	# so this is safe in typical GDScript usage
	var v = obj.get(key)
	return v

# เมื่อมี Area2D หรือ Hitbox ของศัตรูมาชน (เช่นยิง/พั้นช์เข้ามา)
func _on_area_entered(area: Area2D) -> void:
	if not is_instance_valid(area):
		return
	var dmg_val = _safe_read(area, "damage")
	var dmg: int = 0
	if dmg_val != null:
		# ป้องกันกรณีที่ค่าไม่ใช่ตัวเลข
		if typeof(dmg_val) in [TYPE_INT, TYPE_FLOAT]:
			dmg = int(dmg_val)
		else:
			# ถ้าเป็นสตริงที่เป็นตัวเลข
			var parsed = int(str(dmg_val))
			dmg = parsed

	# source จาก area (ถ้ามี) — อาจเป็น node reference หรืออื่น ๆ
	var src = _safe_read(area, "source")
	# prefer source_player metadata / property if area carries it
	if src == null:
		var sp = _safe_read(area, "source_player")
		if sp != null:
			src = sp

	# เรียก method take_damage บน parent (player) ถ้ามี
	if dmg > 0 and is_instance_valid(get_parent()) and get_parent().has_method("take_damage"):
		get_parent().take_damage(dmg, src)

# หากชนเป็น PhysicsBody2D (บางระบบอาจส่งเป็น body_entered)
func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return
	var dmg_val = _safe_read(body, "damage")
	var dmg: int = 0
	if dmg_val != null:
		if typeof(dmg_val) in [TYPE_INT, TYPE_FLOAT]:
			dmg = int(dmg_val)
		else:
			var parsed = int(str(dmg_val))
			dmg = parsed

	var src = _safe_read(body, "source")
	if src == null:
		var sp = _safe_read(body, "source_player")
		if sp != null:
			src = sp

	if dmg > 0 and is_instance_valid(get_parent()) and get_parent().has_method("take_damage"):
		get_parent().take_damage(dmg, src)

# Helper accessors (enemy code may query these)
func get_source_player() -> Node:
	return source_player

func set_source_player(p: Node) -> void:
	source_player = p

# helper to expose layer value for other scripts
func get_hurtbox_layer() -> int:
	return hurtbox_layer
