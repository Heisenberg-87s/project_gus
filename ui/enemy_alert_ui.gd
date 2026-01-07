extends Control

@onready var combat_label: Label = get_node_or_null("PanelContainer/ColorRect/VBoxContainer/CombatLabel") as Label
@onready var caution_label: Label = get_node_or_null("PanelContainer/ColorRect/VBoxContainer/CautionLabel") as Label
@onready var timer_label: Label = get_node_or_null("PanelContainer/ColorRect/VBoxContainer/TimerLabel") as Label

const COMBAT_DISPLAY_VALUE: float = 99.99
const MAX_DISPLAY_TIME: float = 999.99

var _caution_set: Array = []

func _ready() -> void:
	# try to auto-find missing labels by name in current scene
	_try_resolve_labels()

	# connect to existing enemies' signals
	for e in get_tree().get_nodes_in_group("enemies"):
		_connect_enemy(e)
	# listen for new enemies being added later
	get_tree().connect("node_added", Callable(self, "_on_node_added"))
	# listen for nodes removed (cleanup _caution_set)
	get_tree().connect("node_removed", Callable(self, "_on_node_removed"))

	# initial hide
	_safe_set_visible(false)

func _try_resolve_labels() -> void:
	# If any label is null, attempt to find by name in current_scene
	var root = get_tree().current_scene if get_tree().current_scene != null else get_tree().root
	if combat_label == null:
		combat_label = _find_label_in_tree(root, "CombatLabel")
	if caution_label == null:
		caution_label = _find_label_in_tree(root, "CautionLabel")
	if timer_label == null:
		timer_label = _find_label_in_tree(root, "TimerLabel")
	# warn if still missing
	if combat_label == null:
		push_warning("CautionUI: CombatLabel not found. Update the onready path or add a Label named 'CombatLabel'.")
	if caution_label == null:
		push_warning("CautionUI: CautionLabel not found. Update the onready path or add a Label named 'CautionLabel'.")
	if timer_label == null:
		push_warning("CautionUI: TimerLabel not found. Update the onready path or add a Label named 'TimerLabel'.")

func _find_label_in_tree(root: Node, target_name: String) -> Label:
	if root == null:
		return null
	if root.name == target_name and root is Label:
		return root as Label
	for child in root.get_children():
		if not is_instance_valid(child):
			continue
		if child is Label and child.name == target_name:
			return child as Label
		var found = _find_label_in_tree(child, target_name)
		if found != null:
			return found
	return null

# safe setter to avoid null instance errors
func _safe_set_visible(v: bool) -> void:
	if self != null:
		visible = v
	if combat_label != null:
		combat_label.visible = v
	if caution_label != null:
		caution_label.visible = v
	if timer_label != null:
		timer_label.visible = v

func _on_node_added(node: Node) -> void:
	if node == null:
		return
	if node.is_in_group("enemies"):
		_connect_enemy(node)

func _on_node_removed(node: Node) -> void:
	if node == null:
		return
	# node_removed fires when nodes are freed / removed: remove from caution set if present
	if node in _caution_set:
		_caution_set.erase(node)
		_update_ui_visibility()

