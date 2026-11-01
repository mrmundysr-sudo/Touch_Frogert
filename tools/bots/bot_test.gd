extends SceneTree
## Usage: godot --headless --path . -s res://tools/bots/bot_test.gd -- <first_level> <last_level> <episodes> [profiles,comma]
const Tuning = preload("res://src/sim/tuning.gd")
const Sim = preload("res://src/sim/sim.gd")
const Session = preload("res://src/sim/session.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
const Bot = preload("res://src/sim/bot.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var first := int(a[0]) if a.size() > 0 else 1
	var last := int(a[1]) if a.size() > 1 else 3
	var eps := int(a[2]) if a.size() > 2 else 5
	var profiles: PackedStringArray = (a[3] as String).split(",") if a.size() > 3 else PackedStringArray(["skilled", "average", "slow", "mistake"])
	var tun := Tuning.make()
	var table := _load_attempts()
	var any_fail := false
	print("%-5s %-8s %6s %8s %8s  %s" % ["level", "profile", "clear%", "avg_t", "deaths/ep", "death causes"])
	for lv in range(first, last + 1):
		var lvl: Dictionary = LevelGen.generate(tun, lv, int(table.get(str(lv), 0)))
		for prof in profiles:
			var clears := 0
			var total_t := 0.0
			var total_deaths := 0
			var causes := {}
			for e in eps:
				var sess := Session.make(tun)
				sess["level"] = lv
				var sim := Sim.new(tun, sess)
				sim.log_enabled = false
				sim.start_level(lv, 0, lvl)
				var bot := Bot.new(prof, 1000 + e * 37 + lv)
				var frames := 0
				var deaths_before := 0
				while not sim.finished_win and not sim.finished_over and frames < 60 * 240:
					bot.act(sim)
					sim.step(1.0 / 60.0)
					for ev in sim.events:
						if ev[0] == "restart":
							bot.reset_for_new_attempt()
						if ev[0] == "die":
							causes[ev[1]] = int(causes.get(ev[1], 0)) + 1
							total_deaths += 1
					sim.events.clear()
					frames += 1
				if sim.finished_win:
					clears += 1
					total_t += sim.t
			var pct := 100.0 * clears / eps
			print("%-5d %-8s %5.0f%% %8.1f %8.2f  %s" % [lv, prof, pct, (total_t / maxf(1, clears)), float(total_deaths) / eps, str(causes)])
			if prof == "skilled" and clears < eps:
				any_fail = true
	if any_fail:
		print("WARNING: skilled bot failed on some levels (possible impossible/unfair layout)")
	quit(1 if any_fail else 0)

func _load_attempts() -> Dictionary:
	var f := FileAccess.open("res://src/data/level_attempts.json", FileAccess.READ)
	if f:
		var v = JSON.parse_string(f.get_as_text())
		if v is Dictionary:
			return v
	return {}
