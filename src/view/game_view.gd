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
var show_sprites := false
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
var cubes_layer: Node2D
var surface_layer: Node2D
var rims_layer: Node2D
var built_rows := -1
var static_key := ""
var dia_cache := {}
## render prototype switches:  pad_mode = clip (old: pads cut into cube tops) | whole (full objects) | film (whole + water film under)
var pad_mode := "whole"
var water_bridge := false
var cache_static := true
var bake_static := false           # render the stationary cubes/rims ONCE into textures (one quad each per frame)
var bake_vps: Array = []
var bake_sprites: Array = []
var perf := {"surf": 0, "obj": 0, "ovl": 0, "cubes": 0, "frames": 0, "clips": 0}

## Per-row control: draws the objects riding that row (pads, stone blocks, flies), clipped to the row's extent.
class RowCtl extends Control:
	var gv
	var r := 0
	func _draw() -> void:
		gv.draw_objects(self, r)

## Whole-pyramid layers. "cubes" and "rims" are STATIC (retained: drawn once, redrawn only on layout/level change).
class LayerNode extends Node2D:
	var gv
	var which := ""
	func _draw() -> void:
		match which:
			"cubes": gv.draw_cubes(self)
			"surface": gv.draw_surfaces(self)
			"rims": gv.draw_rims(self)

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
	for nd in [cubes_layer, surface_layer, rims_layer, overlay] + bake_sprites:
		if nd != null and nd.get_parent() != null:
			remove_child(nd)
	if cubes_layer == null:
		cubes_layer = LayerNode.new(); cubes_layer.gv = self; cubes_layer.which = "cubes"
		surface_layer = LayerNode.new(); surface_layer.gv = self; surface_layer.which = "surface"
		rims_layer = LayerNode.new(); rims_layer.gv = self; rims_layer.which = "rims"
	# paint order: all cube bodies, then the moving surface, then cube rims, then objects riding the rows, then the frog/HUD overlay
	if bake_static:
		_make_baked()
		add_child(bake_sprites[0])
		add_child(surface_layer)
		add_child(bake_sprites[1])
	else:
		add_child(cubes_layer)
		add_child(surface_layer)
		add_child(rims_layer)
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
	static_key = ""

func _make_baked() -> void:
	if not bake_vps.is_empty():
		return
	for i in 2:
		var vp := SubViewport.new()
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		var layer: Node2D = cubes_layer if i == 0 else rims_layer
		vp.add_child(layer)
		add_child(vp)
		var sp := Sprite2D.new()
		sp.centered = false
		sp.texture = vp.get_texture()
		bake_vps.append(vp)
		bake_sprites.append(sp)

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
	var key := "%d|%.2f|%.1f|%.1f|%s|%s" % [n, W, cx, y_top, str(sim.level.get("seed", 0)), str(sim.level.get("attempt", 0))]
	if key != static_key:
		static_key = key
		dia_cache.clear()
		cubes_layer.queue_redraw()
		rims_layer.queue_redraw()
		if bake_static:
			for vp in bake_vps:
				vp.size = Vector2i(int(vsize.x), int(vsize.y))
				vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	for r in n:
		var c: Control = row_ctls[r]
		var w := float(sim.board.w[r])
		var top := y_top + r * P - W * 0.25 - above
		var bottom := y_top + r * P + W * 0.25 + Hs + 2.0
		c.position = Vector2(cx - w * W * 0.5, top)
		c.size = Vector2(w * W, bottom - top)

func spos(row_f: float, wx: float) -> Vector2:
	return Vector2(cx + wx * W, y_top + row_f * P)

## centre of the top face of FIXED cube c in row r
func cube_screen(r: int, c: int) -> Vector2:
	return spos(float(r), float(c) + 0.5 - float(sim.board.w[r]) * 0.5)

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
		"barrier_down": burst(cube_screen(ev[1], ev[2]) + Vector2(0, -W * 0.3), Color("b9b6d3"), 18, 280.0, 0.7); shake = 0.25
		"fly_zap": burst(cube_screen(ev[1], ev[2]) + Vector2(0, -W * 0.4), Color("ff3d71"), 14, 240.0)
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
		surface_layer.queue_redraw()
		overlay.queue_redraw()
		if not cache_static:
			cubes_layer.queue_redraw()
			rims_layer.queue_redraw()
		perf["frames"] += 1
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
		"river": return [Color(0.12, 0.38 + lift, 0.72 + lift), Color("1d3f52"), Color("2d5c70")]
		_: return [Color(0.4 + lift, 0.76 + lift, 0.34 + lift), Color("22592a"), Color("30803a")]

