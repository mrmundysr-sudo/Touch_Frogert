extends RefCounted
## All Touch Frogert artwork is drawn in code (original, vector-style) -- no external assets.
## Face: 0 UP, 1 DOWN, 2 LEFT, 3 RIGHT (matches Sim.Face).

const C_FROG := Color("3ddc4b")
const C_FROG_D := Color("1f8f33")
const C_BELLY := Color("c8f7a0")
const C_OUT := Color("0d3d1a")
const C_PAD := Color("39b54a")
const C_PAD_D := Color("1f7a31")
const C_STONE := Color("8d8aa8")
const C_STONE_L := Color("b9b6d3")
const C_STONE_D := Color("56536f")
const C_WATER := Color("1457a8")
const C_WATER_D := Color("0b2f66")
const C_WATER_L := Color("3b8fe0")

static func ell(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, seg := 20) -> void:
	var pts := PackedVector2Array()
	for i in seg:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_colored_polygon(pts, col)

static func ell_line(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, w := 2.0, seg := 20) -> void:
	var pts := PackedVector2Array()
	for i in seg + 1:
		var a := TAU * i / seg
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	ci.draw_polyline(pts, col, w)

static func fuse_tint(stage: int, age: float, t1: float, t2: float, t3: float, time: float) -> Color:
	# green -> yellow -> orange -> red, flashing brighter in the last second
	var base := C_FROG
	if stage == 1:
		base = C_FROG.lerp(Color("d9e83a"), clampf(age / t1, 0.0, 1.0) * 0.8)
	elif stage == 2:
		base = Color("e8c23a").lerp(Color("ff8a1f"), clampf((age - t1) / (t2 - t1), 0.0, 1.0))
	elif stage == 3:
		base = Color("ff5a1f").lerp(Color("ff1010"), clampf((age - t2) / (t3 - t2), 0.0, 1.0))
		if age > t3 - 1.0 and int(time * 12.0) % 2 == 0:
			base = Color("ffffff").lerp(base, 0.35)
	return base

