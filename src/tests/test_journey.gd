extends SceneTree

const SaveMgr = preload("res://scripts/SaveManager.gd")
const MainScene = preload("res://scenes/Main.tscn")
const PATH := "res://.godot/test_journey.cfg"
var failures := 0


func _init() -> void:
	call_deferred("run")


func run() -> void:
	OS.low_processor_usage_mode = false
	await test_travel_resume()
	await test_manual_reward("20", 12)
	await test_manual_reward("40", 24)
	await test_auto_mode()
	await test_approach_resume()
	await test_onboarding_claim_resume()
	await test_desktop_preferences()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PATH))
	if failures == 0:
		print("PASS: journey, rewards and desktop tests")
	quit(failures)


func fresh(mode: String = "20") -> Node:
	var save = SaveMgr.new()
	save.save_path = PATH
	save.onboarding_step = 3
	save.interval_mode = mode
	save.save_game()
	return await restore()


func restore() -> Node:
	var game = MainScene.instantiate()
	game._save.save_path = PATH
	root.add_child(game)
	await process_frame
	await process_frame
	return game


func dispose(game: Node) -> void:
	for player in game.get_node("Audio").get_children():
		player.stop()
	await create_timer(0.1).timeout
	game.free()
	await process_frame


func test_travel_resume() -> void:
	var game = await fresh()
	game._station_remaining = 93.0
	game._persist_save()
	await dispose(game)
	game = await restore()
	check(game._station_remaining > 92.0 and game._station_remaining <= 93.0,
		"restart resumes remaining journey, without advancing while closed")
	check(game._save.tickets == 0, "restart grants no offline Tickets")
	game._station_remaining = 81.0
	game._autosave_remaining = 0.01
	await create_timer(0.05).timeout
	var saved = SaveMgr.new()
	saved.save_path = PATH
	saved.load_game()
	check(saved.journey_remaining > 80.0 and saved.journey_remaining <= 81.0,
		"periodic autosave checkpoints the active route")
	await dispose(game)


func test_manual_reward(mode: String, reward: int) -> void:
	var game = await fresh(mode)
	game.open_station(true, 0.05)
	await create_timer(0.15).timeout
	check(game._station_root.visible, "manual mode shows station interaction")
	check(game._save.tickets == 0, "manual reward waits for claim")
	await capture("manual_" + mode)
	game._persist_save()
	await dispose(game)
	game = await restore()
	check(game._station_open, "restart at station restores unclaimed reward")
	game._take_button.pressed.emit()
	game._take_button.pressed.emit()
	check(game._save.tickets == reward, "mode " + mode + " pays once at proportional rate")
	await dispose(game)
	game = await restore()
	check(not game._station_open, "claimed station does not reopen on restart")
	check(game._save.tickets == reward, "restart does not duplicate a claimed reward")
	await dispose(game)


func test_auto_mode() -> void:
	var game = await fresh("off")
	check(game._station_interval_seconds() == 1200.0, "Off uses a 20-minute interval")
	check(game._countdown_active, "Off keeps scheduling stations")
	game.open_station(false, 0.05)
	await create_timer(0.15).timeout
	check(game._station_open, "Off actually arrives before automatic departure")
	check(not game._station_root.visible, "Off never shows reward modal")
	await capture("automatic_station")
	game._persist_save()
	await dispose(game)
	game = await restore()
	check(game._station_open and not game._station_root.visible, "Off resumes unclaimed automatic stop without a modal")
	await create_timer(1.2).timeout
	check(game._save.tickets == 12, "Off grants base reward automatically")
	check(not game._station_open and game._countdown_active, "Off departs automatically")
	await capture("automatic_reward")
	await dispose(game)
	game = await restore()
	check(game._save.tickets == 12, "automatic claim is durable and not repeated")
	await dispose(game)


func test_approach_resume() -> void:
	var game = await fresh()
	game.open_station(true, 1.0)
	await create_timer(0.5).timeout
	game._persist_save()
	var position_before: float = game.get_node("StationMarker").position.x
	await dispose(game)
	game = await restore()
	check(game._station_pending, "restart during approach resumes arrival")
	check(absf(game.get_node("StationMarker").position.x - position_before) < 80.0,
		"station position resumes near saved position")
	await create_timer(0.65).timeout
	check(game._station_open, "resumed approach reaches the station")
	check(game._save.tickets == 0, "resumed approach does not auto-claim in manual mode")
	await dispose(game)


func test_desktop_preferences() -> void:
	var game = await fresh()
	check(not game.get_node("StatusHUD/Bar").visible, "controls start collapsed")
	await capture("passive")
	check(game.has_node("StatusHUD/Chrome"), "hover chrome exists without covering the train")
	game._on_pointer_entered()
	check(game.get_node("StatusHUD/Chrome").visible, "hover reveals compact chrome")
	await capture("hover")
	game.get_node("StatusHUD/Chrome").pressed.emit()
	check(game.get_node("StatusHUD/Bar").visible, "chrome click expands controls")
	check(game._station_button.is_visible_in_tree() and game._speed_button.is_visible_in_tree(), "debug controls stay accessible")
	await capture("controls")
	game._on_pointer_exited()
	check(not game.get_node("StatusHUD/Bar").visible, "leaving the strip collapses controls")
	game.cycle_monitor()
	check(game._save.screen_index >= 0 and game._save.screen_index < maxi(1, DisplayServer.get_screen_count()), "monitor switch keeps a valid monitor")
	game._hide_strip()
	game._persist_save()
	check(game._save.get("hidden") == true, "hidden preference persists")
	await dispose(game)
	game = await restore()
	check(game._hidden, "restart preserves sound-only mode")
	game.open_station(false, 0.05)
	await create_timer(0.15).timeout
	check(game._hidden, "station does not reveal a deliberately hidden window")
	game._show_strip()
	if DisplayServer.get_name() != "headless":
		check(root.always_on_top, "restoring re-enables always-on-top")
	game.toggle_mute()
	check(game._hidden and game._save.muted, "mute hides and silences the strip")
	await dispose(game)
	game = await restore()
	check(game._hidden and game._save.muted, "restart preserves hidden and mute preferences")
	game.toggle_mute()
	game._show_strip()
	await dispose(game)


func test_onboarding_claim_resume() -> void:
	var save = SaveMgr.new()
	save.save_path = PATH
	save.save_game()
	var game = await restore()
	game.open_station(true, 0.05)
	await create_timer(0.15).timeout
	game._take_button.pressed.emit()
	await dispose(game)
	game = await restore()
	check(game._save.onboarding_step == 1 and game._save.tickets == 12, "onboarding grant persists once")
	check(not game._station_open and game._station_remaining > 298.0, "onboarding reload resumes next leg, not the next reward")
	await dispose(game)


func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr("FAIL: " + message)


func capture(label: String) -> void:
	if "--screenshots" not in OS.get_cmdline_user_args():
		return
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://.godot/journey_" + label + ".png")
