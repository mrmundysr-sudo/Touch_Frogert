extends RefCounted
## Touch Frogert simulation: deterministic, fixed-step, no nodes, no rendering.
## Drive it with step(dt) at 1/60 and feed input via swipe()/press_a().
const Board = preload("res://src/sim/board.gd")
const Tuning = preload("res://src/sim/tuning.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
const Hopmap = preload("res://src/sim/hopmap.gd")

enum Mode { READY, PLAY, DYING, WIN, OVER }
enum Face { UP, RIGHT, DOWN, LEFT }   # named by SWIPE; the frog looks along that swipe's hop direction

const READY_TIME := 0.9
const DEATH_TIME := 1.15
const WIN_TIME := 1.9

var tun_base: Dictionary
var tun: Dictionary
var session: Dictionary          # shared across restarts/levels: score, lives, level, next_bonus, max_level
var level: Dictionary
var board: Board
var mode := Mode.READY
var mode_t := 0.0
var t := 0.0                    # level time (only runs in PLAY)
var attempt_no := 0             # deaths so far on this level
var finished_win := false
var finished_over := false
var death_cause := ""

# frog
var frog_r := 0
var frog_rel := 0.0
var face := Face.UP
var hopping := false
var hop_t := 0.0
var hop_dur := 0.18
var hop_from_r := 0
var hop_from_wx := 0.0
var hop_to_r := 0
var hop_to_rel := 0.0
var hop_to_wx := 0.0
var hop_to_c := 0
var hop_launch_t := 0.0
var hop_dir := Vector2i.ZERO
var best_row := 0
var carry_age := -1.0
var floating := false
var lock_t := 0.0
var tongue_t := 0.0
var tongue_r := 0
var tongue_k := 0
var tongue_c := 0
var tongue_hit := false
var buf_dir := Vector2i.ZERO
var buf_t := 0.0
var buf_a := 0.0
var bonk_t := 0.0
var shots: Array = []            # {t0, targets:[[r,k]], applied, range}
var events: Array = []           # consumed by view/audio: [name, a, b]
var log: Array = []              # development log (dictionaries)
var log_enabled := true
var warned_red := false
var warned_fuse := false

func _init(tuning: Dictionary, sess: Dictionary) -> void:
	tun_base = tuning
	session = sess

# ------------------------------------------------------------------ setup

func start_level(lv_number: int, attempt: int = 0, lv: Dictionary = {}) -> void:
	session["level"] = lv_number
	tun = Tuning.for_level(tun_base, lv_number)
	level = lv if not lv.is_empty() else LevelGen.generate(tun_base, lv_number, attempt)
	attempt_no = 0
	finished_win = false
	finished_over = false
	_reset_level_state()

func _reset_level_state() -> void:
	board = Board.new()
	board.load_level(level, tun)
	t = 0.0
	mode = Mode.READY
	mode_t = 0.0
	frog_r = board.n - 1
	frog_rel = Board.start_rel(board.w[frog_r])
	best_row = frog_r
	face = Face.UP
	hopping = false
	carry_age = -1.0
	floating = false
	lock_t = 0.0
	tongue_t = 0.0
	buf_dir = Vector2i.ZERO
	buf_t = 0.0
	buf_a = 0.0
	bonk_t = 0.0
	shots.clear()
	warned_red = false
	warned_fuse = false
	death_cause = ""
	hop_dur = float(tun["hop_time"])
	_log("level_start", {"seed": level["seed"], "attempt": level["attempt"], "death_no": attempt_no})

## Live tuning changes (dev panel). Keeps the ring positions continuous.
func set_tuning(new_tun: Dictionary) -> void:
	tun_base = new_tun
	tun = Tuning.for_level(new_tun, int(session["level"]))
	hop_dur = float(tun["hop_time"])
	board.apply_speeds(tun, t)

# ------------------------------------------------------------------ helpers

func _log(ev: String, extra: Dictionary = {}) -> void:
	if not log_enabled:
		return
	var d := {"t": snappedf(t, 0.001), "lvl": session.get("level", 0), "ev": ev, "row": frog_r, "x": snappedf(board.local_x(frog_r, frog_rel, t) if board else 0.0, 0.01), "lives": session.get("lives", 0)}
	d.merge(extra)
	log.append(d)
	if log.size() > 4000:
		log.remove_at(0)

func _emit(name: String, a: Variant = null, b: Variant = null) -> void:
	events.append([name, a, b])

func frog_cube() -> int:
	return clampi(board.cube_under(frog_r, frog_rel, t), 0, int(board.w[frog_r]) - 1)

## unit hop vector (hx, hy) the frog is currently facing
func face_hop() -> Vector2i:
	return Hopmap.hop_for_name(tun, Hopmap.NAMES[face])

func frog_slot() -> int:
	return board.slot_of_rel(frog_r, frog_rel)

func frog_world_x() -> float:
	return board.world_x(frog_r, frog_rel, t)

## [row_float, world_x, arc] for drawing
func frog_view() -> Array:
	if hopping:
		var s := clampf(hop_t / hop_dur, 0.0, 1.0)
		return [lerpf(hop_from_r, hop_to_r, s), lerpf(hop_from_wx, hop_to_wx, s), sin(s * PI)]
	return [float(frog_r), frog_world_x(), 0.0]

func stage() -> int:
	if carry_age < 0.0:
		return 0
	if carry_age < float(tun["fly_t1"]):
		return 1
	if carry_age < float(tun["fly_t2"]):
		return 2
	return 3

func stage_range() -> int:
	match stage():
		1: return int(tun["range1"])
		2: return int(tun["range2"])
		3: return int(tun["range3"])
	return 0

func add_score(v: int) -> void:
	session["score"] = int(session["score"]) + v
	# bonus lives at bonus_first, then every bonus_every after that
	while int(session["score"]) >= int(session["next_bonus"]):
		session["bonus_given"] = int(session["bonus_given"]) + 1
		session["next_bonus"] = int(tun["bonus_first"]) + int(tun["bonus_every"]) * int(session["bonus_given"])
		session["lives"] = mini(int(session["lives"]) + 1, 9)
		_emit("extra_life")
		_log("extra_life", {"score": session["score"]})

func time_left() -> float:
	return maxf(0.0, float(tun["time_limit"]) - t)

# ------------------------------------------------------------------ input

static func face_from(dx: int, dy: int) -> int:
	if dy < 0: return Face.UP
	if dy > 0: return Face.DOWN
	return Face.RIGHT if dx > 0 else Face.LEFT

## dx,dy = the SWIPE direction (exactly one non-zero). aim=true (B held) only turns the frog.
func swipe(dx: int, dy: int, aim: bool = false) -> void:
	if dx != 0 and dy != 0:
		dx = 0                      # controls are strictly 4-way
	if mode != Mode.PLAY or (dx == 0 and dy == 0):
		return
	if aim:
		face = face_from(dx, dy)
		_emit("turn")
		return
	if hopping or lock_t > 0.0 or bonk_t > 0.0:
		buf_dir = Vector2i(dx, dy)
		buf_t = float(tun["buffer_time"])
		return
	_try_hop(dx, dy)

func press_a() -> void:
	if mode != Mode.PLAY:
		return
	if hopping or lock_t > 0.0:
		buf_a = float(tun["buffer_time"])
		return
	_do_a()

func _try_hop(dx: int, dy: int) -> void:
	face = face_from(dx, dy)
	var hv := Hopmap.hop_for_swipe(tun, dx, dy)
	var pr := board.plan_hop(frog_r, frog_rel, hv.x, hv.y, t, hop_dur)
	if int(pr[0]) == 2:
		_emit("bump")
		return
	if int(pr[0]) == 1:
		bonk_t = 0.12
		_emit("bonk", frog_r)
		_log("bonk", {"swipe": [dx, dy]})
		return
	hopping = true
	hop_t = 0.0
	hop_launch_t = t
	hop_from_r = frog_r
	hop_from_wx = frog_world_x()
	hop_to_r = int(pr[1])
	hop_to_rel = pr[2]
	hop_to_c = int(pr[5])
	hop_to_wx = float(hop_to_c) + 0.5 - float(board.w[hop_to_r]) * 0.5
	hop_dir = Vector2i(dx, dy)
	floating = false
	_emit("hop")

func _do_a() -> void:
	if carry_age < 0.0:
		var tgt := _facing_cube(1)
		tongue_t = 0.26
		lock_t = float(tun["tongue_lock"])
		tongue_hit = false
		if tgt.size() == 3:
			tongue_r = tgt[0]; tongue_c = tgt[1]
			var fi := board.fly_at(tongue_r, tgt[2])
			if fi >= 0 and board.fly_state(fi, t) == Board.RIPE:
				board.consume_fly(fi, t)
				carry_age = 0.0
				tongue_hit = true
				warned_red = false; warned_fuse = false
				add_score(int(tun["pts_catch"]))
				_emit("catch", tongue_r, tongue_c)
				_log("catch", {"fr": tongue_r, "fc": tongue_c})
				return
		else:
			tongue_r = frog_r; tongue_c = frog_cube()
		_emit("whiff")
		return
	# carrying a fly -> shoot
	if board.landing_result(frog_r, frog_rel, t, true) == Board.R_FLOAT:
		_log("shoot_while_floating")
		die("sink")
		return
	var rng := stage_range()
	var targets: Array = []
	for j in range(1, rng + 1):
		var tg := _facing_cube(j)
		if tg.size() != 3:
			break
		targets.append([tg[0], tg[1]])
	shots.append({"t0": t, "targets": targets, "applied": 0, "range": rng, "face": face, "from_r": frog_r, "from_wx": frog_world_x()})
	_log("shoot", {"range": rng, "stage": stage(), "age": snappedf(carry_age, 0.01), "face": face})
	carry_age = -1.0
	lock_t = 0.12
	_emit("shoot", rng)

## The cube `dist` spaces away along the facing diagonal: [row, cube, slot_over_it] or [] if off the pyramid.
func _facing_cube(dist: int) -> Array:
	var hv := face_hop()
	var r := frog_r
	var c := frog_cube()
	for i in dist:
		r += hv.y
		c += Hopmap.cube_step(hv)
		if r < 0 or r >= board.n or c < 0 or c >= int(board.w[r]):
			return []
	return [r, c, board.slot_over_cube(r, c, t)]

# ------------------------------------------------------------------ step

func step(dt: float) -> void:
	mode_t += dt
	match mode:
		Mode.READY:
			if mode_t >= READY_TIME:
				mode = Mode.PLAY
				mode_t = 0.0
				_emit("go")
		Mode.PLAY:
			_play(dt)
		Mode.DYING:
			if mode_t >= DEATH_TIME:
				if int(session["lives"]) <= 0:
					mode = Mode.OVER
					finished_over = true
					_emit("game_over")
				else:
					attempt_no += 1
					_reset_level_state()
					_emit("restart")
		Mode.WIN:
			if mode_t >= WIN_TIME:
				finished_win = true

func _play(dt: float) -> void:
	t += dt
	lock_t = maxf(0.0, lock_t - dt)
	bonk_t = maxf(0.0, bonk_t - dt)
	tongue_t = maxf(0.0, tongue_t - dt)
	buf_t = maxf(0.0, buf_t - dt)
	buf_a = maxf(0.0, buf_a - dt)
	_update_shots()
	if carry_age >= 0.0:
		carry_age += dt
		var s := stage()
		if s == 3 and not warned_red:
			warned_red = true
			_emit("warn_red")
		if carry_age >= float(tun["fly_t3"]) - 1.0 and not warned_fuse:
			warned_fuse = true
			_emit("warn_fuse")
		if carry_age >= float(tun["fly_t3"]):
			die("pop")
			return
	if float(tun["time_limit"]) > 0.0 and t >= float(tun["time_limit"]):
		die("timeout")
		return
	if hopping:
		hop_t += dt
		if hop_t >= hop_dur:
			_land()
		return
	# attached to a row
	var k := frog_slot()
	var fi := board.fly_at(frog_r, k)
	if fi >= 0 and board.fly_state(fi, t) != Board.NO_FLY:
		board.consume_fly(fi, t)       # standing on a slot squashes the fly emerging there
		_emit("crush")
	var res := board.landing_result(frog_r, frog_rel, t, carry_age >= 0.0)
	if _handle_result(res):
		return
	if buf_dir != Vector2i.ZERO and buf_t > 0.0 and lock_t <= 0.0 and bonk_t <= 0.0:
		var d := buf_dir
		buf_dir = Vector2i.ZERO
		_try_hop(d.x, d.y)
	elif buf_a > 0.0 and lock_t <= 0.0:
		buf_a = 0.0
		_do_a()

func _handle_result(res: int) -> bool:
	match res:
		Board.R_FELL:
			die("fell"); return true
		Board.R_DROWN:
			die("drown"); return true
		Board.R_FLY:
			die("fly"); return true
		Board.R_FLOAT:
			if not floating:
				floating = true
				_emit("float")
		_:
			floating = false
	return false

func _land() -> void:
	hopping = false
	var tl := hop_launch_t + hop_dur
	frog_r = hop_to_r
	frog_rel = hop_to_rel
	var res := board.landing_result(frog_r, frog_rel, tl, carry_age >= 0.0)
	_emit("land", frog_r)
	if _handle_result(res):
		return
	var fi := board.fly_at(frog_r, frog_slot())
	if fi >= 0 and board.fly_state(fi, tl) == Board.GROW:
		board.consume_fly(fi, tl)
		_emit("crush")
	if frog_r < best_row:
		add_score(int(tun["pts_row"]) * (best_row - frog_r))
		best_row = frog_r
	if frog_r == 0:
		_win()
		return
	# queued input executes immediately on landing
	if buf_dir != Vector2i.ZERO and buf_t > 0.0:
		var d := buf_dir
		buf_dir = Vector2i.ZERO
		_try_hop(d.x, d.y)
	elif buf_a > 0.0:
		buf_a = 0.0
		_do_a()

func _win() -> void:
	mode = Mode.WIN
	mode_t = 0.0
	var bonus := int(tun["pts_level"]) + int(time_left()) * int(tun["pts_time"])
	add_score(bonus)
	session["max_level"] = maxi(int(session.get("max_level", 1)), int(session["level"]))
	_emit("win", bonus)
	_log("win", {"bonus": bonus, "time": snappedf(t, 0.01)})

func die(cause: String) -> void:
	if mode != Mode.PLAY and mode != Mode.READY:
		return
	mode = Mode.DYING
	mode_t = 0.0
	death_cause = cause
	hopping = false
	session["lives"] = int(session["lives"]) - 1
	_log("death", {"cause": cause, "carry": snappedf(carry_age, 0.01), "death_no": attempt_no + 1})
	_emit("die", cause)

func _update_shots() -> void:
	var ps := float(tun["proj_speed"])
	var i := shots.size() - 1
	while i >= 0:
		var s: Dictionary = shots[i]
		var targets: Array = s["targets"]
		while int(s["applied"]) < targets.size() and t >= float(s["t0"]) + float(int(s["applied"]) + 1) / ps:
			var tg: Array = targets[int(s["applied"])]
			_hit_cube(tg[0], tg[1])
			s["applied"] = int(s["applied"]) + 1
		if t >= float(s["t0"]) + float(targets.size() + 1) / ps + 0.15:
			shots.remove_at(i)
		i -= 1

func _hit_cube(r: int, c: int) -> void:
	var k := board.slot_over_cube(r, c, t)      # whatever surface is over that cube right now
	if int(board.slots[r][k]) == Board.BARRIER:
		board.slots[r][k] = Board.PAD
		add_score(int(tun["pts_barrier"]))
		_emit("barrier_down", r, c)
		_log("barrier_destroyed", {"br": r, "bc": c})
	var fi := board.fly_at(r, k)
	if fi >= 0 and board.fly_state(fi, t) != Board.NO_FLY:
		board.consume_fly(fi, t)
		add_score(int(tun["pts_fly_kill"]))
		_emit("fly_zap", r, c)
