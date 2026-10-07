extends Node2D

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

const STATION_FIRST_DELAY := 40.0
const STATION_INTERVAL := 90.0

@onready var _mountains_layer: Parallax2D = $MountainsLayer
@onready var _forest_layer: Parallax2D = $ForestLayer
@onready var _rail_loop: AudioStreamPlayer = $Audio/RailLoop
@onready var _rain_loop: AudioStreamPlayer = $Audio/RainLoop
@onready var _cafe_loop: AudioStreamPlayer = $Audio/CafeLoop
@onready var _radio_loop: AudioStreamPlayer = $Audio/RadioLoop
@onready var _tunnel_sfx: AudioStreamPlayer = $Audio/TunnelSfx
@onready var _tunnel_overlay: ColorRect = $TunnelOverlay
@onready var _fog_overlay: ColorRect = $FogOverlay
@onready var _station_root: Control = $StationUI/Root
@onready var _station_title: Label = $StationUI/Root/Center/Panel/Margin/VBox/Title
@onready var _station_body: Label = $StationUI/Root/Center/Panel/Margin/VBox/Body
@onready var _take_button: Button = $StationUI/Root/Center/Panel/Margin/VBox/Buttons/TakeButton
@onready var _skip_button: Button = $StationUI/Root/Center/Panel/Margin/VBox/Buttons/SkipButton

var _hidden := false
var _muted := false
var _in_tunnel := false
var _in_fog := false
var _station_open := false
var _event_lock := false
var _last_hide_toggle_ms := 0
var _tickets := 0

var _mountains_scroll := Vector2(-30, 0)
var _forest_scroll := Vector2(-90, 0)


func _ready() -> void:
	_mountains_scroll = _mountains_layer.autoscroll
	_forest_scroll = _forest_layer.autoscroll

	_take_button.pressed.connect(_on_take_pressed)
	_skip_button.pressed.connect(_on_skip_pressed)
	_station_root.visible = false

	setup_window()
	start_ambiance()
	_schedule_fog(FOG_FIRST_DELAY)
	_schedule_tunnel(TUNNEL_FIRST_DELAY)
	_schedule_station(STATION_FIRST_DELAY)


func setup_window() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

	var screen_index := DisplayServer.window_get_current_screen()
	var screen_rect := DisplayServer.screen_get_usable_rect(screen_index)

	var window_width: int = screen_rect.size.x
	DisplayServer.window_set_size(Vector2i(window_width, WINDOW_HEIGHT))

	var target_pos_y: int = screen_rect.position.y + screen_rect.size.y - WINDOW_HEIGHT
	DisplayServer.window_set_position(Vector2i(screen_rect.position.x, target_pos_y))

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)


func start_ambiance() -> void:
	_ensure_loop(_rail_loop)
	_ensure_loop(_rain_loop)
	_ensure_loop(_cafe_loop)
	_ensure_loop(_radio_loop)

	_play_if_needed(_rail_loop)
	_play_if_needed(_rain_loop)
	_play_if_needed(_cafe_loop)
	_play_if_needed(_radio_loop)


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
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _muted)


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
	get_tree().create_timer(delay).timeout.connect(_on_station_due, CONNECT_ONE_SHOT)


func _on_station_due() -> void:
	await open_station()
	_schedule_station(STATION_INTERVAL)


func open_station() -> void:
	if _station_open:
		return

	# Wait out tunnel/event lock briefly instead of skipping the station forever.
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
	_station_body.text = "Passenger: night-shift nurse  ·  +12 tickets"
	_station_root.visible = true


func _on_take_pressed() -> void:
	_resolve_station(true)


func _on_skip_pressed() -> void:
	_resolve_station(false)


func _resolve_station(took_passenger: bool) -> void:
	if not _station_open:
		return

	if took_passenger:
		_tickets += 12

	_station_root.visible = false
	_station_open = false
	_event_lock = false
	_set_parallax_running(true)

	# Clear leftover fog if a bank was held during the stop.
	if _fog_overlay.color.a > 0.0 and not _in_fog:
		var clear_fog := create_tween()
		clear_fog.tween_property(_fog_overlay, "color:a", 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _station_open:
			_resolve_station(false)
			return
		get_tree().quit()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key == KEY_NONE:
			key = event.keycode
		match key:
			KEY_H:
				if not _station_open:
					toggle_hide()
			KEY_M:
				toggle_mute()
