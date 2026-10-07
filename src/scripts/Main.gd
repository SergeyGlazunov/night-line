extends Node2D

const SaveMgr = preload("res://scripts/SaveManager.gd")
const Onboarding = preload("res://scripts/OnboardingFlow.gd")

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

const STATION_PANEL_SIZE := Vector2(440, 80)
const STATION_APPROACH_SECONDS := 4.0
const STATION_DEPART_SECONDS := 2.0
const AUTO_STATION_PAUSE := 1.0
const AUTOSAVE_INTERVAL := 5.0
const BASE_STATION_REWARD := 12
const REAL_INTERVAL_20_SEC := 20.0 * 60.0
const REAL_INTERVAL_40_SEC := 40.0 * 60.0

# Temporary full-scene art preview. ColorRect prototype stays in the tree.
const USE_MOCK_PREVIEW := false
const MOCK_PATH := "res://assets/sprites/mock.png"
# Approximate share of mock art that is the bottom ground band.
const MOCK_GROUND_FRAC := 0.24

@onready var _mountains_layer: Parallax2D = $MountainsLayer
@onready var _forest_layer: Parallax2D = $ForestLayer
@onready var _rail_loop: AudioStreamPlayer = $Audio/RailLoop
@onready var _rain_loop: AudioStreamPlayer = $Audio/RainLoop
@onready var _cafe_loop: AudioStreamPlayer = $Audio/CafeLoop
@onready var _radio_loop: AudioStreamPlayer = $Audio/RadioLoop
@onready var _greenhouse_loop: AudioStreamPlayer = $Audio/GreenhouseLoop
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
@onready var _status_label: Label = $StatusHUD/Bar/Margin/VBox/StatusLabel
@onready var _mode20_button: Button = $StatusHUD/Bar/Margin/VBox/Buttons/Mode20Button
@onready var _mode40_button: Button = $StatusHUD/Bar/Margin/VBox/Buttons/Mode40Button
@onready var _mode_off_button: Button = $StatusHUD/Bar/Margin/VBox/Buttons/ModeOffButton
@onready var _station_button: Button = $StatusHUD/Bar/Margin/VBox/Buttons/StationButton
@onready var _speed_button: Button = $StatusHUD/Bar/Margin/VBox/Buttons/SpeedButton
@onready var _station_marker: Node2D = $StationMarker
@onready var _countdown_label: Label = $StatusHUD/ArrivalInfo/Countdown
@onready var _arrival_notice: Label = $StatusHUD/ArrivalInfo/Notice

var _save := SaveMgr.new()
var _hidden := false
var _in_tunnel := false
var _in_fog := false
var _station_open := false
var _event_lock := false
var _last_hide_toggle_ms := 0
var _use_mock_preview := USE_MOCK_PREVIEW
var _station_pending := false
var _station_remaining := 0.0
var _countdown_active := false
var _departure_notice_left := 0.0
var _station_motion: Tween
var _station_departing := false
var _station_progress := 0.0
var _auto_depart_remaining := 0.0
var _autosave_remaining := AUTOSAVE_INTERVAL
var _booted := false
var _last_auto_reward := 0
var _hovered := false
var _controls_open := false
var _tray: StatusIndicator
var _screen_check_remaining := 2.0
var _last_screen_rect := Rect2i()
var _onboarding := Onboarding.new()

var _mountains_scroll := Vector2(-30, 0)
var _forest_scroll := Vector2(-90, 0)
var _prototype_visuals: Array[CanvasItem] = []


func _ready() -> void:
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
	$StatusHUD/Chrome.pressed.connect(_toggle_controls)
	$StatusHUD/Bar/Margin/VBox/DesktopButtons/HideButton.pressed.connect(toggle_hide)
	$StatusHUD/Bar/Margin/VBox/DesktopButtons/MuteButton.pressed.connect(toggle_mute)
	$StatusHUD/Bar/Margin/VBox/DesktopButtons/MonitorButton.pressed.connect(cycle_monitor)
	$StatusHUD/Bar/Margin/VBox/DesktopButtons/CloseButton.pressed.connect(_toggle_controls)
	get_window().mouse_entered.connect(_on_pointer_entered)
	get_window().mouse_exited.connect(_on_pointer_exited)
	get_window().focus_entered.connect(_on_window_focus)
	get_tree().auto_accept_quit = false
	_station_root.visible = false
	get_viewport().size_changed.connect(_on_viewport_size_changed)

	_save.load_game()
	_setup_tray()
	_use_mock_preview = _save.use_mock_preview
	# A full-scene illustration cannot represent onboarding ownership.
	if _is_onboarding():
		_use_mock_preview = false

	# Apply window chrome after the first frame so DisplayServer is ready.
	call_deferred("_boot_window_and_game")


