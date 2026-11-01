extends Node
## Touch Frogert -- application shell: state machine, fixed-step loop, input + audio wiring.
const Tuning = preload("res://src/sim/tuning.gd")
const SimC = preload("res://src/sim/sim.gd")
const Session = preload("res://src/sim/session.gd")
const LevelGen = preload("res://src/sim/level_gen.gd")
const GameView = preload("res://src/view/game_view.gd")
const TouchArcade = preload("res://src/arcade/touch_arcade.gd")
const AudioBank = preload("res://src/audio/audio.gd")
const Bot = preload("res://src/sim/bot.gd")
const Setup = preload("res://src/arcade/controller_setup.gd")

enum S { TITLE, PLAY }
const STEP := 1.0 / 60.0

var state := S.TITLE
var tun: Dictionary
var session: Dictionary
var sim: SimC
var view: GameView
var arcade: TouchArcade
var audio: AudioBank
var acc := 0.0
var hi_score := 0
var title_t := 0.0
var bot: Bot = null          # attract/autoplay driver
var autoplay := false
var setup: Setup
var setup_layer: CanvasLayer

func _ready() -> void:
	tun = Tuning.make()
	audio = AudioBank.new()
	add_child(audio)
	arcade = TouchArcade.new()
	add_child(arcade)
	arcade.setup("frogert", [{"name": "B", "label": "AIM"}, {"name": "A", "label": "TONGUE"}],
		{"A": Rect2(0.62, 0.84, 0.36, 0.15), "B": Rect2(0.28, 0.84, 0.32, 0.15)},
		[{"name": "AB", "actions": ["A", "B"], "window": 0.15}])
	arcade.swiped.connect(_on_swipe)
	arcade.action_pressed.connect(_on_action)
	add_child(arcade.make_overlay())
	view = GameView.new()
	add_child(view)
	setup_layer = CanvasLayer.new()
	setup_layer.layer = 100
	add_child(setup_layer)
	setup = Setup.new()
	setup.visible = false
	setup_layer.add_child(setup)
	setup.closed.connect(func(): title_t = 0.0)
	_load_hi()
	get_window().min_size = Vector2i(360, 640)
	if "--autoplay" in OS.get_cmdline_user_args():
		autoplay = true
		new_game()
		bot = Bot.new(OS.get_cmdline_user_args()[-1] if OS.get_cmdline_user_args().size() > 1 and OS.get_cmdline_user_args()[-1] != "--autoplay" else "average", 77)

func _load_hi() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://frogert.cfg") == OK:
		hi_score = int(cf.get_value("game", "hi", 0))

func new_game() -> void:
	session = Session.make(tun)
	start_level(1)
	state = S.PLAY
	audio.sfx("start")
	audio.play_music("play")

func start_level(lv: int) -> void:
	sim = SimC.new(tun, session)
	sim.start_level(lv, 0, LevelGen.for_game(tun, lv))
	view.sim = sim
	view.hi_score = hi_score

func open_setup() -> void:
	setup.open(arcade)

func _on_swipe(dx: int, dy: int) -> void:
	if state == S.TITLE:
		new_game()
		return
	sim.swipe(dx, dy, arcade.is_held("B"))

func _on_action(name: String) -> void:
	if state == S.TITLE:
		new_game()
		return
	if name == "A":
		sim.press_a()

func _unhandled_key_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F2 and not setup.visible:
		open_setup()

func _process(delta: float) -> void:
	if setup.visible:
		return
	if state == S.TITLE:
		title_t += delta
		view.time += delta
		queue_redraw_title()
		return
	acc += minf(delta, 0.1)
	while acc >= STEP:
		acc -= STEP
		if bot:
			bot.act(sim)
		sim.step(STEP)
		_handle_events()
		if sim.finished_win:
			session["level"] = int(session["level"]) + 1
			start_level(int(session["level"]))
		elif sim.finished_over:
			hi_score = maxi(hi_score, int(session["score"]))
			state = S.TITLE
			audio.stop_music()
			break
	view.update(delta)

func _handle_events() -> void:
	for ev in sim.events:
		view.on_event(ev)
		match ev[0]:
			"die":
				match ev[1]:
					"pop": audio.sfx("pop")
					"fell": audio.sfx("fell")
					"fly": audio.sfx("buzz")
					_: audio.sfx("splash")
			"game_over": audio.sfx("game_over")
			"warn_fuse": audio.sfx("warn_red")
			_: audio.sfx(ev[0])
	sim.events.clear()

func queue_redraw_title() -> void:
	view.sim = null
	view.queue_redraw()
	if not has_node("TitleLabel"):
		var l := Label.new()
		l.name = "TitleLabel"
		l.text = "TOUCH FROGERT\n\nSwipe to start"
		var btn := Button.new()
		btn.text = "CONTROLS"
		btn.add_theme_font_size_override("font_size", 34)
		btn.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
		btn.position = Vector2(-110, -200)
		btn.custom_minimum_size = Vector2(220, 80)
		btn.pressed.connect(open_setup)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_font_size_override("font_size", 56)
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var cl := CanvasLayer.new()
		cl.name = "TitleLabel"
		cl.add_child(l)
		cl.add_child(btn)
		add_child(cl)
