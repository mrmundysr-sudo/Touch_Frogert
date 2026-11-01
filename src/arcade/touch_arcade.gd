extends Node
## TouchArcade: reusable invisible touch controller for Touch Arcade games.
##  * Directional swipes (8-way) anywhere outside the action regions.
##  * Up to N invisible, user-movable/resizable action regions (Frogert uses two: A and B).
##  * Real multitouch: every finger is tracked independently by touch index.
##  * Hold actions (is_held), tap actions (action_pressed) and configurable combos.
##  * Left/right-handed layouts, per-game saved config, restore defaults.
## Nothing is drawn unless show_regions is on (setup/test screens or the optional overlay).

signal swiped(dx: int, dy: int)                 # dx,dy in {-1,0,1}; dy=-1 is UP
signal action_pressed(action: String)
signal action_released(action: String)
signal combo(combo_name: String)

var game_id := "game"
var actions: Array = []            # [{name, label}]  order = draw order
var default_regions := {}          # name -> Rect2 (normalised 0..1, right-handed)
var regions := {}                  # name -> Rect2 (normalised, current)
var combos: Array = []             # [{name, actions:[..], window:float}]
var handed := "right"
var swipe_threshold := 0.045       # fraction of the shorter screen side
var show_regions := false
var enabled := true
var held := {}
var last_press_time := {}
var touches := {}                  # index -> {kind, action, start, last}
var key_dirs := {}
var min_region := Vector2(0.14, 0.08)
var overlay_ctl: Control = null

func setup(id: String, action_defs: Array, defaults: Dictionary, combo_defs: Array = []) -> void:
	game_id = id
	actions = action_defs
	default_regions = defaults
	combos = combo_defs
	regions = defaults.duplicate()
	for a in actions:
		held[a["name"]] = false
	load_config()

# ------------------------------------------------------------------ config

func _cfg_path() -> String:
	return "user://touch_arcade_%s.cfg" % game_id

func save_config() -> void:
	var cf := ConfigFile.new()
	cf.set_value("layout", "handed", handed)
	cf.set_value("layout", "threshold", swipe_threshold)
	cf.set_value("layout", "show_regions", show_regions)
	for n in regions:
		var r: Rect2 = regions[n]
		cf.set_value("regions", n, [r.position.x, r.position.y, r.size.x, r.size.y])
	cf.save(_cfg_path())

func load_config() -> void:
	var cf := ConfigFile.new()
	if cf.load(_cfg_path()) != OK:
		return
	handed = cf.get_value("layout", "handed", "right")
	swipe_threshold = float(cf.get_value("layout", "threshold", 0.045))
	show_regions = bool(cf.get_value("layout", "show_regions", false))
	for n in regions.keys():
		var v = cf.get_value("regions", n, null)
		if v is Array and v.size() == 4:
			regions[n] = Rect2(v[0], v[1], v[2], v[3])

func restore_defaults() -> void:
	regions = default_regions.duplicate()
	handed = "right"
	swipe_threshold = 0.045
	save_config()

## Mirror the layout for left/right-handed play.
func set_handed(h: String) -> void:
	if h == handed:
		return
	handed = h
	for n in regions:
		var r: Rect2 = regions[n]
		regions[n] = Rect2(1.0 - r.position.x - r.size.x, r.position.y, r.size.x, r.size.y)
	save_config()

var view_size_override := Vector2.ZERO   # tests / headless
func _vsize() -> Vector2:
	if view_size_override != Vector2.ZERO:
		return view_size_override
	return get_viewport().get_visible_rect().size

func region_px(name: String) -> Rect2:
	var s := _vsize()
	var r: Rect2 = regions[name]
	return Rect2(r.position.x * s.x, r.position.y * s.y, r.size.x * s.x, r.size.y * s.y)

func set_region_px(name: String, px: Rect2) -> void:
	var s := _vsize()
	var minpx := Vector2(min_region.x * s.x, min_region.y * s.y)
	var w := clampf(px.size.x, minpx.x, s.x)
	var h := clampf(px.size.y, minpx.y, s.y)
	var x := clampf(px.position.x, 0.0, s.x - w)
	var y := clampf(px.position.y, 0.0, s.y - h)
	regions[name] = Rect2(x / s.x, y / s.y, w / s.x, h / s.y)

