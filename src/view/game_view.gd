extends Node2D
## Draws a Sim. Pure presentation: never mutates simulation state.
const Art = preload("res://src/view/art.gd")
const Board = preload("res://src/sim/board.gd")
const SimC = preload("res://src/sim/sim.gd")

var sim: SimC
var time := 0.0
var show_row_numbers := false
var hi_score := 0
var parts: Array = []          # [pos, vel, life, max_life, color, size]
var shake := 0.0
var flash := 0.0
var flash_col := Color.WHITE
var banner := ""
var banner_t := 0.0
var demo_label := false
var cs := 70.0
var row_h := 90.0
var y_top := 200.0
var cx := 360.0
var vsize := Vector2(720, 1280)
var font: Font

func _ready() -> void:
	font = ThemeDB.fallback_font

func layout() -> void:
	vsize = get_viewport_rect().size
	var n: int = sim.board.n
	cs = minf(vsize.x * 0.94 / float(n + 2), 92.0)
	row_h = minf(cs * 1.32, (vsize.y - 360.0) / float(n))
	y_top = (vsize.y - row_h * n) * 0.46 + 20.0
	cx = vsize.x * 0.5

func row_y(row_f: float) -> float:
	return y_top + (row_f + 0.5) * row_h

func spos(row_f: float, wx: float) -> Vector2:
	return Vector2(cx + wx * cs, row_y(row_f))

func slot_screen(r: int, k: int) -> Vector2:
	var b := sim.board
	var xl := fposmod(float(k) + 0.5 + b.raw(r, sim.t), float(b.L[r]))
	return spos(float(r), xl - float(b.w[r]) * 0.5)

# ------------------------------------------------------------------ events -> particles

func burst(p: Vector2, col: Color, n: int = 14, speed: float = 220.0, life: float = 0.6) -> void:
	for i in n:
		var a := randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * randf_range(0.3, 1.0)
		parts.append([p, v, life * randf_range(0.6, 1.0), life, col, randf_range(3.0, 7.0)])
	if parts.size() > 220:
		parts = parts.slice(parts.size() - 220)

func on_event(ev: Array) -> void:
	var fv: Array = sim.frog_view()
	var fp := spos(fv[0], fv[1])
	match ev[0]:
		"land": burst(fp + Vector2(0, 10), Color(0.7, 0.9, 1.0, 0.8), 5, 90.0, 0.35)
		"catch": burst(fp, Color("ffe14d"), 12, 200.0); flash = 0.15; flash_col = Color(1, 1, 0.6)
		"shoot": burst(fp, Color("ff9d00"), 10, 260.0, 0.4)
		"barrier_down": burst(slot_screen(ev[1], ev[2]), Color("b9b6d3"), 18, 280.0, 0.7); shake = 0.25
		"fly_zap": burst(slot_screen(ev[1], ev[2]), Color("ff3d71"), 14, 240.0)
		"die":
			shake = 0.5
			flash = 0.35
			flash_col = Color(1, 0.2, 0.2)
			if ev[1] == "pop":
				burst(fp, Color("ff2a2a"), 40, 520.0, 1.0)
				burst(fp, Color("ffd24d"), 24, 380.0, 0.9)
			elif ev[1] == "drown" or ev[1] == "sink":
				burst(fp, Color(0.6, 0.85, 1.0), 26, 280.0, 0.9)
		"win": burst(fp, Color("ffe14d"), 40, 420.0, 1.1); burst(fp, Color("ff3d9a"), 30, 360.0, 1.1)
		"extra_life": banner = "EXTRA LIFE!"; banner_t = 1.4
		"go": banner = "GO!"; banner_t = 0.6

func update(dt: float) -> void:
	time += dt
	shake = maxf(0.0, shake - dt)
	flash = maxf(0.0, flash - dt)
	banner_t = maxf(0.0, banner_t - dt)
	var i := parts.size() - 1
	while i >= 0:
		var p: Array = parts[i]
		p[2] = float(p[2]) - dt
		if float(p[2]) <= 0.0:
			parts.remove_at(i)
		else:
			p[0] = (p[0] as Vector2) + (p[1] as Vector2) * dt
			p[1] = (p[1] as Vector2) * 0.96 + Vector2(0, 260.0 * dt)
		i -= 1
	queue_redraw()