## u = half body size in pixels. tint = body colour. puff 0..1 cheeks. tongue: tip offset in px or null.
static func draw_frog(ci: CanvasItem, p: Vector2, u: float, face: int, tint: Color, puff: float, tongue: Variant, squash: float, time: float, dead: bool = false) -> void:
	var sx := 1.0 + squash * 0.12
	var sy := 1.0 - squash * 0.12
	var d := Vector2.ZERO
	match face:
		0: d = Vector2(0, -1)
		1: d = Vector2(0, 1)
		2: d = Vector2(-1, 0)
		3: d = Vector2(1, 0)
	var side := face >= 2
	var dark := tint.darkened(0.35)
	# back legs
	if side:
		ell(ci, p + Vector2(-d.x * 0.35 * u, 0.45 * u), 0.55 * u * sx, 0.3 * u * sy, dark)
	else:
		ell(ci, p + Vector2(-0.75 * u, 0.35 * u), 0.3 * u, 0.5 * u, dark)
		ell(ci, p + Vector2(0.75 * u, 0.35 * u), 0.3 * u, 0.5 * u, dark)
	# body
	var brx := (0.95 if side else 0.78) * u * sx
	var bry := (0.62 if side else 0.7) * u * sy
	ell(ci, p, brx + 2.0, bry + 2.0, C_OUT)
	ell(ci, p, brx, bry, tint)
	if face == 1:
		ell(ci, p + Vector2(0, 0.12 * u), 0.5 * u, 0.42 * u, C_BELLY.lerp(tint, 0.25))
	elif face == 0:
		for sp in [Vector2(-0.3, 0.1), Vector2(0.28, 0.25), Vector2(0.0, -0.1)]:
			ell(ci, p + sp * u, 0.12 * u, 0.1 * u, dark, 8)
	# cheeks (inflated when holding a fly)
	var cheek_r := (0.16 + 0.34 * puff) * u
	var cheek_c: Array = []
	match face:
		0, 1: cheek_c = [Vector2(-0.62 * u, d.y * 0.42 * u), Vector2(0.62 * u, d.y * 0.42 * u)]
		_: cheek_c = [Vector2(d.x * 0.5 * u, 0.18 * u), Vector2(d.x * 0.15 * u, 0.28 * u)]
	if puff > 0.0:
		for c in cheek_c:
			ell(ci, p + c, cheek_r + 2.0, cheek_r + 2.0, C_OUT, 14)
			ell(ci, p + c, cheek_r, cheek_r, tint.lightened(0.18), 14)
			ell(ci, p + c + Vector2(-cheek_r * 0.3, -cheek_r * 0.3), cheek_r * 0.3, cheek_r * 0.25, Color(1, 1, 1, 0.45), 8)
	# eyes
	var eye_r := 0.26 * u
	var eyes: Array = []
	match face:
		0: eyes = [Vector2(-0.42 * u, -0.5 * u), Vector2(0.42 * u, -0.5 * u)]
		1: eyes = [Vector2(-0.42 * u, -0.5 * u), Vector2(0.42 * u, -0.5 * u)]
		_: eyes = [Vector2(d.x * 0.38 * u, -0.5 * u), Vector2(-d.x * 0.1 * u, -0.55 * u)]
	for e in eyes:
		ell(ci, p + e, eye_r + 2.0, eye_r + 2.0, C_OUT, 14)
		ell(ci, p + e, eye_r, eye_r, Color.WHITE, 14)
		var pup := Vector2(d.x * 0.1 * u, d.y * 0.12 * u)
		if dead:
			ci.draw_line(p + e - Vector2(5, 5), p + e + Vector2(5, 5), C_OUT, 3.0)
			ci.draw_line(p + e - Vector2(5, -5), p + e + Vector2(5, -5), C_OUT, 3.0)
		else:
			ell(ci, p + e + pup, eye_r * 0.5, eye_r * 0.5, C_OUT, 10)
	# MOUTH -- always on the facing side so the firing direction is unmistakable
	var mc := p + d * 0.78 * u
	if side:
		mc = p + Vector2(d.x * 0.92 * u, 0.12 * u)
	var open := 0.0
	if tongue != null:
		open = 1.0
	if side:
		var w := 0.34 * u
		ci.draw_colored_polygon(PackedVector2Array([mc, mc + Vector2(-d.x * w, -0.1 * u - open * 0.1 * u), mc + Vector2(-d.x * w, 0.18 * u + open * 0.14 * u)]), Color("5a0f1c"))
		ci.draw_line(mc + Vector2(-d.x * 0.45 * u, 0.02 * u), mc + Vector2(-d.x * 0.02 * u, 0.02 * u), C_OUT, 2.5)
	elif face == 0:
		ci.draw_colored_polygon(PackedVector2Array([mc + Vector2(-0.3 * u, 0.08 * u), mc + Vector2(0.3 * u, 0.08 * u), mc + Vector2(0, -0.14 * u - open * 0.1 * u)]), Color("5a0f1c"))
		ci.draw_line(mc + Vector2(-0.45 * u, 0.1 * u), mc + Vector2(0.45 * u, 0.1 * u), C_OUT, 2.5)
	else:
		var mm := p + Vector2(0, 0.33 * u)
		ci.draw_arc(mm, 0.38 * u, 0.15, PI - 0.15, 14, C_OUT, 3.0)
		if open > 0.0:
			ell(ci, mm + Vector2(0, 0.05 * u), 0.24 * u, 0.16 * u, Color("5a0f1c"), 10)
	# tongue
	if tongue != null:
		var tip: Vector2 = p + (tongue as Vector2)
		ci.draw_line(mc, tip, Color("ff6f91"), 5.0)
		ell(ci, tip, 6.0, 6.0, Color("ff3d71"), 10)

static func draw_fly(ci: CanvasItem, p: Vector2, u: float, state: int, prog: float, time: float, seed_: float) -> void:
	# state: 1 = emerging (translucent, growing), 2 = fully formed (dangerous: glowing red eyes)
	var sc := 1.0
	var a := 1.0
	if state == 1:
		sc = 0.25 + 0.55 * prog
		a = 0.35 + 0.4 * prog
	var flap := sin(time * 40.0 + seed_) * 0.35 + 0.65
	var wing := Color(0.85, 0.95, 1.0, 0.65 * a)
	ell(ci, p + Vector2(-0.45, -0.25) * u * sc, 0.45 * u * sc, 0.22 * u * sc * flap, wing, 10)
	ell(ci, p + Vector2(0.45, -0.25) * u * sc, 0.45 * u * sc, 0.22 * u * sc * flap, wing, 10)
	ell(ci, p + Vector2(0, 0.05) * u * sc, 0.28 * u * sc, 0.36 * u * sc, Color(0.12, 0.1, 0.16, a), 12)
	var eye := Color(1.0, 0.1, 0.1, a) if state == 2 else Color(0.8, 0.8, 0.3, a)
	for sgn in [-1.0, 1.0]:
		ell(ci, p + Vector2(sgn * 0.14, -0.2) * u * sc, 0.1 * u * sc, 0.1 * u * sc, eye, 8)
	if state == 2:
		var pulse := 0.5 + 0.5 * sin(time * 9.0)
		ell_line(ci, p, 0.85 * u + pulse * 0.1 * u, 0.85 * u + pulse * 0.1 * u, Color(1, 0.2, 0.2, 0.35 + 0.3 * pulse), 2.0, 20)

