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
var caption := ""
var caption_dir := Vector2i.ZERO
var show_labels := false        # dev/demo: show row direction + "carried" labels
var W := 70.0                   # cube width in px
var Hs := 43.0                  # cube side height
var P := 60.0                   # row pitch (top-face centre to next row's top-face centre)
var y_top := 300.0              # screen y of row 0's top-face centre
var cx := 360.0
var vsize := Vector2(720, 1280)
var font: Font
var row_ctls: Array = []
var overlay: Node2D
var built_rows := -1

class RowCtl extends Control:
	var gv
	var r := 0
	func _draw() -> void:
		gv.draw_row(self, r)

class Overlay extends Node2D:
	var gv
	func _draw() -> void:
		gv.draw_overlay(self)

func _ready() -> void:
	font = ThemeDB.fallback_font
	overlay = Overlay.new()
	overlay.gv = self

func _ensure_rows() -> void:
	if built_rows == sim.board.n:
		return
	for c in row_ctls:
		c.queue_free()
	row_ctls.clear()
	if overlay.get_parent() != null:
		remove_child(overlay)
	for r in sim.board.n:
		var c := RowCtl.new()
		c.gv = self
		c.r = r
		c.clip_contents = true
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(c)
		row_ctls.append(c)
	add_child(overlay)
	built_rows = sim.board.n

func layout() -> void:
	vsize = get_viewport_rect().size
	var n: int = sim.board.n
	W = minf(vsize.x * 0.94 / float(n + 2), 96.0)
	Hs = W * 0.78
	P = W * 0.25 + Hs
	var total := float(n - 1) * P + W * 0.5 + Hs
	var above := W * 1.05
	y_top = 150.0 + above + maxf(0.0, (vsize.y - 150.0 - above - 260.0 - total) * 0.35)
	cx = vsize.x * 0.5
	_ensure_rows()
	for r in n:
		var c: Control = row_ctls[r]
		var w := float(sim.board.w[r])
		var top := y_top + r * P - W * 0.25 - above
		var bottom := y_top + r * P + W * 0.25 + Hs + 2.0
		c.position = Vector2(cx - w * W * 0.5, top)
		c.size = Vector2(w * W, bottom - top)

func spos(row_f: float, wx: float) -> Vector2:
	return Vector2(cx + wx * W, y_top + row_f * P)

## centre of the top face of slot k in row r (moves with the conveyor)
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

func body_pos() -> Vector2:
	var fv: Array = sim.frog_view()
	return spos(fv[0], fv[1]) + Vector2(0, -W * 0.3 - float(fv[2]) * Hs * 0.9)

func on_event(ev: Array) -> void:
	var fp := body_pos()
	match ev[0]:
		"land": burst(fp + Vector2(0, W * 0.3), Color(0.8, 0.95, 1.0, 0.8), 5, 90.0, 0.35)
		"catch": burst(fp, Color("ffe14d"), 12, 200.0); flash = 0.15; flash_col = Color(1, 1, 0.6)
		"shoot": burst(fp, Color("ff9d00"), 10, 260.0, 0.4)
		"barrier_down": burst(slot_screen(ev[1], ev[2]) + Vector2(0, -W * 0.3), Color("b9b6d3"), 18, 280.0, 0.7); shake = 0.25
		"fly_zap": burst(slot_screen(ev[1], ev[2]) + Vector2(0, -W * 0.4), Color("ff3d71"), 14, 240.0)
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
	if sim != null and sim.board != null:
		layout()
		position = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake * 14.0 if shake > 0.0 else Vector2.ZERO
		for c in row_ctls:
			c.queue_redraw()
		overlay.queue_redraw()
	queue_redraw()

# ------------------------------------------------------------------ drawing: backdrop (this node)

func _draw() -> void:
	vsize = get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vsize), Color("07142e"))
	for i in 12:
		var y := vsize.y * float(i) / 12.0
		draw_rect(Rect2(0, y, vsize.x, vsize.y / 12.0 + 1.0), Color(0.03 + 0.012 * i, 0.07 + 0.012 * i, 0.16 + 0.015 * i, 1.0))
	for i in 26:
		var sx := fposmod(float(i * 97) + time * (3.0 + (i % 5)), vsize.x)
		var sy := fposmod(float(i * 211), vsize.y)
		draw_circle(Vector2(sx, sy), 1.4 + (i % 3) * 0.6, Color(1, 1, 1, 0.07 + 0.03 * (i % 4)))