## Optional thin outlines drawn by a CanvasLayer overlay (off by default: no buttons cover the screen).
func make_overlay() -> CanvasLayer:
	var cl := CanvasLayer.new()
	cl.layer = 50
	var c := Control.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		if not show_regions:
			return
		for a in actions:
			var r := region_px(a["name"])
			c.draw_rect(r, Color(1, 1, 1, 0.07 if not held.get(a["name"], false) else 0.25))
			c.draw_rect(r, Color(1, 1, 1, 0.35), false, 2.0)
			c.draw_string(ThemeDB.fallback_font, r.position + Vector2(0, r.size.y * 0.6), a["name"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 36, Color(1, 1, 1, 0.5)))
	cl.add_child(c)
	overlay_ctl = c
	return cl

func _process(_dt: float) -> void:
	if show_regions and overlay_ctl != null:
		overlay_ctl.queue_redraw()

func is_held(name: String) -> bool:
	return held.get(name, false)

func clear_state() -> void:
	touches.clear()
	for k in held.keys():
		if held[k]:
			held[k] = false
			action_released.emit(k)

# ------------------------------------------------------------------ input

func _action_at(p: Vector2) -> String:
	for i in range(actions.size() - 1, -1, -1):
		var n: String = actions[i]["name"]
		if region_px(n).has_point(p):
			return n
	return ""

func _input(ev: InputEvent) -> void:
	if not enabled:
		return
	if ev is InputEventScreenTouch:
		if ev.pressed:
			var a := _action_at(ev.position)
			if a != "":
				touches[ev.index] = {"kind": "action", "action": a, "start": ev.position, "last": ev.position}
				_press(a)
			else:
				touches[ev.index] = {"kind": "swipe", "action": "", "start": ev.position, "last": ev.position}
		else:
			if touches.has(ev.index):
				var t: Dictionary = touches[ev.index]
				if t["kind"] == "action":
					_release(t["action"])
				touches.erase(ev.index)
	elif ev is InputEventScreenDrag:
		if touches.has(ev.index):
			var t: Dictionary = touches[ev.index]
			t["last"] = ev.position
			if t["kind"] == "swipe":
				_check_swipe(t)
	elif ev is InputEventKey and not ev.echo:
		_key(ev)

func _check_swipe(t: Dictionary) -> void:
	var s := _vsize()
	var thr := swipe_threshold * minf(s.x, s.y)
	var d: Vector2 = t["last"] - t["start"]
	if d.length() < thr:
		return
	var ang := rad_to_deg(atan2(d.y, d.x))          # 0 = right, 90 = down (screen coords)
	var sector := int(round(ang / 45.0))             # -4..4
	var dx := 0
	var dy := 0
	match sector:
		0: dx = 1
		1: dx = 1; dy = 1
		2: dy = 1
		3: dx = -1; dy = 1
		4, -4: dx = -1
		-3: dx = -1; dy = -1
		-2: dy = -1
		-1: dx = 1; dy = -1
	t["start"] = t["last"]        # re-anchor: a continuing drag can chain another hop
	swiped.emit(dx, dy)

func _press(name: String) -> void:
	if held.get(name, false):
		return
	held[name] = true
	var now := Time.get_ticks_msec() / 1000.0
	last_press_time[name] = now
	action_pressed.emit(name)
	for c in combos:
		if name in c["actions"]:
			var ok := true
			for other in c["actions"]:
				if not held.get(other, false) or now - float(last_press_time.get(other, -9.0)) > float(c["window"]):
					ok = false
			if ok:
				combo.emit(c["name"])

func _release(name: String) -> void:
	if not held.get(name, false):
		return
	held[name] = false
	action_released.emit(name)

# desktop keyboard (testing): arrows/WASD + QEZC diagonals, Space/J = A, Shift/K = B
func _key(ev: InputEventKey) -> void:
	var k: int = ev.physical_keycode
	if ev.pressed:
		var d := Vector2i.ZERO
		match k:
			KEY_UP, KEY_W: d = Vector2i(0, -1)
			KEY_DOWN, KEY_S: d = Vector2i(0, 1)
			KEY_LEFT, KEY_A: d = Vector2i(-1, 0)
			KEY_RIGHT, KEY_D: d = Vector2i(1, 0)
			KEY_Q: d = Vector2i(-1, -1)
			KEY_E: d = Vector2i(1, -1)
			KEY_Z: d = Vector2i(-1, 1)
			KEY_C: d = Vector2i(1, 1)
		if d != Vector2i.ZERO:
			swiped.emit(d.x, d.y)
			return
	var act := ""
	match k:
		KEY_SPACE, KEY_J: act = "A"
		KEY_SHIFT, KEY_K: act = "B"
	if act != "" and held.has(act):
		if ev.pressed:
			_press(act)
		else:
			_release(act)
