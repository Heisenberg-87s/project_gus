extends Control
# Health bar UI controller
# - Attach this script to a Control node (e.g., "HealthUI") placed under a CanvasLayer for UI.
# - The Control node should have:
#     - ProgressBar node named "Bar"
#     - (optional) Label node named "ValueLabel" for numeric display
# The script will look for a node in group "player" and read `health` and `max_health`.
# If your player uses different property names, set `player_health_key` / `player_max_health_key`.

@export var player_health_key: String = "health"
@export var player_max_health_key: String = "max_health"

@export var update_mode_poll: bool = true   # true = update every frame, false = listen to signals if available
@export var progress_max_value: float = 100.0

@export var show_percentage: bool = false   # if true shows "75%", else shows "75 / 100" when ValueLabel present
@export var hide_when_no_player: bool = false

@onready var bar: ProgressBar = $Bar if has_node("Bar") else null
@onready var value_label: Label = $ValueLabel if has_node("ValueLabel") else null

var _player_node: Node = null

func _ready() -> void:
	# bar fallback safety
	if bar == null:
		push_error("%s: ProgressBar node 'Bar' not found as child." % [self.name])
	# attempt to find player immediately
	_find_player_node()
	# if player has a "damaged" signal we could connect to it when update_mode_poll == false
	if not update_mode_poll and _player_node != null:
		_try_connect_player_signals()

func _process(delta: float) -> void:
	if update_mode_poll:
		_update_from_player()

func _find_player_node() -> void:
	var arr = get_tree().get_nodes_in_group("player")
	if arr.size() > 0:
		_player_node = arr[0]
		# connect if using event-driven mode
		if not update_mode_poll:
			_try_connect_player_signals()
		visible = true
	else:
		_player_node = null
		if hide_when_no_player:
			visible = false

func _try_connect_player_signals() -> void:
	if _player_node == null:
		return
	# Try common signals: "damaged" or "health_changed"
	if _player_node.has_signal("damaged") and not _player_node.is_connected("damaged", Callable(self, "_on_player_damaged")):
		_player_node.connect("damaged", Callable(self, "_on_player_damaged"))
	if _player_node.has_signal("health_changed") and not _player_node.is_connected("health_changed", Callable(self, "_on_player_damaged")):
		_player_node.connect("health_changed", Callable(self, "_on_player_damaged"))

func _on_player_damaged(amount = null) -> void:
	# signal handler for event-driven update
	_update_from_player()

func _update_from_player() -> void:
	if _player_node == null or not is_instance_valid(_player_node):
		_find_player_node()
		if _player_node == null:
			return
	# read properties safely using get() (returns null if not present)
	var hp = 0.0
	var mx = 1.0
	var h = null
	var m = null
	# use get() as a general-purpose accessor
	h = _player_node.get(player_health_key)
	m = _player_node.get(player_max_health_key)
	if typeof(h) in [TYPE_INT, TYPE_FLOAT]:
		hp = float(h)
	if typeof(m) in [TYPE_INT, TYPE_FLOAT] and float(m) > 0.0:
		mx = float(m)

	# clamp
	hp = clamp(hp, 0.0, mx)
	# update bar
	if bar != null:
		bar.min_value = 0.0
		bar.max_value = progress_max_value
		# map hp/mx to progress range
		var value = (hp / max(mx, 1.0)) * progress_max_value
		bar.value = value

	# update label
	if value_label != null:
		if show_percentage:
			var pct = int(round((hp / max(mx, 1.0)) * 100.0))
			value_label.text = "%d%%" % pct
		else:
			# show "current / max"
			# show integers if values are ints
			if int(hp) == hp and int(mx) == mx:
				value_label.text = "%d / %d" % [int(hp), int(mx)]
			else:
				value_label.text = "%.1f / %.1f" % [hp, mx]

# Optional helper to set a specific player node (useful if you spawn player later)
func set_player_node(node: Node) -> void:
	_player_node = node
	if not update_mode_poll:
		_try_connect_player_signals()
	visible = true