# ------------------------------------------------------------------ drawing: one row of cubes (clipped to the pyramid)

func _palette(r: int, kind: String) -> Array:
	var n: int = sim.board.n
	var lift := 0.07 * (1.0 - float(r) / float(n - 1))      # higher rows a touch lighter
	match kind:
		"summit": return [Color("ffd75a"), Color("a9741a"), Color("d19a2c")]
		"start": return [Color("5fb04a"), Color("2e6a2c"), Color("3f8a38")]
		"river": return [Color(0.38 + lift, 0.64 + lift, 0.7 + lift), Color("1d3f52"), Color("2d5c70")]
		_: return [Color(0.4 + lift, 0.76 + lift, 0.34 + lift), Color("22592a"), Color("30803a")]

func draw_row(ci: Control, r: int) -> void:
	var b := sim.board
	var w := float(b.w[r])
	var is_start := r == b.n - 1
	var is_top := r == 0
	var kind: String = "start" if is_start else ("summit" if is_top else String(sim.level["rows"][r].get("kind", "ground")))
	var pal := _palette(r, kind)
	var raw := b.raw(r, sim.t)
	var org := ci.position
	var order: Array = []
	for k in int(b.L[r]):
		var xl := fposmod(float(k) + 0.5 + raw, float(b.L[r]))
		if xl < -0.6 or xl > w + 0.6:
			continue
		order.append([xl, k])
	order.sort_custom(func(a, c): return a[0] < c[0])
	var dir := signf(b.speed[r])
	for o in order:
		var xl2: float = o[0]
		var k2: int = o[1]
		var c := Vector2(xl2 * W, y_top + r * P - org.y)
		var base: int = b.slots[r][k2]
		var cont := b.content(r, k2, sim.t)
		var shade := 1.0 if (k2 % 2 == 0) else 0.94
		var top_c: Color = (pal[0] as Color) * Color(shade, shade, shade, 1.0)
		match base:
			Board.WATER:
				Art.water_pit(ci, c, W, Hs, W * 0.3, time, float(k2), pal[1], pal[2])
			Board.SINK:
				if cont == Board.WATER:
					Art.water_pit(ci, c, W, Hs, W * 0.3, time, float(k2), pal[1], pal[2])
				else:
					var wob := b.sink_warning(r, k2, sim.t)
					var cc := c + Vector2(0, wob * W * 0.1)
					Art.cube(ci, cc, W, Hs, top_c, pal[1], pal[2])
					Art.pad_on_top(ci, cc, W, k2, wob, time, true)
			Board.BARRIER:
				Art.cube(ci, c, W, Hs, top_c, pal[1], pal[2])
				Art.stone_block(ci, c, W)
			_:
				Art.cube(ci, c, W, Hs, top_c, pal[1], pal[2])
				if kind == "river":
					Art.pad_on_top(ci, c, W, k2, 0.0, time, false)
				elif dir != 0.0:
					# faint chevron on the top face shows the conveyor direction
					var q := c + Vector2(0, -1)
					ci.draw_polyline(PackedVector2Array([q + Vector2(-dir * W * 0.1, -W * 0.07), q + Vector2(dir * W * 0.08, 0), q + Vector2(-dir * W * 0.1, W * 0.07)]), Color(1, 1, 1, 0.22), 2.0)
	# flies travel with their slots
	for fi in b.flies.size():
		var f: Dictionary = b.flies[fi]
		if int(f["r"]) != r:
			continue
		var st := b.fly_state(fi, sim.t)
		if st == Board.NO_FLY:
			continue
		var kk: int = f["k"]
		var xl3 := fposmod(float(kk) + 0.5 + raw, float(b.L[r]))
		if xl3 < -0.6 or xl3 > w + 0.6:
			continue
		var fp := Vector2(xl3 * W, y_top + r * P - org.y - W * 0.42 + sin(time * 6.0 + kk) * 3.0)
		Art.draw_fly(ci, fp, W * 0.5, st, b.fly_progress(fi, sim.t), time, float(kk))
	if show_row_numbers:
		ci.draw_string(font, Vector2(2, y_top + r * P - org.y + 6), "R%d" % (r + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.3))