static func draw_pad(ci: CanvasItem, p: Vector2, u: float, k: int, alpha: float, wobble: float, time: float, sink: bool, sunk: float) -> void:
	var off := Vector2(sin(time * 30.0) * wobble * 3.0, 0.0)
	var c := p + off
	var sc := 1.0 - sunk * 0.2
	var col := C_PAD if not sink else Color("2fa26b")
	col.a = alpha
	var dk := C_PAD_D
	dk.a = alpha
	ell(ci, c + Vector2(0, 3), 0.98 * u * sc, 0.62 * u * sc, Color(0, 0, 0, 0.25 * alpha), 20)
	ell(ci, c, 0.95 * u * sc, 0.6 * u * sc, dk, 22)
	ell(ci, c + Vector2(0, -1.5), 0.88 * u * sc, 0.54 * u * sc, col, 22)
	# notch wedge (water colour) gives the lily-pad silhouette
	var ang := float((k * 37) % 6) * 1.0472
	var nw := PackedVector2Array([c, c + Vector2(cos(ang - 0.18), sin(ang - 0.18) * 0.62) * u * 1.0, c + Vector2(cos(ang + 0.18), sin(ang + 0.18) * 0.62) * u * 1.0])
	ci.draw_colored_polygon(nw, Color(C_WATER.r, C_WATER.g, C_WATER.b, alpha * 0.9))
	ci.draw_arc(c, 0.45 * u * sc, ang + 0.4, ang + TAU - 0.4, 14, Color(1, 1, 1, 0.18 * alpha), 2.0)
	if k % 5 == 0 and not sink:
		ell(ci, c + Vector2(0.3, -0.1) * u, 0.16 * u, 0.12 * u, Color(1, 0.6, 0.85, alpha), 8)
	if sink:
		for i in 3:
			ell(ci, c + Vector2((i - 1) * 0.3 * u, -0.12 * u), 0.07 * u, 0.05 * u, Color(1, 1, 1, 0.5 * alpha), 6)
	if wobble > 0.0:
		ell_line(ci, c, (0.95 + wobble * 0.3) * u, (0.6 + wobble * 0.2) * u, Color(1, 0.9, 0.3, 0.6 * alpha), 2.0, 20)

static func draw_stone(ci: CanvasItem, p: Vector2, u: float, alpha: float) -> void:
	var r := Rect2(p - Vector2(0.88 * u, 0.62 * u), Vector2(1.76 * u, 1.24 * u))
	ci.draw_rect(Rect2(r.position + Vector2(0, 4), r.size), Color(0, 0, 0, 0.3 * alpha))
	var d := C_STONE_D; d.a = alpha
	var m := C_STONE; m.a = alpha
	var l := C_STONE_L; l.a = alpha
	ci.draw_rect(r, d)
	ci.draw_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 6)), m)
	ci.draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 6)), l)
	ci.draw_line(p + Vector2(-0.3, -0.3) * u, p + Vector2(0.0, 0.1) * u, d, 2.0)
	ci.draw_line(p + Vector2(0.0, 0.1) * u, p + Vector2(0.3, 0.4) * u, d, 2.0)

static func draw_miss(ci: CanvasItem, p: Vector2, u: float, time: float, hop: float = 0.0) -> void:
	var q := p + Vector2(0, -abs(sin(time * 3.0)) * u * 0.25 - hop)
	draw_frog(ci, q, u, 1, Color("ff8fc8"), 0.0, null, 0.0, time)
	# bow, lashes, blush
	ell(ci, q + Vector2(-0.18 * u, -0.88 * u), 0.2 * u, 0.13 * u, Color("ff3d9a"), 8)
	ell(ci, q + Vector2(0.18 * u, -0.88 * u), 0.2 * u, 0.13 * u, Color("ff3d9a"), 8)
	ell(ci, q + Vector2(0, -0.88 * u), 0.08 * u, 0.08 * u, Color("c2185b"), 6)
	for sgn in [-1.0, 1.0]:
		ci.draw_line(q + Vector2(sgn * 0.5 * u, -0.7 * u), q + Vector2(sgn * 0.72 * u, -0.82 * u), C_OUT, 2.0)
		ell(ci, q + Vector2(sgn * 0.5 * u, -0.1 * u), 0.14 * u, 0.09 * u, Color(1, 0.4, 0.5, 0.6), 8)
	# floating heart
	var hy := -u * 1.3 - fmod(time * 20.0, 22.0)
	ell(ci, q + Vector2(-0.08 * u, hy / u * u), 0.1 * u, 0.1 * u, Color("ff3d71"), 8)
	ell(ci, q + Vector2(0.08 * u, hy / u * u), 0.1 * u, 0.1 * u, Color("ff3d71"), 8)
