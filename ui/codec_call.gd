extends CanvasLayer

signal codec_ready

@onready var anim: AnimationPlayer = $AnimationPlayer
var active := false

func _ready() -> void:
	visible = false
	anim.animation_finished.connect(_on_animation_finished)
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)

func play_codec():
	if active:
		return

	active = true
	visible = true
	
	var gameplay = get_tree().get_first_node_in_group("gameplay")
	if gameplay:
		var levelholder = gameplay.get_node("LevelHolder")
		levelholder.process_mode = Node.PROCESS_MODE_DISABLED
	anim.play("codec_call")

func _on_animation_finished(name: StringName) -> void:
	if name == "codec_call":
		# ✅ บอกว่า animation พร้อมแล้ว
		emit_signal("codec_ready")

	elif name == "codec_end":
		visible = false
		active = false

func _on_dialogue_ended(_res):
	if active:
		anim.play("codec_end")
	var gameplay = get_tree().get_first_node_in_group("gameplay")
	if gameplay:
		var levelholder = gameplay.get_node("LevelHolder")
		levelholder.process_mode = Node.PROCESS_MODE_INHERIT
