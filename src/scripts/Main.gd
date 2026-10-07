extends Node2D

const SaveMgr = preload("res://scripts/SaveManager.gd")

const WINDOW_HEIGHT := 120
const TUNNEL_FIRST_DELAY := 20.0
const TUNNEL_INTERVAL := 70.0
const TUNNEL_DURATION := 8.0
const TUNNEL_FADE_IN := 1.2
const TUNNEL_FADE_OUT := 1.5
const TUNNEL_MAX_ALPHA := 0.72
const HIDE_TOGGLE_DEBOUNCE_MS := 300

const FOG_FIRST_DELAY := 12.0
const FOG_INTERVAL := 55.0
const FOG_HOLD := 14.0
const FOG_FADE := 2.5
const FOG_MAX_ALPHA := 0.28

const STATION_PANEL_SIZE := Vector2(400, 64)
const REAL_INTERVAL_20_SEC := 20.0 * 60.0
const REAL_INTERVAL_40_SEC := 40.0 * 60.0

# Temporary full-scene art preview. ColorRect prototype stays in the tree.
const USE_MOCK_PREVIEW := true
const MOCK_PATH := "res://assets/sprites/mock.png"
const MOCK_FOCUS_Y := 0.5

@onready var _mountains_layer: Parallax2D = $MountainsLayer
@onready var _forest_layer: Parallax2D = $ForestLayer
@onready var _rail_loop: AudioStreamPlayer = $Audio/RailLoop
@onready var _rain_loop: AudioStreamPlayer = $Audio/RainLoop
@onready var _cafe_loop: AudioStreamPlayer = $Audio/CafeLoop
@onready var _radio_loop: AudioStreamPlayer = $Audio/RadioLoop
@onready var _tunnel_sfx: AudioStreamPlayer = $Audio/TunnelSfx
@onready var _tunnel_overlay: ColorRect = $TunnelOverlay
@onready var _fog_overlay: ColorRect = $FogOverlay
@onready var _mock_preview: Node2D = $MockPreview
@onready var _mock_sprite: Sprite2D = $MockPreview/Sprite
@onready var _station_root: Control = $StationUI/Root
@onready var _station_panel: Control = $StationUI/Root/Panel
@onready var _station_title: Label = $StationUI/Root/Panel/Margin/VBox/Title
@onready var _station_body: Label = $StationUI/Root/Panel/Margin/VBox/Body
@onready var _take_button: Button = $StationUI/Root/Panel/Margin/VBox/Buttons/TakeButton
@onready var _skip_button: Button = $StationUI/Root/Panel/Margin/VBox/Buttons/SkipButton
@onready var _status_label: Label = $StatusHUD/Bar/StatusLabel
@onready var _mode20_button: Button = $StatusHUD/Bar/Buttons/Mode20Button
@onready var _mode40_button: Button = $StatusHUD/Bar/Buttons/Mode40Button
@onready var _mode_off_button: Button = $StatusHUD/Bar/Buttons/ModeOffButton
@onready var _station_button: Button = $StatusHUD/Bar/Buttons/StationButton
@onready var _speed_button: Button = $StatusHUD/Bar/Buttons/SpeedButton

var _save = null
var _hidden := false
var _in_tunnel := false
var _in_fog := false
var _station_open := false
var _event_lock := false
var _last_hide_toggle_ms := 0
var _use_mock_preview := USE_MOCK_PREVIEW
var _station_token := 0

var _mountains_scroll := Vector2(-30, 0)
var _forest_scroll := Vector2(-90, 0)
var _prototype_visuals: Array[CanvasItem] = []


