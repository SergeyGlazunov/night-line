extends RefCounted

const SAVE_PATH := "user://night_line_save.cfg"

const MODE_20 := "20"
const MODE_40 := "40"
const MODE_OFF := "off"
const ONBOARDING_COMPLETE := 3

var save_path: String = SAVE_PATH
var tickets: int = 0
var interval_mode: String = MODE_20
var muted: bool = false
var hidden: bool = false
var screen_index: int = 0
var has_passenger: bool = true
var has_cafe: bool = false
var has_greenhouse: bool = false
var has_radio: bool = false
var onboarding_step: int = 0
var use_mock_preview: bool = false
var debug_time_scale: float = 1.0
var journey_phase: String = "travel"
# Negative remaining time means an older save has no journey snapshot yet.
var journey_remaining: float = -1.0
var station_progress: float = 0.0


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(save_path) != OK:
		return

	tickets = int(cfg.get_value("progress", "tickets", tickets))
	interval_mode = str(cfg.get_value("prefs", "interval_mode", interval_mode))
	muted = bool(cfg.get_value("prefs", "muted", muted))
	hidden = bool(cfg.get_value("prefs", "hidden", hidden))
	screen_index = int(cfg.get_value("prefs", "screen_index", screen_index))
	has_passenger = bool(cfg.get_value("train", "has_passenger", has_passenger))
	has_cafe = bool(cfg.get_value("train", "has_cafe", has_cafe))
	has_greenhouse = bool(cfg.get_value("train", "has_greenhouse", has_greenhouse))
	has_radio = bool(cfg.get_value("train", "has_radio", has_radio))
	use_mock_preview = bool(cfg.get_value("prefs", "use_mock_preview", use_mock_preview))
	debug_time_scale = float(cfg.get_value("debug", "time_scale", debug_time_scale))

	if cfg.has_section_key("progress", "onboarding_step"):
		onboarding_step = clampi(
			int(cfg.get_value("progress", "onboarding_step", onboarding_step)),
			0,
			ONBOARDING_COMPLETE
		)
	else:
		# Saves from the prototype predate onboarding and already grant its cars.
		onboarding_step = ONBOARDING_COMPLETE

	if interval_mode not in [MODE_20, MODE_40, MODE_OFF]:
		interval_mode = MODE_20
	debug_time_scale = clampf(debug_time_scale, 1.0, 120.0)
	journey_phase = str(cfg.get_value("journey", "phase", "travel"))
	if journey_phase not in ["travel", "approach", "station", "departure"]:
		journey_phase = "travel"
	journey_remaining = float(cfg.get_value("journey", "remaining", -1.0))
	if not is_finite(journey_remaining):
		journey_remaining = -1.0
	journey_remaining = clampf(journey_remaining, -1.0, 2400.0)
	station_progress = float(cfg.get_value("journey", "station_progress", 0.0))
	if not is_finite(station_progress):
		station_progress = 0.0
	station_progress = clampf(station_progress, 0.0, 1.0)


func save_game() -> Error:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "tickets", tickets)
	cfg.set_value("progress", "onboarding_step", onboarding_step)
	cfg.set_value("prefs", "interval_mode", interval_mode)
	cfg.set_value("prefs", "muted", muted)
	cfg.set_value("prefs", "hidden", hidden)
	cfg.set_value("prefs", "screen_index", screen_index)
	cfg.set_value("prefs", "use_mock_preview", use_mock_preview)
	cfg.set_value("train", "has_passenger", has_passenger)
	cfg.set_value("train", "has_cafe", has_cafe)
	cfg.set_value("train", "has_greenhouse", has_greenhouse)
	cfg.set_value("train", "has_radio", has_radio)
	cfg.set_value("debug", "time_scale", debug_time_scale)
	cfg.set_value("journey", "phase", journey_phase)
	cfg.set_value("journey", "remaining", journey_remaining)
	cfg.set_value("journey", "station_progress", station_progress)
	# One replacement commits Tickets and journey state together.
	var temporary := save_path + ".tmp"
	var error := cfg.save(temporary)
	if error == OK:
		error = DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(save_path))
	if error != OK:
		push_error("Cannot save Night Line: " + error_string(error))
	return error


func mode_label() -> String:
	match interval_mode:
		MODE_20:
			return "20"
		MODE_40:
			return "40"
		MODE_OFF:
			return "Off"
		_:
			return MODE_20
