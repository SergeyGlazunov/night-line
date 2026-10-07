extends RefCounted

const STEP_CAFE := 0
const STEP_CHOICE := 1
const STEP_PURCHASE := 2
const STEP_COMPLETE := 3

const STATION_REWARD := 12
const REMAINING_CAR_PRICE := 24


func interval_seconds(step: int) -> float:
	match step:
		STEP_CAFE:
			return 20.0
		STEP_CHOICE:
			return 5.0 * 60.0
		STEP_PURCHASE:
			return 20.0 * 60.0
		_:
			return 0.0


func resolve(
	step: int,
	action: String,
	tickets: int,
	has_cafe: bool,
	has_greenhouse: bool,
	has_radio: bool
) -> Dictionary:
	var result := {
		"accepted": false,
		"step": step,
		"tickets": tickets,
		"has_cafe": has_cafe,
		"has_greenhouse": has_greenhouse,
		"has_radio": has_radio,
	}

	match step:
		STEP_CAFE:
			if action != "accept_cafe":
				return result
			result.accepted = true
			result.step = STEP_CHOICE
			result.tickets += STATION_REWARD
			result.has_cafe = true
		STEP_CHOICE:
			if action not in ["greenhouse", "radio"]:
				return result
			result.accepted = true
			result.step = STEP_PURCHASE
			result.tickets += STATION_REWARD
			result.has_greenhouse = action == "greenhouse" or has_greenhouse
			result.has_radio = action == "radio" or has_radio
		STEP_PURCHASE:
			if action != "buy_remaining" or tickets < REMAINING_CAR_PRICE:
				return result
			result.accepted = true
			result.step = STEP_COMPLETE
			result.tickets -= REMAINING_CAR_PRICE
			result.has_greenhouse = true
			result.has_radio = true

	return result