const WATER_TOP := Color("1b6fc4")
const WATER_RIP := Color("3f93e6")

static func _area(poly: PackedVector2Array) -> float:
	var a := 0.0
	var n := poly.size()
	for i in n:
		var p := poly[i]
		var q := poly[(i + 1) % n]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5

## Fill `poly` (a convex region in row-local px) clipped to the moving surface's cube tops.
## `dia` = cached diamond polygons per cube. Returns the clipped pieces so callers can add shading.
func _fill_on_tops(ci: CanvasItem, dia: Array, poly: PackedVector2Array, xa: float, xb: float, col: Color, w: int) -> Array:
	var pieces: Array = []
	var c0 := maxi(0, int(floor(xa)))
	var c1 := mini(w - 1, int(floor(xb - 0.0001)))
	for c in range(c0, c1 + 1):
		var res: Array = Geometry2D.intersect_polygons(dia[c], poly)
		for piece in res:
			if piece.size() >= 3 and _area(piece) > 1.5:
				ci.draw_colored_polygon(piece, col)
				pieces.append(piece)
	return pieces

func _slab_poly(xa: float, xb: float, y0: float) -> PackedVector2Array:
	var b := W * 0.25
	return PackedVector2Array([Vector2(xa * W, y0 - b - 1.0), Vector2(xb * W, y0 - b - 1.0), Vector2(xb * W, y0 + b + 1.0), Vector2(xa * W, y0 + b + 1.0)])

func _ellipse_poly(c: Vector2, rx: float, ry: float, n: int = 16) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * float(i) / float(n)
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return pts

func _kind(r: int) -> String:
	var b := sim.board
	if r == b.n - 1:
		return "start"
	if r == 0:
		return "summit"
	return String(sim.level["rows"][r].get("kind", "ground"))

func _dia(w: int) -> Array:
	if dia_cache.has(w):
		return dia_cache[w]
	var qb := W * 0.25
	var out: Array = []
	for c in w:
		var cc := Vector2((float(c) + 0.5) * W, 0.0)
		out.append(PackedVector2Array([cc + Vector2(0, -qb), cc + Vector2(W * 0.5, 0), cc + Vector2(0, qb), cc + Vector2(-W * 0.5, 0)]))
	dia_cache[w] = out
	return out

## STATIC: the permanent pyramid bodies (never move, never wrap). Retained: redrawn only on layout/level change.
func draw_cubes(ci: Node2D) -> void:
	var t0 := Time.get_ticks_usec()
	var b := sim.board
	for r in b.n:
		var w: int = b.w[r]
		var pal := _palette(r, _kind(r))
		var ox := cx - float(w) * W * 0.5
		for c in w:
			var shade := 1.0 if (c % 2 == 0) else 0.95
			Art.cube(ci, Vector2(ox + (float(c) + 0.5) * W, y_top + r * P), W, Hs, (pal[0] as Color) * Color(shade, shade, shade, 1.0), pal[1], pal[2])
	perf["cubes"] += Time.get_ticks_usec() - t0

func draw_rims(ci: Node2D) -> void:
	var b := sim.board
	for r in b.n:
		var w: int = b.w[r]
		var ox := cx - float(w) * W * 0.5
		for c in w:
			Art.cube_rim(ci, Vector2(ox + (float(c) + 0.5) * W, y_top + r * P), W)

