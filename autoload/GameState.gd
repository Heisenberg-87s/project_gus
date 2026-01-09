extends Node

# Global caution state (shared across scenes)
@export var caution_time_remaining: float = 0.0
var caution_total_duration: float = 0.0
var is_in_caution: bool = false
var last_player_spawn_marker: String = ""

func _ready() -> void:
	print("[GameState] ready. initial caution_time_remaining=", caution_time_remaining, " is_in_caution=", is_in_caution)

func _process(delta: float) -> void:
	if is_in_caution and caution_time_remaining > 0.0:
		caution_time_remaining = max(caution_time_remaining - delta, 0.0)
		# Debug: tick occasionally to avoid spam
		if int(caution_time_remaining) != int(caution_time_remaining + delta) or caution_time_remaining <= 1.0:
			print("[GameState] ticking, remaining:", "%.2f" % caution_time_remaining)
		if caution_time_remaining <= 0.0:
			is_in_caution = false
			caution_total_duration = 0.0
			last_player_spawn_marker = ""
			print("[GameState] caution ended")

# Called before performing level transfer so new level can use spawn marker + preserve timer
func prepare_transfer_spawn(spawn_marker_name: String, time_remaining: float) -> void:
	print("[GameState] prepare_transfer_spawn:", spawn_marker_name, "time_remaining:", time_remaining, "prev_remain:", caution_time_remaining, "is_in_caution:", is_in_caution)
	if spawn_marker_name != "":
		last_player_spawn_marker = spawn_marker_name
	if time_remaining > 0.0:
		if not is_in_caution or time_remaining > caution_time_remaining:
			caution_time_remaining = time_remaining
			caution_total_duration = time_remaining
			is_in_caution = true
			print("[GameState] preserved/started caution: remaining=", caution_time_remaining)

# Called by enemies when they start their evasion countdown so the global timer exists / extends
func start_global_caution(duration: float) -> void:
	if duration <= 0.0:
		return
	print("[GameState] start_global_caution requested duration=", duration, "current_remaining=", caution_time_remaining, "is_in_caution=", is_in_caution)
	if not is_in_caution:
		is_in_caution = true
		caution_time_remaining = duration
		caution_total_duration = duration
		print("[GameState] started global caution duration=", duration)
	else:
		# extend if longer than current remaining
		if duration > caution_time_remaining:
			caution_time_remaining = duration
			caution_total_duration = duration
			print("[GameState] extended global caution to duration=", duration)
