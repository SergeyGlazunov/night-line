class_name SaveManager
extends RefCounted

const SAVE_PATH := "user://night_line_save.cfg"

const MODE_20 := "20"
const MODE_40 := "40"
const MODE_OFF := "off"

var tickets: int = 0
var interval_mode: String = MODE_20
var muted: bool = false
var screen_index: int = 0
var has_passenger: bool = true
var has_cafe: bool = true
var has_radio: bool = true
var use_mock_preview: bool = true
var debug_time_scale: float = 60.0


func load_game() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return

	tickets = int(cfg.get_value("progress", "tickets", tickets))
	interval_mode = str(cfg.get_value("prefs", "interval_mode", interval_mode))
	muted = bool(cfg.get_value("prefs", "muted", muted))
	screen_index = int(cfg.get_value("prefs", "screen_index", screen_index))
	has_passenger = bool(cfg.get_value("train", "has_passenger", has_passenger))
	has_cafe = bool(cfg.get_value("train", "has_cafe", has_cafe))
	has_radio = bool(cfg.get_value("train", "has_radio", has_radio))
	use_mock_preview = bool(cfg.get_value("prefs", "use_mock_preview", use_mock_preview))
	debug_time_scale = float(cfg.get_value("debug", "time_scale", debug_time_scale))

	if interval_mode not in [MODE_20, MODE_40, MODE_OFF]:
		interval_mode = MODE_20
	debug_time_scale = clampf(debug_time_scale, 1.0, 120.0)


func save_game() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("progress", "tickets", tickets)
	cfg.set_value("prefs", "interval_mode", interval_mode)
	cfg.set_value("prefs", "muted", muted)
	cfg.set_value("prefs", "screen_index", screen_index)
	cfg.set_value("prefs", "use_mock_preview", use_mock_preview)
	cfg.set_value("train", "has_passenger", has_passenger)
	cfg.set_value("train", "has_cafe", has_cafe)
	cfg.set_value("train", "has_radio", has_radio)
	cfg.set_value("debug", "time_scale", debug_time_scale)
	cfg.save(SAVE_PATH)


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