## DYNAMIC: the moving surface texture (water gaps, ripples, ground stripes), clipped to the fixed cube tops.
func draw_surfaces(ci: Node2D) -> void:
	var t0 := Time.get_ticks_usec()
	var b := sim.board
	var qb := W * 0.25
	for r in range(1, b.n - 1):
		var w: int = b.w[r]
		var kind := _kind(r)
		var river := kind == "river"
		var dia := _dia(w)
		ci.draw_set_transform(Vector2(cx - float(w) * W * 0.5, y_top + r * P), 0.0, Vector2.ONE)
		var raw := b.raw(r, sim.t)
		var Lr: int = b.L[r]
		for k in Lr:
			var xl := fposmod(float(k) + 0.5 + raw, float(Lr))
			if xl < -0.5 or xl > float(w) + 0.5:
				continue
			var xa := maxf(xl - 0.5, 0.0)
			var xb := minf(xl + 0.5, float(w))
			if xb - xa < 0.01:
				continue
			var cont := b.content(r, k, sim.t)
			var slab := _slab_poly(xa, xb, 0.0)
			if river:
				if k % 2 == 0:
					_fill_on_tops(ci, dia, slab, xa, xb, Color(WATER_RIP.r, WATER_RIP.g, WATER_RIP.b, 0.22), w)
				if pad_mode == "clip" and cont != Board.WATER:
					_clipped_pad(ci, dia, r, k, xl, w)
			else:
				if cont == Board.WATER:
					var pieces := _fill_on_tops(ci, dia, slab, xa, xb, WATER_TOP, w)
					for piece in pieces:
						var sh_poly := PackedVector2Array()
						for v in piece:
							sh_poly.append(v + Vector2(0, W * 0.16))
						for sp in Geometry2D.clip_polygons(piece, sh_poly):
							if sp.size() >= 3 and _area(sp) > 1.0:
								ci.draw_colored_polygon(sp, Color(0.0, 0.05, 0.25, 0.6))
					if water_bridge:
						# fill the notches above/below every cube seam inside the gap so the water stays ONE connected piece
						for sv in range(maxi(1, int(ceil(xa - 0.0001))), mini(w - 1, int(floor(xb + 0.0001))) + 1):
							var vx := float(sv) * W
							var up := PackedVector2Array([Vector2(vx - W * 0.5, -qb), Vector2(vx, 0), Vector2(vx + W * 0.5, -qb)])
							var dn := PackedVector2Array([Vector2(vx - W * 0.5, qb), Vector2(vx, 0), Vector2(vx + W * 0.5, qb)])
							for tri in [up, dn]:
								for piece in Geometry2D.intersect_polygons(tri, slab):
									if piece.size() >= 3 and _area(piece) > 1.0:
										ci.draw_colored_polygon(piece, Color(WATER_TOP.r, WATER_TOP.g, WATER_TOP.b, 0.92))
					for ex in [xl - 0.5, xl + 0.5]:
						if ex > 0.0 and ex < float(w):
							var cidx := clampi(int(floor(ex)), 0, w - 1)
							var hh := qb * (1.0 - absf(ex * W - (float(cidx) + 0.5) * W) / (W * 0.5))
							if hh > 2.0:
								ci.draw_line(Vector2(ex * W, -hh), Vector2(ex * W, hh), Color(0.02, 0.1, 0.3, 0.9), 3.0)
								ci.draw_line(Vector2(ex * W + 2, -hh), Vector2(ex * W + 2, hh), Color(1, 1, 1, 0.18), 1.5)
				else:
					if k % 2 == 0:
						_fill_on_tops(ci, dia, slab, xa, xb, Color(1, 1, 0.8, 0.20), w)
					else:
						_fill_on_tops(ci, dia, slab, xa, xb, Color(0, 0.12, 0, 0.18), w)
					var sx_ := xl - 0.5
					if sx_ > 0.02 and sx_ < float(w) - 0.02:
						var ci_ := clampi(int(floor(sx_)), 0, w - 1)
						var hh2 := qb * (1.0 - absf(sx_ * W - (float(ci_) + 0.5) * W) / (W * 0.5))
						if hh2 > 2.0:
							ci.draw_line(Vector2(sx_ * W, -hh2), Vector2(sx_ * W, hh2), Color(0, 0.15, 0, 0.45), 2.0)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	perf["surf"] += Time.get_ticks_usec() - t0

## OLD behaviour (pad_mode == "clip"), kept for before/after comparison: a pad cut into the diamonds it overlaps.
func _clipped_pad(ci: Node2D, dia: Array, r: int, k: int, xl: float, w: int) -> void:
	var b := sim.board
	var base: int = b.slots[r][k]
	var wob := b.sink_warning(r, k, sim.t)
	var pc := Vector2(xl * W + (sin(time * 30.0) * wob * 2.0), -1.0 + wob * W * 0.05)
	var rx := W * (0.4 - 0.08 * wob)
	var ry := W * (0.19 - 0.04 * wob)
	var ring := _ellipse_poly(pc + Vector2(0, 2), rx + 2.0, ry + 1.5)
	var body := _ellipse_poly(pc, rx, ry)
	var padc := Color("39b54a") if base != Board.SINK else Color("2fa26b")
	for c in range(maxi(0, int(floor(xl - 0.5))), mini(w - 1, int(floor(xl + 0.5))) + 1):
		perf["clips"] += 2
		for piece in Geometry2D.intersect_polygons(dia[c], ring):
			if piece.size() >= 3 and _area(piece) > 1.0:
				ci.draw_colored_polygon(piece, Color("1f7a31"))
		for piece in Geometry2D.intersect_polygons(dia[c], body):
			if piece.size() >= 3 and _area(piece) > 1.0:
				ci.draw_colored_polygon(piece, padc.lerp(Color("e8c23a"), wob * 0.6))

