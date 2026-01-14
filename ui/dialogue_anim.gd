extends CanvasLayer

signal dialogue_ready

@onready var anim: AnimationPlayer = $AnimationPlayer
var active := false

func _ready() -> void:
	visible = false
	anim.animation_finished.connect(_on_animation_finished)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

func play_dialogue():
	if active:
		return

	active = true
	visible = true
	anim.play("dialogue_up")

func _on_animation_finished(name: StringName) -> void:
	if name == "dialogue_up":
		# ✅ บอกว่า animation พร้อมแล้ว
		emit_signal("dialogue_ready")

	elif name == "dialogue_end":
		visible = false
		active = false

func _on_dialogue_ended(_res):
	if active:
		anim.play("dialogue_end")