# ------------------------------------------------------------------ drawing: overlay (frog, effects, HUD)

func draw_overlay(ci: Node2D) -> void:
	var p := spos(0.0, 0.0)
	var u := W * 0.52
	if sim.mode == SimC.Mode.WIN:
		Art.draw_miss(ci, p + Vector2(0, -W * 0.3), u, time, sin(sim.mode_t * 12.0) * 4.0)
	else:
		Art.draw_miss(ci, p + Vector2(0, -W * 0.3), u, time)
	_frog(ci)
	_shots(ci)
	for q in parts:
		var col: Color = q[4]
		col.a *= clampf(float(q[2]) / float(q[3]), 0.0, 1.0)
		ci.draw_circle(q[0], float(q[5]), col)
	if flash > 0.0:
		ci.draw_rect(Rect2(Vector2.ZERO, vsize), Color(flash_col.r, flash_col.g, flash_col.b, flash * 0.9))
	_fuse_vignette(ci)
	if show_labels:
		_labels(ci)
	if caption != "":
		_caption(ci)
	_hud(ci)

func _caption(ci: Node2D) -> void:
	var y := vsize.y - 190.0
	_txt(ci, caption, Vector2(0, y), 44, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
	var c := Vector2(vsize.x * 0.5, y - 100.0)
	var d := Vector2(caption_dir)
	if d != Vector2.ZERO:
		var n := Vector2(-d.y, d.x)
		var pts := PackedVector2Array([c + d * 34.0, c - d * 20.0 + n * 30.0, c - d * 20.0 - n * 30.0])
		ci.draw_colored_polygon(pts, Color("ffe14d"))
		ci.draw_line(c - d * 60.0, c - d * 16.0, Color("ffe14d"), 14.0)

func _labels(ci: Node2D) -> void:
	var b := sim.board
	for r in range(1, b.n - 1):
		var v := b.speed[r]
		var left := cx + float(b.w[r]) * W * 0.5 + 8.0
		var txt := ("%s %.1f" % ["-->" if v > 0.0 else "<--", absf(v)])
		ci.draw_string(font, Vector2(left, y_top + r * P + 6), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(1, 0.9, 0.3))
	if sim.mode == SimC.Mode.PLAY and not sim.hopping and sim.frog_r > 0 and sim.frog_r < b.n - 1:
		var v2 := b.speed[sim.frog_r]
		ci.draw_string(font, Vector2(10, vsize.y - 330), "CARRIED %s  (row speed %.2f cubes/s)" % ["RIGHT" if v2 > 0.0 else "LEFT", absf(v2)], HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.4, 1, 0.6))
	var fv: Array = sim.frog_view()
	ci.draw_string(font, Vector2(10, vsize.y - 296), "frog row R%d  x=%.2f" % [sim.frog_r + 1, b.local_x(sim.frog_r, sim.frog_rel, sim.t)], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.8, 0.9, 1))