func _boot_window_and_game() -> void:
	setup_window()
	_apply_mute_state()
	_ensure_mock_texture()
	_apply_visual_mode()
	_sync_train_visuals()
	start_ambiance()
	_restore_journey()
	_hidden = _save.hidden
	if _hidden:
		_hide_strip()
	_booted = true
	_update_status_hud()
	_schedule_fog(FOG_FIRST_DELAY)
	_schedule_tunnel(TUNNEL_FIRST_DELAY)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_persist_save()
		get_tree().quit()


func _process(delta: float) -> void:
	if not _booted:
		return
	_departure_notice_left = maxf(0.0, _departure_notice_left - delta)
	if _countdown_active:
		_station_remaining = maxf(0.0, _station_remaining - delta)
		if not _station_pending and _station_remaining <= STATION_APPROACH_SECONDS:
			open_station(false, maxf(0.1, _station_remaining))
	if _station_open and _is_automatic():
		_auto_depart_remaining -= delta
		if _auto_depart_remaining <= 0.0:
			_resolve_station(true)
	_autosave_remaining -= delta
	if _autosave_remaining <= 0.0:
		_persist_save()
		_autosave_remaining = AUTOSAVE_INTERVAL
	_screen_check_remaining -= delta
	if _screen_check_remaining <= 0.0:
		_screen_check_remaining = 2.0
		_check_monitor_layout()
	_update_arrival_info()


func _update_arrival_info() -> void:
	if _station_open:
		_countdown_label.text = "На станции: Hollow Creek"
		_arrival_notice.text = "Поезд остановился"
		if _is_automatic():
			_arrival_notice.text = "Автоматическая остановка · +%d Tickets" % _station_reward()
	elif _station_pending:
		_countdown_label.text = "До станции: %s" % _format_station_time(_station_remaining)
		_arrival_notice.text = "Прибываем на станцию…"
	elif _countdown_active:
		_countdown_label.text = "До станции: %s" % _format_station_time(_station_remaining)
		_arrival_notice.text = ""
		if _station_remaining <= 60.0 or _departure_notice_left > 0.0:
			var seconds := int(ceil(_station_remaining))
			_arrival_notice.text = "Следующая станция через %d мин." % int(ceil(seconds / 60.0)) if seconds > 60 else "Прибытие через %d сек." % seconds
		if _departure_notice_left > 0.0 and _last_auto_reward > 0:
			_arrival_notice.text = "Автоматически получено +%d Tickets" % _last_auto_reward
	else:
		_countdown_label.text = "Остановки отключены"
		_arrival_notice.text = ""


func _format_station_time(seconds: float) -> String:
	var total := int(ceil(maxf(0.0, seconds)))
	return "%02d:%02d" % [total / 60, total % 60]


func _on_viewport_size_changed() -> void:
	_resize_strip_layers()
	if _use_mock_preview:
		_layout_mock_preview()
	if _station_open:
		_layout_station_panel()


func setup_window() -> void:
	var screen_count := DisplayServer.get_screen_count()
	var screen_index := clampi(_save.screen_index, 0, maxi(0, screen_count - 1))
	var screen_rect := DisplayServer.screen_get_usable_rect(screen_index)
	if screen_rect.size.x <= 0:
		screen_rect = Rect2i(0, 0, 1920, 1080)
	_last_screen_rect = screen_rect

	# Use Window API (same path for Project Manager run and Editor F5).
	# content_scale_factor=1 keeps Control hitboxes aligned with pixels.
	var win := get_window()
	win.mode = Window.MODE_WINDOWED
	win.borderless = true
	win.always_on_top = true
	win.current_screen = screen_index
	win.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	win.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_IGNORE
	win.content_scale_factor = 1.0

	var window_width: int = maxi(WINDOW_HEIGHT, screen_rect.size.x)
	win.size = Vector2i(window_width, WINDOW_HEIGHT)
	win.position = Vector2i(
		screen_rect.position.x,
		screen_rect.position.y + screen_rect.size.y - WINDOW_HEIGHT
	)

	# Mirror via DisplayServer for hosts that ignore Window flags on first frame.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)
	DisplayServer.window_set_size(win.size)
	DisplayServer.window_set_position(win.position)

	_save.screen_index = screen_index
	call_deferred("_after_window_ready")