func _ready() -> void:
	_save = SaveMgr.new()

	_prototype_visuals = [
		$Sky as CanvasItem,
		$MountainsLayer as CanvasItem,
		$ForestLayer as CanvasItem,
		$Ground as CanvasItem,
		$Train as CanvasItem,
	]

	_mountains_scroll = _mountains_layer.autoscroll
	_forest_scroll = _forest_layer.autoscroll

	_take_button.pressed.connect(_on_take_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_mode20_button.pressed.connect(func() -> void: set_interval_mode(SaveMgr.MODE_20))
	_mode40_button.pressed.connect(func() -> void: set_interval_mode(SaveMgr.MODE_40))
	_mode_off_button.pressed.connect(func() -> void: set_interval_mode(SaveMgr.MODE_OFF))
	_station_button.pressed.connect(_on_station_button_pressed)
	_speed_button.pressed.connect(cycle_debug_time_scale)
	_station_root.visible = false
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	_save.load_game()
	_use_mock_preview = _save.use_mock_preview

	# Apply window chrome after the first frame so DisplayServer is ready.
	call_deferred("_boot_window_and_game")


func _boot_window_and_game() -> void:
	setup_window()
	_apply_mute_state()
	_ensure_mock_texture()
	_apply_visual_mode()
	start_ambiance()
	_update_status_hud()

	_schedule_fog(FOG_FIRST_DELAY)
	_schedule_tunnel(TUNNEL_FIRST_DELAY)
	_restart_station_schedule(true)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist_save()


func _on_viewport_size_changed() -> void:
	if _use_mock_preview:
		_layout_mock_preview()
	if _station_open:
		_layout_station_panel()


func setup_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var screen_count := DisplayServer.get_screen_count()
	var screen_index := clampi(_save.screen_index, 0, maxi(0, screen_count - 1))
	DisplayServer.window_set_current_screen(screen_index)

	var screen_rect := DisplayServer.screen_get_usable_rect(screen_index)
	var window_width: int = screen_rect.size.x
	DisplayServer.window_set_size(Vector2i(window_width, WINDOW_HEIGHT))

	var target_pos_y: int = screen_rect.position.y + screen_rect.size.y - WINDOW_HEIGHT
	DisplayServer.window_set_position(Vector2i(screen_rect.position.x, target_pos_y))

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)

	_save.screen_index = screen_index
	if _use_mock_preview:
		_layout_mock_preview()


func _apply_visual_mode() -> void:
	for node in _prototype_visuals:
		node.visible = not _use_mock_preview
	_mock_preview.visible = _use_mock_preview
	if _use_mock_preview:
		_ensure_mock_texture()
		_layout_mock_preview()


func _ensure_mock_texture() -> void:
	if _mock_sprite.texture != null and _mock_sprite.texture.get_width() > 0:
		return

	var image := Image.new()
	var abs_path := ProjectSettings.globalize_path(MOCK_PATH)
	var err := image.load(abs_path)
	if err != OK:
		push_error("Failed to load mock preview: %s (%s)" % [abs_path, error_string(err)])
		return

	_mock_sprite.texture = ImageTexture.create_from_image(image)
	_mock_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _layout_mock_preview() -> void:
	_ensure_mock_texture()
	if _mock_sprite.texture == null:
		return

	var source_size := Vector2(
		_mock_sprite.texture.get_width(),
		_mock_sprite.texture.get_height()
	)
	if source_size.x <= 0.0 or source_size.y <= 0.0:
		return

	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		vp = Vector2(1920.0, float(WINDOW_HEIGHT))

	# New mock is already strip-shaped (e.g. 1920x180): fit width, center vertically.
	var scale := vp.x / source_size.x
	var scaled_h := source_size.y * scale
	var top := (scaled_h - vp.y) * MOCK_FOCUS_Y
	top = clampf(top, 0.0, maxf(0.0, scaled_h - vp.y))

	_mock_sprite.scale = Vector2(scale, scale)
	_mock_sprite.position = Vector2(0.0, -top)


func toggle_mock_preview() -> void:
	_use_mock_preview = not _use_mock_preview
	_save.use_mock_preview = _use_mock_preview
	_apply_visual_mode()
	_persist_save()


func start_ambiance() -> void:
	_ensure_loop(_rail_loop)
	_ensure_loop(_rain_loop)
	_ensure_loop(_cafe_loop)
	_ensure_loop(_radio_loop)

	_play_if_needed(_rail_loop)
	_play_if_needed(_rain_loop)

	if _save.has_cafe:
		_play_if_needed(_cafe_loop)
	else:
		_cafe_loop.stop()

	if _save.has_radio:
		_play_if_needed(_radio_loop)
	else:
		_radio_loop.stop()


func _play_if_needed(player: AudioStreamPlayer) -> void:
	if player.stream != null and not player.playing:
		player.play()


func _ensure_loop(player: AudioStreamPlayer) -> void:
	var stream := player.stream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


