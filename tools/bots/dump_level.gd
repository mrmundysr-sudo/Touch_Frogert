extends SceneTree
const Tuning = preload("res://src/sim/tuning.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
func _init() -> void:
	var tun := Tuning.make()
	for lv in [1, 2, 5]:
		var l := LevelGen.generate(tun, lv, 0)
		print("LEVEL ", lv, " seed ", l["seed"], " flies ", l["flies"].size())
		for r in l["rows"]:
			var s := ""
			for c in r["slots"]:
				s += ".~ s#"[c] if c < 4 else "?"
			print("row %d w=%d L=%d v=%.2f %s [%s]" % [r["idx"], r["w"], r["L"], r["speed"], r["kind"], s])
	quit()
