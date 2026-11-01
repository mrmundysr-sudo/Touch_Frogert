extends RefCounted
## Rule-based, seed-reproducible level generator.  Same (tuning, level, attempt) -> identical level, always.
## Row numbering: row 0 = SUMMIT (Miss Frogert), last row = start. Width of row r = 3 + r (narrower at the top).
const Tuning = preload("res://src/sim/tuning.gd")
const Board = preload("res://src/sim/board.gd")

static func level_seed(tun: Dictionary, level: int, attempt: int) -> int:
	return int(tun.get("game_seed", 1)) * 1000003 + level * 7919 + attempt * 104729

static func generate(tun_base: Dictionary, level: int, attempt: int = 0) -> Dictionary:
	var tun := Tuning.for_level(tun_base, level)
	var rng := RandomNumberGenerator.new()
	rng.seed = level_seed(tun, level, attempt)
	var n: int = tun["lvl_rows"]
	var rows: Array = []
	var dir_sign := 1.0 if rng.randf() < 0.5 else -1.0
	var water_p: float = tun["lvl_water"]
	var kinds: Array = []
	for r in n:
		var w := 3 + r
		var row := {"idx": r, "w": w, "L": w, "speed": 0.0, "phase": 0.0, "slots": [], "sinkph": [], "kind": "static"}
		if r > 0 and r < n - 1:
			var prev_river: bool = kinds.size() > 0 and kinds[kinds.size() - 1] == "river"
			var p := water_p + (0.12 if r < n / 2 else -0.08) - (0.18 if prev_river else 0.0)
			var kind := "river" if rng.randf() < p else "ground"
			if r == n - 2 and kind == "river" and n > 6:
				kind = "ground"   # first row off the start line is always forgiving
			kinds.append(kind)
			row["kind"] = kind
			var L := w + 2 + rng.randi_range(0, 2)
			row["L"] = L
			var v: float = tun["lvl_speed"] * (1.0 + float(tun["speed_top_boost"]) * (1.0 - float(r) / float(n - 1)))
			v *= rng.randf_range(0.85, 1.15)
			if kind == "ground":
				v *= 0.85
			v = minf(v, float(tun["speed_max"]))
			row["speed"] = v * dir_sign
			dir_sign = -dir_sign
			row["phase"] = rng.randf() * L
			var sl: Array = []
			sl.resize(L)
			sl.fill(Board.PAD)
			if kind == "river":
				sl.fill(Board.WATER)
				var pos := rng.randi_range(0, L - 1)
				var filled := 0
				var guard := 0
				while filled < L and guard < 40:
					guard += 1
					var run := 1 + int(rng.randf() * (1.0 + 2.2 * float(tun["pad_density"])))
					run = clampi(run, 1, 3)
					var gap := rng.randi_range(1, 3)
					for j in run:
						sl[(pos + j) % L] = Board.PAD
					pos += run + gap
					filled += run + gap
			else:
				var nb := int(round(float(tun["lvl_barrier"]) * L)) + (1 if rng.randf() < 0.3 else 0)
				if r >= n - 2:
					nb = 0
				for b in nb:
					var bk := rng.randi_range(0, L - 1)
					if sl[bk] == Board.PAD and sl[(bk + 1) % L] != Board.BARRIER and sl[(bk + L - 1) % L] != Board.BARRIER:
						sl[bk] = Board.BARRIER
				if rng.randf() < water_p * 0.6 and r < n - 2:
					var wk := rng.randi_range(0, L - 1)
					if sl[wk] == Board.PAD:
						sl[wk] = Board.WATER
			var sp: Array = []
			sp.resize(L)
			var period := float(tun["sink_up"]) + float(tun["sink_warn"]) + float(tun["sink_down"])
			for k in L:
				sp[k] = rng.randf() * period
				if sl[k] == Board.PAD and kind == "river" and rng.randf() < float(tun["lvl_sink"]):
					sl[k] = Board.SINK
			row["slots"] = sl
			row["sinkph"] = sp
		else:
			var sl2: Array = []
			var sp2: Array = []
			for k in w:
				sl2.append(Board.PAD)
				sp2.append(0.0)
			row["slots"] = sl2
			row["sinkph"] = sp2
		rows.append(row)
	# flies: only on plain pad slots of conveyor rows below the top two rows
	var flies: Array = []
	var max_flies := 2 + level / 3
	for r in range(2, n - 1):
		var row2: Dictionary = rows[r]
		for k in int(row2["L"]):
			if flies.size() >= max_flies:
				break
			if row2["slots"][k] == Board.PAD and rng.randf() < float(tun["lvl_fly"]) * 0.08 * (1.0 + float(r) / n):
				flies.append({"r": r, "k": k, "period": float(tun["fly_grow"]) + float(tun["fly_ripe"]) + rng.randf_range(4.0, 9.0),
					"start": rng.randf_range(1.0, 9.0), "grow": float(tun["fly_grow"]), "ripe": float(tun["fly_ripe"])})
	return {"level": level, "attempt": attempt, "seed": level_seed(tun, level, attempt), "n_rows": n, "rows": rows, "flies": flies, "tun_gen": Tuning.gen_hash(tun_base)}

## Generate level + validate with the planner; returns first attempt that is solvable pad-only, with slack,
## and not trivially short. Used by CI/bots and the build-time attempt table.
static func generate_valid(tun_base: Dictionary, level: int, max_attempts: int = 60) -> Dictionary:
	var Planner = load("res://src/sim/planner.gd")
	var tun := Tuning.for_level(tun_base, level)
	for attempt in max_attempts:
		var lv := generate(tun_base, level, attempt)
		var b := Board.new()
		b.load_level(lv, tun)
		var hop := float(tun["hop_time"])
		var res: Dictionary = Planner.solve(b, hop, b.n - 1, float(b.w[b.n - 1]) * 0.5, 0.0, float(tun["max_route_time"]), float(tun["route_margin"]))
		if res["ok"] and float(res["time"]) >= float(tun["min_route_factor"]) * float(b.n - 1) * hop:
			lv["route_time"] = res["time"]
			lv["route_hops"] = res["plan"].size()
			return lv
	var lv2 := generate(tun_base, level, 0)
	lv2["route_time"] = -1.0
	return lv2

## Level used by the real game: honours the precomputed table of validated attempts when the
## generation tuning is unchanged; otherwise falls back to attempt 0 (dev-tuned levels).
static var _table: Dictionary = {}
static var _table_loaded := false
static func for_game(tun_base: Dictionary, level: int) -> Dictionary:
	if not _table_loaded:
		_table_loaded = true
		var f := FileAccess.open("res://src/data/level_attempts.json", FileAccess.READ)
		if f:
			var v = JSON.parse_string(f.get_as_text())
			if v is Dictionary:
				_table = v
	var attempt := 0
	if _table.has(str(level)) and int(_table.get("_gen_hash", 0)) == Tuning.gen_hash(tun_base):
		attempt = int(_table[str(level)])
	return generate(tun_base, level, attempt)