## DYNAMIC: objects riding the row. Pads are drawn WHOLE here (never cut into cube tops); the row control
## clips only at the pyramid's side edges so nothing hangs in empty space or pops when it wraps.
func draw_objects(ci: Control, r: int) -> void:
	var t0 := Time.get_ticks_usec()
	var b := sim.board
	if r == 0 or r == b.n - 1:
		return
	var w: int = b.w[r]
	var kind := _kind(r)
	var raw := b.raw(r, sim.t)
	var y0 := y_top + r * P - ci.position.y
	var objs: Array = []
	if pad_mode != "clip" and kind == "river":
		for k in int(b.L[r]):
			var base: int = b.slots[r][k]
			if base != Board.PAD and base != Board.SINK:
				continue
			if b.content(r, k, sim.t) == Board.WATER:
				continue
			var xl := fposmod(float(k) + 0.5 + raw, float(b.L[r]))
			if xl < -0.6 or xl > float(w) + 0.6:
				continue
			objs.append([xl, "pad", k])
	for k in int(b.L[r]):
		if int(b.slots[r][k]) == Board.BARRIER:
			var xs := fposmod(float(k) + 0.5 + raw, float(b.L[r]))
			if xs > -0.6 and xs < float(w) + 0.6:
				objs.append([xs, "stone", k])
	for fi in b.flies.size():
		var f: Dictionary = b.flies[fi]
		if int(f["r"]) == r and b.fly_state(fi, sim.t) != Board.NO_FLY:
			objs.append([fposmod(float(int(f["k"])) + 0.5 + raw, float(b.L[r])), "fly", fi])
	objs.sort_custom(func(a, c): return a[0] < c[0])
	for o in objs:
		var xo: float = o[0]
		if xo < -0.6 or xo > float(w) + 0.6:
			continue
		match o[1]:
			"pad":
				var k2: int = o[2]
				var wob := b.sink_warning(r, k2, sim.t)
				var cc := Vector2(xo * W, y0 + wob * W * 0.05)
				if pad_mode == "film":
					Art.ell(ci, cc + Vector2(0, 1), W * 0.62, W * 0.27, Color(WATER_TOP.r, WATER_TOP.g, WATER_TOP.b, 0.95), 20)
				Art.pad_on_top(ci, cc, W, k2, wob, time, int(b.slots[r][k2]) == Board.SINK)
			"stone":
				Art.stone_block(ci, Vector2(xo * W, y0), W)
			_:
				var fi2: int = o[2]
				var fp := Vector2(xo * W, y0 - W * 0.42 + sin(time * 6.0 + float(fi2)) * 3.0)
				Art.draw_fly(ci, fp, W * 0.5, b.fly_state(fi2, sim.t), b.fly_progress(fi2, sim.t), time, float(fi2))
	if show_row_numbers:
		ci.draw_string(font, Vector2(2, y0 + 6), "R%d" % (r + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(1, 1, 0.3))
	perf["obj"] += Time.get_ticks_usec() - t0

func perf_report() -> String:
	var f := maxi(1, int(perf["frames"]))
	return "perf over %d frames: surfaces %.2f ms/frame, objects %.2f ms/frame, static cubes %.2f ms total (%d redraws est), overlay %.2f ms/frame, polygon clips for pads %.1f/frame" % [f, float(perf["surf"]) / 1000.0 / f, float(perf["obj"]) / 1000.0 / f, float(perf["cubes"]) / 1000.0, 1, float(perf["ovl"]) / 1000.0 / f, float(perf["clips"]) / f]

# ------------------------------------------------------------------ drawing: overlay (frog, effects, HUD)

func draw_overlay(ci: Node2D) -> void:
	var t0 := Time.get_ticks_usec()
	var p := spos(0.0, 0.0)
	var u := W * 0.52
	if sim.mode == SimC.Mode.WIN:
		Art.draw_miss(ci, p + Vector2(0, -W * 0.3), u, time, sin(sim.mode_t * 12.0) * 4.0)
	else:
		Art.draw_miss(ci, p + Vector2(0, -W * 0.3), u, time)
	_aim_preview(ci)
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
	if show_sprites:
		_sprite_sheet(ci)
	_hud(ci)
	perf["ovl"] += Time.get_ticks_usec() - t0

func _sprite_sheet(ci: Node2D) -> void:
	ci.draw_rect(Rect2(Vector2.ZERO, vsize), Color(0.02, 0.05, 0.12, 0.96))
	_txt(ci, "FROGERT FACINGS (swipe -> hop/aim diagonal)", Vector2(0, 150), 30, Color("ffe14d"), HORIZONTAL_ALIGNMENT_CENTER, vsize.x)
	var names := ["UP  (up-right)", "RIGHT  (down-right)", "DOWN  (down-left)", "LEFT  (up-left)"]
	var dirs := [Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1), Vector2(-1, -1)]
	for i in 4:
		var col := i % 2
		var row := i / 2
		var c := Vector2(vsize.x * (0.27 + 0.46 * col), 380.0 + row * 420.0)
		var d: Vector2 = dirs[i]
		var u := 85.0
		Art.cube(ci, c + Vector2(0, 70), 220.0, 60.0, Color("66c24c"), Color("22592a"), Color("30803a"))
		var tip := Vector2(d.x * 120.0, d.y * 105.0)
		Art.draw_frog(ci, c, u, d, Art.C_FROG, 0.0, tip if (int(time * 1.5) % 2 == 0) else null, 0.0, time)
		_txt(ci, names[i], Vector2(c.x - 160, c.y + 200), 24, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, 320.0)

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

