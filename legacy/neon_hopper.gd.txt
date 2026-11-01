extends Node2D
## NEON HOPPER - an original isometric hop-and-claim arcade game.
## Hop around the pyramid to claim every tile. Your tongue auto-grabs flies,
## and your cheek auto-spits them at baddies lined up on a diagonal.

const N := 7
const TW := 96.0
const HA := 48.0   # half tile width
const HB := 24.0   # half tile (diamond) height
const SH := 48.0   # cube side height
const DY := 72.0   # row spacing
const ORIGIN := Vector2(360, 340)
const W := 720.0
const H := 1280.0
const CHEEK_MAX := 2

const DIR_LIST: Array[Vector2i] = [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(1, 1)]
const DOWN_DIRS: Array[Vector2i] = [Vector2i(1, 0), Vector2i(1, 1)]

const FINALS: Array[Color] = [Color("00f0ff"), Color("b6ff00"), Color("ff9d00"), Color("ff4fd8")]
const BASE_TOP := Color("1b1050")
const MID_TOP := Color("ff2fa0")
const SIDE_L := Color("22126b")
const SIDE_R := Color("3a1a9e")
const NEON_PINK := Color("ff2fa0")
const NEON_CYAN := Color("00f0ff")
const NEON_GREEN := Color("39ff14")
const NEON_YELLOW := Color("fff200")

enum State { TITLE, PLAY, DYING, CLEAR, OVER }

class Actor:
	var kind := ""
	var r := 0
	var c := 0
	var from := Vector2.ZERO
	var to := Vector2.ZERO
	var t := 1.0
	var dur := 0.22
	var hop_h := 28.0
	var timer := 0.0
	var beat := 0.8
	var falling := false
	var fall_t := 0.0
	var dead := false
	var face := Vector2i(1, 1)
	var life := 0.0
	var wobble := 0.0
	var squash := 0.0
	var immune := 0.0

var state: int = State.TITLE
var time := 0.0
var score := 0
var hi := 0
var lives := 3
var level := 1
var need := 1
var next_life_at := 5000
var tiles: Array = []
var pulses: Array = []
var frog: Actor
var frog_hidden := false
var enemies: Array[Actor] = []
var flies: Array[Actor] = []
var shots: Array = []
var parts: Array = []
var popups: Array = []
var stars: Array[Vector3] = []

var cheek := 0
var tongue_active := false
var tongue_t := 0.0
var tongue_cd := 0.0
var tongue_captured := false
var tongue_target: Actor = null
var tongue_target_pos := Vector2.ZERO
var spit_cd := 0.0
var spit_anim := 0.0

var buffer_dir := Vector2i.ZERO
var buffer_t := 0.0
var death_t := 0.0
var clear_t := 0.0
var banner_t := 0.0
var shake := 0.0
var over_t := 0.0
var beetle_timer := 2.0
var heron_timer := 7.0
var fly_timer := 1.5

var pressing := false
var consumed := false
var press_pos := Vector2.ZERO

var players: Array[AudioStreamPlayer] = []
var player_i := 0
var sounds := {}

var ai := false
var ai_timer := 0.0
var shot_frames: Array[int] = []
var frame_count := 0
var shot_dir := ""

# ---------------------------------------------------------------- setup

func _ready() -> void:
	randomize()
	load_hi()
	for i in 90:
		stars.append(Vector3(randf() * W, randf() * H * 0.78, randf() * TAU))
	build_sounds()
	for i in 8:
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)
	level = 1
	setup_level()
	frog.t = 1.0
	frog.immune = 0.0
	var args := OS.get_cmdline_user_args()
	if "--autotest" in args:
		run_autotest()
	elif "--shots" in args:
		shot_dir = "/tmp/shots"
		DirAccess.make_dir_recursive_absolute(shot_dir)
		shot_frames = [20, 120, 400, 700, 1000, 1400]
		start_game()
		ai = true

func start_game() -> void:
	score = 0
	lives = 3
	level = 1
	next_life_at = 5000
	setup_level()
	state = State.PLAY

func setup_level() -> void:
	need = 1 if level < 3 else 2
	tiles.clear()
	pulses.clear()
	for r in N:
		var row: Array = []
		var prow: Array = []
		for c in r + 1:
			row.append(0)
			prow.append(0.0)
		tiles.append(row)
		pulses.append(prow)
	enemies.clear()
	flies.clear()
	shots.clear()
	cheek = 0
	tongue_active = false
	buffer_t = 0.0
	spawn_frog()
	beetle_timer = 2.0
	heron_timer = 7.0
	fly_timer = 1.5
	banner_t = 1.8

func spawn_frog() -> void:
	frog = Actor.new()
	frog.kind = "frog"
	frog.r = 0
	frog.c = 0
	frog.to = tpos(0, 0)
	frog.from = frog.to + Vector2(0, -500)
	frog.t = 0.0
	frog.dur = 0.6
	frog.hop_h = 0.0
	frog.immune = 2.2
	frog.face = Vector2i(1, 1)
	frog_hidden = false

# ---------------------------------------------------------------- geometry

func tpos(r: int, c: int) -> Vector2:
	return ORIGIN + Vector2((c - r * 0.5) * TW, r * DY)

func valid(r: int, c: int) -> bool:
	return r >= 0 and r < N and c >= 0 and c <= r

func apos(a: Actor) -> Vector2:
	var p: Vector2
	if a.t < 1.0:
		p = a.from.lerp(a.to, a.t)
		p.y -= sin(PI * a.t) * a.hop_h
	else:
		p = a.to
	if a.falling:
		p.y += a.fall_t * a.fall_t * 900.0
	return p