# ------------------------------------------------------------------ drawing

func _draw() -> void:
	if sim == null or sim.board == null:
		return
	layout()
	var off := Vector2.ZERO
	if shake > 0.0:
		off = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 14.0
	draw_set_transform(off, 0.0, Vector2.ONE)
	_backdrop()
	var b := sim.board
	for r in b.n:
		_row(r)
	_miss_and_goal()
	_flies_and_items_overlay()
	_frog()
	_shots()
	for p in parts:
		var col: Color = p[4]
		col.a *= clampf(float(p[2]) / float(p[3]), 0.0, 1.0)
		draw_circle(p[0], float(p[5]), col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	if flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, vsize), Color(flash_col.r, flash_col.g, flash_col.b, flash * 0.9))
	_fuse_vignette()
	_hud()

func _backdrop() -> void:
	draw_rect(Rect2(Vector2.ZERO, vsize), Color("07142e"))
	for i in 12:
		var y := vsize.y * float(i) / 12.0
		draw_rect(Rect2(0, y, vsize.x, vsize.y / 12.0 + 1.0), Color(0.03 + 0.012 * i, 0.07 + 0.012 * i, 0.16 + 0.015 * i, 1.0))
	for i in 26:
		var sx := fposmod(float(i * 97) + time * (3.0 + (i % 5)), vsize.x)
		var sy := fposmod(float(i * 211), vsize.y)
		draw_circle(Vector2(sx, sy), 1.4 + (i % 3) * 0.6, Color(1, 1, 1, 0.07 + 0.03 * (i % 4)))

func _row(r: int) -> void:
	var b := sim.board
	var w := float(b.w[r])
	var y0 := y_top + r * row_h
	var left := cx - w * cs * 0.5
	var width := w * cs
	var is_start := r == b.n - 1
	var is_top := r == 0
	var band := Rect2(left, y0 + 2.0, width, row_h - 4.0)
	if is_start:
		draw_rect(Rect2(band.position - Vector2(6, 0), band.size + Vector2(12, 8)), Color("2a1a0a"))
		draw_rect(band, Color("3f7d2a"))
		for i in int(w * 2):
			draw_rect(Rect2(left + i * cs * 0.5, y0 + row_h * 0.6, cs * 0.25, row_h * 0.3), Color(0.25, 0.55, 0.2))
		return
	if is_top:
		draw_rect(Rect2(band.position - Vector2(6, 0), band.size + Vector2(12, 6)), Color("5a3b08"))
		draw_rect(band, Color("e8b83a"))
		draw_rect(Rect2(band.position, Vector2(band.size.x, 6)), Color("ffe58a"))
		return
	var shade := 0.0 if r % 2 == 0 else 0.05
	draw_rect(Rect2(band.position - Vector2(5, 0), band.size + Vector2(10, 6)), Color("041022"))
	draw_rect(band, Color(0.06 + shade, 0.26 + shade, 0.58 + shade))
	# drifting ripple lines show the current direction
	var raw := b.raw(r, sim.t)
	var spacing := 1.7
	for i in int(w / spacing) + 3:
		var xl := fposmod(float(i) * spacing + raw, w + spacing * 2.0) - spacing
		if xl < 0.0 or xl > w:
			continue
		var p := Vector2(left + xl * cs, y0 + row_h * (0.25 + 0.5 * float((i * 7) % 3) / 3.0))
		draw_line(p, p + Vector2(cs * 0.35 * signf(b.speed[r] if b.speed[r] != 0.0 else 1.0), 0), Color(0.45, 0.75, 1.0, 0.28), 2.0)
	# slots
	for k in int(b.L[r]):
		var xl2 := fposmod(float(k) + 0.5 + raw, float(b.L[r]))
		var over := maxf(maxf(-xl2, xl2 - w), 0.0)
		if over > 0.55:
			continue
		var alpha := clampf(1.0 - over / 0.55, 0.0, 1.0)
		var p2 := Vector2(left + xl2 * cs, y0 + row_h * 0.5)
		var base: int = b.slots[r][k]
		var u := cs * 0.5
		match base:
			Board.PAD:
				Art.draw_pad(self, p2, u, k, alpha, 0.0, time, false, 0.0)
			Board.SINK:
				var wob := b.sink_warning(r, k, sim.t)
				var down := b.content(r, k, sim.t) == Board.WATER
				if not down:
					Art.draw_pad(self, p2, u, k, alpha, wob, time, true, wob * 0.5)
				else:
					Art.ell_line(self, p2, u * 0.8, u * 0.45, Color(1, 1, 1, 0.3 * alpha), 2.0)
			Board.BARRIER:
				Art.draw_pad(self, p2, u, k, alpha * 0.7, 0.0, time, false, 0.0)
				Art.draw_stone(self, p2 + Vector2(0, -3), u, alpha)
	if show_row_numbers:
		draw_string(font, Vector2(left - 40, y0 + row_h * 0.62), "R%d" % (r + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 1, 0.3))

