extends RefCounted
## Swipe -> hop mapping (configurable, `hop_map` in the tuning data).
## A swipe is one of four axis directions.  A hop is one diagonal step on the isometric pyramid,
## written as [hx, hy]: hy = -1 hops UP a row (toward Miss Frogert), +1 hops DOWN;
## hx = -1 / +1 is the left / right neighbour cube in that row.
## Default is the NES-style rotated scheme:
##   swipe UP = up-right, RIGHT = down-right, DOWN = down-left, LEFT = up-left.
const NES := {"up": [1, -1], "right": [1, 1], "down": [-1, 1], "left": [-1, -1]}
const NAMES := ["up", "right", "down", "left"]        # index == Sim.Face
const SWIPES := {"up": Vector2i(0, -1), "right": Vector2i(1, 0), "down": Vector2i(0, 1), "left": Vector2i(-1, 0)}

static func name_of(dx: int, dy: int) -> String:
	if dy < 0: return "up"
	if dy > 0: return "down"
	return "right" if dx > 0 else "left"

static func hop_for_name(tun: Dictionary, name: String) -> Vector2i:
	var m: Dictionary = tun.get("hop_map", NES)
	var v: Array = m.get(name, NES[name])
	return Vector2i(int(v[0]), int(v[1]))

static func hop_for_swipe(tun: Dictionary, dx: int, dy: int) -> Vector2i:
	return hop_for_name(tun, name_of(dx, dy))

## [[swipe Vector2i, hop Vector2i], ...] in a fixed order (used by planner/bots)
static func all(tun: Dictionary) -> Array:
	var out: Array = []
	for n in NAMES:
		out.append([SWIPES[n], hop_for_name(tun, n)])
	return out

## neighbour cube index in the next row for a hop (cube indices are staggered by half a cube per row)
static func cube_step(h: Vector2i) -> int:
	return (h.x + h.y) / 2