func toggle_hide() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_hide_toggle_ms < HIDE_TOGGLE_DEBOUNCE_MS:
		return
	_last_hide_toggle_ms = now

	if _hidden:
		_show_strip()
	else:
		_hide_strip()


func _hide_strip() -> void:
	_hidden = true
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_size(Vector2i(1, 1))
	DisplayServer.window_set_position(Vector2i(-10000, -10000))


func _show_strip() -> void:
	_hidden = false
	setup_window()


func toggle_mute() -> void:
	_save.muted = not _save.muted
	_apply_mute_state()
	_persist_save()
	_update_status_hud()


func _apply_mute_state() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _save.muted)


func set_interval_mode(mode: String) -> void:
	if mode not in [SaveMgr.MODE_20, SaveMgr.MODE_40, SaveMgr.MODE_OFF]:
		return
	if _save.interval_mode == mode:
		return

	_save.interval_mode = mode
	_persist_save()
	_update_status_hud()
	_restart_station_schedule(true)


func cycle_debug_time_scale() -> void:
	match int(_save.debug_time_scale):
		1:
			_save.debug_time_scale = 10.0
		10:
			_save.debug_time_scale = 60.0
		_:
			_save.debug_time_scale = 1.0
	_persist_save()
	_update_status_hud()
	_restart_station_schedule(true)


func _station_interval_seconds() -> float:
	var real := 0.0
	match _save.interval_mode:
		SaveMgr.MODE_20:
			real = REAL_INTERVAL_20_SEC
		SaveMgr.MODE_40:
			real = REAL_INTERVAL_40_SEC
		_:
			return 0.0
	return maxf(1.0, real / maxf(1.0, _save.debug_time_scale))


func _restart_station_schedule(_immediate_countdown: bool) -> void:
	_station_token += 1
	if _save.interval_mode == SaveMgr.MODE_OFF:
		_update_status_hud()
		return
	_schedule_station(_station_interval_seconds())


func _set_parallax_running(running: bool) -> void:
	if running:
		_mountains_layer.autoscroll = _mountains_scroll
		_forest_layer.autoscroll = _forest_scroll
	else:
		_mountains_layer.autoscroll = Vector2.ZERO
		_forest_layer.autoscroll = Vector2.ZERO