func start_hop(a: Actor, d: Vector2i, dur: float, h: float) -> void:
	a.from = apos(a)
	a.r += d.x
	a.c += d.y
	a.to = tpos(a.r, a.c)
	a.t = 0.0
	a.dur = dur
	a.hop_h = h
	a.face = d

func frog_idle() -> bool:
	return frog.t >= 1.0 and not frog.falling and not frog_hidden

func swipe_dir(v: Vector2) -> Vector2i:
	if v.x < 0.0 and v.y < 0.0:
		return DIR_LIST[0]
	if v.x >= 0.0 and v.y < 0.0:
		return DIR_LIST[1]
	if v.x < 0.0:
		return DIR_LIST[2]
	return DIR_LIST[3]

# ---------------------------------------------------------------- input

func queue_dir(d: Vector2i) -> void:
	buffer_dir = d
	buffer_t = 0.3

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		match ev.keycode:
			KEY_Q, KEY_KP_7:
				press_dir(DIR_LIST[0])
			KEY_E, KEY_KP_9:
				press_dir(DIR_LIST[1])
			KEY_Z, KEY_KP_1:
				press_dir(DIR_LIST[2])
			KEY_C, KEY_KP_3:
				press_dir(DIR_LIST[3])
			KEY_SPACE, KEY_ENTER:
				tap_action(Vector2(-1, -1))
	elif ev is InputEventMouseButton and ev.button_index == MOUSE_BUTTON_LEFT:
		if ev.pressed:
			pressing = true
			consumed = false
			press_pos = ev.position
		else:
			pressing = false
			if not consumed:
				tap_action(ev.position)
	elif ev is InputEventMouseMotion and pressing and not consumed:
		var v: Vector2 = ev.position - press_pos
		if state == State.PLAY and v.length() > 50.0:
			queue_dir(swipe_dir(v))
			consumed = true

func press_dir(d: Vector2i) -> void:
	if state == State.PLAY:
		queue_dir(d)
	else:
		tap_action(Vector2(-1, -1))

func tap_action(p: Vector2) -> void:
	match state:
		State.TITLE:
			start_game()
			sfx("start")
		State.OVER:
			if over_t > 0.9:
				start_game()
				sfx("start")
		State.PLAY:
			if p.x >= 0.0:
				var origin := apos(frog) + Vector2(0, -18)
				queue_dir(swipe_dir(p - origin))

# ---------------------------------------------------------------- main loop

func _process(delta: float) -> void:
	step(minf(delta, 0.05))
	if shot_dir != "":
		frame_count += 1
		if frame_count in shot_frames:
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/shot_%04d.png" % [shot_dir, frame_count])
		if frame_count > 1450:
			get_tree().quit()

func step(dt: float) -> void:
	time += dt
	update_particles(dt)
	shake = maxf(0.0, shake - dt * 30.0)
	position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake
	banner_t = maxf(0.0, banner_t - dt)
	for r in N:
		for c in r + 1:
			pulses[r][c] = maxf(0.0, float(pulses[r][c]) - dt * 3.0)
	match state:
		State.PLAY:
			if ai:
				ai_update(dt)
			update_play(dt)
		State.DYING:
			update_dying(dt)
		State.CLEAR:
			update_clear(dt)
		State.OVER:
			over_t += dt
			if ai and over_t > 1.0:
				start_game()
	queue_redraw()

func update_play(dt: float) -> void:
	frog.immune = maxf(0.0, frog.immune - dt)
	frog.squash = maxf(0.0, frog.squash - dt * 5.0)
	if frog.t < 1.0:
		frog.t += dt / frog.dur
		if frog.t >= 1.0:
			frog.t = 1.0
			on_frog_land()
			if state != State.PLAY:
				return
	elif buffer_t > 0.0 and frog_idle():
		start_hop(frog, buffer_dir, 0.2, 30.0)
		buffer_t = 0.0
		sfx("hop")
	buffer_t = maxf(0.0, buffer_t - dt)

	update_tongue(dt)
	update_spit(dt)
	update_shots(dt)
	for e in enemies:
		update_enemy(e, dt)
	for f in flies:
		update_fly(f, dt)
	for i in range(enemies.size() - 1, -1, -1):
		if enemies[i].dead:
			enemies.remove_at(i)
	for i in range(flies.size() - 1, -1, -1):
		if flies[i].dead:
			flies.remove_at(i)
	update_spawns(dt)
	check_collisions()

func on_frog_land() -> void:
	frog.squash = 1.0
	if not valid(frog.r, frog.c):
		frog.falling = true
		frog.fall_t = 0.0
		lose_life(false)
		return
	var st: int = tiles[frog.r][frog.c]
	if st < need:
		tiles[frog.r][frog.c] = st + 1
		add_score(25, tpos(frog.r, frog.c) + Vector2(0, -34))
		sfx("tile")
		burst(tpos(frog.r, frog.c), final_color(), 8, 140.0)
	pulses[frog.r][frog.c] = 1.0
	check_clear()

func check_clear() -> void:
	if state != State.PLAY:
		return
	for r in N:
		for c in r + 1:
			if int(tiles[r][c]) < need:
				return
	state = State.CLEAR
	clear_t = 0.0
	for e in enemies:
		burst(apos(e) + Vector2(0, -16), NEON_PINK, 14, 220.0)
	enemies.clear()
	shots.clear()
	add_score(500 * level, Vector2(360, 200))
	sfx("clear")

