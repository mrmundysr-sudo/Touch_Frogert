extends SceneTree
## Does what the player SEES agree with what the simulation DECIDES?  Samples bot play on every level.
## Usage: godot --headless --path . -s res://tools/bots/visual_consistency.gd -- <first> <last> <episodes>
const Tuning = preload("res://src/sim/tuning.gd")
const SimC = preload("res://src/sim/sim.gd")
const Session = preload("res://src/sim/session.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
const Board = preload("res://src/sim/board.gd")
const Bot = preload("res://src/sim/bot.gd")

func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var first := int(a[0]) if a.size() > 0 else 1
	var last := int(a[1]) if a.size() > 1 else 12
	var eps := int(a[2]) if a.size() > 2 else 4
	var tun := Tuning.make()
	var st := {"stand": 0, "river_stand": 0, "river_overhang_water": 0, "ground_stand": 0, "ground_at_seam": 0,
		"land": 0, "land_river": 0, "land_edge015": 0, "land_old_pad_mismatch": 0, "land_new_pad_mismatch": 0, "land_overhang_water": 0, "land_seam_ground": 0, "land_ground": 0}
	for lv in range(first, last + 1):
		var lvl := LevelGen.for_game(tun, lv)
		for prof in ["average", "mistake", "skilled"]:
			for e in eps:
				var sess := Session.make(tun)
				var sim := SimC.new(tun, sess)
				sim.log_enabled = false
				sim.start_level(lv, 0, lvl)
				var bot := Bot.new(prof, 500 + e * 31 + lv)
				var frames := 0
				while not sim.finished_win and not sim.finished_over and frames < 60 * 90:
					bot.act(sim)
					sim.step(1.0 / 60.0)
					for ev in sim.events:
						if ev[0] == "restart":
							bot.reset_for_new_attempt()
						if ev[0] == "land" and sim.mode == SimC.Mode.PLAY:
							_sample(sim, lvl, st, true)
					sim.events.clear()
					if sim.mode == SimC.Mode.PLAY and not sim.hopping and frames % 6 == 0:
						_sample(sim, lvl, st, false)
					frames += 1
	var pct := func(n, d): return 100.0 * float(n) / maxf(1.0, float(d))
	print("== standing samples: %d" % st["stand"])
	print("  river rows: %d samples; body overhangs WATER (safe by centre point but part of the frog is over water): %.1f%%" % [st["river_stand"], pct.call(st["river_overhang_water"], st["river_stand"])])
	print("  ground rows: %d samples; feet within 0.12 cube of a seam (standing on the corner where two tops meet): %.1f%%" % [st["ground_stand"], pct.call(st["ground_at_seam"], st["ground_stand"])])
	print("== landings: %d" % st["land"])
	print("  on river rows: %d; centre within 0.15 slot of the pad edge: %.1f%%; body overhangs water: %.1f%%" % [st["land_river"], pct.call(st["land_edge015"], st["land_river"]), pct.call(st["land_overhang_water"], st["land_river"])])
	print("  would look like 'landed in water but safe' with the OLD narrow pad (rx 0.38): %.1f%%   with the new pad (rx 0.45): %.1f%%" % [pct.call(st["land_old_pad_mismatch"], st["land_river"]), pct.call(st["land_new_pad_mismatch"], st["land_river"])])
	print("  on ground rows: %d; landed within 0.12 of a seam: %.1f%%" % [st["land_ground"], pct.call(st["land_seam_ground"], st["land_ground"])])
	quit()

func _sample(sim, lvl: Dictionary, st: Dictionary, landing: bool) -> void:
	var b: Board = sim.board
	var r: int = sim.frog_r
	if r <= 0 or r >= b.n - 1:
		return
	var kind: String = String(lvl["rows"][r].get("kind", "ground"))
	var rel: float = sim.frog_rel
	var k := b.slot_of_rel(r, rel)
	var fr := fposmod(rel, 1.0)
	var d_edge := minf(fr, 1.0 - fr)
	var toward := -1 if fr < 0.5 else 1
	var nk := posmod(k + toward, int(b.L[r]))
	var nbr_water: bool = b.slots[r][nk] == Board.WATER
	var x := b.local_x(r, rel, sim.t)
	var d_seam: float = absf(x - roundf(x))
	var body_over := d_edge < 0.4          # frog body half-width ~0.4 cube
	if landing:
		st["land"] += 1
		if kind == "river":
			st["land_river"] += 1
			if d_edge < 0.15: st["land_edge015"] += 1
			if d_edge < 0.12: st["land_old_pad_mismatch"] += 1
			if d_edge < 0.05: st["land_new_pad_mismatch"] += 1
			if body_over and nbr_water: st["land_overhang_water"] += 1
		else:
			st["land_ground"] += 1
			if d_seam < 0.12: st["land_seam_ground"] += 1
	else:
		st["stand"] += 1
		if kind == "river":
			st["river_stand"] += 1
			if body_over and nbr_water: st["river_overhang_water"] += 1
		else:
			st["ground_stand"] += 1
			if d_seam < 0.12: st["ground_at_seam"] += 1