func cycle_monitor() -> void:
	var count := maxi(1, DisplayServer.get_screen_count())
	_save.screen_index = (_save.screen_index + 1) % count
	if not _hidden:
		setup_window()
	_persist_save()
	_update_status_hud()


func _check_monitor_layout() -> void:
	if DisplayServer.get_name() == "headless":
		return
	var index := clampi(_save.screen_index, 0, maxi(0, DisplayServer.get_screen_count() - 1))
	var rect := DisplayServer.screen_get_usable_rect(index)
	if index != _save.screen_index or rect != _last_screen_rect:
		_save.screen_index = index
		_last_screen_rect = rect
		if not _hidden:
			setup_window()
		_persist_save()


func _setup_tray() -> void:
	if not DisplayServer.has_feature(DisplayServer.FEATURE_STATUS_INDICATOR):
		return
	_tray = StatusIndicator.new()
	_tray.icon = preload("res://icon.svg")
	_tray.tooltip = "NIGHT LINE · клик: показать / скрыть · правый клик: звук"
	_tray.pressed.connect(_on_tray_pressed)
	add_child(_tray)


func _on_tray_pressed(button: int, _position: Vector2i) -> void:
	if button == MOUSE_BUTTON_LEFT:
		toggle_hide()
	elif button == MOUSE_BUTTON_RIGHT:
		toggle_mute()


func _on_pointer_entered() -> void:
	_hovered = true
	_update_status_hud()


func _on_window_focus() -> void:
	# Restoring from the taskbar must behave like restoring from the tray.
	if _booted and _hidden and get_window().mode != Window.MODE_MINIMIZED:
		_show_strip()


func _on_pointer_exited() -> void:
	_hovered = false
	_controls_open = false
	_update_status_hud()


func _toggle_controls() -> void:
	_controls_open = not _controls_open
	_update_status_hud()


func _after_window_ready() -> void:
	_resize_strip_layers()
	if _use_mock_preview:
		_layout_mock_preview()
	_update_status_hud()


func _resize_strip_layers() -> void:
	var vp := get_viewport().get_visible_rect().size
	if vp.x < 2.0 or vp.y < 2.0:
		vp = Vector2(1920.0, float(WINDOW_HEIGHT))

	$Sky.size = vp
	_fog_overlay.size = vp
	_tunnel_overlay.size = vp
	$Ground.size = Vector2(vp.x, $Ground.size.y)
	if has_node("Ground/Rail"):
		$Ground/Rail.size = Vector2(vp.x, $Ground/Rail.size.y)
	if has_node("MountainsLayer/Mountains"):
		$MountainsLayer/Mountains.size = Vector2(vp.x, $MountainsLayer/Mountains.size.y)
	if has_node("ForestLayer/Forest"):
		$ForestLayer/Forest.size = Vector2(vp.x, $ForestLayer/Forest.size.y)


func _apply_visual_mode() -> void:
	var show_mock := _use_mock_preview and not _station_marker.visible
	for node in _prototype_visuals:
		node.visible = not show_mock
	_mock_preview.visible = show_mock
	if show_mock:
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

	# Fit width, keep only half of the bottom ground band in frame.
	var scale := vp.x / source_size.x
	var scaled_h := source_size.y * scale
	var max_top := maxf(0.0, scaled_h - vp.y)
	var ground_keep := scaled_h * MOCK_GROUND_FRAC * 0.5
	var top := clampf(scaled_h - vp.y - ground_keep, 0.0, max_top)

	_mock_sprite.scale = Vector2(scale, scale)
	_mock_sprite.position = Vector2(0.0, -top)


func toggle_mock_preview() -> void:
	if _is_onboarding():
		return
	_use_mock_preview = not _use_mock_preview
	_save.use_mock_preview = _use_mock_preview
	_apply_visual_mode()
	_persist_save()


func start_ambiance() -> void:
	_ensure_loop(_rail_loop)
	_ensure_loop(_rain_loop)
	_ensure_loop(_cafe_loop)
	_ensure_loop(_radio_loop)
	_ensure_loop(_greenhouse_loop)

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
	if _save.has_greenhouse:
		_play_if_needed(_greenhouse_loop)
	else:
		_greenhouse_loop.stop()


