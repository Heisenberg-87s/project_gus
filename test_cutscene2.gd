extends Area2D

@onready var collision: CollisionShape2D = $CollisionShape2D
# @onready var codec := get_node("/root/Gameplay/CanvasLayer_Codec")
@export var resource = Resource
@export var balloon = PackedScene
@onready var codec: CanvasLayer = $"../CanvasLayer"
@onready var anim: AnimationPlayer = $".../AnimationPlayer"

func _ready() -> void:
	body_entered.connect(_on_body_entered)
	anim.animation_finished.connect(_on_animation_finished)
	# ✅ ต่อ signal END ของ Dialogue Manager
	DialogueManager.dialogue_ended.connect(_on_dialogue_ended)
	
func play_codec():
	visible = true
	anim.play("codec_call")

func end_codec():
	anim.play("codec_end")

func _on_body_entered(body: Node2D) -> void:
	if body.is_in_group("player"):
		codec.play_codec()
		collision.set_deferred("disabled", true)


func _on_animation_finished(name: StringName) -> void:
	if name == "codec_call":
		# เข้า Dialogue
		DialogueManager.show_dialogue_balloon_scene(balloon, resource, "start")
		
# ✅ ตรงนี้แหละ = => END
func _on_dialogue_ended(_resource) -> void:
	# เล่น anim จบสาย / ปิด codec
	anim.play("codec_end")