func _miss_and_goal() -> void:
	var p := spos(0.0, 0.0)
	var u := cs * 0.52
	if sim.mode == SimC.Mode.WIN:
		Art.draw_miss(self, p + Vector2(0, -4), u, time, sin(sim.mode_t * 12.0) * 4.0)
	else:
		Art.draw_miss(self, p + Vector2(0, -4), u, time)

func _flies_and_items_overlay() -> void:
	var b := sim.board
	for fi in b.flies.size():
		var f: Dictionary = b.flies[fi]
		var st := b.fly_state(fi, sim.t)
		if st == Board.NO_FLY:
			continue
		var r: int = f["r"]
		var k: int = f["k"]
		var xl := fposmod(float(k) + 0.5 + b.raw(r, sim.t), float(b.L[r]))
		if xl < -0.3 or xl > float(b.w[r]) + 0.3:
			continue
		var p := spos(float(r), xl - float(b.w[r]) * 0.5)
		Art.draw_fly(self, p + Vector2(0, -cs * 0.18 + sin(time * 6.0 + k) * 3.0), cs * 0.5, st, b.fly_progress(fi, sim.t), time, float(k))

func _frog() -> void:
	var fv: Array = sim.frog_view()
	var row_f: float = fv[0]
	var p := spos(row_f, fv[1]) + Vector2(0, -float(fv[2]) * row_h * 0.55)
	var u := cs * 0.46
	var stage := sim.stage()
	var tint := Art.C_FROG
	var puff := 0.0
	if sim.carry_age >= 0.0:
		tint = Art.fuse_tint(stage, sim.carry_age, float(sim.tun["fly_t1"]), float(sim.tun["fly_t2"]), float(sim.tun["fly_t3"]), time)
		puff = clampf(0.35 + 0.65 * sim.carry_age / float(sim.tun["fly_t3"]), 0.0, 1.0)
		if sim.carry_age > float(sim.tun["fly_t3"]) - 1.0:
			p += Vector2(randf_range(-2, 2), randf_range(-2, 2))
		if sim.carry_age > float(sim.tun["fly_t2"]):
			puff *= 1.0 + 0.08 * sin(time * 30.0)
	var tongue: Variant = null
	if sim.tongue_t > 0.0:
		var tt := 1.0 - sim.tongue_t / 0.26
		var ext := sin(clampf(tt, 0.0, 1.0) * PI)
		var tp := slot_screen(sim.tongue_r, sim.tongue_k)
		var want := tp - p
		if not sim.tongue_hit and want.length() > cs * 1.6:
			want = want.normalized() * cs * 1.2
		tongue = want * ext
	var squash := 0.0
	if sim.hopping:
		squash = -sin(clampf(sim.hop_t / sim.hop_dur, 0.0, 1.0) * PI)
	if sim.mode == SimC.Mode.DYING:
		_dying_frog(p, u, tint, puff)
		return
	if sim.mode == SimC.Mode.WIN:
		squash = sin(sim.mode_t * 18.0) * 0.8
	# shadow
	Art.ell(self, spos(row_f, fv[1]) + Vector2(0, cs * 0.22), u * 0.9 * (1.0 - float(fv[2]) * 0.3), u * 0.35, Color(0, 0, 0, 0.3))
	if sim.floating:
		Art.ell_line(self, spos(row_f, fv[1]) + Vector2(0, cs * 0.2), u * (1.1 + 0.1 * sin(time * 8.0)), u * 0.5, Color(0.8, 0.95, 1.0, 0.8), 3.0)
		Art.ell_line(self, spos(row_f, fv[1]) + Vector2(0, cs * 0.2), u * (1.5 + 0.12 * sin(time * 8.0 + 1.0)), u * 0.7, Color(0.8, 0.95, 1.0, 0.4), 2.0)
	Art.draw_frog(self, p, u, sim.face, tint, puff, tongue, squash, time)
	# fuse ring
	if sim.carry_age >= 0.0:
		var frac := clampf(sim.carry_age / float(sim.tun["fly_t3"]), 0.0, 1.0)
		var col := Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.1, 0.1), frac)
		draw_arc(p + Vector2(0, -u * 1.25), u * 0.35, -PI / 2, -PI / 2 + TAU * (1.0 - frac), 18, col, 5.0)
		if sim.floating:
			draw_string(font, p + Vector2(-30, -u * 2.0), "FLOAT", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color(0.8, 0.95, 1.0))