func update_clear(dt: float) -> void:
	clear_t += dt
	frog.squash = maxf(0.0, frog.squash - dt * 5.0)
	if int(clear_t * 12.0) != int((clear_t - dt) * 12.0):
		var rr := randi() % N
		var cc := randi() % (rr + 1)
		burst(tpos(rr, cc), Color.from_hsv(randf(), 0.9, 1.0), 6, 200.0)
	if clear_t > 2.4:
		level += 1
		setup_level()
		state = State.PLAY

func lose_life(hit: bool) -> void:
	state = State.DYING
	death_t = 0.0
	lives -= 1
	cheek = 0
	tongue_active = false
	shots.clear()
	shake = 14.0
	sfx("die")
	if hit:
		frog_hidden = true
		burst(apos(frog) + Vector2(0, -18), NEON_GREEN, 26, 320.0)

func update_dying(dt: float) -> void:
	death_t += dt
	if frog.falling:
		frog.fall_t += dt
	for e in enemies:
		if e.falling:
			e.fall_t += dt
			if e.fall_t > 1.0:
				e.dead = true
	if death_t > 1.3:
		if lives <= 0:
			state = State.OVER
			over_t = 0.0
			save_hi()
		else:
			enemies.clear()
			shots.clear()
			spawn_frog()
			buffer_t = 0.0
			beetle_timer = 2.5
			state = State.PLAY

func add_score(v: int, at: Vector2, show := true) -> void:
	score += v
	if score > hi:
		hi = score
	if score >= next_life_at:
		next_life_at += 5000
		lives += 1
		sfx("clear")
		popups.append({"p": Vector2(360, 120), "s": "EXTRA LIFE!", "life": 1.4, "col": NEON_GREEN})
	if show:
		popups.append({"p": at, "s": "+%d" % v, "life": 0.9, "col": NEON_YELLOW})

# ---------------------------------------------------------------- tongue / spit

func update_tongue(dt: float) -> void:
	tongue_cd -= dt
	if tongue_active:
		tongue_t += dt / 0.24
		if not tongue_captured and tongue_t >= 0.5:
			tongue_captured = true
			if tongue_target != null and not tongue_target.dead:
				tongue_target.dead = true
				cheek = mini(cheek + 1, CHEEK_MAX)
				add_score(50, tongue_target_pos)
				burst(tongue_target_pos, NEON_YELLOW, 10, 160.0)
				sfx("catch")
		if tongue_t >= 1.0:
			tongue_active = false
			tongue_cd = 0.12
		return
	if tongue_cd > 0.0 or cheek >= CHEEK_MAX or not frog_idle():
		return
	var best: Actor = null
	var best_k := 99
	for f in flies:
		if f.dead or f.t < 1.0:
			continue
		for d in DIR_LIST:
			for k in 3:
				if f.r == frog.r + k * d.x and f.c == frog.c + k * d.y:
					if k < best_k:
						best_k = k
						best = f
					break
	if best != null:
		tongue_active = true
		tongue_t = 0.0
		tongue_captured = false
		tongue_target = best
		tongue_target_pos = apos(best) + Vector2(0, -40)
		sfx("tongue")

func update_spit(dt: float) -> void:
	spit_cd -= dt
	spit_anim = maxf(0.0, spit_anim - dt)
	if cheek <= 0 or spit_cd > 0.0 or not frog_idle() or tongue_active:
		return
	var best_d := Vector2i.ZERO
	var best_k := 99
	for d in DIR_LIST:
		for k in range(1, 7):
			var rr := frog.r + k * d.x
			var cc := frog.c + k * d.y
			if not valid(rr, cc):
				break
			if enemy_at(rr, cc) != null:
				if k < best_k:
					best_k = k
					best_d = d
				break
	if best_k < 99:
		cheek -= 1
		spit_cd = 0.35
		spit_anim = 0.25
		frog.face = best_d
		var from := tpos(frog.r, frog.c)
		shots.append({"r": frog.r, "c": frog.c, "d": best_d, "t": 0.0, "from": from, "to": tpos(frog.r + best_d.x, frog.c + best_d.y), "prev": from})
		sfx("spit")

func enemy_at(r: int, c: int) -> Actor:
	for e in enemies:
		if not e.dead and not e.falling and e.r == r and e.c == c:
			return e
	return null

func update_shots(dt: float) -> void:
	for i in range(shots.size() - 1, -1, -1):
		var s: Dictionary = shots[i]
		s["prev"] = s["from"].lerp(s["to"], s["t"])
		s["t"] = float(s["t"]) + dt / 0.06
		if float(s["t"]) >= 1.0:
			var d: Vector2i = s["d"]
			s["r"] = int(s["r"]) + d.x
			s["c"] = int(s["c"]) + d.y
			s["from"] = tpos(int(s["r"]), int(s["c"]))
			s["to"] = tpos(int(s["r"]) + d.x, int(s["c"]) + d.y)
			s["t"] = 0.0
			var hit := enemy_at(int(s["r"]), int(s["c"]))
			if hit != null:
				kill_enemy(hit)
				shots.remove_at(i)
				continue
			if not valid(int(s["r"]) + d.x, int(s["c"]) + d.y):
				shots.remove_at(i)

func kill_enemy(e: Actor) -> void:
	e.dead = true
	var p := apos(e) + Vector2(0, -16)
	var col := NEON_PINK if e.kind == "beetle" else Color("ff7a00")
	burst(p, col, 24, 300.0)
	burst(p, Color.WHITE, 8, 180.0)
	add_score(500 if e.kind == "heron" else 200, p)
	shake = 8.0
	sfx("kill")

