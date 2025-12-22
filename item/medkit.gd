extends Area2D

@export var heal_amount: int = 25
@export var one_time: bool = true
@export var pickup_sound: AudioStream = null

func _ready() -> void:
	# เชื่อมสัญญาณ body_entered (player เป็น CharacterBody2D -> จะเป็น body)
	if not is_connected("body_entered", Callable(self, "_on_body_entered")):
		connect("body_entered", Callable(self, "_on_body_entered"))

func _on_body_entered(body: Node) -> void:
	if not is_instance_valid(body):
		return

	# เฉพาะ player เท่านั้น (player เพิ่ม group "player" ใน _ready ของ player.gd)
	if not body.is_in_group("player"):
		return

	# พยายามเรียกเมธอด heal ถ้ามี และตรวจผลลัพธ์ (true = ฟื้นจริง)
	var picked_up: bool = false
	if body.has_method("heal"):
		# heal() ควรคืนค่า bool (true = เพิ่มเลือดจริง)
		var ok = body.heal(heal_amount, self)
		if typeof(ok) == TYPE_BOOL:
			picked_up = ok
		else:
			# หาก heal ไม่คืนค่าเป็น bool (compatibility), ให้ถือว่าเก็บสำเร็จเมื่อเลือดเพิ่ม
			picked_up = true
	else:
		# fallback: ถ้า player มี property health/max_health ให้เพิ่มตรง ๆ แต่ตรวจสอบก่อน
		if "health" in body and "max_health" in body:
			if int(body.health) < int(body.max_health):
				body.health = min(int(body.health) + heal_amount, int(body.max_health))
				picked_up = true

	# ถ้าเก็บสำเร็จ -> เล่นเสียงและลบไอเท็ม (ถ้ากำหนด)
	if picked_up:
		if pickup_sound != null:
			var s = AudioStreamPlayer2D.new()
			s.stream = pickup_sound
			s.global_position = global_position
			get_tree().current_scene.add_child(s)
			s.play()
		if one_time:
			queue_free()
