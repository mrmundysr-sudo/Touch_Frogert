extends RefCounted
## Deterministic board model: conveyor rows, slot contents, flies.
## Shared by the live Sim, the level validator and every bot, so they all agree exactly.
##
## Coordinates: row 0 is the SUMMIT (row numbers grow downward). Each row is a ring of L slots
## (L >= visible width w). A slot k of row r has centre ring-position k+0.5; the ring slides by
## raw(r,t) = phase + speed*t. Local x in [0,w] is the visible window; leaving it = falling off.
## "rel" = frog x relative to the ring (constant while riding), so world-local x = rel + raw(r,t).

const WATER := 0
const PAD := 1
const SINK := 2
const BARRIER := 3
const NO_FLY := 0
const GROW := 1
const RIPE := 2
# landing results
const R_OK := 0
const R_FELL := 1
const R_DROWN := 2
const R_FLY := 3
const R_FLOAT := 4

var n := 0
var w := PackedInt32Array()
var L := PackedInt32Array()
var speed := PackedFloat64Array()
var phase := PackedFloat64Array()
var slots: Array = []     # PackedInt32Array per row (mutable: destroyed barriers become PAD)
var sinkph: Array = []    # PackedFloat64Array per row
var flies: Array = []     # {r,k,period,start,grow,ripe,consumed}
var fly_idx := {}
var sink_up := 3.0
var sink_warn := 0.9
var sink_down := 1.8
var base_speed := PackedFloat64Array()

func load_level(lv: Dictionary, tun: Dictionary) -> void:
	n = lv["n_rows"]
	w.resize(n); L.resize(n); speed.resize(n); phase.resize(n); base_speed.resize(n)
	slots.clear(); sinkph.clear(); flies.clear(); fly_idx.clear()
	sink_up = float(tun.get("sink_up", 3.0)); sink_warn = float(tun.get("sink_warn", 0.9)); sink_down = float(tun.get("sink_down", 1.8))
	for r in n:
		var row: Dictionary = lv["rows"][r]
		w[r] = row["w"]; L[r] = row["L"]
		base_speed[r] = row["speed"]
		phase[r] = row["phase"]
		slots.append(PackedInt32Array(row["slots"]))
		sinkph.append(PackedFloat64Array(row["sinkph"]))
	for f in lv["flies"]:
		var d: Dictionary = f.duplicate()
		d["consumed"] = -1
		fly_idx[int(d["r"]) * 64 + int(d["k"])] = flies.size()
		flies.append(d)
	apply_speeds(tun, 0.0)

## Recompute effective speeds from tuning; keeps ring positions continuous at time t.
func apply_speeds(tun: Dictionary, t: float) -> void:
	var gm := float(tun.get("speed_mul", 1.0))
	var adj: Dictionary = tun.get("row_speed_adj", {})
	for r in n:
		var old_raw := phase[r] + speed[r] * t
		var s := base_speed[r] * gm * float(adj.get(str(r), 1.0))
		if r == 0 or r == n - 1:
			s = 0.0
		speed[r] = s
		phase[r] = old_raw - s * t

static func start_rel(width: int) -> float:
	return floorf(float(width) * 0.5) + 0.5

func raw(r: int, t: float) -> float:
	return phase[r] + speed[r] * t

func slot_of_rel(r: int, rel: float) -> int:
	return int(floor(fposmod(rel, float(L[r]))))

func content(r: int, k: int, t: float) -> int:
	var b: int = slots[r][k]
	if b == SINK:
		var p := fposmod(t + sinkph[r][k], sink_up + sink_warn + sink_down)
		return PAD if p < sink_up + sink_warn else WATER
	return b

## 0..1 wobble intensity while a sinking pad is about to go under (0 otherwise)
func sink_warning(r: int, k: int, t: float) -> float:
	if slots[r][k] != SINK:
		return 0.0
	var p := fposmod(t + sinkph[r][k], sink_up + sink_warn + sink_down)
	if p >= sink_up and p < sink_up + sink_warn:
		return (p - sink_up) / sink_warn
	return 0.0

func fly_state(fi: int, t: float) -> int:
	var f: Dictionary = flies[fi]
	var c: float = t - float(f["start"])
	if c < 0.0:
		return NO_FLY
	var cyc := int(floor(c / float(f["period"])))
	if cyc == int(f["consumed"]):
		return NO_FLY
	var cp: float = c - cyc * float(f["period"])
	if cp < float(f["grow"]):
		return GROW
	if cp < float(f["grow"]) + float(f["ripe"]):
		return RIPE
	return NO_FLY

func fly_progress(fi: int, t: float) -> float:
	var f: Dictionary = flies[fi]
	var c: float = t - float(f["start"])
	var cp: float = c - floor(c / float(f["period"])) * float(f["period"])
	return clampf(cp / float(f["grow"]), 0.0, 1.0)

func consume_fly(fi: int, t: float) -> void:
	var f: Dictionary = flies[fi]
	f["consumed"] = int(floor((t - float(f["start"])) / float(f["period"])))

func fly_at(r: int, k: int) -> int:
	return fly_idx.get(r * 64 + k, -1)

## Plan a hop (4-way: dy=-1 up, dy=+1 down, dx=-1/+1 sideways along the row). Returns [status, row2, rel2, slot2]; status 0 = go, 1 = blocked (barrier), 2 = no such row.
## bias: for vertical hops, the aim point is shifted this many cells toward the frog's preferred side.
func plan_hop(r: int, rel: float, dx: int, dy: int, t: float, hop: float, bias: float = 0.0) -> PackedFloat64Array:
	var tl := t + hop
	if dy == 0:
		var rel2 := rel + float(dx)
		var k2 := slot_of_rel(r, rel2)
		if slots[r][k2] == BARRIER:
			return PackedFloat64Array([1.0, r, rel2, k2])
		return PackedFloat64Array([0.0, r, rel2, k2])
	var r2 := r + dy
	if r2 < 0 or r2 >= n:
		return PackedFloat64Array([2.0, r, rel, 0])
	var wx0 := rel + raw(r, t) - float(w[r]) * 0.5
	var xa := wx0 + bias + float(w[r2]) * 0.5
	var u := fposmod(xa - raw(r2, tl), float(L[r2]))
	var k2 := int(floor(u))
	var xl := xa + (0.5 - (u - float(k2)))
	var rel2 := xl - raw(r2, tl)
	if xl >= 0.0 and xl <= float(w[r2]) and slots[r2][k2] == BARRIER:
		return PackedFloat64Array([1.0, r2, rel2, k2])
	return PackedFloat64Array([0.0, r2, rel2, k2])

## What happens to a frog that lands/stands at (r, rel) at time t.
func landing_result(r: int, rel: float, t: float, carrying: bool) -> int:
	var x := rel + raw(r, t)
	if x < 0.0 or x > float(w[r]):
		return R_FELL
	var k := slot_of_rel(r, rel)
	var fi := fly_idx.get(r * 64 + k, -1) as int
	if fi >= 0 and fly_state(fi, t) == RIPE:
		return R_FLY
	if content(r, k, t) == WATER:
		return R_FLOAT if carrying else R_DROWN
	return R_OK

func local_x(r: int, rel: float, t: float) -> float:
	return rel + raw(r, t)

func world_x(r: int, rel: float, t: float) -> float:
	return rel + raw(r, t) - float(w[r]) * 0.5
