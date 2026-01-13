extends CanvasLayer

@onready var anim: AnimationPlayer = $AnimationPlayer

func _ready() -> void:
	visible = false
	anim.animation_finished.connect(_on_animation_finished)
	# ✅ ต่อ signal END ของ Dialogue Manager
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)


func play_codec():
	visible = true
	anim.play("codec_call")


func _on_animation_finished(name: StringName) -> void:
	if name == "codec_call":
		# เข้า Dialogue
		DialogueManager.show_dialogue_balloon(
			load("res://Dialogue/test2.dialogue"),
			"start"
		)
# ✅ ตรงนี้แหละ = => END
func _on_dialogue_ended(_resource) -> void:
	# เล่น anim จบสาย / ปิด codec
	anim.play("codec_end")