func _sync_train_visuals() -> void:
	var cars := [$Train/PassengerCar, $Train/CafeCar, $Train/GreenhouseCar, $Train/RadioCar]
	var owned := [_save.has_passenger, _save.has_cafe, _save.has_greenhouse, _save.has_radio]
	var couplers := [$Train/CouplerA, $Train/CouplerB, $Train/CouplerC, $Train/CouplerD]
	for coupler in couplers:
		coupler.visible = false
	var count := 0
	for i in range(cars.size()):
		cars[i].visible = owned[i]
		if owned[i]:
			cars[i].position.x = count * 110.0
			couplers[count].position.x = count * 110.0 + 100.0
			couplers[count].visible = true
			count += 1
	$Train/Locomotive.position.x = count * 110.0


func _is_onboarding() -> bool:
	return _save.onboarding_step < Onboarding.STEP_COMPLETE


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
	_hovered = false
	_controls_open = false
	# Minimize instead of moving a 1x1 window off-screen: retain its viewport,
	# keep the audio running, and allow return via tray or the taskbar.
	get_window().always_on_top = false
	get_window().mode = Window.MODE_MINIMIZED
	if _booted:
		_persist_save()
	_update_status_hud()


func _show_strip() -> void:
	_hidden = false
	setup_window()
	_persist_save()


func toggle_mute() -> void:
	_save.muted = not _save.muted
	_apply_mute_state()
	if _save.muted:
		_hide_strip()
	_persist_save()
	_update_status_hud()


func _apply_mute_state() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _save.muted)


func set_interval_mode(mode: String) -> void:
	if _is_onboarding() or _station_open or _station_pending:
		return
	if mode not in [SaveMgr.MODE_20, SaveMgr.MODE_40, SaveMgr.MODE_OFF]:
		return
	if _save.interval_mode == mode:
		return

	_save.interval_mode = mode
	_update_status_hud()
	_restart_station_schedule(true)
	_persist_save()


func cycle_debug_time_scale() -> void:
	if _station_open or _station_pending:
		return
	var old_scale := _save.debug_time_scale
	match int(_save.debug_time_scale):
		1:
			_save.debug_time_scale = 10.0
		10:
			_save.debug_time_scale = 60.0
		_:
			_save.debug_time_scale = 1.0
	_update_status_hud()
	if _countdown_active:
		_station_remaining *= old_scale / _save.debug_time_scale
	_persist_save()
	_update_arrival_info()


func _station_interval_seconds() -> float:
	var real := 0.0
	if _is_onboarding():
		return _onboarding.interval_seconds(_save.onboarding_step) / maxf(1.0, _save.debug_time_scale)
	match _save.interval_mode:
		SaveMgr.MODE_20, SaveMgr.MODE_OFF:
			real = REAL_INTERVAL_20_SEC
		SaveMgr.MODE_40:
			real = REAL_INTERVAL_40_SEC
		_:
			return 0.0
	return maxf(1.0, real / maxf(1.0, _save.debug_time_scale))


func _restart_station_schedule(_immediate_countdown: bool) -> void:
	_countdown_active = false
	if _station_open or _station_pending:
		_update_status_hud()
		_update_arrival_info()
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
	if _station_open or _station_pending or _in_tunnel or _in_fog:
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
	# The first tunnel shares the 20-second deadline with the welcome station.
	# Keep that first reward on time instead of waiting for a full tunnel pass.
	if _save.onboarding_step != Onboarding.STEP_CAFE:
		await run_tunnel()
	_schedule_tunnel(TUNNEL_INTERVAL)


func run_tunnel() -> void:
	if _in_tunnel or _station_open or _station_pending or _event_lock:
		return
	# Leave enough time to exit the tunnel before the station comes into view.
	if _countdown_active and _station_remaining <= STATION_APPROACH_SECONDS + TUNNEL_FADE_IN + TUNNEL_DURATION + TUNNEL_FADE_OUT:
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
	_station_remaining = delay
	_countdown_active = true
	_departure_notice_left = 6.0
	_update_arrival_info()


func _is_automatic() -> bool:
	return not _is_onboarding() and _save.interval_mode == SaveMgr.MODE_OFF


func _station_reward() -> int:
	return BASE_STATION_REWARD * (2 if _save.interval_mode == SaveMgr.MODE_40 else 1)


func _restore_journey() -> void:
	_station_remaining = _save.journey_remaining
	if _station_remaining < 0.0:
		_restart_station_schedule(true)
		return
	match _save.journey_phase:
		"station":
			_arrive_at_station()
		"approach":
			open_station(true, maxf(0.05, _station_remaining), _save.station_progress)
		"departure":
			_countdown_active = true
			_depart_station(_save.station_progress)
		_:
			_countdown_active = true