func _schedule_fog(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(_on_fog_due, CONNECT_ONE_SHOT)


func _on_fog_due() -> void:
	await run_fog()
	_schedule_fog(FOG_INTERVAL)


func run_fog() -> void:
	if _station_open or _in_tunnel or _in_fog:
		return

	_in_fog = true
	var fade_in := create_tween()
	fade_in.tween_property(_fog_overlay, "color:a", FOG_MAX_ALPHA, FOG_FADE)
	await fade_in.finished

	await get_tree().create_timer(FOG_HOLD).timeout

	if _station_open:
		_in_fog = false
		return

	var fade_out := create_tween()
	fade_out.tween_property(_fog_overlay, "color:a", 0.0, FOG_FADE)
	await fade_out.finished
	_in_fog = false


func _schedule_tunnel(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(_on_tunnel_due, CONNECT_ONE_SHOT)


func _on_tunnel_due() -> void:
	await run_tunnel()
	_schedule_tunnel(TUNNEL_INTERVAL)


func run_tunnel() -> void:
	if _in_tunnel or _station_open or _event_lock:
		return

	_in_tunnel = true
	_event_lock = true

	var fade_in := create_tween()
	fade_in.tween_property(_tunnel_overlay, "color:a", TUNNEL_MAX_ALPHA, TUNNEL_FADE_IN)
	await fade_in.finished

	if _tunnel_sfx.stream != null:
		_tunnel_sfx.play()

	await get_tree().create_timer(TUNNEL_DURATION).timeout

	if _tunnel_sfx.playing:
		_tunnel_sfx.stop()

	var fade_out := create_tween()
	fade_out.tween_property(_tunnel_overlay, "color:a", 0.0, TUNNEL_FADE_OUT)
	await fade_out.finished

	_in_tunnel = false
	_event_lock = false


func _schedule_station(delay: float) -> void:
	_station_token += 1
	var token := _station_token
	get_tree().create_timer(delay).timeout.connect(
		func() -> void:
			if token != _station_token:
				return
			await _on_station_due()
	)


func _on_station_due() -> void:
	if _save.interval_mode == SaveMgr.MODE_OFF:
		return
	await open_station()
	if _save.interval_mode != SaveMgr.MODE_OFF:
		_schedule_station(_station_interval_seconds())


func open_station(force: bool = false) -> void:
	if _station_open:
		return
	if not force and _save.interval_mode == SaveMgr.MODE_OFF:
		return

	var waited := 0.0
	while (_in_tunnel or _event_lock) and waited < 20.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5

	if _hidden:
		_show_strip()

	_station_open = true
	_event_lock = true
	_set_parallax_running(false)

	_station_title.text = "Hollow Creek · arrival"
	_station_body.text = "Passenger: night-shift nurse  ·  +12 tickets  ·  now %dt" % _save.tickets
	_layout_station_panel()
	_station_root.visible = true
	_update_status_hud()


func _layout_station_panel() -> void:
	var vp := get_viewport().get_visible_rect().size
	var panel_size := STATION_PANEL_SIZE
	panel_size.y = minf(panel_size.y, maxf(52.0, vp.y - 16.0))
	_station_panel.size = panel_size
	_station_panel.position = Vector2(
		(vp.x - panel_size.x) * 0.5,
		(vp.y - panel_size.y) * 0.5
	)


func _on_take_pressed() -> void:
	_resolve_station(true)


func _on_skip_pressed() -> void:
	_resolve_station(false)


func _resolve_station(took_passenger: bool) -> void:
	if not _station_open:
		return

	if took_passenger and _save.interval_mode != SaveMgr.MODE_OFF:
		_save.tickets += 12
		_persist_save()

	_station_root.visible = false
	_station_open = false
	_event_lock = false
	_set_parallax_running(true)
	_update_status_hud()

	if _fog_overlay.color.a > 0.0 and not _in_fog:
		var clear_fog := create_tween()
		clear_fog.tween_property(_fog_overlay, "color:a", 0.0, 1.0)


func _on_station_button_pressed() -> void:
	skip_to_station()


func skip_to_station() -> void:
	if _station_open:
		return
	_station_token += 1
	await open_station(true)
	if _save.interval_mode != SaveMgr.MODE_OFF:
		_schedule_station(_station_interval_seconds())


func _persist_save() -> void:
	if _save == null:
		return
	_save.use_mock_preview = _use_mock_preview
	_save.screen_index = DisplayServer.window_get_current_screen()
	_save.save_game()


func _update_status_hud() -> void:
	if _save == null:
		return
	var mode_text := "Off"
	match _save.interval_mode:
		SaveMgr.MODE_20:
			mode_text = "20 min"
		SaveMgr.MODE_40:
			mode_text = "40 min"
	var mute_mark := "   MUTE" if _save.muted else ""
	_status_label.text = "Mode: %s   Tickets: %d   speed x%.0f%s" % [
		mode_text,
		_save.tickets,
		_save.debug_time_scale,
		mute_mark,
	]
	_speed_button.text = "x%.0f" % _save.debug_time_scale


func _is_key(event: InputEventKey, code: Key) -> bool:
	return (
		event.physical_keycode == code
		or event.keycode == code
		or event.key_label == code
	)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _station_open:
			_resolve_station(false)
			return
		_persist_save()
		get_tree().quit()
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var key_event := event as InputEventKey
	if _is_key(key_event, KEY_H) and not _station_open:
		toggle_hide()
	elif _is_key(key_event, KEY_M):
		toggle_mute()
	elif _is_key(key_event, KEY_P):
		toggle_mock_preview()
	elif _is_key(key_event, KEY_1) or _is_key(key_event, KEY_KP_1):
		set_interval_mode(SaveMgr.MODE_20)
	elif _is_key(key_event, KEY_2) or _is_key(key_event, KEY_KP_2):
		set_interval_mode(SaveMgr.MODE_40)
	elif _is_key(key_event, KEY_3) or _is_key(key_event, KEY_KP_3):
		set_interval_mode(SaveMgr.MODE_OFF)
	elif _is_key(key_event, KEY_0) or _is_key(key_event, KEY_KP_0):
		cycle_debug_time_scale()
	elif _is_key(key_event, KEY_9) or _is_key(key_event, KEY_KP_9):
		skip_to_station()