func _dying_frog(p: Vector2, u: float, tint: Color, puff: float) -> void:
	var s := sim.mode_t / SimC.DEATH_TIME
	match sim.death_cause:
		"pop":
			if s < 0.12:
				Art.draw_frog(self, p, u * (1.0 + s * 9.0), sim.face, Color("ff1010"), 1.0, null, 0.0, time)
			else:
				draw_arc(p, u * (1.5 + s * 5.0), 0, TAU, 28, Color(1, 0.6, 0.2, 1.0 - s), 6.0)
		"fell":
			var q := p + Vector2(0, s * 260.0)
			Art.draw_frog(self, q, u * (1.0 - s * 0.7), sim.face, tint.darkened(s * 0.5), puff, null, 0.0, time, true)
		"fly":
			Art.draw_frog(self, p + Vector2(0, -sin(s * PI) * 40.0), u, sim.face, Color("ff6a6a"), puff, null, 0.0, time, true)
		_:   # drown / sink / timeout: bob under
			var sink := clampf(s * 1.4, 0.0, 1.0)
			var q2 := p + Vector2(0, sink * u * 0.9)
			Art.draw_frog(self, q2, u * (1.0 - sink * 0.4), sim.face, tint.lerp(Color("1457a8"), sink), puff, null, 0.0, time, true)
			for i in 3:
				Art.ell_line(self, p + Vector2(0, u * 0.6), u * (0.5 + s * 2.0 + i * 0.4), u * (0.25 + s * 0.8 + i * 0.15), Color(0.8, 0.95, 1.0, (1.0 - s) * 0.6), 2.5)

func _shots() -> void:
	var ps := float(sim.tun["proj_speed"])
	for s in sim.shots:
		var targets: Array = s["targets"]
		var pts: Array = [spos(float(s["from_r"]), float(s["from_wx"]))]
		for tg in targets:
			pts.append(slot_screen(tg[0], tg[1]))
		var f := (sim.t - float(s["t0"])) * ps
		if f < 0.0 or pts.size() < 2:
			continue
		var idx := int(floor(f))
		if idx >= pts.size() - 1:
			if f < float(pts.size()) + 0.3:
				var endp: Vector2 = pts[pts.size() - 1]
				Art.ell_line(self, endp, cs * 0.3 * (f - pts.size() + 1.4), cs * 0.3 * (f - pts.size() + 1.4), Color(1, 0.8, 0.3, 0.8), 3.0)
			continue
		var p: Vector2 = (pts[idx] as Vector2).lerp(pts[idx + 1], f - idx)
		var col: Color = [Color("ffe14d"), Color("ffe14d"), Color("ff9d00"), Color("ff3030")][clampi(int(s["range"]), 0, 3)]
		for i in 4:
			var tp: Vector2 = p - (pts[idx + 1] - pts[idx]).normalized() * (i * cs * 0.18)
			draw_circle(tp, cs * (0.2 - i * 0.04), Color(col.r, col.g, col.b, 0.8 - i * 0.2))
		draw_circle(p, cs * 0.17, Color.WHITE)

