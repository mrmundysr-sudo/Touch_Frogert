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

## Where the mouth is, relative to the frog's centre, for a facing d = (hx, hy) with hx,hy in {-1,+1}.
static func mouth_offset(d: Vector2, u: float) -> Vector2:
	return Vector2(d.x * 0.78 * u, d.y * 0.34 * u + (0.1 * u if d.y > 0.0 else -0.22 * u))

## Three-quarter-view frog. d = facing diagonal (the hop direction of the last swipe/aim):
##   (+1,-1) up-right = back view looking right     (-1,-1) up-left = back view looking left
##   (+1,+1) down-right = front view looking right  (-1,+1) down-left = front view looking left
## u = half body size in px.  puff 0..1 = cheek inflation.  tongue: tip offset in px or null.
static func draw_frog(ci: CanvasItem, p: Vector2, u: float, d: Vector2, tint: Color, puff: float, tongue: Variant, squash: float, time: float, dead: bool = false) -> void:
	var sx := 1.0 + squash * 0.12
	var sy := 1.0 - squash * 0.12
	var front := d.y > 0.0
	var dark := tint.darkened(0.35)
	# rear legs (tucked behind / beside the body)
	ell(ci, p + Vector2(-d.x * 0.55 * u, 0.5 * u), 0.5 * u, 0.3 * u * sy, dark)
	ell(ci, p + Vector2(d.x * 0.1 * u, 0.58 * u), 0.42 * u, 0.26 * u * sy, dark)
	# body
	var brx := 0.92 * u * sx
	var bry := 0.66 * u * sy
	ell(ci, p, brx + 2.0, bry + 2.0, C_OUT)
	ell(ci, p, brx, bry, tint)
	if front:
		ell(ci, p + Vector2(d.x * 0.18 * u, 0.2 * u), 0.5 * u, 0.36 * u, C_BELLY.lerp(tint, 0.25))
	else:
		for sp in [Vector2(-0.35, 0.05), Vector2(0.25, 0.2), Vector2(-0.05, -0.15)]:
			ell(ci, p + sp * u, 0.11 * u, 0.09 * u, dark, 8)
	# head, shifted toward the facing diagonal
	var hc := p + Vector2(d.x * 0.3 * u, (0.12 if front else -0.18) * u)
	ell(ci, hc, 0.7 * u + 2.0, 0.52 * u + 2.0, C_OUT)
	ell(ci, hc, 0.7 * u, 0.52 * u, tint.lightened(0.04))
	# cheeks
	var cheek_r := (0.15 + 0.34 * puff) * u
	if puff > 0.0:
		for sgn in [-1.0, 1.0]:
			var cc: Vector2 = hc + Vector2(sgn * 0.62 * u, 0.2 * u)
			ell(ci, cc, cheek_r + 2.0, cheek_r + 2.0, C_OUT, 14)
			ell(ci, cc, cheek_r, cheek_r, tint.lightened(0.18), 14)
			ell(ci, cc + Vector2(-cheek_r * 0.3, -cheek_r * 0.3), cheek_r * 0.3, cheek_r * 0.25, Color(1, 1, 1, 0.45), 8)
	# eyes on top of the head
	var er := 0.24 * u
	for sgn in [-1.0, 1.0]:
		var ec: Vector2 = hc + Vector2(sgn * 0.36 * u + d.x * 0.08 * u, -0.42 * u)
		ell(ci, ec, er + 2.0, er + 2.0, C_OUT, 14)
		ell(ci, ec, er, er, Color.WHITE if (front or dead) else tint.lightened(0.25), 14)
		if dead:
			ci.draw_line(ec - Vector2(5, 5), ec + Vector2(5, 5), C_OUT, 3.0)
			ci.draw_line(ec - Vector2(5, -5), ec + Vector2(5, -5), C_OUT, 3.0)
		elif front:
			ell(ci, ec + Vector2(d.x * 0.1 * u, 0.04 * u), er * 0.5, er * 0.5, C_OUT, 10)
		else:
			ell(ci, ec + Vector2(-sgn * 0.05 * u, -0.05 * u), er * 0.32, er * 0.28, Color(1, 1, 1, 0.55), 8)
	# MOUTH / snout: always on the facing side so the firing direction is unmistakable
	var mc := p + mouth_offset(d, u)
	var open := 1.0 if tongue != null else 0.0
	var inside := Vector2(-d.x, 0.0)
	if front:
		# side-on grin ending in an open wedge toward the facing side
		ci.draw_colored_polygon(PackedVector2Array([mc, mc + inside * 0.42 * u + Vector2(0, -0.12 * u - open * 0.1 * u), mc + inside * 0.42 * u + Vector2(0, 0.18 * u + open * 0.14 * u)]), Color("5a0f1c"))
		ci.draw_line(mc + inside * 0.7 * u + Vector2(0, 0.0), mc, C_OUT, 3.0)
	else:
		# seen from behind: a snout poking out toward the facing side with the mouth line on its tip
		ell(ci, mc + Vector2(-d.x * 0.12 * u, 0.0), 0.3 * u, 0.2 * u, tint.lightened(0.1), 12)
		ci.draw_colored_polygon(PackedVector2Array([mc + Vector2(d.x * 0.1 * u, -0.02 * u), mc + Vector2(-d.x * 0.25 * u, -0.1 * u - open * 0.08 * u), mc + Vector2(-d.x * 0.25 * u, 0.12 * u + open * 0.1 * u)]), Color("5a0f1c"))
		ci.draw_arc(mc + Vector2(-d.x * 0.12 * u, 0.0), 0.3 * u, 0.0, TAU, 14, C_OUT, 1.5)
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
	draw_frog(ci, q, u, Vector2(1, 1), Color("ff8fc8"), 0.0, null, 0.0, time)
	# bow, lashes, blush
	var bo := Vector2(-0.3 * u, -0.78 * u)
	ell(ci, q + bo + Vector2(-0.18 * u, 0), 0.2 * u, 0.13 * u, Color("ff3d9a"), 8)
	ell(ci, q + bo + Vector2(0.18 * u, 0), 0.2 * u, 0.13 * u, Color("ff3d9a"), 8)
	ell(ci, q + bo, 0.08 * u, 0.08 * u, Color("c2185b"), 6)
	for sgn in [-1.0, 1.0]:
		ci.draw_line(q + Vector2(sgn * 0.5 * u, -0.7 * u), q + Vector2(sgn * 0.72 * u, -0.82 * u), C_OUT, 2.0)
		ell(ci, q + Vector2(sgn * 0.5 * u, -0.1 * u), 0.14 * u, 0.09 * u, Color(1, 0.4, 0.5, 0.6), 8)
	# floating heart
	var hy := -u * 1.3 - fmod(time * 20.0, 22.0)
	ell(ci, q + Vector2(-0.08 * u, hy / u * u), 0.1 * u, 0.1 * u, Color("ff3d71"), 8)
	ell(ci, q + Vector2(0.08 * u, hy / u * u), 0.1 * u, 0.1 * u, Color("ff3d71"), 8)


