extends Node2D

# Simple gun attached to player. No pickup from ground.
# Toggle mode (gun <-> fist) via toggle_mode() or player calling weapon_swap action.
const BULLET = preload("res://bullet.tscn")
@onready var muzzle: Marker2D = $Marker2D
@export var cooldown_time: float = 0.25
var cooldown: float = 0.0

var mode_is_gun: bool = true   # true = gun mode, false = fist mode
var equipped: bool = true      # gun is permanently attached to player in this setup

func _ready() -> void:
	# Ensure visible state matches mode
	visible = mode_is_gun

func _process(delta: float) -> void:
	# cooldown timer
	if cooldown > 0.0:
		cooldown = max(cooldown - delta, 0.0)

	# follow player's facing if parent is player
	if is_inside_tree() and get_parent():
		var p = get_parent()
		if "facing" in p:
			rotation = p.facing.angle()

	# update flip for visual
	rotation_degrees = wrapf(rotation_degrees, 0.0, 360.0)
	if rotation_degrees > 90 and rotation_degrees < 270:
		scale.y = -1
	else:
		scale.y = 1

# toggle mode between gun and fist
func toggle_mode() -> void:
	mode_is_gun = not mode_is_gun
	visible = mode_is_gun
	# notify parent if they implement handler
	var p = get_parent()
	if p and p.has_method("on_weapon_swapped"):
		p.on_weapon_swapped(mode_is_gun ? "gun" : "fist")

# try to shoot; if in fist mode, caller (player) should trigger punch instead
func try_shoot() -> void:
	if not equipped:
		return
	if not mode_is_gun:
		# nothing to do; player should handle punching
		return
	if cooldown > 0.0:
		return
	# spawn bullet in player's facing direction
	var dir = Vector2.RIGHT.rotated(rotation)
	var bullet = BULLET.instantiate()
	bullet.global_position = muzzle.global_position
	# prefer parent facing if available
	var p = get_parent()
	if p and "facing" in p:
		bullet.set_direction(p.facing)
	else:
		bullet.set_direction(dir)
	get_tree().current_scene.add_child(bullet)
	cooldown = cooldown_time

# helper: set mode explicitly
func set_mode_gun() -> void:
	mode_is_gun = true
	visible = true
func set_mode_fist() -> void:
	mode_is_gun = false
	visible = false

# optional: expose whether currently gun mode
func is_gun_mode() -> bool:
	return mode_is_gun
