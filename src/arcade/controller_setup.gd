extends Control
## Controller setup + test screen for TouchArcade.
## Drag a region to move it, drag its corner handle to resize it. Handedness, defaults and a live test.
signal closed

const TouchArcadeC = preload("res://src/arcade/touch_arcade.gd")
var arcade: TouchArcadeC
var font: Font
var drag := {}          # touch index -> {name, mode:"move"/"size", off:Vector2}
var test_mode := false
var swipe_flash := {}   # dir text, time
var last_swipe := ""
var last_swipe_t := 0.0
var buttons: Array = []  # [{rect, label, id}]
const HANDLE := 54.0

func _ready() -> void:
	font = ThemeDB.fallback_font
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func open(a: TouchArcadeC) -> void:
	arcade = a
	arcade.enabled = false          # this screen handles raw touches itself
	arcade.clear_state()
	visible = true
	test_mode = false
	grab_focus()
	queue_redraw()

func close() -> void:
	arcade.enabled = true
	arcade.save_config()
	visible = false
	closed.emit()

func _layout_buttons() -> void:
	var s := size
	var w := s.x * 0.44
	var h := 78.0
	var y := s.y * 0.2
	buttons = [
		{"id": "hand", "label": "Layout: %s-HANDED" % arcade.handed.to_upper(), "rect": Rect2(s.x * 0.04, y, w, h)},
		{"id": "test", "label": "TEST MODE: %s" % ("ON" if test_mode else "OFF"), "rect": Rect2(s.x * 0.52, y, w, h)},
		{"id": "show", "label": "Show regions in game: %s" % ("ON" if arcade.show_regions else "OFF"), "rect": Rect2(s.x * 0.04, y + 92, w, h)},
		{"id": "reset", "label": "RESTORE DEFAULTS", "rect": Rect2(s.x * 0.52, y + 92, w, h)},
		{"id": "sens", "label": "Swipe length: %.1f%% (tap to change)" % (arcade.swipe_threshold * 100.0), "rect": Rect2(s.x * 0.04, y + 184, w, h)},
		{"id": "done", "label": "SAVE & BACK", "rect": Rect2(s.x * 0.52, y + 184, w, h)},
	]

func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventScreenTouch:
		_touch(ev.index, ev.position, ev.pressed)
	elif ev is InputEventScreenDrag:
		_drag(ev.index, ev.position)
	accept_event()

func _btn_at(p: Vector2) -> String:
	for b in buttons:
		if (b["rect"] as Rect2).has_point(p):
			return b["id"]
	return ""

func _touch(idx: int, p: Vector2, pressed: bool) -> void:
	if pressed:
		var bid := _btn_at(p)
		if bid != "":
			_press_button(bid)
			return
		# regions (topmost first)
		for i in range(arcade.actions.size() - 1, -1, -1):
			var n: String = arcade.actions[i]["name"]
			var r := arcade.region_px(n)
			if test_mode:
				if r.has_point(p):
					arcade.held[n] = true
					drag[idx] = {"name": n, "mode": "test"}
					return
				continue
			var handle := Rect2(r.end - Vector2(HANDLE, HANDLE), Vector2(HANDLE, HANDLE))
			if handle.grow(10).has_point(p):
				drag[idx] = {"name": n, "mode": "size", "off": r.end - p}
				return
			if r.has_point(p):
				drag[idx] = {"name": n, "mode": "move", "off": r.position - p}
				return
		# swipe tracking for the test display
		drag[idx] = {"name": "", "mode": "swipe", "start": p}
	else:
		if drag.has(idx):
			var d: Dictionary = drag[idx]
			if d["mode"] == "test":
				arcade.held[d["name"]] = false
			drag.erase(idx)
	queue_redraw()

