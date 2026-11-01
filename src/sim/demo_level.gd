extends RefCounted
## Hand-built showcase level used by the visual checkpoint / dev demos (not part of normal progression).
const Board = preload("res://src/sim/board.gd")

static func _row(idx: int, kind: String, pattern: String, speed: float) -> Dictionary:
	var sl: Array = []
	var sp: Array = []
	for ch in pattern:
		sl.append({"P": Board.PAD, "W": Board.WATER, "B": Board.BARRIER, "S": Board.SINK}[ch])
		sp.append(0.0)
	return {"idx": idx, "w": 3 + idx, "L": pattern.length(), "speed": speed, "phase": 0.0, "slots": sl, "sinkph": sp, "kind": kind}

static func make() -> Dictionary:
	var rows: Array = []
	rows.append(_row(0, "summit", "PPP", 0.0))
	rows.append(_row(1, "ground", "PPPPPPPP", 1.2))
	rows.append(_row(2, "river", "PPPWWPPPP", -1.0))
	rows.append(_row(3, "ground", "PPPBPPPPPP", 1.1))
	rows.append(_row(4, "river", "PPPPPWWWPPP", -0.9))
	rows.append(_row(5, "ground", "PPPPPPPPPPPP", 0.9))
	rows.append(_row(6, "start", "PPPPPPPPP", 0.0))
	return {"level": 1, "attempt": 0, "seed": 0, "n_rows": 7, "rows": rows, "flies": [], "tun_gen": 0}

## Scripted swipes: ["hop", dx, dy] waits until the landing is safe; ["wait", seconds].
const SCRIPT := [
	["wait", 1.2],
	["hop", 0, -1], ["wait", 1.5],        # UP onto a ground row (moves right) and ride it
	["hop", -1, 0], ["wait", 0.35],       # LEFT along the row (against the drift)
	["hop", -1, 0], ["wait", 0.35],
	["hop", 1, 0], ["wait", 0.5],         # RIGHT
	["center"], ["hop", 0, -1], ["wait", 1.2],   # UP onto the river row (moves left): carried left
	["hop", 0, 1], ["wait", 0.5],         # DOWN: retreat to the lower, wider row
	["center"], ["hop", 0, -1], ["wait", 0.2],
	["center"], ["hop", 0, -1], ["wait", 0.2],
	["center"], ["hop", 0, -1], ["wait", 0.2],
	["center"], ["hop", 0, -1], ["wait", 0.2],
	["center"], ["hop", 0, -1], ["wait", 2.2],
]

var caption := ""
var caption_dir := Vector2i.ZERO
var caption_t := 0.0
var idx := 0
var wait_left := 0.0
var give_up := 0.0

## Call every frame before sim.step. Returns a short caption of the current action for the demo overlay.
func act(sim) -> String:
	caption_t = maxf(0.0, caption_t - 1.0 / 60.0)
	if caption_t <= 0.0 and sim.mode == sim.Mode.PLAY and not sim.hopping and sim.frog_r > 0 and sim.frog_r < sim.board.n - 1:
		var v: float = sim.board.speed[sim.frog_r]
		caption = "RIDING THE CONVEYOR  %s" % ("-->" if v > 0.0 else "<--")
		caption_dir = Vector2i(1 if v > 0.0 else -1, 0)
	if sim.mode != sim.Mode.PLAY or idx >= SCRIPT.size():
		return ""
	var step_: Array = SCRIPT[idx]
	if step_[0] == "wait":
		wait_left += 1.0 / 60.0
		if wait_left >= float(step_[1]):
			wait_left = 0.0
			idx += 1
		return ""
	if sim.hopping or sim.lock_t > 0.0:
		return ""
	if step_[0] == "center":
		# nudge back toward the middle of the row so the conveyor drift never carries the demo frog off the edge
		var xl: float = sim.board.local_x(sim.frog_r, sim.frog_rel, sim.t)
		var mid := float(sim.board.w[sim.frog_r]) * 0.5
		idx += 1
		if absf(xl - mid) > 1.3 and not sim.hopping:
			var cdx := -1 if xl > mid else 1
			var cpr: PackedFloat64Array = sim.board.plan_hop(sim.frog_r, sim.frog_rel, cdx, 0, sim.t, sim.hop_dur)
			if int(cpr[0]) == 0 and sim.board.landing_result(int(cpr[1]), cpr[2], sim.t + sim.hop_dur, false) == sim.board.R_OK:
				sim.swipe(cdx, 0)
				caption = "SWIPE LEFT" if cdx < 0 else "SWIPE RIGHT"
				caption_dir = Vector2i(cdx, 0)
				caption_t = 0.7
		return ""
	var dx: int = step_[1]
	var dy: int = step_[2]
	var pr: PackedFloat64Array = sim.board.plan_hop(sim.frog_r, sim.frog_rel, dx, dy, sim.t, sim.hop_dur, 0.25 * float(sim.pref) if dx == 0 else 0.0)
	var ok: bool = int(pr[0]) == 0 and sim.board.landing_result(int(pr[1]), pr[2], sim.t + sim.hop_dur, false) == sim.board.R_OK
	give_up += 1.0 / 60.0
	if ok or give_up > 3.0:
		give_up = 0.0
		idx += 1
		if ok:
			sim.swipe(dx, dy)
			caption = {Vector2i(0, -1): "SWIPE UP", Vector2i(0, 1): "SWIPE DOWN", Vector2i(-1, 0): "SWIPE LEFT", Vector2i(1, 0): "SWIPE RIGHT"}[Vector2i(dx, dy)]
			caption_dir = Vector2i(dx, dy)
			caption_t = 0.9
			return ""
	return ""