## While holding a fly: outline the cubes the shot would clear (1/2/3 by fly age), along the facing diagonal.
func _aim_preview(ci: Node2D) -> void:
	if sim.mode != SimC.Mode.PLAY or sim.carry_age < 0.0 or sim.hopping:
		return
	var rng := sim.stage_range()
	var col: Color = [Color("ffe14d"), Color("ffe14d"), Color("ff9d00"), Color("ff3030")][clampi(rng, 0, 3)]
	for j in range(1, rng + 1):
		var tg := sim._facing_cube(j)
		if tg.size() != 3:
			break
		var c := cube_screen(tg[0], tg[1])
		var a := W * 0.5
		var bq := W * 0.25
		var pulse := 0.5 + 0.5 * sin(time * 8.0)
		ci.draw_polyline(PackedVector2Array([c + Vector2(0, -bq), c + Vector2(a, 0), c + Vector2(0, bq), c + Vector2(-a, 0), c + Vector2(0, -bq)]), Color(col.r, col.g, col.b, 0.45 + 0.4 * pulse), 3.0)

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
		var tp := cube_screen(sim.tongue_r, sim.tongue_c) + Vector2(0, -W * 0.3)
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
	Art.draw_frog(ci, p, u, Vector2(sim.face_hop()), tint, puff, tongue, squash, time)
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
				Art.draw_frog(ci, p, u * (1.0 + s * 9.0), Vector2(sim.face_hop()), Color("ff1010"), 1.0, null, 0.0, time)
			else:
				ci.draw_arc(p, u * (1.5 + s * 5.0), 0, TAU, 28, Color(1, 0.6, 0.2, 1.0 - s), 6.0)
		"fell":
			var q := p + Vector2(0, s * 300.0)
			Art.draw_frog(ci, q, u * (1.0 - s * 0.7), Vector2(sim.face_hop()), tint.darkened(s * 0.5), puff, null, 0.0, time, true)
		"fly":
			Art.draw_frog(ci, p + Vector2(0, -sin(s * PI) * 40.0), u, Vector2(sim.face_hop()), Color("ff6a6a"), puff, null, 0.0, time, true)
		_:
			var sink := clampf(s * 1.4, 0.0, 1.0)
			var q2 := p + Vector2(0, sink * u * 1.1)
			Art.draw_frog(ci, q2, u * (1.0 - sink * 0.4), Vector2(sim.face_hop()), tint.lerp(Color("1457a8"), sink), puff, null, 0.0, time, true)
			for i in 3:
				Art.ell_line(ci, p + Vector2(0, u * 0.8), u * (0.5 + s * 2.0 + i * 0.4), u * (0.22 + s * 0.6 + i * 0.12), Color(0.8, 0.95, 1.0, (1.0 - s) * 0.6), 2.5)

func _shots(ci: Node2D) -> void:
	var ps := float(sim.tun["proj_speed"])
	for s in sim.shots:
		var targets: Array = s["targets"]
		var pts: Array = [spos(float(s["from_r"]), float(s["from_wx"])) + Vector2(0, -W * 0.3)]
		for tg in targets:
			pts.append(cube_screen(tg[0], tg[1]) + Vector2(0, -W * 0.3))
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
		Art.draw_frog(ci, Vector2(vsize.x - 40 - i * 46, 78), 15.0, Vector2(1, 1), Art.C_FROG, 0.0, null, 0.0, time)
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
