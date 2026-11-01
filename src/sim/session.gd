extends RefCounted
## A fresh game session: nothing carries over between games.
const Tuning = preload("res://src/sim/tuning.gd")
static func make(tun: Dictionary) -> Dictionary:
	return {"score": 0, "lives": int(tun["start_lives"]), "level": 1, "max_level": 1,
		"next_bonus": int(tun["bonus_first"]), "bonus_given": 0}