func _frog(ci: Node2D) -> void:
	var fv: Array = sim.frog_view()
	var row_f: float = fv[0]
	var foot := spos(row_f, fv[1])
	var p := foot + Vector2(0, -W * 0.3 - float(fv[2]) * Hs * 0.9)
	var u := W * 0.44
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
		var tp := slot_screen(sim.tongue_r, sim.tongue_k) + Vector2(0, -W * 0.3)
		var want := tp - p
		if not sim.tongue_hit and want.length() > W * 1.7:
			want = want.normalized() * W * 1.2
		tongue = want * ext
	var squash := 0.0
	if sim.hopping:
		squash = -sin(clampf(sim.hop_t / sim.hop_dur, 0.0, 1.0) * PI)
	if sim.mode == SimC.Mode.DYING:
		_dying_frog(ci, p, u, tint, puff)
		return
	if sim.mode == SimC.Mode.WIN:
		squash = sin(sim.mode_t * 18.0) * 0.8
	# soft shadow on the top face
	Art.ell(ci, foot + Vector2(0, -2), u * 0.8 * (1.0 - float(fv[2]) * 0.35), u * 0.32, Color(0, 0, 0, 0.32))
	if sim.floating:
		Art.ell_line(ci, foot, u * (1.0 + 0.1 * sin(time * 8.0)), u * 0.42, Color(0.8, 0.95, 1.0, 0.8), 3.0)
		Art.ell_line(ci, foot, u * (1.4 + 0.12 * sin(time * 8.0 + 1.0)), u * 0.6, Color(0.8, 0.95, 1.0, 0.4), 2.0)
	Art.draw_frog(ci, p, u, sim.face, tint, puff, tongue, squash, time)
	if sim.carry_age >= 0.0:
		var frac := clampf(sim.carry_age / float(sim.tun["fly_t3"]), 0.0, 1.0)
		var col := Color(0.3, 1.0, 0.3).lerp(Color(1.0, 0.1, 0.1), frac)
		ci.draw_arc(p + Vector2(0, -u * 1.35), u * 0.35, -PI / 2, -PI / 2 + TAU * (1.0 - frac), 18, col, 5.0)
		if sim.floating:
			ci.draw_string(font, p + Vector2(-30, -u * 2.0), "FLOAT", HORIZONTAL_ALIGNMENT_CENTER, 60, 16, Color(0.8, 0.95, 1.0))

func _dying_frog(ci: Node2D, p: Vector2, u: float, tint: Color, puff: float) -> void:
	var s := sim.mode_t / SimC.DEATH_TIME
	match sim.death_cause:
		"pop":
			if s < 0.12:
				Art.draw_frog(ci, p, u * (1.0 + s * 9.0), sim.face, Color("ff1010"), 1.0, null, 0.0, time)
			else:
				ci.draw_arc(p, u * (1.5 + s * 5.0), 0, TAU, 28, Color(1, 0.6, 0.2, 1.0 - s), 6.0)
		"fell":
			var q := p + Vector2(0, s * 300.0)
			Art.draw_frog(ci, q, u * (1.0 - s * 0.7), sim.face, tint.darkened(s * 0.5), puff, null, 0.0, time, true)
		"fly":
			Art.draw_frog(ci, p + Vector2(0, -sin(s * PI) * 40.0), u, sim.face, Color("ff6a6a"), puff, null, 0.0, time, true)
		_:
			var sink := clampf(s * 1.4, 0.0, 1.0)
			var q2 := p + Vector2(0, sink * u * 1.1)
			Art.draw_frog(ci, q2, u * (1.0 - sink * 0.4), sim.face, tint.lerp(Color("1457a8"), sink), puff, null, 0.0, time, true)
			for i in 3:
				Art.ell_line(ci, p + Vector2(0, u * 0.8), u * (0.5 + s * 2.0 + i * 0.4), u * (0.22 + s * 0.6 + i * 0.12), Color(0.8, 0.95, 1.0, (1.0 - s) * 0.6), 2.5)

func _shots(ci: Node2D) -> void:
	var ps := float(sim.tun["proj_speed"])
	for s in sim.shots:
		var targets: Array = s["targets"]
		var pts: Array = [spos(float(s["from_r"]), float(s["from_wx"])) + Vector2(0, -W * 0.3)]
		for tg in targets:
			pts.append(slot_screen(tg[0], tg[1]) + Vector2(0, -W * 0.3))
		var f := (sim.t - float(s["t0"])) * ps
		if f < 0.0 or pts.size() < 2:
			continue
		var idx := int(floor(f))
		if idx >= pts.size() - 1:
			if f < float(pts.size()) + 0.3:
				var endp: Vector2 = pts[pts.size() - 1]
				Art.ell_line(ci, endp, W * 0.3 * (f - pts.size() + 1.4), W * 0.3 * (f - pts.size() + 1.4), Color(1, 0.8, 0.3, 0.8), 3.0)
			continue
		var p: Vector2 = (pts[idx] as Vector2).lerp(pts[idx + 1], f - idx)
		var col: Color = [Color("ffe14d"), Color("ffe14d"), Color("ff9d00"), Color("ff3030")][clampi(int(s["range"]), 0, 3)]
		for i in 4:
			var tp: Vector2 = p - (pts[idx + 1] - pts[idx]).normalized() * (i * W * 0.18)
			ci.draw_circle(tp, W * (0.2 - i * 0.04), Color(col.r, col.g, col.b, 0.8 - i * 0.2))
		ci.draw_circle(p, W * 0.17, Color.WHITE)