# ---------------------------------------------------------------- enemies & flies

func update_spawns(dt: float) -> void:
	beetle_timer -= dt
	if beetle_timer <= 0.0:
		var cnt := 0
		for e in enemies:
			if e.kind == "beetle":
				cnt += 1
		if cnt < 2 + level / 2 and not (frog.r == 0 and frog.t >= 1.0):
			spawn_enemy("beetle")
		beetle_timer = maxf(1.6, 3.8 - 0.25 * level)
	if level >= 2:
		heron_timer -= dt
		if heron_timer <= 0.0:
			var cnt := 0
			for e in enemies:
				if e.kind == "heron":
					cnt += 1
			if cnt < (1 if level < 5 else 2) and not (frog.r == 0 and frog.t >= 1.0):
				spawn_enemy("heron")
			heron_timer = maxf(7.0, 15.0 - level)
	fly_timer -= dt
	if fly_timer <= 0.0:
		if flies.size() < (2 if level < 2 else 3) + (1 if cheek == 0 else 0) - (1 if level < 2 else 0):
			spawn_fly()
		fly_timer = 3.5

func spawn_enemy(kind: String) -> void:
	var e := Actor.new()
	e.kind = kind
	e.r = 0
	e.c = 0
	e.to = tpos(0, 0)
	e.from = e.to + Vector2(0, -420)
	e.t = 0.0
	e.dur = 0.55
	e.hop_h = 0.0
	e.beat = maxf(0.45, 0.8 - 0.04 * level) if kind == "beetle" else maxf(0.5, 0.95 - 0.05 * level)
	e.timer = -0.3
	enemies.append(e)

func spawn_fly() -> void:
	for tries in 10:
		var rr := randi() % N
		var cc := randi() % (rr + 1)
		if rr == frog.r and cc == frog.c:
			continue
		var f := Actor.new()
		f.kind = "fly"
		f.r = rr
		f.c = cc
		f.to = tpos(rr, cc)
		f.t = 1.0
		f.life = 12.0
		f.beat = 1.2
		f.wobble = randf() * TAU
		flies.append(f)
		burst(f.to + Vector2(0, -40), NEON_YELLOW, 8, 100.0)
		return

func update_enemy(e: Actor, dt: float) -> void:
	if e.dead:
		return
	if e.falling:
		e.fall_t += dt
		if e.fall_t > 1.0:
			e.dead = true
		return
	if e.t < 1.0:
		e.t += dt / e.dur
		if e.t >= 1.0:
			e.t = 1.0
			e.squash = 1.0
			if not valid(e.r, e.c):
				e.falling = true
				e.fall_t = 0.0
		return
	e.timer += dt
	if e.timer >= e.beat:
		e.timer = 0.0
		enemy_think(e)

func enemy_think(e: Actor) -> void:
	if e.kind == "beetle":
		start_hop(e, DOWN_DIRS[randi() % 2], 0.28, 26.0)
		return
	var choices: Array[Vector2i] = []
	for d in DIR_LIST:
		if valid(e.r + d.x, e.c + d.y):
			choices.append(d)
	if choices.is_empty():
		return
	var pick: Vector2i = choices[randi() % choices.size()]
	if e.r >= 2 and randf() > 0.15 and not frog.falling:
		var target := tpos(frog.r, frog.c)
		var bd := 1e9
		for d in choices:
			var dd := tpos(e.r + d.x, e.c + d.y).distance_to(target)
			if dd < bd:
				bd = dd
				pick = d
	elif e.r < 2:
		pick = DOWN_DIRS[randi() % 2]
	start_hop(e, pick, 0.26, 26.0)

func update_fly(f: Actor, dt: float) -> void:
	f.life -= dt
	if f.life <= 0.0 and not f.dead:
		f.dead = true
		burst(apos(f) + Vector2(0, -40), NEON_YELLOW, 6, 90.0)
		return
	if f.t < 1.0:
		f.t += dt / f.dur
		if f.t >= 1.0:
			f.t = 1.0
		return
	f.timer += dt
	if f.timer >= f.beat:
		f.timer = 0.0
		var choices: Array[Vector2i] = []
		for d in DIR_LIST:
			if valid(f.r + d.x, f.c + d.y):
				choices.append(d)
		if not choices.is_empty():
			start_hop(f, choices[randi() % choices.size()], 0.5, 10.0)

func check_collisions() -> void:
	if frog.immune > 0.0 or frog.falling or frog.t < 0.6:
		return
	for e in enemies:
		if e.dead or e.falling or e.t < 0.6:
			continue
		if e.r == frog.r and e.c == frog.c:
			lose_life(true)
			return

# ---------------------------------------------------------------- particles

func burst(p: Vector2, col: Color, n := 14, speed := 220.0) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * randf_range(0.3, 1.0) * speed
		var life := randf_range(0.4, 0.9)
		parts.append({"p": p, "v": v, "life": life, "max": life, "col": col, "sz": randf_range(3.0, 7.0)})