# ------------------------------------------------------------------ isometric cubes
## A cube is centred on the middle of its TOP face c; W = cube width, H = side height.
## top rhombus half-width a = W/2, half-height b = W/4 (2:1 isometric), side faces drop by H.
static func cube(ci: CanvasItem, c: Vector2, W: float, H: float, top: Color, left: Color, right: Color, edge: Color = Color(0, 0, 0, 0.35)) -> void:
	var a := W * 0.5
	var b := W * 0.25
	var T := c + Vector2(0, -b)
	var R := c + Vector2(a, 0)
	var B := c + Vector2(0, b)
	var Lf := c + Vector2(-a, 0)
	var dh := Vector2(0, H)
	ci.draw_colored_polygon(PackedVector2Array([Lf, B, B + dh, Lf + dh]), left)
	ci.draw_colored_polygon(PackedVector2Array([B, R, R + dh, B + dh]), right)
	ci.draw_colored_polygon(PackedVector2Array([T, R, B, Lf]), top)
	ci.draw_polyline(PackedVector2Array([Lf + dh, B + dh, R + dh]), edge, 1.5)
	ci.draw_polyline(PackedVector2Array([Lf, Lf + dh]), edge, 1.5)
	ci.draw_polyline(PackedVector2Array([R, R + dh]), edge, 1.5)
	ci.draw_line(B, B + dh, edge, 1.5)
	cube_rim(ci, c, W)

## Edge definition of a cube top; drawn AFTER the moving surface so the cube stays readable.
static func cube_rim(ci: CanvasItem, c: Vector2, W: float) -> void:
	var a := W * 0.5
	var b := W * 0.25
	var T := c + Vector2(0, -b)
	var R := c + Vector2(a, 0)
	var B := c + Vector2(0, b)
	var Lf := c + Vector2(-a, 0)
	ci.draw_polyline(PackedVector2Array([Lf, T, R]), Color(1, 1, 1, 0.3), 1.5)
	ci.draw_polyline(PackedVector2Array([Lf, B, R]), Color(0, 0, 0, 0.28), 1.5)