func _fuse_vignette(ci: Node2D) -> void:
	if sim.carry_age < 0.0 or sim.mode != SimC.Mode.PLAY:
		return
	var t3 := float(sim.tun["fly_t3"])
	var rem := t3 - sim.carry_age
	if rem < 2.0:
		var a := (1.0 - rem / 2.0) * (0.12 + 0.12 * (0.5 + 0.5 * sin(time * (10.0 + (2.0 - rem) * 8.0))))
		ci.draw_rect(Rect2(0, 0, vsize.x, 30), Color(1, 0, 0, a * 2.0))
		ci.draw_rect(Rect2(0, vsize.y - 30, vsize.x, 30), Color(1, 0, 0, a * 2.0))
		ci.draw_rect(Rect2(0, 0, 30, vsize.y), Color(1, 0, 0, a * 2.0))
		ci.draw_rect(Rect2(vsize.x - 30, 0, 30, vsize.y), Color(1, 0, 0, a * 2.0))

func _txt(ci: Node2D, s: String, p: Vector2, size: int, col: Color, align := HORIZONTAL_ALIGNMENT_LEFT, w := -1.0) -> void:
	ci.draw_string_outline(font, p, s, align, w, size, 6, Color(0, 0, 0, 0.85))
	ci.draw_string(font, p, s, align, w, size, col)

func _hud(ci: Node2D) -> void:
	var sess: Dictionary = sim.session
	_txt(ci, "SCORE", Vector2(24, 40), 20, Color("7be8ff"))
	_txt(ci, str(int(sess["score"])), Vector2(24, 76), 34, Color.WHITE)
	_txt(ci, "HI", Vector2(vsize.x * 0.5, 40), 20, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, 0.0)
	_txt(ci, str(maxi(hi_score, int(sess["score"]))), Vector2(vsize.x * 0.5 - 80, 76), 34, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, 160.0)
	_txt(ci, "LEVEL %d" % int(sess["level"]), Vector2(vsize.x - 24 - 150, 40), 22, Color("b6ff00"), HORIZONTAL_ALIGNMENT_RIGHT, 150.0)
	for i in int(sess["lives"]):
		Art.draw_frog(ci, Vector2(vsize.x - 40 - i * 46, 78), 15.0, 1, Art.C_FROG, 0.0, null, 0.0, time)
	# time bar
	var lim := float(sim.tun["time_limit"])
	if lim > 0.0:
		var frac := clampf(sim.time_left() / lim, 0.0, 1.0)
		ci.draw_rect(Rect2(24, 100, vsize.x - 48, 10), Color(0, 0, 0, 0.5))
		ci.draw_rect(Rect2(24, 100, (vsize.x - 48) * frac, 10), Color("39ff14").lerp(Color("ff3030"), 1.0 - frac))
	if demo_label:
		_txt(ci, "DEMO - TOUCH TO PLAY", Vector2(0, vsize.y - 110), 30, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
	match sim.mode:
		SimC.Mode.READY:
			_txt(ci, "GET READY!", Vector2(0, vsize.y * 0.5 + 30), 56, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
			_txt(ci, "LEVEL %d" % int(sess["level"]), Vector2(0, vsize.y * 0.5 + 90), 34, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
		SimC.Mode.WIN:
			_txt(ci, "LEVEL CLEAR!", Vector2(0, vsize.y * 0.5), 60, Color("39ff14"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
		SimC.Mode.DYING:
			var msg := {"fell": "OFF THE EDGE!", "drown": "SPLASH!", "fly": "BUZZ OFF!", "pop": "POP!", "sink": "GLUB GLUB!", "timeout": "TIME'S UP!"}
			_txt(ci, msg.get(sim.death_cause, "OOPS!"), Vector2(0, vsize.y * 0.5), 52, Color("ff6a6a"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
		SimC.Mode.OVER:
			_txt(ci, "GAME OVER", Vector2(0, vsize.y * 0.5), 64, Color("ff3030"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
	if banner_t > 0.0:
		_txt(ci, banner, Vector2(0, vsize.y * 0.28), 48, Color("ff3d9a"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