func open_station(_force: bool = false, approach_seconds: float = STATION_APPROACH_SECONDS, progress: float = 0.0) -> void:
	if _station_open or _station_pending:
		return
	_station_departing = false
	if _station_motion and _station_motion.is_running():
		_station_motion.kill()
	_station_progress = progress
	_station_pending = true
	_countdown_active = false
	_station_remaining = approach_seconds
	_update_status_hud()

	var waited := 0.0
	while (_in_tunnel or _event_lock) and waited < 20.0:
		await get_tree().create_timer(0.5).timeout
		waited += 0.5

	if _station_motion and _station_motion.is_running():
		_station_motion.kill()
	_station_marker.visible = true
	_apply_visual_mode()
	_event_lock = true
	_countdown_active = true
	_set_arrival_progress(progress)
	_station_motion = create_tween()
	_station_motion.tween_method(_set_arrival_progress, progress, 1.0, approach_seconds)
	_station_motion.finished.connect(_arrive_at_station)
	if _booted:
		_persist_save()


func _station_destination() -> float:
	return $Train.position.x + $Train/Locomotive.position.x + 60.0 - 90.0


func _set_arrival_progress(progress: float) -> void:
	_station_progress = progress
	var eased := 1.0 - pow(1.0 - progress, 2.0)
	var destination := _station_destination()
	var entry := maxf(get_viewport().get_visible_rect().size.x + 20.0, destination + 200.0)
	_station_marker.position.x = lerpf(entry, destination, eased)
	_mountains_layer.autoscroll = _mountains_scroll * (1.0 - eased)
	_forest_layer.autoscroll = _forest_scroll * (1.0 - eased)
	_rail_loop.volume_db = lerpf(-4.0, -40.0, eased)


func _arrive_at_station() -> void:
	_countdown_active = false
	_station_remaining = 0.0
	_rail_loop.stop()

	_station_open = true
	_station_pending = false
	_station_departing = false
	_station_marker.visible = true
	_station_marker.position.x = _station_destination()
	_apply_visual_mode()
	_event_lock = true
	_set_parallax_running(false)

	_refresh_station_content()
	_layout_station_panel()
	_station_root.visible = not _is_automatic()
	_auto_depart_remaining = AUTO_STATION_PAUSE
	_update_status_hud()
	_update_arrival_info()
	if _booted:
		_persist_save()


func _refresh_station_content() -> void:
	_take_button.disabled = false
	_skip_button.visible = true
	_station_title.text = "Hollow Creek · arrival"
	match _save.onboarding_step:
		Onboarding.STEP_CAFE:
			_station_body.text = "A warm welcome: Cafe Car + 12 Tickets"
			_take_button.text = "Accept Cafe"
			_skip_button.visible = false
		Onboarding.STEP_CHOICE:
			_station_body.text = "Choose a free car + 12 Tickets: glass and rain, or radio"
			_take_button.text = "Greenhouse"
			_skip_button.text = "Radio"
		Onboarding.STEP_PURCHASE:
			var car := "Radio" if _save.has_greenhouse else "Greenhouse"
			_station_body.text = "%s Car · 24 Tickets · you have %d" % [car, _save.tickets]
			_take_button.text = "Buy " + car
			_take_button.disabled = _save.tickets < Onboarding.REMAINING_CAR_PRICE
			_skip_button.text = "Later"
		_:
			_station_body.text = "Награда за маршрут: +%d Tickets · сейчас %d" % [_station_reward(), _save.tickets]
			_take_button.text = "Забрать и ехать"
			_skip_button.visible = false


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
	match _save.onboarding_step:
		Onboarding.STEP_CAFE:
			_resolve_onboarding("accept_cafe")
		Onboarding.STEP_CHOICE:
			_resolve_onboarding("greenhouse")
		Onboarding.STEP_PURCHASE:
			_resolve_onboarding("buy_remaining")
		_:
			_resolve_station(true)


func _on_skip_pressed() -> void:
	if _save.onboarding_step == Onboarding.STEP_CHOICE:
		_resolve_onboarding("radio")
	elif _save.onboarding_step != Onboarding.STEP_CAFE:
		_resolve_station(false)


func _resolve_onboarding(action: String) -> void:
	if not _station_open:
		return
	var result := _onboarding.resolve(_save.onboarding_step, action, _save.tickets,
		_save.has_cafe, _save.has_greenhouse, _save.has_radio)
	if not result.accepted:
		return
	_save.onboarding_step = result.step
	_save.tickets = result.tickets
	_save.has_cafe = result.has_cafe
	_save.has_greenhouse = result.has_greenhouse
	_save.has_radio = result.has_radio
	_sync_train_visuals()
	start_ambiance()
	_resolve_station(false)


