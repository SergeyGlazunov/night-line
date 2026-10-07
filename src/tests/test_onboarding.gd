extends SceneTree

const SaveMgr = preload("res://scripts/SaveManager.gd")

var _failures := 0


func _init() -> void:
	_test_new_save_starts_before_first_station()
	_test_onboarding_progress_round_trips_in_save()
	_test_three_stations_unlock_modes_with_both_special_cars()
	if _failures == 0:
		print("PASS: onboarding tests")
	quit(_failures)


func _test_new_save_starts_before_first_station() -> void:
	var save = SaveMgr.new()
	_expect_equal(save.get("onboarding_step"), 0, "new save starts at onboarding station 1")
	_expect_equal(save.has_cafe, false, "new save does not own Cafe")
	_expect_equal(save.get("has_greenhouse"), false, "new save does not own Greenhouse")
	_expect_equal(save.has_radio, false, "new save does not own Radio")


func _test_onboarding_progress_round_trips_in_save() -> void:
	var test_path := "user://night_line_test_onboarding.cfg"
	var save = SaveMgr.new()
	if save.get("save_path") == null:
		_failures += 1
		printerr("FAIL: save path cannot be isolated for persistence tests")
		return

	save.set("save_path", test_path)
	save.onboarding_step = 2
	save.has_cafe = true
	save.has_greenhouse = true
	save.tickets = 24
	save.save_game()

	var loaded = SaveMgr.new()
	loaded.set("save_path", test_path)
	loaded.load_game()
	_expect_equal(loaded.onboarding_step, 2, "onboarding step persists")
	_expect_equal(loaded.has_cafe, true, "Cafe ownership persists")
	_expect_equal(loaded.has_greenhouse, true, "Greenhouse ownership persists")
	_expect_equal(loaded.tickets, 24, "onboarding Tickets persist")

	DirAccess.remove_absolute(ProjectSettings.globalize_path(test_path))


func _test_three_stations_unlock_modes_with_both_special_cars() -> void:
	var flow_path := "res://scripts/OnboardingFlow.gd"
	if not ResourceLoader.exists(flow_path):
		_failures += 1
		printerr("FAIL: three-station onboarding flow is missing")
		return

	var flow = load(flow_path).new()
	_expect_equal(flow.interval_seconds(0), 20.0, "first station arrives after 20 seconds")
	_expect_equal(flow.interval_seconds(1), 300.0, "second station arrives after 5 minutes")
	_expect_equal(flow.interval_seconds(2), 1200.0, "third station arrives after 20 minutes")

	var state: Dictionary = flow.resolve(0, "accept_cafe", 0, false, false, false)
	_expect_equal(state, {
		"accepted": true,
		"step": 1,
		"tickets": 12,
		"has_cafe": true,
		"has_greenhouse": false,
		"has_radio": false,
	}, "station 1 grants Cafe and 12 Tickets")

	state = flow.resolve(1, "greenhouse", 12, true, false, false)
	_expect_equal(state, {
		"accepted": true,
		"step": 2,
		"tickets": 24,
		"has_cafe": true,
		"has_greenhouse": true,
		"has_radio": false,
	}, "station 2 grants the chosen car and 12 Tickets")

	state = flow.resolve(2, "buy_remaining", 24, true, true, false)
	_expect_equal(state, {
		"accepted": true,
		"step": 3,
		"tickets": 0,
		"has_cafe": true,
		"has_greenhouse": true,
		"has_radio": true,
	}, "station 3 sells the remaining car and completes onboarding")


func _expect_equal(actual: Variant, expected: Variant, message: String) -> void:
	if actual == expected:
		return
	_failures += 1
	printerr("FAIL: %s; expected %s, got %s" % [message, expected, actual])
