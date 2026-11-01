extends SceneTree
## Usage: godot --headless --path . -s res://tools/bots/validate_levels.gd -- [first] [last] [margin]
const Tuning = preload("res://src/sim/tuning.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
const Board = preload("res://src/sim/board.gd")
const Planner = preload("res://src/sim/planner.gd")

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var first := int(args[0]) if args.size() > 0 else 1
	var last := int(args[1]) if args.size() > 1 else 12
	var margin := float(args[2]) if args.size() > 2 else 0.1
	var tun := Tuning.make()
	for lv in range(first, last + 1):
		var t0 := Time.get_ticks_msec()
		var found := -1
		var rt := -1.0
		var level := {}
		for attempt in 60:
			level = LevelGen.generate(tun, lv, attempt)
			var b := Board.new()
			var e := Tuning.for_level(tun, lv)
			b.load_level(level, e)
			var hop := float(e["hop_time"])
			var r := Planner.solve(b, hop, b.n - 1, Board.start_rel(b.w[b.n - 1]), 0.0, float(e["max_route_time"]), margin)
			if r["ok"] and float(r["time"]) >= float(e["min_route_factor"]) * float(b.n - 1) * hop:
				found = attempt; rt = r["time"]
				break
		print("level %2d rows=%d attempt=%2d route_time=%.2f (%d ms)" % [lv, level["n_rows"], found, rt, Time.get_ticks_msec() - t0])
	quit()
