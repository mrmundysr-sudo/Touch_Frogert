extends SceneTree
## Deterministic rule tests. Usage: godot --headless --path . -s res://tools/bots/sim_tests.gd
const Tuning = preload("res://src/sim/tuning.gd")
const SimC = preload("res://src/sim/sim.gd")
const Session = preload("res://src/sim/session.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
const Board = preload("res://src/sim/board.gd")
const Bot = preload("res://src/sim/bot.gd")
const TouchArcade = preload("res://src/arcade/touch_arcade.gd")

var fails := 0
var passes := 0

func check(cond: bool, name: String) -> void:
	if cond:
		passes += 1
		print("  ok   ", name)
	else:
		fails += 1
		print("  FAIL ", name)

func new_sim(level := 1, tun_over := {}) -> SimC:
	var tun := Tuning.make()
	for k in tun_over:
		tun[k] = tun_over[k]
	var sess := Session.make(tun)
	var sim := SimC.new(tun, sess)
	sim.start_level(level, 0, LevelGen.for_game(tun, level))
	return sim

func run(sim: SimC, seconds: float) -> void:
	for i in int(seconds * 60.0):
		sim.step(1.0 / 60.0)
		sim.events.clear()

## Calm arena: 6 rows (0 summit .. 5 start), widths 3..8, every conveyor slot a pad; `speed` for row 3; optional water band on row 2.
func _arena_level(speed3: float = 0.0, water_row2: bool = false) -> Dictionary:
	var rows: Array = []
	for r in 6:
		var w := 3 + r
		var L := w + 4 if (r > 0 and r < 5) else w
		var sl: Array = []
		var sp: Array = []
		for k in L:
			sl.append(Board.PAD)
			sp.append(0.0)
		if water_row2 and r == 2:
			for k in L:
				sl[k] = Board.WATER
		rows.append({"idx": r, "w": w, "L": L, "speed": speed3 if r == 3 else 0.0, "phase": 0.0, "slots": sl, "sinkph": sp, "kind": "ground"})
	return {"level": 1, "attempt": 0, "seed": 0, "n_rows": 6, "rows": rows, "flies": [], "tun_gen": 0}

func _arena_sim(lv: Dictionary, tun: Dictionary) -> SimC:
	var sess := Session.make(tun)
	var sim := SimC.new(tun, sess)
	sim.start_level(1, 0, lv)
	to_play(sim)
	return sim

## put the frog on cube c of row r (centre of that cube)
func _place(sim: SimC, r: int, c: int) -> void:
	sim.frog_r = r
	sim.frog_rel = float(c) + 0.5 - sim.board.raw(r, sim.t)

func to_play(sim: SimC) -> void:
	run(sim, SimC.READY_TIME + 0.05)

func _init() -> void:
	print("== determinism")
	var a := new_sim(2)
	var b := new_sim(2)
	var ba := Bot.new("mistake", 5)
	var bb := Bot.new("mistake", 5)
	var trace_a := ""
	var trace_b := ""
	for i in 60 * 30:
		ba.act(a); bb.act(b)
		a.step(1.0 / 60.0); b.step(1.0 / 60.0)
		a.events.clear(); b.events.clear()
		if i % 10 == 0:
			trace_a += "%d,%.5f,%d|" % [a.frog_r, a.frog_rel, a.mode]
			trace_b += "%d,%.5f,%d|" % [b.frog_r, b.frog_rel, b.mode]
	check(trace_a == trace_b and trace_a.length() > 100 and JSON.stringify(a.log) == JSON.stringify(b.log), "identical inputs -> identical frame-by-frame trace and event log (%d log entries)" % a.log.size())
	check(a.session["score"] == b.session["score"], "identical score")

	print("== level generation reproducible")
	var tun := Tuning.make()
	var l1 := LevelGen.generate(tun, 7, 3)
	var l2 := LevelGen.generate(tun, 7, 3)
	check(JSON.stringify(l1) == JSON.stringify(l2), "same seed+level+attempt -> identical level")
	check(JSON.stringify(LevelGen.generate(tun, 7, 4)) != JSON.stringify(l1), "different attempt -> different level")
	var narrow := true
	for r in l1["n_rows"] - 1:
		if int(l1["rows"][r]["w"]) >= int(l1["rows"][r + 1]["w"]):
			narrow = false
	check(narrow, "pyramid narrows toward the summit")
	var alt := true
	for r in range(1, l1["n_rows"] - 2):
		if signf(l1["rows"][r]["speed"]) == signf(l1["rows"][r + 1]["speed"]):
			alt = false
	check(alt, "adjacent conveyor rows alternate direction")

	print("== death restarts level identically, keeps score+lives")
	var s := new_sim(1)
	to_play(s)
	var slots0 := JSON.stringify(s.board.slots)
	var raw0: Array = []
	for r in s.board.n:
		raw0.append(s.board.raw(r, 0.0))
	s.session["score"] = 1234
	s.hop_dur = 0.18
	s.die("drown")
	check(int(s.session["lives"]) == 2, "life lost on death")
	run(s, SimC.DEATH_TIME + 0.1)
	check(s.mode == SimC.Mode.READY and s.t == 0.0, "level restarts from t=0")
	check(s.frog_r == s.board.n - 1, "frog back at the bottom")
	check(JSON.stringify(s.board.slots) == slots0, "obstacles/pads restored")
	var same := true
	for r in s.board.n:
		if absf(s.board.raw(r, 0.0) - raw0[r]) > 1e-9:
			same = false
	check(same, "conveyor start positions restored")
	check(int(s.session["score"]) == 1234 and int(s.session["lives"]) == 2, "score and lives preserved")

	print("== game over")
	var g := new_sim(1)
	to_play(g)
	g.session["lives"] = 1
	g.die("fell")
	run(g, SimC.DEATH_TIME + 0.1)
	check(g.finished_over and int(g.session["lives"]) == 0, "no lives -> game over")

	print("== extra lives: 10,000 then every 25,000")
	var e := new_sim(1)
	e.add_score(9990)
	check(int(e.session["lives"]) == 3, "no bonus before 10,000")
	e.add_score(20)
	check(int(e.session["lives"]) == 4, "bonus at 10,000")
	e.add_score(24000)
	check(int(e.session["lives"]) == 4, "no bonus before 35,000")
	e.add_score(1100)
	check(int(e.session["lives"]) == 5, "bonus at 35,000 (10k + 25k)")
	var fresh := Session.make(Tuning.make())
	check(int(fresh["lives"]) == 3 and int(fresh["score"]) == 0, "new game: 3 lives, nothing carried over")

	print("== NES-style four-neighbour hops on the fixed cube grid")
	var arena := _arena_level()
	var tun_a := Tuning.make()
	tun_a["time_limit"] = 0.0
	var hs := {"up": Vector2i(1, -1), "right": Vector2i(1, 1), "down": Vector2i(-1, 1), "left": Vector2i(-1, -1)}
	var swipes := {"up": Vector2i(0, -1), "right": Vector2i(1, 0), "down": Vector2i(0, 1), "left": Vector2i(-1, 0)}
	# From the middle of row 3 of the calm arena (all pads, still rows): each swipe lands on exactly one neighbour cube.
	var exp := {"up": [2, 3], "right": [4, 4], "down": [4, 3], "left": [2, 2]}   # [row, cube] from (row 3, cube 3)
	for nm in swipes:
		var q := _arena_sim(arena, tun_a)
		_place(q, 3, 3)
		q.swipe(swipes[nm].x, swipes[nm].y)
		run(q, 0.25)
		check(q.frog_r == exp[nm][0] and q.frog_cube() == exp[nm][1], "swipe %s hops to the %s neighbour -> row %d cube %d" % [nm, ["up-right", "down-right", "down-left", "up-left"][["up", "right", "down", "left"].find(nm)], q.frog_r, q.frog_cube()])
	# facing never changes where an ordinary swipe goes
	var f1 := _arena_sim(arena, tun_a)
	_place(f1, 3, 3)
	f1.swipe(-1, 0, true)           # B + swipe left: turn only
	check(not f1.hopping and f1.face == SimC.Face.LEFT and f1.frog_r == 3, "B + swipe turns without hopping")
	f1.swipe(0, -1)                 # ordinary swipe up, previously facing LEFT
	run(f1, 0.25)
	check(f1.frog_r == 2 and f1.frog_cube() == 3, "swipe UP still goes up-right regardless of previous facing")
	check(not ("pref" in f1), "no hidden preferred-side variable")
	# the four swipes make a closed loop
	var lp := _arena_sim(arena, tun_a)
	_place(lp, 3, 3)
	for nm in ["up", "right", "down", "left"]:
		lp.swipe(swipes[nm].x, swipes[nm].y)
		run(lp, 0.25)
	check(lp.frog_r == 3 and lp.frog_cube() == 3, "UP, RIGHT, DOWN, LEFT returns to the start cube")
	# remapping is purely configuration
	var tun_b := tun_a.duplicate(true)
	tun_b["hop_map"] = {"up": [-1, -1], "left": [-1, 1], "down": [1, 1], "right": [1, -1]}
	var rm := _arena_sim(arena, tun_b)
	_place(rm, 3, 3)
	rm.swipe(0, -1)
	run(rm, 0.25)
	check(rm.frog_r == 2 and rm.frog_cube() == 2, "hop_map remaps swipe UP to up-left without code changes")
	# edges
	var ed := _arena_sim(arena, tun_a)
	_place(ed, 3, 0)
	ed.swipe(-1, 0)                 # up-left from the left-most cube leaves the pyramid
	run(ed, 0.3)
	check(ed.mode == SimC.Mode.DYING and ed.death_cause == "fell", "hopping off the pyramid edge = fall")
	var bt := _arena_sim(arena, tun_a)
	_place(bt, 5, 3)                # bottom row
	bt.swipe(0, 1)
	check(not bt.hopping and bt.mode == SimC.Mode.PLAY, "cannot hop below the bottom row (no accidental death)")
	# conveyor carry + fall off the edge
	var cv := _arena_sim(_arena_level(1.0), tun_a)
	_place(cv, 3, 3)
	var x0: float = cv.board.local_x(3, cv.frog_rel, cv.t)
	run(cv, 1.0)
	var x1: float = cv.board.local_x(3, cv.frog_rel, cv.t)
	check(absf((x1 - x0) - 1.0) < 0.05, "standing frog is carried 1.0 cube/s with the row (moved %.3f)" % (x1 - x0))
	var guard := 0
	while cv.mode == SimC.Mode.PLAY and guard < 60 * 12:
		cv.step(1.0 / 60.0); cv.events.clear(); guard += 1
	check(cv.mode == SimC.Mode.DYING and cv.death_cause == "fell", "carried beyond the pyramid edge = fall (after %.1fs)" % cv.t)
	# landing samples the moving surface at the destination cube centre
	var wt := _arena_sim(_arena_level(0.0, true), tun_a)
	_place(wt, 3, 3)
	wt.swipe(0, -1)                 # up-right lands on row 2, cube 3 -> water there, no fly
	run(wt, 0.25)
	check(wt.mode == SimC.Mode.DYING and wt.death_cause == "drown", "landing on water drowns")
	var hb := _arena_sim(arena, tun_a)
	_place(hb, 5, 3)
	hb.swipe(0, -1)
	check(hb.hopping, "swipe starts a hop")

	print("== skilled bot clears levels 1-6 without dying")
	for lv in range(1, 7):
		var q := new_sim(lv)
		var bot := Bot.new("skilled", 1)
		var frames := 0
		while not q.finished_win and not q.finished_over and frames < 60 * 90:
			bot.act(q); q.step(1.0 / 60.0); q.events.clear(); frames += 1
		check(q.finished_win and int(q.session["lives"]) == 3, "level %d cleared flawlessly in %.1fs" % [lv, q.t])

	print("== TouchArcade controller")
	_controller_tests()
	print("\n%d passed, %d failed" % [passes, fails])
	quit(1 if fails > 0 else 0)

var _sw: Array = []
var _ap: Array = []
var _ar: Array = []
var _cb: Array = []

func _touch(arc, idx: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = idx; e.position = pos; e.pressed = pressed
	arc._input(e)

func _drag_to(arc, idx: int, pos: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = idx; e.position = pos
	arc._input(e)

func _controller_tests() -> void:
	var arc := TouchArcade.new()
	root.add_child(arc)
	arc.game_id = "test_%d" % randi()
	arc.view_size_override = Vector2(720, 1280)
	arc.setup(arc.game_id, [{"name": "B", "label": "AIM"}, {"name": "A", "label": "TONGUE"}],
		{"A": Rect2(0.62, 0.84, 0.36, 0.15), "B": Rect2(0.28, 0.84, 0.32, 0.15)}, [{"name": "AB", "actions": ["A", "B"], "window": 0.15}])
	arc.swiped.connect(func(dx, dy): _sw.append(Vector2i(dx, dy)))
	arc.action_pressed.connect(func(a): _ap.append(a))
	arc.action_released.connect(func(a): _ar.append(a))
	arc.combo.connect(func(c): _cb.append(c))
	var s := Vector2(720, 1280)
	var A := Vector2(s.x * 0.8, s.y * 0.9)
	var B := Vector2(s.x * 0.4, s.y * 0.9)
	# swipes: 8 directions from the centre of the swipe area
	var c := Vector2(s.x * 0.3, s.y * 0.4)
	var dirs := {Vector2i(0, -1): Vector2(0, -1), Vector2i(1, 0): Vector2(1, 0), Vector2i(0, 1): Vector2(0, 1), Vector2i(-1, 0): Vector2(-1, 0)}
	var all_ok := true
	for d in dirs:
		_sw.clear()
		_touch(arc, 0, c, true)
		_drag_to(arc, 0, c + (dirs[d] as Vector2).normalized() * 120.0)
		_touch(arc, 0, c + dirs[d] * 120.0, false)
		if _sw.size() != 1 or _sw[0] != d:
			all_ok = false
	check(all_ok, "4 swipe directions recognised exactly once")
	_sw.clear()
	_sw.clear()
	_touch(arc, 0, c, true); _drag_to(arc, 0, c + Vector2(100, 70)); _touch(arc, 0, c, false)
	check(_sw.size() == 1 and _sw[0] == Vector2i(1, 0), "a diagonal-ish swipe resolves to its dominant axis (no diagonals)")
	_sw.clear()
	_touch(arc, 0, c, true); _drag_to(arc, 0, c + Vector2(5, 0)); _touch(arc, 0, c, false)
	check(_sw.is_empty(), "tiny movement is not a swipe")
	# multitouch: hold B with one finger while swiping with another
	_touch(arc, 1, B, true)
	check(arc.is_held("B"), "B held by finger 1")
	_sw.clear()
	_touch(arc, 2, c, true); _drag_to(arc, 2, c + Vector2(-120, 0))
	check(_sw.size() == 1 and _sw[0] == Vector2i(-1, 0) and arc.is_held("B"), "swipe works while B held (independent touches)")
	_touch(arc, 2, c, false)
	_ap.clear(); _cb.clear()
	_touch(arc, 3, A, true)
	check(_ap == ["A"] and _cb == ["AB"], "A pressed while B held fires the AB combo")
	_touch(arc, 3, A, false); _touch(arc, 1, B, false)
	check(not arc.is_held("A") and not arc.is_held("B"), "releasing fingers releases actions")
	# a swipe that passes over the A region must not press A
	_ap.clear(); _sw.clear()
	_touch(arc, 4, Vector2(s.x * 0.1, s.y * 0.9), true); _drag_to(arc, 4, Vector2(s.x * 0.8, s.y * 0.9))
	check(_ap.is_empty() and _sw.size() == 1, "swipe starting outside a region never presses it")
	_touch(arc, 4, Vector2(s.x * 0.8, s.y * 0.9), false)
	# layout: handedness mirror, resize clamps, defaults
	var before: Rect2 = arc.regions["A"]
	arc.set_handed("left")
	var mirrored: Rect2 = arc.regions["A"]
	check(absf(mirrored.position.x - (1.0 - before.position.x - before.size.x)) < 1e-6, "left-handed layout mirrors the regions")
	arc.set_region_px("A", Rect2(-500, -500, 10, 10))
	var clamped: Rect2 = arc.regions["A"]
	check(clamped.position.x >= 0.0 and clamped.position.y >= 0.0 and clamped.size.x >= arc.min_region.x - 1e-6, "regions clamp to the screen and a minimum size")
	arc.restore_defaults()
	check(arc.regions["A"] == arc.default_regions["A"] and arc.handed == "right", "restore defaults")
	check(arc.actions.size() <= 2, "Frogert uses at most two action regions")
	arc.queue_free()
