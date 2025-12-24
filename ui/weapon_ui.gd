extends Control
#
# HUD : Weapon Mode Icon (Hand / Gun) + Ammo
# Godot 4 compatible
#
# Scene Tree:
# HUD (Control)
# └─ RightPanel (MarginContainer)
#    ├─ WeaponIconContainer (HBoxContainer or Control)
#    │  └─ WeaponIcon (TextureRect)
#    └─ AmmoLabel (Label)
#

@export var icon_texture_hand: Texture2D
@export var icon_texture_gun: Texture2D

@export var icon_scale_idle: float = 2.0
@export var icon_scale_active: float = 2.4
@export var tween_up_time: float = 0.12
@export var tween_down_time: float = 0.18
@export var tween_delay: float = 0.02

@onready var icon_rect: TextureRect = $RightPanel/WeaponIconContainer/WeaponIcon
@onready var ammo_label: Label = $RightPanel/AmmoLabel

var _last_mode: int = -1

# --------------------------------------------------
func _ready() -> void:
	# TextureRect setup (Godot 4)
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.custom_minimum_size = Vector2(64, 64)
	icon_rect.scale = Vector2.ONE * icon_scale_idle	

	# Init with HAND icon
	_set_icon_immediate(0)

	# Auto-connect to player
	var players := get_tree().get_nodes_in_group("player")
	if players.size() > 0:
		var p = players[0]
		if p.has_signal("weapon_mode_changed"):
			p.connect("weapon_mode_changed", Callable(self, "set_weapon_mode"))
		if p.has_signal("ammo_changed"):
			p.connect("ammo_changed", Callable(self, "set_ammo"))

# --------------------------------------------------
# PUBLIC API
# --------------------------------------------------

# mode: 0 = HAND / NORMAL , 1 = GUN
func set_weapon_mode(mode: int) -> void:
	if _last_mode == mode:
		_flash()
		return

	_last_mode = mode

	var tex := icon_texture_hand if mode == 0 else icon_texture_gun
	_apply_texture_and_size(tex)
	_play_tween()

func set_ammo(amount: int) -> void:
	if amount < 0:
		ammo_label.visible = false
	else:
		ammo_label.visible = true
		ammo_label.text = str(amount)

# --------------------------------------------------
# INTERNAL
# --------------------------------------------------

func _set_icon_immediate(mode: int) -> void:
	var tex := icon_texture_hand if mode == 0 else icon_texture_gun
	_apply_texture_and_size(tex)

func _apply_texture_and_size(tex: Texture2D) -> void:
	icon_rect.texture = tex
	icon_rect.visible = tex != null

	if tex != null:
		var size := tex.get_size()
		if size == Vector2.ZERO:
			size = Vector2(16, 16)

		# ✅ Godot 4 FIX: ป้องกัน Container บีบ
		icon_rect.custom_minimum_size = size
		icon_rect.scale = Vector2.ONE * icon_scale_idle
	else:
		icon_rect.custom_minimum_size = Vector2.ZERO
		icon_rect.scale = Vector2.ONE * icon_scale_idle

func _play_tween() -> void:
	icon_rect.scale = Vector2.ONE * icon_scale_idle
	var tw := get_tree().create_tween()
	tw.tween_property(
		icon_rect,
		"scale",
		Vector2.ONE * icon_scale_active,
		tween_up_time
	).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

	tw.tween_property(
		icon_rect,
		"scale",
		Vector2.ONE * icon_scale_idle,
		tween_down_time
	).set_delay(tween_delay).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)

func _flash() -> void:
	var tw := get_tree().create_tween()
	tw.tween_property(icon_rect, "modulate", Color(1.2, 1.2, 1.2, 1), 0.08)
	tw.tween_property(icon_rect, "modulate", Color.WHITE, 0.12)
