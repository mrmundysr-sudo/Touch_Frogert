extends SceneTree
## Offline: find the first VALID attempt per level and write src/data/level_attempts.json
## Usage: godot --headless --path . -s res://tools/bots/gen_attempts.gd -- <last_level>
const Tuning = preload("res://src/sim/tuning.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var last := int(a[0]) if a.size() > 0 else 40
	var tun := Tuning.make()
	var out := {"_gen_hash": Tuning.gen_hash(tun)}
	for lv in range(1, last + 1):
		var l := LevelGen.generate_valid(tun, lv, 400)
		out[str(lv)] = int(l["attempt"])
		print("level %d attempt %d route %.2fs hops %s" % [lv, l["attempt"], l.get("route_time", -1.0), l.get("route_hops", 0)])
	var f := FileAccess.open("res://src/data/level_attempts.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "\t"))
	quit()
