extends Control

@onready var new_game := $VBoxContainer/newgame
@onready var continue_btn := $VBoxContainer/continue
@onready var exit_btn := $VBoxContainer/exit
@onready var anim: AnimationPlayer = $AnimationPlayer
@onready var buzz_sfx: AudioStreamPlayer2D = $buzzSFX

func _ready() -> void:
	anim.animation_finished.connect(_on_animation_finished)
	new_game.grab_focus()
	# ถ้าไม่มี save → disable Continue
	if not SaveManager.has_save():
		continue_btn.disabled = true

func _on_newgame_pressed() -> void:
	anim.play("MenuFade")
	
func _on_animation_finished(anim_name: StringName) -> void:
	if anim_name == "MenuFade":
		get_tree().change_scene_to_file("res://Levels/intro-test.tscn")

func _on_continue_pressed() -> void:
	if not SaveManager.has_save():
		buzz_sfx.play()
		return

	# Try to get data via SaveManager.load_game() (preferred)
	var data = await SaveManager.load_game()
	# If SaveManager returned nothing (null) or not a usable dictionary, try direct file fallback
	if data == null or typeof(data) != TYPE_DICTIONARY or data.is_empty():
		var path := "user://save.json"
		if not FileAccess.file_exists(path):
			# no save file
			buzz_sfx.play()
			return
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			buzz_sfx.play()
			return
		var raw := f.get_as_text()
		f.close()
		var parsed: Variant = JSON.parse_string(raw)
		# Handle both Godot 4 JSONParseResult and plain dictionary results
		if typeof(parsed) == TYPE_DICTIONARY:
			data = parsed
		else:
			# parsed is likely a JSONParseResult-like object with .error and .result
			# Check parse error first
			if parsed.error != OK:
				push_warning("SelectMenu: failed to parse save.json: error %s" % str(parsed.error))
				buzz_sfx.play()
				return
			# get the actual result
			data = parsed.result

	# final check
	if data == null or typeof(data) != TYPE_DICTIONARY or data.is_empty():
		buzz_sfx.play()
		return

	# Load gameplay scene and hand off save data
	var tree := get_tree()
	# change to gameplay scene
	tree.change_scene_to_file("res://Levels/gameplay.tscn")
	# wait until scene changed
	await tree.scene_changed
	# allow one frame for nodes to initialize
	await tree.process_frame

	# find gameplay node (should be added to group "gameplay" by its _ready)
	var gameplay := tree.get_first_node_in_group("gameplay")
	if gameplay == null:
		push_error("Continue: Gameplay not found after scene change")
		return

	# mark loading flag if present
	if gameplay.has_variable != null and gameplay.has_variable("is_loading_from_save"):
		gameplay.is_loading_from_save = true if gameplay.has_variable("is_loading_from_save") else false

	# hand off data
	if gameplay.has_method("load_from_save"):
		gameplay.load_from_save(data)
	else:
		# fallback: if gameplay exposes a differently-named loader, try common alternatives
		if gameplay.has_method("apply_save_data"):
			gameplay.call_deferred("apply_save_data", data)
		else:
			push_error("Continue: gameplay node has no load_from_save() method to accept save data")
			return

func _on_exit_pressed() -> void:
	get_tree().quit()