func _resolve_station(took_passenger: bool) -> void:
	if not _station_open:
		return

	if took_passenger and not _is_onboarding():
		_save.tickets += _station_reward()
		_last_auto_reward = _station_reward() if _is_automatic() else 0

	_station_root.visible = false
	_station_open = false
	_event_lock = false
	_depart_station()
	_update_status_hud()
	_restart_station_schedule(true)
	# Commit the reward and departure in the same save, never a claimed station.
	_persist_save()

	if _fog_overlay.color.a > 0.0 and not _in_fog:
		var clear_fog := create_tween()
		clear_fog.tween_property(_fog_overlay, "color:a", 0.0, 1.0)


func _on_station_button_pressed() -> void:
	# Fire-and-forget from UI signal; never block the button callback.
	if _station_open or _station_pending:
		return
	open_station(true)


func _depart_station(progress: float = 0.0) -> void:
	_station_departing = true
	_station_marker.visible = true
	_apply_visual_mode()
	_play_if_needed(_rail_loop)
	_set_departure_progress(progress)
	_station_motion = create_tween()
	_station_motion.tween_method(_set_departure_progress, progress, 1.0, maxf(0.05, STATION_DEPART_SECONDS * (1.0 - progress)))
	_station_motion.finished.connect(_finish_departure)


func _set_departure_progress(progress: float) -> void:
	_station_progress = progress
	var eased := progress * progress
	_station_marker.position.x = lerpf(_station_destination(), -200.0, eased)
	_mountains_layer.autoscroll = _mountains_scroll * eased
	_forest_layer.autoscroll = _forest_scroll * eased
	_rail_loop.volume_db = lerpf(-40.0, -4.0, eased)


func _finish_departure() -> void:
	_station_departing = false
	_station_marker.visible = false
	_apply_visual_mode()
	_persist_save()


func skip_to_station() -> void:
	_on_station_button_pressed()


func _persist_save() -> void:
	if _save == null:
		return
	_save.use_mock_preview = _use_mock_preview
	_save.hidden = _hidden
	_save.journey_phase = "station" if _station_open else ("approach" if _station_pending else ("departure" if _station_departing else "travel"))
	_save.journey_remaining = _station_remaining
	_save.station_progress = _station_progress
	_save.save_game()


func _update_status_hud() -> void:
	if _save == null:
		return
	var mode_text := "Off · авто / 20 min"
	match _save.interval_mode:
		SaveMgr.MODE_20:
			mode_text = "20 min"
		SaveMgr.MODE_40:
			mode_text = "40 min"
	if _is_onboarding():
		mode_text = "Welcome %d/3" % (_save.onboarding_step + 1)
	for button in [_mode20_button, _mode40_button, _mode_off_button]:
		button.disabled = _is_onboarding() or _station_open or _station_pending
		button.tooltip_text = "Available after the third welcome station" if _is_onboarding() else ""
	var mute_mark := "   MUTE" if _save.muted else ""
	_status_label.text = "Mode: %s   Tickets: %d   speed x%.0f%s" % [
		mode_text,
		_save.tickets,
		_save.debug_time_scale,
		mute_mark,
	]
	_speed_button.text = "x%.0f" % _save.debug_time_scale
	_speed_button.disabled = _station_open or _station_pending
	_station_button.disabled = _station_open or _station_pending
	$StatusHUD/Bar.visible = _controls_open and not (_station_open or _station_pending or _hidden)
	$StatusHUD/Chrome.visible = _hovered and not (_controls_open or _station_open or _station_pending or _hidden)
	$StatusHUD/Bar/Margin/VBox/DesktopButtons/MuteButton.text = "Звук: выкл" if _save.muted else "Звук: вкл"
	$StatusHUD/Bar/Margin/VBox/DesktopButtons/MonitorButton.text = "Монитор %d →" % (_save.screen_index + 1)


func _is_key(event: InputEventKey, code: Key) -> bool:
	return (
		event.physical_keycode == code
		or event.keycode == code
		or event.key_label == code
	)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _station_open:
			if not _is_onboarding():
				_resolve_station(true)
			elif _save.onboarding_step == Onboarding.STEP_PURCHASE:
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
	elif _is_key(key_event, KEY_N):
		cycle_monitor()
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