func _drag(idx: int, p: Vector2) -> void:
	if not drag.has(idx):
		return
	var d: Dictionary = drag[idx]
	match d["mode"]:
		"move":
			var r := arcade.region_px(d["name"])
			arcade.set_region_px(d["name"], Rect2(p + (d["off"] as Vector2), r.size))
		"size":
			var r2 := arcade.region_px(d["name"])
			var end: Vector2 = p + (d["off"] as Vector2)
			arcade.set_region_px(d["name"], Rect2(r2.position, end - r2.position))
		"swipe":
			var v: Vector2 = p - (d["start"] as Vector2)
			var thr := arcade.swipe_threshold * minf(size.x, size.y)
			if v.length() >= thr:
				var ang := rad_to_deg(atan2(v.y, v.x))
				var names := {0: "RIGHT", 1: "DOWN-RIGHT", 2: "DOWN", 3: "DOWN-LEFT", 4: "LEFT", -4: "LEFT", -3: "UP-LEFT", -2: "UP", -1: "UP-RIGHT"}
				last_swipe = names[int(round(ang / 45.0))]
				last_swipe_t = 1.0
				d["start"] = p
	queue_redraw()

func _press_button(id: String) -> void:
	match id:
		"hand": arcade.set_handed("left" if arcade.handed == "right" else "right")
		"test": test_mode = not test_mode
		"show": arcade.show_regions = not arcade.show_regions
		"reset": arcade.restore_defaults()
		"sens":
			arcade.swipe_threshold = 0.03 if arcade.swipe_threshold >= 0.07 else arcade.swipe_threshold + 0.015
		"done": close(); return
	queue_redraw()

func _process(dt: float) -> void:
	if visible:
		last_swipe_t = maxf(0.0, last_swipe_t - dt)
		queue_redraw()

func _draw() -> void:
	if arcade == null:
		return
	_layout_buttons()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.05, 0.12, 0.96))
	draw_string(font, Vector2(0, size.y * 0.09), "CONTROLLER SETUP", HORIZONTAL_ALIGNMENT_CENTER, size.x, 44, Color("ffe14d"))
	var hint := "TEST MODE: touch A / B and swipe to check them" if test_mode else "Drag a box to move it. Drag its corner dot to resize."
	draw_string(font, Vector2(0, size.y * 0.09 + 40), hint, HORIZONTAL_ALIGNMENT_CENTER, size.x, 22, Color(0.8, 0.9, 1))
	for b in buttons:
		var r: Rect2 = b["rect"]
		draw_rect(r, Color("143a7a"))
		draw_rect(r, Color("7be8ff"), false, 2.0)
		draw_string(font, r.position + Vector2(0, r.size.y * 0.62), b["label"], HORIZONTAL_ALIGNMENT_CENTER, r.size.x, 20, Color.WHITE)
	for a in arcade.actions:
		var n: String = a["name"]
		var r2 := arcade.region_px(n)
		var held: bool = arcade.held.get(n, false)
		draw_rect(r2, Color(1, 0.8, 0.2, 0.55) if held else Color(0.2, 0.7, 1.0, 0.28))
		draw_rect(r2, Color("ffe14d"), false, 3.0)
		draw_string(font, r2.position + Vector2(0, r2.size.y * 0.5 - 4), n, HORIZONTAL_ALIGNMENT_CENTER, r2.size.x, 44, Color.WHITE)
		draw_string(font, r2.position + Vector2(0, r2.size.y * 0.5 + 24), a.get("label", ""), HORIZONTAL_ALIGNMENT_CENTER, r2.size.x, 18, Color(1, 1, 1, 0.8))
		if not test_mode:
			draw_circle(r2.end - Vector2(HANDLE * 0.5, HANDLE * 0.5), 16.0, Color("ffe14d"))
	# swipe test area
	var area := Rect2(size.x * 0.06, size.y * 0.52, size.x * 0.88, size.y * 0.16)
	draw_rect(area, Color(1, 1, 1, 0.06))
	draw_string(font, area.position + Vector2(0, area.size.y * 0.55), "SWIPE ANYWHERE: " + (last_swipe if last_swipe_t > 0.0 else "-"), HORIZONTAL_ALIGNMENT_CENTER, area.size.x, 30, Color("7be8ff") if last_swipe_t > 0.0 else Color(1, 1, 1, 0.35))
