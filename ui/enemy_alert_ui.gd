extends Control

@onready var combat_label: Label = get_node_or_null("PanelContainer/ColorRect/VBoxContainer/CombatLabel") as Label
@onready var caution_label: Label = get_node_or_null("PanelContainer/ColorRect/VBoxContainer/CautionLabel") as Label
@onready var timer_label: Label = get_node_or_null("PanelContainer/ColorRect/VBoxContainer/TimerLabel") as Label

const COMBAT_DISPLAY_VALUE: float = 99.99

var _caution_set: Array = []

func _ready() -> void:
	_try_resolve_labels()

	# connect to existing enemies' signals
	for e in get_tree().get_nodes_in_group("enemies"):
		_connect_enemy(e)
	# listen for new enemies being added later
	get_tree().connect("node_added", Callable(self, "_on_node_added"))
	# listen for nodes removed (cleanup _caution_set)
	get_tree().connect("node_removed", Callable(self, "_on_node_removed"))

	# Ensure caution_label is hidden (we use an image background instead)
	if caution_label != null:
		caution_label.visible = false

	_safe_set_visible(false)

func _try_resolve_labels() -> void:
	# If labels not assigned, try to find them in current scene
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

func _safe_set_visible(v: bool) -> void:
	if self != null:
		visible = v
	if combat_label != null:
		combat_label.visible = v
	# caution_label intentionally not toggled here (we use image background instead)
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

	# connect tree_exited with a bound argument so our handler receives the enemy node
	var bound_call := Callable(self, "_on_enemy_tree_exited").bind(enemy)
	# avoid duplicate connections: check is_connected against the same bound callable
	if not enemy.is_connected("tree_exited", bound_call):
		enemy.connect("tree_exited", bound_call)

func _on_enemy_tree_exited(enemy: Node) -> void:
	# When connected with .bind(enemy), this handler receives the enemy node even though tree_exited emits no args.
	if enemy in _caution_set:
		_caution_set.erase(enemy)
		_update_ui_visibility()

func _on_enemy_caution_started(enemy: Node) -> void:
	if not is_instance_valid(enemy):
		return
	if enemy in _caution_set:
		return
	_caution_set.append(enemy)
	_update_ui_visibility()

func _on_enemy_caution_ended(enemy: Node) -> void:
	if enemy in _caution_set:
		_caution_set.erase(enemy)
	_update_ui_visibility()

func _update_ui_visibility() -> void:
	# Basic visibility based on _caution_set
	if _caution_set.size() > 0:
		_safe_set_visible(true)
		# caution_label removed from visible flow — background image used instead
	else:
		if caution_label != null:
			caution_label.visible = false

func _process(_delta: float) -> void:
	# make sure labels exist
	if (combat_label == null or caution_label == null or timer_label == null):
		_try_resolve_labels()

	# prune invalid entries
	for e in _caution_set.duplicate():
		if not is_instance_valid(e) or not e.is_inside_tree():
			_caution_set.erase(e)
	_update_ui_visibility()

	# Prefer global GameState autoload for continuous caution timer if available
	var gs = get_node_or_null("/root/GameState")
	var any_combat: bool = false
	var found_timer: bool = false
	var mapped_value: float = -1.0

	if gs != null:
		# debug print to verify GameState presence (comment out to reduce spam)
		# print("[CautionUI] found GameState: is_in_caution=", gs.is_in_caution, "remaining=", gs.caution_time_remaining)
		if gs.is_in_caution and gs.caution_time_remaining > 0.0:
			if gs.caution_total_duration > 0.0:
				mapped_value = COMBAT_DISPLAY_VALUE * (gs.caution_time_remaining / gs.caution_total_duration)
			else:
				mapped_value = COMBAT_DISPLAY_VALUE
			found_timer = true

	# fallback: aggregate per-enemy state if no global timer
	if not found_timer:
		var enemies = get_tree().get_nodes_in_group("enemies")
		var max_mapped: float = -1.0
		for e in enemies:
			if not is_instance_valid(e):
				continue
			# explicit caution flag
			var flag = null
			if e.has_method("get"):
				flag = e.get("_caution_active") if e.has_method("get") else null
			if typeof(flag) != TYPE_NIL and bool(flag):
				any_combat = true
			# fallback ai state check
			var ai = null
			if e.has_method("get"):
				ai = e.get("ai_state")
			if not any_combat and typeof(ai) != TYPE_NIL and "AIState" in e and ai == e.AIState.COMBAT:
				any_combat = true
			# evasion timer mapping
			if typeof(ai) != TYPE_NIL and "AIState" in e and ai == e.AIState.EVASION:
				var t = e.get("_evasion_time_left") if e.has_method("get") else null
				var dur = e.get("evasion_duration") if e.has_method("get") else null
				if typeof(t) != TYPE_NIL:
					var tf = float(t)
					var d = 10.0
					if typeof(dur) != TYPE_NIL and float(dur) > 0.0:
						d = float(dur)
					var mapped = COMBAT_DISPLAY_VALUE * (tf / d)
					if mapped > max_mapped:
						max_mapped = mapped
		if max_mapped >= 0.0:
			found_timer = true
			mapped_value = max_mapped

	# Apply UI based on computed timer / flags
	if found_timer and mapped_value >= 0.0:
		if timer_label != null:
			timer_label.visible = true
			timer_label.text = "%05.2f" % clamp(mapped_value, 0.0, COMBAT_DISPLAY_VALUE)
		# caution_label intentionally not shown; background image will represent caution state
		if combat_label != null:
			combat_label.visible = false
		visible = true
	else:
		if timer_label != null:
			timer_label.visible = false

	# Show combat label if any source indicates combat/caution and no timer active
	if (any_combat or _caution_set.size() > 0) and (timer_label == null or not timer_label.visible):
		if combat_label != null:
			combat_label.visible = true
			combat_label.text = "%05.2f" % COMBAT_DISPLAY_VALUE
		visible = true
	else:
		if combat_label != null and (timer_label == null or not timer_label.visible):
			if not any_combat and _caution_set.size() == 0:
				combat_label.visible = false

	# If no combat/caution/timer -> hide UI
	if not any_combat and _caution_set.size() == 0 and (timer_label == null or not timer_label.visible):
		_safe_set_visible(false)