func _fuse_vignette() -> void:
	if sim.carry_age < 0.0 or sim.mode != SimC.Mode.PLAY:
		return
	var t3 := float(sim.tun["fly_t3"])
	var rem := t3 - sim.carry_age
	if rem < 2.0:
		var a := (1.0 - rem / 2.0) * (0.12 + 0.12 * (0.5 + 0.5 * sin(time * (10.0 + (2.0 - rem) * 8.0))))
		draw_rect(Rect2(0, 0, vsize.x, 30), Color(1, 0, 0, a * 2.0))
		draw_rect(Rect2(0, vsize.y - 30, vsize.x, 30), Color(1, 0, 0, a * 2.0))
		draw_rect(Rect2(0, 0, 30, vsize.y), Color(1, 0, 0, a * 2.0))
		draw_rect(Rect2(vsize.x - 30, 0, 30, vsize.y), Color(1, 0, 0, a * 2.0))

func _txt(s: String, p: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	draw_string_outline(font, p, s, align, w, size, 6, Color(0, 0, 0, 0.85))
	draw_string(font, p, s, align, w, size, col)

func _hud() -> void:
	var sess: Dictionary = sim.session
	_txt("SCORE", Vector2(24, 40), 20, Color("7be8ff"))
	_txt(str(int(sess["score"])), Vector2(24, 76), 34, Color.WHITE)
	_txt("HI", Vector2(vsize.x * 0.5, 40), 20, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_txt(str(maxi(hi_score, int(sess["score"]))), Vector2(vsize.x * 0.5 - 80, 76), 34, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	_txt("LEVEL %d" % int(sess["level"]), Vector2(vsize.x - 24 - 150, 40), 22, Color("b6ff00"), HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
	for i in int(sess["lives"]):
		Art.draw_frog(self, Vector2(vsize.x - 40 - i * 46, 78), 15.0, 1, Art.C_FROG, 0.0, null, 0.0, time)
	# time bar
	var lim := float(sim.tun["time_limit"])
	if lim > 0.0:
		var frac := clampf(sim.time_left() / lim, 0.0, 1.0)
		draw_rect(Rect2(24, 100, vsize.x - 48, 10), Color(0, 0, 0, 0.5))
		draw_rect(Rect2(24, 100, (vsize.x - 48) * frac, 10), Color("39ff14").lerp(Color("ff3030"), 1.0 - frac))
	if demo_label:
		_txt("DEMO - TOUCH TO PLAY", Vector2(0, vsize.y - 110), 30, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
	match sim.mode:
		SimC.Mode.READY:
			_txt("GET READY!", Vector2(0, vsize.y * 0.5 + 30), 56, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
			_txt("LEVEL %d" % int(sess["level"]), Vector2(0, vsize.y * 0.5 + 90), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
		SimC.Mode.WIN:
			_txt("LEVEL CLEAR!", Vector2(0, vsize.y * 0.5), 60, Color("39ff14"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
		SimC.Mode.DYING:
			var msg := {"fell": "OFF THE EDGE!", "drown": "SPLASH!", "fly": "BUZZ OFF!", "pop": "POP!", "sink": "GLUB GLUB!", "timeout": "TIME'S UP!"}
			_txt(msg.get(sim.death_cause, "OOPS!"), Vector2(0, vsize.y * 0.5), 52, Color("ff6a6a"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
		SimC.Mode.OVER:
			_txt("GAME OVER", Vector2(0, vsize.y * 0.5), 64, Color("ff3030"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
	if banner_t > 0.0:
		_txt(banner, Vector2(0, vsize.y * 0.28), 48, Color("ff3d9a"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