func _connect_enemy(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	# connect caution signals
	if enemy.has_signal("caution_started") and not enemy.is_connected("caution_started", Callable(self, "_on_enemy_caution_started")):
		enemy.connect("caution_started", Callable(self, "_on_enemy_caution_started"))
	if enemy.has_signal("caution_ended") and not enemy.is_connected("caution_ended", Callable(self, "_on_enemy_caution_ended")):
		enemy.connect("caution_ended", Callable(self, "_on_enemy_caution_ended"))
	# connect tree_exited to clean up when enemy leaves scene
	if not enemy.is_connected("tree_exited", Callable(self, "_on_enemy_tree_exited")):
		enemy.connect("tree_exited", Callable(self, "_on_enemy_tree_exited"))

func _on_enemy_tree_exited(enemy: Node) -> void:
	if enemy in _caution_set:
		_caution_set.erase(enemy)
		_update_ui_visibility()

func _on_enemy_caution_started(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy in _caution_set:
		return
	_caution_set.append(enemy)
	print("CautionUI: caution started from", enemy.name, " total:", _caution_set.size())
	_update_ui_visibility()

func _on_enemy_caution_ended(enemy: Node) -> void:
	if enemy in _caution_set:
		_caution_set.erase(enemy)
		print("CautionUI: caution ended from", enemy.name, " total:", _caution_set.size())
	_update_ui_visibility()

func _update_ui_visibility() -> void:
	# show/hide basic CAUTION label based on _caution_set
	if _caution_set.size() > 0:
		_safe_set_visible(true)
		if caution_label != null:
			caution_label.visible = true
			caution_label.text = "CAUTION"
	else:
		# do not hide completely here; fallback polling will decide to hide completely if nothing active
		if caution_label != null:
			caution_label.visible = false

func _process(_delta: float) -> void:
	# Ensure we have label references (try resolving once per frame until found)
	if (combat_label == null or caution_label == null or timer_label == null):
		_try_resolve_labels()

	# Prune invalid entries from _caution_set (cleanup freed enemies)
	for e in _caution_set.duplicate():
		if not is_instance_valid(e) or not e.is_inside_tree():
			_caution_set.erase(e)
	# After pruning, update visibility if needed
	_update_ui_visibility()

	# Poll enemies for display values
	var enemies = get_tree().get_nodes_in_group("enemies")
	var any_combat: bool = false
	var max_mapped_value: float = -1.0
	var found_any_evasion: bool = false

	for e in enemies:
		if not is_instance_valid(e):
			continue
		# Prefer explicit flag
		var flag = e.get("_caution_active")
		if typeof(flag) != TYPE_NIL and bool(flag):
			any_combat = true
		# Fallback by state
		var ai = e.get("ai_state")
		if not any_combat and typeof(ai) != TYPE_NIL and "AIState" in e and ai == e.AIState.COMBAT:
			any_combat = true

		# Evasion: map remaining time -> display value (99.99 -> 0 over evasion_duration)
		if typeof(ai) != TYPE_NIL and "AIState" in e and ai == e.AIState.EVASION:
			var t = e.get("_evasion_time_left")
			var dur = e.get("evasion_duration")
			if typeof(t) != TYPE_NIL:
				var tf = float(t)
				var d = 10.0
				if typeof(dur) != TYPE_NIL and float(dur) > 0.0:
					d = float(dur)
				# mapped value: at full duration -> COMBAT_DISPLAY_VALUE, at 0 -> 0
				var mapped = COMBAT_DISPLAY_VALUE * (tf / d)
				if mapped > max_mapped_value:
					max_mapped_value = mapped
				found_any_evasion = true

	# If there's an active evasion countdown, show timer mapped from 99.99 -> 0 across its duration
	if found_any_evasion and max_mapped_value >= 0.0:
		if timer_label != null:
			timer_label.visible = true
			# format 05.2f
			timer_label.text = "%05.2f" % clamp(max_mapped_value, 0.0, COMBAT_DISPLAY_VALUE)
		if caution_label != null:
			caution_label.visible = true
		# Disable combat_label when timer_label is active
		if combat_label != null:
			combat_label.visible = false
		visible = true
	else:
		if timer_label != null:
			timer_label.visible = false

	# Show combat label if any_combat or we have caution signals (and no active timer)
	if (any_combat or _caution_set.size() > 0) and (timer_label == null or not timer_label.visible):
		if combat_label != null:
			combat_label.visible = true
			combat_label.text = "%05.2f" % COMBAT_DISPLAY_VALUE
		visible = true
	else:
		if combat_label != null and (timer_label == null or not timer_label.visible):
			# hide combat if no sources
			if not any_combat and _caution_set.size() == 0:
				combat_label.visible = false

	# Hide overall UI when no combat/caution and no timer
	if not any_combat and _caution_set.size() == 0 and (timer_label == null or not timer_label.visible):
		_safe_set_visible(false)
