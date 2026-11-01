extends SceneTree
## Prints every swipe the showcase script makes and where the frog is. Usage: -s res://tools/bots/demo_trace.gd
const Tuning = preload("res://src/sim/tuning.gd")
const SimC = preload("res://src/sim/sim.gd")
const Session = preload("res://src/sim/session.gd")
const DemoLevel = preload("res://src/sim/demo_level.gd")
func _init() -> void:
	var tun := Tuning.make()
	var sess := Session.make(tun)
	var sim := SimC.new(tun, sess)
	sim.start_level(1, 0, DemoLevel.make())
	var demo := DemoLevel.new()
	var last := ""
	for i in 60 * 16:
		demo.act(sim)
		sim.step(1.0 / 60.0)
		for ev in sim.events:
			if ev[0] in ["hop", "land", "die", "win"]:
				print("t=%5.2f %-5s row=%d cube=%d  %s" % [sim.t, ev[0], sim.frog_r + 1, sim.frog_cube(), demo.caption if ev[0] == "hop" else ""])
		sim.events.clear()
		if sim.finished_win:
			break
	quit()
