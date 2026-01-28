extends Control


@export var fade_in_time: float = 1.0
@export var panel_fade_delay: float = 0.3
@export var fade_out_time: float = 0.6
@export var show_video_if_present: bool = true

@export var default_message: String = "You Died"
@export var video_autoplay: bool = true

# Typewriter
@export var typewriter_chars_per_sec: float = 45.0

# Enable restart by pressing accept (Enter / gamepad A)
@export var restart_on_accept: bool = true
@export var accept_action: String = "ui_accept"

var fade_rect = null
var panel = null
var video_player = null
var message_node = null
var restart_button = null
var sfx = null

var _connected_to_player: bool = false
var _sequence_playing: bool = false

func _ready() -> void:
	fade_rect = get_node_or_null("Fade")
	panel = get_node_or_null("Panel")
	video_player = get_node_or_null("Panel/Video")
	message_node = get_node_or_null("Panel/Message")
	restart_button = get_node_or_null("Panel/RestartButton")
	sfx = get_node_or_null("Sfx")

	if panel:
		panel.visible = false
	if fade_rect:
		var c = fade_rect.modulate
		c.a = 0.0
		fade_rect.modulate = c
	if restart_button:
		restart_button.disabled = true

	_connect_to_player()

func _process(delta: float) -> void:
	# try connect in case player spawns later
	if not _connected_to_player:
		_connect_to_player()

	# listen for accept (Enter) to restart when panel visible and restart enabled
	if restart_on_accept and panel != null and panel.visible:
		# only accept if sequence finished and restart button is enabled (or no button present)
		var can_accept = (not _sequence_playing)
		if restart_button != null:
			can_accept = can_accept and (not restart_button.disabled)
		if can_accept and Input.is_action_just_pressed(accept_action):
			_on_restart_pressed()

func _connect_to_player() -> void:
	if _connected_to_player:
		return
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() == 0:
		return
	var player = arr[0]
	if player.has_signal("died") and not player.is_connected("died", Callable(self, "_on_player_died")):
		player.connect("died", Callable(self, "_on_player_died"))
		_connected_to_player = true

func _on_player_died() -> void:
	_play_sfx_on_death()
	_sequence_playing = true
	await _fade_in()
	await _show_panel_sequence()
	_sequence_playing = false

func _play_sfx_on_death() -> void:
	if sfx != null:
		if sfx.has_method("play"):
			sfx.play()
		return
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0 and is_instance_valid(arr[0]):
		var p = arr[0]
		if p.has_node("DeathSound"):
			var ds = p.get_node("DeathSound")
			if ds != null and (ds.has_method("play")):
				ds.play()

func _fade_in():
	if fade_rect == null:
		return
	var c = fade_rect.modulate
	c.a = 0.0
	fade_rect.modulate = c
	var tween = create_tween()
	tween.tween_property(fade_rect, "modulate:a", 1.0, fade_in_time).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	await tween.finished

func _show_panel_sequence():
	await get_tree().create_timer(panel_fade_delay).timeout
	if panel:
		panel.visible = true

	# play video if present
	if video_player != null and show_video_if_present:
		var stream = null
		if video_player.has_method("get") and video_player.get("stream") != null:
			stream = video_player.get("stream")
		elif video_player.has_method("get_stream") and video_player.get_stream() != null:
			stream = video_player.get_stream()
		if stream != null:
			if message_node:
				message_node.visible = false
			if video_autoplay and video_player.has_method("play"):
				video_player.play()
			var waited = false
			if video_player.has_signal("finished"):
				await video_player.finished
				waited = true
			elif video_player.has_method("is_playing"):
				while video_player.is_playing():
					await get_tree().process_frame
				waited = true
			if not waited:
				await get_tree().create_timer(1.0).timeout

	# show message (typewriter)
	if message_node != null:
		if message_node.has_method("clear"):
			message_node.clear()
			message_node.append_text(default_message)
			if "visible_ratio" in message_node:
				message_node.set("visible_ratio", 0.0)
			if "visible_characters" in message_node:
				message_node.set("visible_characters", 0)
			var length_chars = str(default_message).length()
			var duration = max(0.01, float(length_chars) / max(1.0, typewriter_chars_per_sec))
			var tween = create_tween()
			if message_node.has_method("set") and "visible_ratio" in message_node:
				tween.tween_property(message_node, "visible_ratio", 1.0, duration).set_trans(Tween.TRANS_LINEAR).set_ease(Tween.EASE_IN_OUT)
				await tween.finished
			else:
				var i = 0
				while i <= length_chars:
					if "visible_characters" in message_node:
						message_node.set("visible_characters", i)
					i += 1
					await get_tree().create_timer(1.0 / max(1.0, typewriter_chars_per_sec)).timeout
		else:
			message_node.visible = true
			var full_text = default_message
			message_node.text = ""
			var n_chars = str(full_text).length()
			for i in range(n_chars + 1):
				message_node.text = full_text.substr(0, i)
				await get_tree().create_timer(1.0 / max(1.0, typewriter_chars_per_sec)).timeout

	if message_node != null:
		if "visible_ratio" in message_node:
			message_node.set("visible_ratio", 1.0)
		if "visible_characters" in message_node:
			message_node.set("visible_characters", -1)
		if message_node.has_method("show"):
			message_node.show()

	if restart_button:
		restart_button.disabled = false
		if not restart_button.is_connected("pressed", Callable(self, "_on_restart_pressed")):
			restart_button.connect("pressed", Callable(self, "_on_restart_pressed"))

	return

func _on_restart_pressed() -> void:
	# prevent double trigger
	if restart_button:
		restart_button.disabled = true
	# optionally fade out quickly then reload
	_do_reload_scene()

func _do_reload_scene() -> void:
	get_tree().reload_current_scene()


func _on_button_pressed() -> void:
	if not SaveManager.has_save():
		get_tree().change_scene_to_file("res://Levels/gameplay.tscn")

	var data: Dictionary = await SaveManager.load_game()
	if data.is_empty():
		return

	# 🔥 บอกไว้ล่วงหน้า
	SaveManager.is_continue = true
	SaveManager.pending_continue_data = data

	get_tree().change_scene_to_file("res://Levels/gameplay.tscn")
