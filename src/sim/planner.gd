extends RefCounted
## Exact time-expanded reachability search over the deterministic Board, using ONLY the real inputs:
## the four swipes (mapped to hops through the configurable hop map).  Used for
##  (1) level validation (is there a pad-only route, with timing slack?), and
##  (2) the "skilled" bot's plan.
const Board = preload("res://src/sim/board.gd")
const Hopmap = preload("res://src/sim/hopmap.gd")
const BIN := 0.05            # states closer than this (in cubes) on the same row at the same instant are merged

static func _safe_stand(b: Board, r: int, rel: float, t: float) -> bool:
	var x := b.local_x(r, rel, t)
	if x < 0.0 or x > float(b.w[r]):
		return false
	return b.content(r, b.slot_of_rel(r, rel), t) != Board.WATER

static func _key(r: int, rel: float) -> int:
	return r * 10000000 + int(round(rel / BIN)) + 5000000

## margin: every hop must still work when launched up to +-margin seconds early/late
## (same origin cube, same destination, safe landing).
## Returns {ok, time, plan:[[t, swipe_dx, swipe_dy, 0],...], nodes}. partial=true returns best progress if no route.
static func solve(b: Board, hop: float, start_r: int, start_rel: float, t0: float, max_t: float, margin: float = 0.0, max_nodes: int = 400000, partial: bool = false, tun: Dictionary = {}) -> Dictionary:
	var moves := Hopmap.all(tun)
	var dt := hop * 0.5
	var layers: Array = []
	var parents := {}
	var nodes := 0
	var max_n := int(max_t / dt)
	var best_r := start_r
	var best_n := 0
	var start_key := _key(start_r, start_rel)
	var best_key := start_key
	for i in max_n + 3:
		layers.append({})
	layers[0][start_key] = [start_r, start_rel]
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
				return _build(parents, n, key, t0, dt)
			var tn := t + dt
			if _safe_stand(b, r, rel, tn):
				var kw := _key(r, rel)
				if not layers[n + 1].has(kw):
					layers[n + 1][kw] = st
					parents[(n + 1) * 100000000000 + kw] = [n * 100000000000 + key, 0, 0, n]
			if n + 2 > max_n:
				continue
			for mv in moves:
				var sw: Vector2i = mv[0]
				var hv: Vector2i = mv[1]
				var pr := b.plan_hop(r, rel, hv.x, hv.y, t, hop)
				if int(pr[0]) != 0:
					continue
				var r2 := int(pr[1]); var rel2 := pr[2]
				var tl := t + hop
				var ok := b.landing_result(r2, rel2, tl, false) == Board.R_OK
				if ok and margin > 0.0:
					for jit in [-margin, margin]:
						var pj := b.plan_hop(r, rel, hv.x, hv.y, t + jit, hop)
						if int(pj[0]) != 0 or int(pj[4]) != int(pr[4]) or int(pj[5]) != int(pr[5]):
							ok = false
							break
						if b.landing_result(r2, pj[2], tl + jit, false) != Board.R_OK:
							ok = false
							break
					if ok:
						ok = _safe_stand(b, r2, rel2, tl - margin) and _safe_stand(b, r2, rel2, tl + margin)
				if not ok:
					continue
				var k3 := _key(r2, rel2)
				if not layers[n + 2].has(k3):
					layers[n + 2][k3] = [r2, rel2]
					parents[(n + 2) * 100000000000 + k3] = [n * 100000000000 + key, sw.x, sw.y, n]
	if partial and best_r < start_r:
		var pr2 := _build(parents, best_n, best_key, t0, dt)
		pr2["ok"] = false; pr2["partial"] = true; pr2["best_row"] = best_r
		return pr2
	return {"ok": false, "time": -1.0, "plan": [], "nodes": nodes, "reason": "unreachable"}

static func _build(parents: Dictionary, n_goal: int, key: int, t0: float, dt: float) -> Dictionary:
	var plan: Array = []
	var cur: int = n_goal * 100000000000 + key
	while parents.has(cur):
		var p: Array = parents[cur]
		if int(p[1]) != 0 or int(p[2]) != 0:
			plan.append([t0 + float(p[3]) * dt, int(p[1]), int(p[2]), 0])
		cur = p[0]
	plan.reverse()
	return {"ok": true, "time": float(n_goal) * dt, "plan": plan, "nodes": 0}
