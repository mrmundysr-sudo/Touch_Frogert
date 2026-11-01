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

const Hopmap = preload("res://src/sim/hopmap.gd")

## Scripted swipes: ["swipe", dx, dy] waits (up to 3s) until the landing is safe; ["climb"] swipes toward the row's middle
## (UP = up-right, LEFT = up-left); ["wait", seconds].
const SCRIPT := [
	["wait", 1.2],
	["climb"], ["wait", 2.2],                       # onto the first conveyor row and ride it
	["swipe", 0, -1], ["wait", 0.7],                # UP    -> up-right
	["swipe", 1, 0], ["wait", 0.7],                 # RIGHT -> down-right
	["swipe", 0, 1], ["wait", 0.7],                 # DOWN  -> down-left
	["swipe", -1, 0], ["wait", 1.6],                # LEFT  -> up-left  (back where we started)
	["climb"], ["wait", 0.3], ["climb"], ["wait", 0.3], ["climb"], ["wait", 0.3],
	["climb"], ["wait", 0.3], ["climb"], ["wait", 2.4],
]
## Ride a lily pad across several cube seams (hop onto a river row, then stand still).
const SCRIPT_RIDE := [
	["wait", 1.0], ["climb"], ["wait", 0.5], ["climb"], ["wait", 4.5], ["climb"], ["wait", 3.0],
]
## Get carried off the pyramid edge by a conveyor and fall.
const SCRIPT_EDGE := [
	["wait", 1.0], ["climb"], ["wait", 9.0],
]
const CAPTIONS := {"up": "SWIPE UP  =  hop up-right", "right": "SWIPE RIGHT  =  hop down-right", "down": "SWIPE DOWN  =  hop down-left", "left": "SWIPE LEFT  =  hop up-left"}

var steps: Array = SCRIPT
var caption := ""
var caption_dir := Vector2i.ZERO
var caption_t := 0.0
var idx := 0
var wait_left := 0.0
var give_up := 0.0

func _safe(sim, sx: int, sy: int) -> bool:
	var hv := Hopmap.hop_for_swipe(sim.tun, sx, sy)
	var pr: PackedFloat64Array = sim.board.plan_hop(sim.frog_r, sim.frog_rel, hv.x, hv.y, sim.t, sim.hop_dur)
	return int(pr[0]) == 0 and sim.board.landing_result(int(pr[1]), pr[2], sim.t + sim.hop_dur, false) == sim.board.R_OK

func _do(sim, sx: int, sy: int) -> void:
	sim.swipe(sx, sy)
	caption = CAPTIONS[Hopmap.name_of(sx, sy)]
	caption_dir = Vector2i(sx, sy)
	caption_t = 0.9

## Call every frame before sim.step.
func act(sim) -> void:
	caption_t = maxf(0.0, caption_t - 1.0 / 60.0)
	if caption_t <= 0.0 and sim.mode == sim.Mode.PLAY and not sim.hopping and sim.frog_r > 0 and sim.frog_r < sim.board.n - 1:
		var v: float = sim.board.speed[sim.frog_r]
		caption = "RIDING THE CONVEYOR  %s" % ("-->" if v > 0.0 else "<--")
		caption_dir = Vector2i(1 if v > 0.0 else -1, 0)
	if sim.mode != sim.Mode.PLAY or idx >= steps.size():
		return
	var step_: Array = steps[idx]
	if step_[0] == "wait":
		wait_left += 1.0 / 60.0
		if wait_left >= float(step_[1]):
			wait_left = 0.0
			idx += 1
		return
	if sim.hopping or sim.lock_t > 0.0:
		return
	give_up += 1.0 / 60.0
	var sx := 0
	var sy := 0
	if step_[0] == "climb":
		var mid := float(int(sim.board.w[sim.frog_r]) - 1) * 0.5
		if float(sim.frog_cube()) < mid:
			sx = 0; sy = -1          # UP = up-right
		else:
			sx = -1; sy = 0          # LEFT = up-left
		if not _safe(sim, sx, sy):
			# try the other upward swipe if the preferred one is not safe right now
			var ax := -1 if sy != 0 else 0
			var ay := 0 if sy != 0 else -1
			if _safe(sim, ax, ay) and give_up > 0.6:
				sx = ax; sy = ay
			else:
				if give_up > 3.0:
					give_up = 0.0
					idx += 1
				return
	else:
		sx = int(step_[1]); sy = int(step_[2])
		if not _safe(sim, sx, sy):
			if give_up > 3.0:
				give_up = 0.0
				idx += 1
			return
	give_up = 0.0
	idx += 1
	_do(sim, sx, sy)
