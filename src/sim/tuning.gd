extends RefCounted
## All gameplay-tunable numbers live here so the dev panel, presets and bots share one source.
## Plain Dictionary on purpose: JSON-serialisable, copy-able, no class_name needed.

const DEFAULTS := {
	# movement
	"hop_time": 0.18,
	"hop_map": {"up": [1, -1], "right": [1, 1], "down": [-1, 1], "left": [-1, -1]},   # swipe -> [hx, hy] (NES rotated scheme)
	"buffer_time": 0.14,        # how long an early swipe/A press is remembered
	"speed_mul": 1.0,           # global conveyor speed multiplier
	"row_speed_adj": {},        # {"<row idx from top>": multiplier}
	# fly / projectile
	"fly_t1": 2.5, "fly_t2": 5.0, "fly_t3": 7.0,
	"range1": 1, "range2": 2, "range3": 3,
	"proj_speed": 18.0,         # spaces per second
	"fly_grow": 1.4, "fly_ripe": 8.0,
	"tongue_lock": 0.22,
	# level generation densities (0..1) -- level 1/2 hand-tuned, rest derived by ramps
	"water_density": 0.70, "pad_density": 0.25, "barrier_density": 0.10,
	"sink_frac": 0.0, "fly_density": 0.45,
	"speed_base": 0.5, "speed_per_level": 0.05, "speed_top_boost": 0.3, "speed_max": 2.4,
	"rows_base": 7, "levels_per_row": 4, "rows_max": 10,
	"water_ramp": 0.025, "barrier_ramp": 0.012, "sink_start_level": 3, "sink_ramp": 0.06,
	"sink_up": 3.0, "sink_warn": 0.9, "sink_down": 1.8,
	"time_limit": 90.0,
	"min_route_factor": 2.2,    # validator: shortest safe route must take >= factor * (rows-1) * hop_time
	"max_route_time": 40.0,     # validator: ...and <= this many seconds
	"route_margin": 0.10,       # validator: timing slack (s) every landing must tolerate
	# session / scoring
	"start_lives": 3, "bonus_first": 10000, "bonus_every": 25000,
	"pts_row": 10, "pts_level": 500, "pts_time": 10, "pts_catch": 100, "pts_barrier": 50, "pts_fly_kill": 150,
	# per-level overrides: {"1": {"water_density": 0.4}, ...}
	"level_overrides": {},
	"game_seed": 20251101,
}

static func make() -> Dictionary:
	return DEFAULTS.duplicate(true)

## Effective tuning for one level (applies hand-tuned overrides, then derives ramps).
static func for_level(t: Dictionary, level: int) -> Dictionary:
	var e: Dictionary = t.duplicate(true)
	var ov: Dictionary = t.get("level_overrides", {}).get(str(level), {})
	var d := float(level - 1)
	e["lvl_water"] = clampf(float(t["water_density"]) + float(t["water_ramp"]) * d, 0.1, 0.85)
	e["lvl_barrier"] = clampf(float(t["barrier_density"]) + float(t["barrier_ramp"]) * d, 0.0, 0.3)
	e["lvl_sink"] = clampf(float(t["sink_frac"]) + float(t["sink_ramp"]) * maxf(0.0, level - int(t["sink_start_level"]) + 1.0), 0.0, 0.6)
	e["lvl_speed"] = minf(float(t["speed_base"]) + float(t["speed_per_level"]) * d, float(t["speed_max"]))
	e["lvl_fly"] = float(t["fly_density"])
	e["lvl_rows"] = mini(int(t["rows_base"]) + int(d / maxf(1.0, float(t["levels_per_row"]))), int(t["rows_max"]))
	for k in ov:
		e[k] = ov[k]
	return e

static func to_json(t: Dictionary) -> String:
	return JSON.stringify(t, "\t")

static func from_json(s: String) -> Dictionary:
	var v = JSON.parse_string(s)
	var out := make()
	if v is Dictionary:
		for k in v:
			out[k] = v[k]
	return out

## Stable fingerprint of everything that influences level GENERATION (not live-tunables).
static func gen_hash(t: Dictionary) -> int:
	var keys := ["water_density","pad_density","barrier_density","sink_frac","fly_density","speed_base","speed_per_level","speed_top_boost","speed_max","rows_base","levels_per_row","rows_max","water_ramp","barrier_ramp","sink_start_level","sink_ramp","game_seed","level_overrides"]
	var s := ""
	for k in keys:
		s += str(k) + "=" + str(t.get(k)) + ";"
	return s.hash()
