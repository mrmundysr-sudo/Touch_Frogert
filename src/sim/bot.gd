extends RefCounted
## Simulated players for testing.  Profiles: skilled, average, slow, mistake.
const Board = preload("res://src/sim/board.gd")
const Planner = preload("res://src/sim/planner.gd")

var profile := "skilled"
var rng := RandomNumberGenerator.new()
var plan: Array = []        # [[t, dx, dy], ...] absolute launch times
var plan_for_attempt := -1
var next_decision := 0.0
var reaction := 0.0
var margin := 0.0
var horizon := 8.0
var jitter := 0.0
var p_mistake := 0.0
var cached_full: Array = []
var use_fly := false

func _init(prof: String, seed_: int) -> void:
	profile = prof
	rng.seed = seed_
	match prof:
		"skilled": reaction = 0.0; margin = 0.08; jitter = 0.0
		"average": reaction = 0.22; margin = 0.06; jitter = 0.035; horizon = 5.0
		"slow": reaction = 0.55; margin = 0.14; jitter = 0.06; horizon = 4.0
		"mistake": reaction = 0.25; margin = 0.05; jitter = 0.07; p_mistake = 0.10; horizon = 5.0

func reset_for_new_attempt() -> void:
	plan.clear()
	next_decision = 0.0

## Called every sim frame while PLAY. Returns nothing; issues sim.swipe().
func act(sim) -> void:
	if sim.mode != sim.Mode.PLAY or sim.hopping or sim.lock_t > 0.0 or sim.bonk_t > 0.0:
		return
	var b: Board = sim.board
	if plan.is_empty():
		if sim.t < next_decision:
			return
		_replan(sim)
		if plan.is_empty():
			next_decision = sim.t + 0.25   # nothing useful found: wait a moment before thinking again
			return
	var step_ = plan[0]
	if sim.t + 1e-6 >= float(step_[0]):
		plan.pop_front()
		var dx: int = step_[1]
		var dy: int = step_[2]
		var aim: bool = int(step_[3]) == 1
		if p_mistake > 0.0 and not aim and rng.randf() < p_mistake:
			var d: Vector2i = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)][rng.randi() % 4]
			dx = d.x; dy = d.y
			plan.clear()          # lost the plan after a slip; re-think next frame
		else:
			if profile != "skilled":
				plan.clear()      # imperfect players re-think after every action
		sim.swipe(dx, dy, aim)

func _replan(sim) -> void:
	var b: Board = sim.board
	var hop := float(sim.hop_dur)
	var start_t: float = sim.t + reaction * rng.randf_range(0.6, 1.4)
	if profile == "skilled":
		start_t = sim.t
	var res := Planner.solve(b, hop, sim.frog_r, sim.frog_rel, start_t, minf(horizon + 30.0 if profile == "skilled" else horizon, 60.0), margin, 300000, true, sim.tun)
	var steps: Array = res["plan"]
	if steps.is_empty():
		return
	# only the first hop is kept for imperfect bots (they re-think after every landing)
	if profile != "skilled":
		steps = [steps[0]]
		steps[0] = [float(steps[0][0]) + rng.randf_range(-jitter, jitter), steps[0][1], steps[0][2], steps[0][3]]
		if steps[0][0] < sim.t:
			steps[0][0] = sim.t
	plan = steps
