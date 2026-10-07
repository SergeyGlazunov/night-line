extends Node2D

const WINDOW_HEIGHT := 120

@onready var _rail_loop: AudioStreamPlayer = $Audio/RailLoop
@onready var _rain_loop: AudioStreamPlayer = $Audio/RainLoop


func _ready() -> void:
	setup_window()
	start_ambiance()


func setup_window() -> void:
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

	if _rail_loop.stream != null and not _rail_loop.playing:
		_rail_loop.play()
	if _rain_loop.stream != null and not _rain_loop.playing:
		_rain_loop.play()


func _ensure_loop(player: AudioStreamPlayer) -> void:
	var stream := player.stream
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
