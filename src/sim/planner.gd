extends RefCounted
## Exact time-expanded reachability search over the deterministic Board, using ONLY the real inputs:
## swipe up/down/left/right, plus "turn" (hold B + swipe left/right) which sets the preferred side
## used when hopping up/down a staggered row.  Used for
##  (1) level validation (is there a pad-only route, with timing slack?), and
##  (2) the "skilled" bot's plan.
const Board = preload("res://src/sim/board.gd")

const DIRS := [Vector2i(0, -1), Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, 1)]   # up, left, right, down
const BIAS := 0.25

static func _safe_stand(b: Board, r: int, rel: float, t: float) -> bool:
	var x := b.local_x(r, rel, t)
	if x < 0.0 or x > float(b.w[r]):
		return false
	return b.content(r, b.slot_of_rel(r, rel), t) != Board.WATER

static func _key(b: Board, r: int, rel: float, pref: int) -> int:
	var k := b.slot_of_rel(r, rel)
	var lap := int(round((rel - (float(k) + 0.5)) / float(b.L[r])))
	return (r * 100000 + (lap + 500) * 100 + k) * 2 + (1 if pref > 0 else 0)

## margin: every landing must stay valid when launched up to +-margin seconds early/late.
## Returns {ok, time, plan:[[t,dx,dy,aim],...], nodes}. partial=true returns the best progress if no route.
static func solve(b: Board, hop: float, start_r: int, start_rel: float, t0: float, max_t: float, margin: float = 0.0, max_nodes: int = 400000, partial: bool = false, start_pref: int = 1) -> Dictionary:
	var dt := hop * 0.5
	var layers: Array = []
	var parents := {}
	var nodes := 0
	var max_n := int(max_t / dt)
	var best_r := start_r
	var best_n := 0
	var start_key := _key(b, start_r, start_rel, start_pref)
	var best_key := start_key
	for i in max_n + 3:
		layers.append({})
	layers[0][start_key] = [start_r, start_rel, start_pref]
	for n in max_n:
		var layer: Dictionary = layers[n]
		if layer.is_empty():
			continue
		var t := t0 + n * dt
		for key in layer:
			var st: Array = layer[key]
			var r: int = st[0]
			var rel: float = st[1]
			var pref: int = st[2]
			nodes += 1
			if partial and r < best_r:
				best_r = r; best_n = n; best_key = key
			if nodes > max_nodes:
				return {"ok": false, "time": -1.0, "plan": [], "nodes": nodes, "reason": "node_limit"}
			if r == 0:
				return _build(parents, n, key, t0, dt)
			var tn := t + dt
			# wait
			if _safe_stand(b, r, rel, tn):
				if not layers[n + 1].has(key):
					layers[n + 1][key] = st
					parents[(n + 1) * 100000000000 + key] = [n * 100000000000 + key, 0, 0, n, 0]
			# turn (B + swipe sideways): costs one step, flips the preferred side
			var other := -pref
			if _safe_stand(b, r, rel, tn):
				var kt := _key(b, r, rel, other)
				if not layers[n + 1].has(kt):
					layers[n + 1][kt] = [r, rel, other]
					parents[(n + 1) * 100000000000 + kt] = [n * 100000000000 + key, other, 0, n, 1]
			# hops
			if n + 2 > max_n:
				continue
			for d in DIRS:
				var bias := BIAS * float(pref) if d.x == 0 else 0.0
				var pr := b.plan_hop(r, rel, d.x, d.y, t, hop, bias)
				if int(pr[0]) != 0:
					continue
				var r2 := int(pr[1]); var rel2 := pr[2]
				var tl := t + hop
				var ok := b.landing_result(r2, rel2, tl, false) == Board.R_OK
				if ok and margin > 0.0:
					for jit in [-margin, margin]:
						var pj := b.plan_hop(r, rel, d.x, d.y, t + jit, hop, bias)
						if int(pj[0]) != 0 or int(pj[1]) != r2 or absf(pj[2] - rel2) > 0.001:
							ok = false
							break
						if b.landing_result(r2, pj[2], tl + jit, false) != Board.R_OK:
							ok = false
							break
					if ok:
						ok = _safe_stand(b, r2, rel2, tl - margin) and _safe_stand(b, r2, rel2, tl + margin)
				if not ok:
					continue
				var pref2: int = d.x if d.x != 0 else pref
				var k3 := _key(b, r2, rel2, pref2)
				if not layers[n + 2].has(k3):
					layers[n + 2][k3] = [r2, rel2, pref2]
					parents[(n + 2) * 100000000000 + k3] = [n * 100000000000 + key, d.x, d.y, n, 0]
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
		if int(p[4]) == 1:
			plan.append([t0 + float(p[3]) * dt, int(p[1]), 0, 1])       # turn toward p[1]
		elif int(p[1]) != 0 or int(p[2]) != 0:
			plan.append([t0 + float(p[3]) * dt, int(p[1]), int(p[2]), 0])
		cur = p[0]
	plan.reverse()
	return {"ok": true, "time": float(n_goal) * dt, "plan": plan, "nodes": 0}