## Recessed water cell: back walls visible, water surface sunk by d below the rim.
static func water_pit(ci: CanvasItem, c: Vector2, W: float, H: float, d: float, time: float, phase: float, side_l: Color, side_r: Color) -> void:
	var a := W * 0.5
	var b := W * 0.25
	var T := c + Vector2(0, -b)
	var R := c + Vector2(a, 0)
	var B := c + Vector2(0, b)
	var Lf := c + Vector2(-a, 0)
	var dh := Vector2(0, H)
	# exterior front faces of the block (same as a cube) so the pit sits inside a solid
	ci.draw_colored_polygon(PackedVector2Array([Lf, B, B + dh, Lf + dh]), side_l)
	ci.draw_colored_polygon(PackedVector2Array([B, R, R + dh, B + dh]), side_r)
	var s := a * (1.0 - d / (2.0 * b))
	var T1 := Vector2(c.x, c.y + d - b)
	var Rm := Vector2(c.x + s, c.y + d * 0.5)
	var Lm := Vector2(c.x - s, c.y + d * 0.5)
	ci.draw_colored_polygon(PackedVector2Array([Lf, T, T1, Lm]), Color("0a2a55"))      # back-left wall
	ci.draw_colored_polygon(PackedVector2Array([T, R, Rm, T1]), Color("06193a"))       # back-right wall
	var wc := C_WATER.lerp(C_WATER_L, 0.25 + 0.2 * sin(time * 2.0 + phase))
	ci.draw_colored_polygon(PackedVector2Array([T1, Rm, B, Lm]), wc)
	# ripples + glint
	var rp := fposmod(time * 0.8 + phase, 1.0)
	ell_line(ci, c + Vector2(0, d * 0.55), a * 0.55 * (0.4 + rp), b * 0.55 * (0.4 + rp), Color(1, 1, 1, 0.35 * (1.0 - rp)), 1.5, 14)
	ci.draw_line(c + Vector2(-a * 0.25, d * 0.3), c + Vector2(a * 0.05, d * 0.3 - 1), Color(1, 1, 1, 0.35), 2.0)
	ci.draw_polyline(PackedVector2Array([Lf, B, R]), Color(0, 0, 0, 0.35), 1.5)
	ci.draw_polyline(PackedVector2Array([Lf, T, R]), Color(1, 1, 1, 0.18), 1.5)
	ci.draw_polyline(PackedVector2Array([Lf, Lf + dh, B + dh, R + dh, R]), Color(0, 0, 0, 0.35), 1.5)

## Lily pad lying on a cube's top face (iso-squashed ellipse).
static func pad_on_top(ci: CanvasItem, c: Vector2, W: float, k: int, wobble: float, time: float, sink: bool) -> void:
	var off := Vector2(sin(time * 30.0) * wobble * 2.5, 0.0)
	var q := c + off + Vector2(0, -1)
	var rx := W * 0.45          # pad width: 90% of its conveyor slot, so pads stay distinct yet "on the pad" ~= "inside the slot"
	var ry := W * 0.2
	ell(ci, q + Vector2(0, 2), rx, ry, C_PAD_D, 20)
	ell(ci, q, rx * 0.94, ry * 0.9, C_PAD if not sink else Color("2fa26b"), 20)
	var ang := float((k * 37) % 6) * 1.0472
	var wedge := PackedVector2Array([q, q + Vector2(cos(ang - 0.2) * rx * 1.05, sin(ang - 0.2) * ry * 1.05), q + Vector2(cos(ang + 0.2) * rx * 1.05, sin(ang + 0.2) * ry * 1.05)])
	ci.draw_colored_polygon(wedge, Color(0.2, 0.35, 0.3, 0.9))
	ell_line(ci, q, rx * 0.55, ry * 0.5, Color(1, 1, 1, 0.2), 1.5, 14)
	if k % 5 == 0 and not sink:
		ell(ci, q + Vector2(rx * 0.3, -ry * 0.5), W * 0.07, W * 0.045, Color(1, 0.6, 0.85), 8)
	if sink:
		for i in 3:
			ell(ci, q + Vector2((i - 1) * W * 0.12, -W * 0.05), W * 0.03, W * 0.02, Color(1, 1, 1, 0.6), 6)
	if wobble > 0.0:
		ell_line(ci, q, rx * (1.0 + wobble * 0.2), ry * (1.0 + wobble * 0.2), Color(1, 0.9, 0.3, 0.7), 2.0, 20)

## Physical barrier: a carved stone block standing on the cube's top face.
static func stone_block(ci: CanvasItem, c: Vector2, W: float) -> void:
	var hs := W * 0.55
	var bc := c + Vector2(0, -hs + 3)
	ell(ci, c + Vector2(0, 2), W * 0.36, W * 0.15, Color(0, 0, 0, 0.3), 14)
	cube(ci, bc, W * 0.66, hs, Color("c5c2de"), Color("6d6a8c"), Color("8d8aa8"), Color(0.1, 0.08, 0.2, 0.55))
	ci.draw_line(bc + Vector2(-W * 0.1, W * 0.04), bc + Vector2(-W * 0.02, W * 0.2), Color(0.15, 0.12, 0.3, 0.6), 2.0)
	ci.draw_line(bc + Vector2(-W * 0.02, W * 0.2), bc + Vector2(W * 0.1, W * 0.3), Color(0.15, 0.12, 0.3, 0.6), 2.0)
