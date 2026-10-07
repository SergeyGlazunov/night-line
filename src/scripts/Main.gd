extends Node2D

const WINDOW_HEIGHT := 180


func _ready() -> void:
	setup_window()


func setup_window() -> void:
	var screen_index := DisplayServer.window_get_current_screen()
	var screen_rect := DisplayServer.screen_get_usable_rect(screen_index)

	var window_width: int = screen_rect.size.x
	DisplayServer.window_set_size(Vector2i(window_width, WINDOW_HEIGHT))

	var target_pos_y: int = screen_rect.position.y + screen_rect.size.y - WINDOW_HEIGHT
	DisplayServer.window_set_position(Vector2i(screen_rect.position.x, target_pos_y))

	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_BORDERLESS, true)
	DisplayServer.window_set_flag(DisplayServer.WINDOW_FLAG_ALWAYS_ON_TOP, true)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_tree().quit()