func update_particles(dt: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var pt: Dictionary = parts[i]
		pt["p"] = (pt["p"] as Vector2) + (pt["v"] as Vector2) * dt
		var v: Vector2 = pt["v"]
		v.y += 320.0 * dt
		pt["v"] = v
		pt["life"] = float(pt["life"]) - dt
		if float(pt["life"]) <= 0.0:
			parts.remove_at(i)
	for i in range(popups.size() - 1, -1, -1):
		var pu: Dictionary = popups[i]
		pu["p"] = (pu["p"] as Vector2) + Vector2(0, -50) * dt
		pu["life"] = float(pu["life"]) - dt
		if float(pu["life"]) <= 0.0:
			popups.remove_at(i)

# ---------------------------------------------------------------- save

func load_hi() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://neon.cfg") == OK:
		hi = int(cf.get_value("game", "hi", 0))

func save_hi() -> void:
	var cf := ConfigFile.new()
	cf.set_value("game", "hi", hi)
	cf.save("user://neon.cfg")

# ---------------------------------------------------------------- AI (demo / autotest)

func ai_update(dt: float) -> void:
	ai_timer -= dt
	if ai_timer > 0.0 or not frog_idle():
		return
	ai_timer = 0.26
	var best_score := -1e9
	var best := DIR_LIST[3]
	for d in DIR_LIST:
		var rr := frog.r + d.x
		var cc := frog.c + d.y
		if not valid(rr, cc):
			continue
		var sc := randf()
		if int(tiles[rr][cc]) < need:
			sc += 10.0
		else:
			sc -= nearest_unclaimed_dist(rr, cc) / 60.0
		for e in enemies:
			if not e.dead and absi(e.r - rr) + absi(e.c - cc) <= 1:
				sc -= 40.0
		if sc > best_score:
			best_score = sc
			best = d
	queue_dir(best)

func nearest_unclaimed_dist(r: int, c: int) -> float:
	var p := tpos(r, c)
	var bd := 1e9
	for rr in N:
		for cc in rr + 1:
			if int(tiles[rr][cc]) < need:
				bd = minf(bd, p.distance_to(tpos(rr, cc)))
	return bd

func run_autotest() -> void:
	start_game()
	ai = true
	var max_level := 1
	var deaths := 0
	var games := 0
	var kills_before := 0
	var last_lives := lives
	for i in 60 * 600:
		step(1.0 / 60.0)
		if lives < last_lives:
			deaths += 1
		last_lives = lives
		max_level = maxi(max_level, level)
		if state == State.OVER and over_t < 0.02:
			games += 1
			print("game over: level=%d score=%d t=%.0f" % [level, score, time])
	print("AUTOTEST DONE sim_time=%.0fs max_level=%d deaths=%d games=%d hi=%d" % [time, max_level, deaths, games, hi])
	get_tree().quit()

# ---------------------------------------------------------------- audio

func make_tone(f0: float, f1: float, dur: float, wave := 0, vol := 0.3) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in n:
		var k := float(i) / n
		phase += lerpf(f0, f1, k) / rate
		var s := 0.0
		match wave:
			0:
				s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			1:
				s = sin(phase * TAU)
			2:
				s = fmod(phase, 1.0) * 2.0 - 1.0
			_:
				s = randf() * 2.0 - 1.0
		var env := (1.0 - k) * minf(1.0, k * 40.0)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.stereo = false
	w.data = data
	return w

func make_seq(freqs: Array, step_len: float, wave := 0) -> AudioStreamWAV:
	var w := make_tone(freqs[0], freqs[0], step_len, wave, 0.28)
	var d := PackedByteArray()
	for f in freqs:
		d.append_array(make_tone(f, f, step_len, wave, 0.28).data)
	w.data = d
	return w

func build_sounds() -> void:
	sounds["hop"] = make_tone(260, 520, 0.09, 1, 0.4)
	sounds["tile"] = make_tone(880, 1320, 0.07, 0, 0.18)
	sounds["tongue"] = make_tone(700, 1500, 0.1, 0, 0.2)
	sounds["catch"] = make_seq([660, 990], 0.06, 0)
	sounds["spit"] = make_tone(1100, 180, 0.16, 2, 0.28)
	sounds["kill"] = make_tone(500, 60, 0.3, 3, 0.4)
	sounds["die"] = make_tone(520, 50, 0.7, 0, 0.3)
	sounds["clear"] = make_seq([523, 659, 784, 1047, 784, 1047, 1318], 0.09, 0)
	sounds["start"] = make_seq([392, 523, 659, 784], 0.07, 0)

func sfx(n: String) -> void:
	if players.is_empty() or not sounds.has(n):
		return
	var p := players[player_i]
	player_i = (player_i + 1) % players.size()
	p.stream = sounds[n]
	p.play()

# ---------------------------------------------------------------- drawing

func final_color() -> Color:
	return FINALS[(level - 1) % FINALS.size()]

func top_color(stage: int, r: int, c: int) -> Color:
	if state == State.CLEAR:
		return Color.from_hsv(fmod(time * 2.0 + (r + c) * 0.09, 1.0), 0.85, 1.0)
	if stage <= 0:
		return BASE_TOP
	if stage >= need:
		return final_color()
	return MID_TOP

func text(s: String, pos: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0) -> void:
	var f := ThemeDB.fallback_font
	draw_string_outline(f, pos, s, align, width, size, 8, Color(col.r, col.g, col.b, 0.18))
	draw_string(f, pos + Vector2(2, 3), s, align, width, size, Color(0, 0, 0, 0.7))
	draw_string(f, pos, s, align, width, size, col)

func neon_loop(pts: PackedVector2Array, col: Color, w := 2.0) -> void:
	var closed := pts.duplicate()
	closed.append(pts[0])
	draw_polyline(closed, Color(col.r, col.g, col.b, 0.14), w * 5.0)
	draw_polyline(closed, Color(col.r, col.g, col.b, 0.3), w * 2.4)
	draw_polyline(closed, col, w)

func ellipse(p: Vector2, rx: float, ry: float, col: Color) -> void:
	draw_set_transform(p, 0.0, Vector2(1.0, ry / rx))
	draw_circle(Vector2.ZERO, rx, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw() -> void:
	draw_backdrop()
	for r in N:
		for c in r + 1:
			draw_tile(r, c)
	draw_actors()
	for s in shots:
		var sp: Vector2 = (s["from"] as Vector2).lerp(s["to"] as Vector2, float(s["t"])) + Vector2(0, -22)
		var pv: Vector2 = (s["prev"] as Vector2) + Vector2(0, -22)
		draw_line(pv, sp, Color(1, 1, 0.4, 0.5), 8.0)
		draw_circle(sp, 15, Color(1, 0.9, 0.2, 0.25))
		draw_circle(sp, 10, NEON_YELLOW)
		draw_circle(sp, 5, Color.WHITE)
	if tongue_active and not frog_hidden:
		draw_tongue()
	for pt in parts:
		var a: float = clampf(float(pt["life"]) / float(pt["max"]), 0.0, 1.0)
		var col: Color = pt["col"]
		var sz: float = pt["sz"]
		draw_rect(Rect2((pt["p"] as Vector2) - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), Color(col.r, col.g, col.b, a))
	for pu in popups:
		var a2: float = clampf(float(pu["life"]) * 2.0, 0.0, 1.0)
		var pc: Color = pu["col"]
		text(pu["s"], (pu["p"] as Vector2) - Vector2(100, 0), 34, Color(pc.r, pc.g, pc.b, a2), HORIZONTAL_ALIGNMENT_CENTER, 200.0)
	draw_hud()
	if state == State.TITLE:
		draw_title()
	elif state == State.OVER:
		draw_over()
	elif banner_t > 0.0 and state == State.PLAY:
		text("LEVEL %d" % level, Vector2(0, 220), 72, NEON_PINK, HORIZONTAL_ALIGNMENT_CENTER, W)
	elif state == State.CLEAR:
		text("LEVEL CLEAR!", Vector2(0, 220), 72, Color.from_hsv(fmod(time * 1.5, 1.0), 0.7, 1.0), HORIZONTAL_ALIGNMENT_CENTER, W)
	# CRT scanlines
	var y := 0.0
	while y < H:
		draw_line(Vector2(0, y), Vector2(W, y), Color(0, 0, 0, 0.16), 1.0)
		y += 4.0

func draw_backdrop() -> void:
	for s in stars:
		var a := 0.2 + 0.5 * (0.5 + 0.5 * sin(time * 2.0 + s.z))
		draw_rect(Rect2(s.x, s.y, 3, 3), Color(1, 1, 1, a))
	var hy := 960.0
	draw_rect(Rect2(0, hy, W, H - hy), Color(0.07, 0.0, 0.16, 1.0))
	var gc := Color(0.95, 0.2, 1.0)
	draw_line(Vector2(0, hy), Vector2(W, hy), Color(gc.r, gc.g, gc.b, 0.9), 3.0)
	for i in 10:
		var k := (float(i) + fmod(time * 0.6, 1.0)) / 10.0
		var y := hy + (H - hy) * k * k
		draw_line(Vector2(0, y), Vector2(W, y), Color(gc.r, gc.g, gc.b, 0.12 + 0.5 * k), 2.0)
	for i in range(-9, 10):
		draw_line(Vector2(360 + i * 22, hy), Vector2(360 + i * 150, H), Color(gc.r, gc.g, gc.b, 0.3), 2.0)

func draw_tile(r: int, c: int) -> void:
	var p := tpos(r, c)
	var pulse: float = pulses[r][c]
	p.y -= pulse * 5.0
	var stage: int = tiles[r][c]
	var tc := top_color(stage, r, c).lerp(Color.WHITE, pulse * 0.5)
	var left := PackedVector2Array([p + Vector2(-HA, 0), p + Vector2(0, HB), p + Vector2(0, HB + SH), p + Vector2(-HA, SH)])
	var right := PackedVector2Array([p + Vector2(0, HB), p + Vector2(HA, 0), p + Vector2(HA, SH), p + Vector2(0, HB + SH)])
	var top := PackedVector2Array([p + Vector2(0, -HB), p + Vector2(HA, 0), p + Vector2(0, HB), p + Vector2(-HA, 0)])
	draw_colored_polygon(left, SIDE_L)
	draw_colored_polygon(right, SIDE_R)
	draw_colored_polygon(top, tc)
	var edge := final_color() if state != State.CLEAR else tc
	var inner := PackedVector2Array([p + Vector2(0, -HB * 0.55), p + Vector2(HA * 0.55, 0), p + Vector2(0, HB * 0.55), p + Vector2(-HA * 0.55, 0)])
	if stage > 0:
		draw_colored_polygon(inner, tc.lerp(Color.WHITE, 0.35))
	else:
		neon_loop(inner, Color(edge.r, edge.g, edge.b, 0.35), 1.0)
	neon_loop(top, edge if stage > 0 else Color(NEON_CYAN.r, NEON_CYAN.g, NEON_CYAN.b, 0.7), 2.0)
	var side_edge := Color(NEON_PINK.r, NEON_PINK.g, NEON_PINK.b, 0.85)
	draw_polyline(PackedVector2Array([p + Vector2(-HA, 0), p + Vector2(-HA, SH), p + Vector2(0, HB + SH), p + Vector2(HA, SH), p + Vector2(HA, 0)]), side_edge, 2.0)
	draw_line(p + Vector2(0, HB), p + Vector2(0, HB + SH), side_edge, 2.0)

func draw_actors() -> void:
	var list: Array = []
	for f in flies:
		list.append([apos(f).y, f])
	for e in enemies:
		list.append([apos(e).y, e])
	if not frog_hidden:
		list.append([apos(frog).y, frog])
	list.sort_custom(func(a, b): return a[0] < b[0])
	for it in list:
		var a: Actor = it[1]
		match a.kind:
			"frog":
				draw_frog(a)
			"beetle":
				draw_beetle(a)
			"heron":
				draw_heron(a)
			"fly":
				draw_fly(a)

func shadow(a: Actor, size: float) -> void:
	if a.falling:
		return
	var g := a.from.lerp(a.to, a.t) if a.t < 1.0 else a.to
	ellipse(g, size, size * 0.5, Color(0, 0, 0, 0.45))

func face_x(a: Actor) -> float:
	return signf(a.face.y - a.face.x * 0.5)

func draw_frog(a: Actor) -> void:
	if a.immune > 0.0 and a.t >= 1.0 and int(time * 14.0) % 2 == 0:
		return
	var p := apos(a)
	shadow(a, 18.0)
	var sx := 1.0
	var sy := 1.0
	if a.t < 1.0:
		var s := sin(PI * a.t)
		sy = 1.0 + 0.22 * s
		sx = 1.0 - 0.12 * s
	elif a.squash > 0.0:
		sy = 1.0 - 0.22 * a.squash
		sx = 1.0 + 0.2 * a.squash
	var fx := face_x(a)
	var up := a.face.x < 0
	var body := p + Vector2(0, -20.0 * sy)
	draw_set_transform(body, 0.0, Vector2(sx, sy))
	draw_circle(Vector2.ZERO, 30, Color(0.2, 1.0, 0.1, 0.12))
	draw_circle(Vector2.ZERO, 25, Color(0.2, 1.0, 0.1, 0.22))
	# back legs
	draw_circle(Vector2(-17, 14), 8, Color("1fa000"))
	draw_circle(Vector2(17, 14), 8, Color("1fa000"))
	draw_circle(Vector2.ZERO, 20, NEON_GREEN)
	draw_circle(Vector2(0, 6), 12, Color("a8ff7a") if not up else NEON_GREEN)
	# cheek pouches
	if cheek > 0 and a == frog:
		draw_circle(Vector2(-15, 5), 8, NEON_YELLOW)
		draw_circle(Vector2(-15, 5), 4, Color.WHITE)
		if cheek > 1:
			draw_circle(Vector2(15, 5), 8, NEON_YELLOW)
			draw_circle(Vector2(15, 5), 4, Color.WHITE)
	# eyes
	var eo := Vector2(fx * 2.5, (-3.0 if up else 2.0))
	for sgn in [-1.0, 1.0]:
		var ec := Vector2(sgn * 10.0, -13.0)
		draw_circle(ec, 8.5, Color("0e5a00"))
		draw_circle(ec, 7.0, Color.WHITE)
		draw_circle(ec + eo * 0.9, 3.6, Color("111111"))
	# mouth
	if not up:
		if spit_anim > 0.0 and a == frog:
			draw_circle(Vector2(fx * 3.0, 6), 5, Color("2a0030"))
		else:
			draw_arc(Vector2(fx * 2.0, 1), 9.0, 0.35, PI - 0.35, 8, Color("0b5a00"), 2.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_beetle(a: Actor) -> void:
	var p := apos(a)
	shadow(a, 15.0)
	var sq := 1.0 - 0.2 * a.squash
	var body := p + Vector2(0, -15)
	draw_set_transform(body, 0.0, Vector2(1.0 + 0.2 * a.squash, sq))
	draw_circle(Vector2.ZERO, 26, Color(1, 0.18, 0.58, 0.15))
	for sgn in [-1.0, 1.0]:
		for i in 3:
			draw_line(Vector2(sgn * 12, -4 + i * 8), Vector2(sgn * 22, -8 + i * 11), Color("ff9ad0"), 2.5)
	draw_circle(Vector2.ZERO, 17, NEON_PINK)
	draw_line(Vector2(0, -16), Vector2(0, 17), Color("7a0040"), 2.5)
	draw_circle(Vector2(-7, -3), 3, Color("7a0040"))
	draw_circle(Vector2(7, 5), 3, Color("7a0040"))
	var fx := face_x(a)
	draw_circle(Vector2(-5 + fx, -12), 4, Color.WHITE)
	draw_circle(Vector2(5 + fx, -12), 4, Color.WHITE)
	draw_circle(Vector2(-5 + fx * 2, -12), 1.8, Color.BLACK)
	draw_circle(Vector2(5 + fx * 2, -12), 1.8, Color.BLACK)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func draw_heron(a: Actor) -> void:
	var p := apos(a)
	shadow(a, 15.0)
	var fx := face_x(a)
	if fx == 0.0:
		fx = 1.0
	var orange := Color("ff7a00")
	var base := p + Vector2(0, -14)
	var head := base + Vector2(fx * 6.0, -42.0 + a.squash * 4.0)
	draw_circle(base, 22, Color(1, 0.48, 0, 0.15))
	draw_line(p + Vector2(-6, 0), p + Vector2(-6, -10), orange, 3.0)
	draw_line(p + Vector2(6, 0), p + Vector2(6, -10), orange, 3.0)
	ellipse(base, 15, 12, orange)
	draw_line(base + Vector2(0, -4), head, orange, 6.0)
	draw_circle(head, 9, orange)
	draw_colored_polygon(PackedVector2Array([head + Vector2(fx * 8, -3), head + Vector2(fx * 24, 3), head + Vector2(fx * 8, 4)]), NEON_YELLOW)
	draw_circle(head + Vector2(fx * 2, -2), 3, Color.WHITE)
	draw_circle(head + Vector2(fx * 3, -2), 1.5, Color.BLACK)

func draw_fly(a: Actor) -> void:
	var p := apos(a)
	var bob := sin(time * 7.0 + a.wobble) * 3.0
	var h := p + Vector2(0, -40 + bob)
	ellipse(a.to if a.t >= 1.0 else a.from.lerp(a.to, a.t), 8.0, 4.0, Color(0, 0, 0, 0.35))
	draw_fly_at(h, time * 30.0 + a.wobble)

func draw_fly_at(h: Vector2, flap: float) -> void:
	var wing := 0.5 + 0.5 * absf(sin(flap))
	draw_circle(h, 16, Color(1, 0.95, 0, 0.14))
	ellipse(h + Vector2(-7, -6), 7.0, 7.0 * wing, Color(0.8, 1.0, 1.0, 0.7))
	ellipse(h + Vector2(7, -6), 7.0, 7.0 * wing, Color(0.8, 1.0, 1.0, 0.7))
	ellipse(h, 6.0, 8.0, NEON_YELLOW)
	draw_circle(h + Vector2(-2, -5), 1.6, Color.BLACK)
	draw_circle(h + Vector2(2, -5), 1.6, Color.BLACK)

func draw_tongue() -> void:
	var mouth := apos(frog) + Vector2(0, -16)
	var e := sin(PI * clampf(tongue_t, 0.0, 1.0))
	var tip := mouth.lerp(tongue_target_pos, e)
	draw_line(mouth, tip, Color(1, 0.2, 0.6, 0.3), 12.0)
	draw_line(mouth, tip, Color("ff5fa8"), 6.0)
	draw_circle(tip, 7, Color("ff5fa8"))
	if tongue_captured and tongue_t < 1.0:
		draw_fly_at(tip + Vector2(0, -6), time * 30.0)

func draw_hud() -> void:
	text("SCORE", Vector2(28, 52), 24, NEON_CYAN)
	text(str(score), Vector2(28, 100), 46, Color.WHITE)
	text("HI-SCORE", Vector2(0, 52), 24, NEON_PINK, HORIZONTAL_ALIGNMENT_CENTER, W)
	text(str(hi), Vector2(0, 100), 40, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("LEVEL", Vector2(0, 52), 24, NEON_YELLOW, HORIZONTAL_ALIGNMENT_RIGHT, W - 28.0)
	text(str(level), Vector2(0, 100), 46, Color.WHITE, HORIZONTAL_ALIGNMENT_RIGHT, W - 28.0)
	for i in maxi(lives, 0):
		var p := Vector2(44 + i * 46, 152)
		draw_circle(p, 15, NEON_GREEN)
		draw_circle(p + Vector2(-6, -9), 5.5, Color.WHITE)
		draw_circle(p + Vector2(6, -9), 5.5, Color.WHITE)
		draw_circle(p + Vector2(-6, -8), 2.5, Color.BLACK)
		draw_circle(p + Vector2(6, -8), 2.5, Color.BLACK)
	text("CHEEK", Vector2(0, 892), 22, NEON_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, W)
	for i in CHEEK_MAX:
		var c := Vector2(360 + (i - 0.5 * (CHEEK_MAX - 1)) * 50, 930)
		if i < cheek:
			draw_circle(c, 15, Color(1, 0.95, 0, 0.25))
			draw_circle(c, 11, NEON_YELLOW)
		else:
			draw_arc(c, 11, 0, TAU, 20, Color(1, 0.95, 0, 0.5), 2.0)

func draw_title() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0, 0.06, 0.72))
	var pulse := 0.5 + 0.5 * sin(time * 3.0)
	text("NEON", Vector2(0, 360), 130, NEON_CYAN, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("HOPPER", Vector2(0, 490), 130, NEON_PINK, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("SWIPE DIAGONALLY TO HOP", Vector2(0, 600), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("CLAIM EVERY TILE", Vector2(0, 650), 34, NEON_GREEN, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("TONGUE GRABS FLIES AUTOMATICALLY", Vector2(0, 720), 28, NEON_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("CHEEK SPITS THEM AT BADDIES", Vector2(0, 760), 28, NEON_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("ON YOUR DIAGONALS", Vector2(0, 800), 28, NEON_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("TAP TO START", Vector2(0, 1000), 52, Color(1, 1, 1, 0.4 + 0.6 * pulse), HORIZONTAL_ALIGNMENT_CENTER, W)
	text("KEYS: Q E Z C", Vector2(0, 1060), 22, Color(1, 1, 1, 0.5), HORIZONTAL_ALIGNMENT_CENTER, W)

func draw_over() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(0.02, 0, 0.06, 0.7))
	text("GAME OVER", Vector2(0, 460), 100, NEON_PINK, HORIZONTAL_ALIGNMENT_CENTER, W)
	text("SCORE %d" % score, Vector2(0, 560), 56, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, W)
	if score >= hi and score > 0:
		text("NEW HIGH SCORE!", Vector2(0, 630), 40, NEON_YELLOW, HORIZONTAL_ALIGNMENT_CENTER, W)
	if over_t > 0.9:
		var pulse := 0.5 + 0.5 * sin(time * 3.0)
		text("TAP TO PLAY AGAIN", Vector2(0, 800), 44, Color(1, 1, 1, 0.4 + 0.6 * pulse), HORIZONTAL_ALIGNMENT_CENTER, W)
