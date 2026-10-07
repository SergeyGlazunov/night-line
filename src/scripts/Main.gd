extends Node2D

const WINDOW_HEIGHT := 120
const TUNNEL_FIRST_DELAY := 20.0
const TUNNEL_INTERVAL := 50.0
const TUNNEL_DURATION := 8.0
const TUNNEL_FADE_IN := 1.2
const TUNNEL_FADE_OUT := 1.5
const TUNNEL_MAX_ALPHA := 0.72
const HIDE_TOGGLE_DEBOUNCE_MS := 300

@onready var _rail_loop: AudioStreamPlayer = $Audio/RailLoop
@onready var _rain_loop: AudioStreamPlayer = $Audio/RainLoop
@onready var _cafe_loop: AudioStreamPlayer = $Audio/CafeLoop
@onready var _tunnel_sfx: AudioStreamPlayer = $Audio/TunnelSfx
@onready var _tunnel_overlay: ColorRect = $TunnelOverlay

var _hidden := false
var _muted := false
var _in_tunnel := false
var _last_hide_toggle_ms := 0


func _ready() -> void:
	setup_window()
	start_ambiance()
	_schedule_tunnel(TUNNEL_FIRST_DELAY)


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

	_play_if_needed(_rail_loop)
	_play_if_needed(_rain_loop)
	_play_if_needed(_cafe_loop)


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
	# Minimize/visible=false flicker on borderless + always-on-top (Windows).
	# Park off-screen; audio keeps playing. Press H again to restore.
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, false)
	DisplayServer.window_set_size(Vector2i(1, 1))
	DisplayServer.window_set_position(Vector2i(-10000, -10000))


func _show_strip() -> void:
	_hidden = false
	setup_window()


func toggle_mute() -> void:
	_muted = not _muted
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Master"), _muted)


func _schedule_tunnel(delay: float) -> void:
	get_tree().create_timer(delay).timeout.connect(_on_tunnel_due, CONNECT_ONE_SHOT)


func _on_tunnel_due() -> void:
	await run_tunnel()
	_schedule_tunnel(TUNNEL_INTERVAL)


func run_tunnel() -> void:
	if _in_tunnel:
		return

	_in_tunnel = true

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


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var key: Key = event.physical_keycode
		if key == KEY_NONE:
			key = event.keycode
		match key:
			KEY_H:
				toggle_hide()
			KEY_M:
				toggle_mute()
