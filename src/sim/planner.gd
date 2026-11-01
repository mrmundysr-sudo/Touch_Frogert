extends RefCounted
## Exact time-expanded reachability search over the deterministic Board.  Used for
##  (1) level validation (is there a pad-only route, with timing slack?), and
##  (2) the "skilled" bot's plan.
const Board = preload("res://src/sim/board.gd")

const DIRS := [Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 1), Vector2i(1, 1)]

static func _safe_stand(b: Board, r: int, rel: float, t: float) -> bool:
	var x := b.local_x(r, rel, t)
	if x < 0.0 or x > float(b.w[r]):
		return false
	return b.content(r, b.slot_of_rel(r, rel), t) != Board.WATER

## margin: landing must stay valid for +-margin seconds around touchdown (timing slack).
## start_*: state to plan from. Returns {ok, time, plan:[[t,dx,dy],...], nodes}
static func solve(b: Board, hop: float, start_r: int, start_rel: float, t0: float, max_t: float, margin: float = 0.0, max_nodes: int = 400000, partial: bool = false) -> Dictionary:
	var dt := hop * 0.5
	var layers: Array = []
	var start := [start_r, start_rel]
	var cur := {}
	var parents := {}   # "n:key" -> [prev "n:key", dx, dy, launch_n]
	var nodes := 0
	var max_n := int(max_t / dt)
	var best_r := start_r
	var best_n := 0
	var best_key := _key(b, start_r, start_rel)
	for i in max_n + 3:
		layers.append({})
	layers[0][_key(b, start_r, start_rel)] = start
	for n in max_n:
		var layer: Dictionary = layers[n]
		if layer.is_empty():
			continue
		var t := t0 + n * dt
		for key in layer:
			var st: Array = layer[key]
			var r: int = st[0]
			var rel: float = st[1]
			nodes += 1
			if partial and r < best_r:
				best_r = r; best_n = n; best_key = key
			if nodes > max_nodes:
				return {"ok": false, "time": -1.0, "plan": [], "nodes": nodes, "reason": "node_limit"}
			if r == 0:
				return _build(layers, parents, n, key, t0, dt)
			# wait one step
			var tn := t + dt
			if _safe_stand(b, r, rel, tn):
				var k2 := _key(b, r, rel)
				if not layers[n + 1].has(k2):
					layers[n + 1][k2] = st
					parents[str(n + 1) + ":" + str(k2)] = [str(n) + ":" + str(key), 0, 0, n]
			# hop in 8 directions
			for d in DIRS:
				var pr := b.plan_hop(r, rel, d.x, d.y, t, hop)
				if int(pr[0]) != 0:
					continue
				var r2 := int(pr[1]); var rel2 := pr[2]
				var tl := t + hop
				var ok := b.landing_result(r2, rel2, tl, false) == Board.R_OK
				if ok and margin > 0.0:
					# timing slack: launching up to `margin` early/late must land in the SAME safe slot
					for jit in [-margin, margin]:
						var pj := b.plan_hop(r, rel, d.x, d.y, t + jit, hop)
						if int(pj[0]) != 0 or int(pj[1]) != r2 or absf(pj[2] - rel2) > 0.001 + absf(jit) * (absf(b.speed[r2]) + 0.0) * 0.0:
							ok = false
							break
						if b.landing_result(r2, pj[2], tl + jit, false) != Board.R_OK:
							ok = false
							break
					if ok:
						ok = _safe_stand(b, r2, rel2, tl - margin) and _safe_stand(b, r2, rel2, tl + margin)
				if not ok:
					continue
				if n + 2 > max_n:
					continue
				var k3 := _key(b, r2, rel2)
				if not layers[n + 2].has(k3):
					layers[n + 2][k3] = [r2, rel2]
					parents[str(n + 2) + ":" + str(k3)] = [str(n) + ":" + str(key), d.x, d.y, n]
	if partial and best_r < start_r:
		var pr := _build(layers, parents, best_n, best_key, t0, dt)
		pr["ok"] = false; pr["partial"] = true; pr["best_row"] = best_r
		return pr
	return {"ok": false, "time": -1.0, "plan": [], "nodes": nodes, "reason": "unreachable"}

static func _key(b: Board, r: int, rel: float) -> int:
	var k := b.slot_of_rel(r, rel)
	var lap := int(round((rel - (float(k) + 0.5)) / float(b.L[r])))
	return r * 100000 + (lap + 500) * 100 + k

static func _build(layers: Array, parents: Dictionary, n_goal: int, key: int, t0: float, dt: float) -> Dictionary:
	var plan: Array = []
	var cur := str(n_goal) + ":" + str(key)
	while parents.has(cur):
		var p: Array = parents[cur]
		if int(p[1]) != 0 or int(p[2]) != 0:
			plan.append([t0 + float(p[3]) * dt, int(p[1]), int(p[2])])
		cur = p[0]
	plan.reverse()
	return {"ok": true, "time": float(n_goal) * dt, "plan": plan, "nodes": 0}
