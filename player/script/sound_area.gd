extends Area2D
class_name ShootArea

# SoundArea: short-lived Area2D used for "sound detection"
# - Spawned by player when pressing the sound-detect button (V)
# - Draws a temporary circle (visualizes the collision)
# - When overlapping enemy hurtboxes, notifies the enemy so it can walk/investigate the player that made the sound

@export var duration: float = 0.25
@export var radius: float = 100.0

# Optional: AudioStream to play when this SoundArea is spawned.
# Assign from Player when instancing, e.g.:
#   var sa = SOUND_AREA_SCENE.instantiate()
#   sa.sound_sfx = sound_emit_sfx
@export var sound_sfx: AudioStream = null

# The player node that created this sound (so enemies can move toward the correct player)
var source_player: Node = null

var _hit_ids := {}

@onready var _colshape: CollisionShape2D = $CollisionShape2D
# try to use an existing AudioStreamPlayer2D child if present
@onready var _audio_player: AudioStreamPlayer2D = $AudioStreamPlayer2D if has_node("AudioStreamPlayer2D") else null

func _ready() -> void:
	# ensure circle shape with radius
	var circ = CircleShape2D.new()
	circ.radius = radius
	if is_instance_valid(_colshape):
		_colshape.shape = circ
	else:
		# create one dynamically if not present
		var cs = CollisionShape2D.new()
		cs.shape = circ
		add_child(cs)

	# ensure we have an AudioStreamPlayer2D as a child to play spatial sound
	if _audio_player == null:
		_audio_player = AudioStreamPlayer2D.new()
		_audio_player.name = "AudioStreamPlayer2D"
		add_child(_audio_player)

	# if a stream was provided, play it (spatial, located at this Area2D)
	if sound_sfx != null and _audio_player != null:
		_audio_player.stream = sound_sfx
		_audio_player.play()

	add_to_group("player_sound")
	connect("area_entered", Callable(self, "_on_area_entered"))
	connect("body_entered", Callable(self, "_on_body_entered"))

	# request a redraw if the method exists (avoids engine/version mismatch errors)
	if has_method("queue_redraw"):
		queue_redraw()

	# auto free after duration
	await get_tree().create_timer(duration).timeout
	if is_instance_valid(self):
		queue_free()

func _draw() -> void:
	# simple visual: translucent circle
	draw_circle(Vector2.ZERO, radius, Color(1, 1, 0, 0.18))
	draw_circle(Vector2.ZERO, max(radius - 3.0, 0.0), Color(1, 1, 0, 0.28))

func _on_area_entered(area: Area2D) -> void:
	if area == null:
		return
	if area.is_in_group("enemy_hurtboxes"):
		_apply_to_enemy_hurtbox(area)

func _on_body_entered(body: Node) -> void:
	if body == null:
		return
	if body.is_in_group("enemy_hurtboxes"):
		_apply_to_enemy_hurtbox(body)

func _apply_to_enemy_hurtbox(hurtbox: Node) -> void:
	if hurtbox == null:
		return
	var enemy = hurtbox.get_parent()
	if enemy == null:
		return
	var id = enemy.get_instance_id()
	if id in _hit_ids:
		return
	_hit_ids[id] = true

	# Notify the enemy. We try several common method names so this system is flexible.
	if enemy.has_method("on_sound_detected"):
		enemy.call_deferred("on_sound_detected", source_player, global_position)
	elif enemy.has_method("investigate_sound"):
		enemy.call_deferred("investigate_sound", global_position, source_player)
	elif enemy.has_method("set_investigate_target"):
		enemy.call_deferred("set_investigate_target", source_player)
	elif enemy.has_method("set_target"):
		enemy.call_deferred("set_target", source_player)
	else:
		# Fallback: if enemy has a method to walk to a position, try that
		if enemy.has_method("walk_to_position"):
			enemy.call_deferred("walk_to_position", global_position)
		else:
			# no known handler on enemy; print a warning (for debugging)
			print("SoundArea: enemy has no sound handler:", enemy)
