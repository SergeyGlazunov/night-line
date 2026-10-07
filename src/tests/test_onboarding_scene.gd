extends SceneTree

const SaveMgr = preload("res://scripts/SaveManager.gd")
const MainScene = preload("res://scenes/Main.tscn")
var failures := 0


func _init() -> void:
	call_deferred("run")


func run() -> void:
	OS.low_processor_usage_mode = false
	for choose_radio in [false, true]:
		await play_onboarding(choose_radio)
	await automatic_first_station()
	if failures == 0:
		print("PASS: onboarding scene tests")
	quit(failures)


func automatic_first_station() -> void:
	var game = MainScene.instantiate()
	game._save.save_path = "res://.godot/test_station_timer.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game._save.save_path))
	root.add_child(game)
	await process_frame
	Engine.time_scale = 20.0
	await create_timer(21.0).timeout
	check(game._station_open, "first station arrives at 20 seconds without tunnel delaying it")
	await create_timer(15.0).timeout
	check(game._save.onboarding_step == 0, "waiting at station cannot grant rewards or advance onboarding")
	Engine.time_scale = 1.0
	await dispose(game)


func play_onboarding(choose_radio: bool) -> void:
	var game = MainScene.instantiate()
	game._save.save_path = "res://.godot/test_scene_save.cfg"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(game._save.save_path))
	root.add_child(game)
	await process_frame
	await process_frame
	check(game._station_interval_seconds() == 20.0, "new game waits 20 real seconds")
	check(game.get_node("StatusHUD/ArrivalInfo/Countdown").text.contains("00:20"), "HUD shows time to first station")
	check(game.get_node("Train").is_visible_in_tree(), "new game shows actual train, not static art")
	check(game._mode_off_button.disabled, "Off locked during onboarding")
	game.set_interval_mode("off")
	check(game._save.interval_mode == "20", "keyboard/API cannot bypass mode lock")
	check(not game.get_node("Train/CafeCar").visible, "unowned Cafe hidden")
	check(not game.get_node("Audio/CafeLoop").playing, "unowned Cafe silent")
	await capture("start")
	game.skip_to_station()
	check(not game._station_open, "reward stays closed during approach")
	check(game.has_node("StationMarker"), "station has a visible world marker")
	var start_x: float = game.get_node("StationMarker").position.x
	await create_timer(2.0).timeout
	check(game.get_node("StationMarker").position.x < start_x, "station moves in from the right")
	check(not game._station_root.visible, "reward remains hidden mid-approach")
	await capture("approach")
	await wait_for_station(game)
	await capture("cafe_station")
	game._take_button.pressed.emit()
	check(game._save.onboarding_step == 1, "first station advances onboarding")
	check(game._save.tickets == 12 and game._save.has_cafe, "first station grants Cafe and Tickets")
	check(game.get_node("Train/CafeCar").visible, "Cafe appears immediately")
	check(game.get_node("Audio/CafeLoop").playing, "Cafe sounds immediately")
	check(game._station_interval_seconds() == 300.0, "next leg lasts five minutes")
	check(game.get_node("StatusHUD/ArrivalInfo/Countdown").text.contains("05:00"), "next countdown resets after departure")
	check(game.get_node("StatusHUD/ArrivalInfo/Notice").text.contains("5 мин."), "departure announces next station")
	game.skip_to_station()
	await wait_for_station(game)
	await capture("choice_station")
	# Escape must never silently select Radio at the choice station.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	game._input(escape)
	check(game._save.onboarding_step == 1, "Escape does not select a car")
	check(game._station_open, "choice remains available after Escape")
	if choose_radio:
		game._skip_button.pressed.emit()
	else:
		game._take_button.pressed.emit()
	check(game._save.onboarding_step == 2, "both choices advance to purchase")
	check(game._save.has_radio == choose_radio, "only selected special car granted")
	check(game._save.has_greenhouse == not choose_radio, "Greenhouse follows choice")
	check(game._station_interval_seconds() == 1200.0, "third leg lasts twenty minutes")
	await dispose(game)
	game = MainScene.instantiate()
	game._save.save_path = "res://.godot/test_scene_save.cfg"
	root.add_child(game)
	await process_frame
	await process_frame
	check(game._save.onboarding_step == 2, "restart resumes purchase step")
	check(game.get_node("Train/CafeCar").visible, "restart restores Cafe visual")
	check(game.get_node("Audio/CafeLoop").playing, "restart restores Cafe audio")
	check(game.get_node("Train/RadioCar").visible == choose_radio, "restart restores chosen car")
	check(game._mode20_button.disabled, "restart preserves mode lock")
	game.skip_to_station()
	await wait_for_station(game)
	await capture("purchase_station")
	game._skip_button.pressed.emit()
	check(game._save.onboarding_step == 2 and game._save.tickets == 24,
		"Later leaves purchase and Tickets intact")
	game.skip_to_station()
	await wait_for_station(game)
	game._take_button.pressed.emit()
	game._take_button.pressed.emit()
	check(game._save.onboarding_step == 3, "purchase completes onboarding")
	check(game._save.tickets == 0, "remaining car costs 24 Tickets")
	check(not game._mode_off_button.disabled, "modes unlock after purchase")
	check(game.has_node("Train/GreenhouseCar"), "Greenhouse has a visual node")
	check(game.has_node("Audio/GreenhouseLoop"), "Greenhouse has an audio layer")
	if game.has_node("Train/GreenhouseCar"):
		check(game.get_node("Train/GreenhouseCar").visible, "owned Greenhouse visible")
	if game.has_node("Audio/GreenhouseLoop"):
		check(game.get_node("Audio/GreenhouseLoop").playing, "owned Greenhouse audible")
	var saved = SaveMgr.new()
	saved.save_path = game._save.save_path
	saved.load_game()
	check(saved.onboarding_step == 3 and saved.has_greenhouse and saved.has_radio,
		"UI actions persist complete ownership")
	await capture("complete")
	game.set_interval_mode("off")
	check(game._save.interval_mode == "off", "Off usable after onboarding")
	check(game._countdown_active, "Off schedules automatic arrivals")
	check(game.get_node("StatusHUD/ArrivalInfo/Countdown").text.contains("20:00"), "Off uses a twenty-minute ETA")
	await create_timer(2.2).timeout
	check(not game.get_node("StationMarker").visible, "station leaves the screen after departure")
	await dispose(game)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(saved.save_path))
	await process_frame


func dispose(game: Node) -> void:
	for player in game.get_node("Audio").get_children():
		player.stop()
	# Let the audio thread release playback before tearing down the tree.
	await create_timer(0.1).timeout
	game.free()


func wait_for_station(game: Node) -> void:
	var elapsed := 0.0
	while not game._station_open and elapsed < 6.0:
		await create_timer(0.1).timeout
		elapsed += 0.1
	check(game._station_open, "arrival finishes before reward opens")
	check(not game.get_node("Audio/RailLoop").playing, "wheel sounds stop at the station")
	var locomotive_x: float = game.get_node("Train/Locomotive").global_position.x + 60.0
	var station_x: float = game.get_node("StationMarker").global_position.x + 90.0
	check(absf(locomotive_x - station_x) < 1.0, "locomotive stops opposite the station")


func capture(label: String) -> void:
	if "--screenshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/onboarding_" + label + ".png")


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)
