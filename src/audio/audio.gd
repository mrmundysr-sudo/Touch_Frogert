extends Node
## SFX bank + music. Streams are built lazily on a worker thread so startup stays fast on budget phones.
const Synth = preload("res://src/audio/synth.gd")
var sounds := {}
var players: Array = []
var pi := 0
var music_player: AudioStreamPlayer
var songs := {}
var muted := false
var thread: Thread
var ready_flag := false

func _ready() -> void:
	for i in 8:
		var p := AudioStreamPlayer.new()
		p.volume_db = -4.0
		add_child(p)
		players.append(p)
	music_player = AudioStreamPlayer.new()
	music_player.volume_db = -11.0
	add_child(music_player)
	thread = Thread.new()
	thread.start(_build)

func _build() -> void:
	var s := {}
	s["hop"] = Synth.stream(Synth.tone(300, 620, 0.09, 1, 0.4))
	s["land"] = Synth.stream(Synth.tone(160, 90, 0.05, 3, 0.18))
	s["bonk"] = Synth.stream(Synth.tone(120, 70, 0.1, 0, 0.3))
	s["turn"] = Synth.stream(Synth.tone(520, 560, 0.04, 4, 0.2))
	s["whiff"] = Synth.stream(Synth.tone(500, 900, 0.12, 4, 0.18))
	s["catch"] = Synth.seq([700, 1050, 1400], 0.05, 4)
	s["shoot"] = Synth.stream(Synth.tone(1400, 200, 0.2, 2, 0.28))
	s["barrier_down"] = Synth.stream(Synth.tone(300, 40, 0.35, 3, 0.45))
	s["fly_zap"] = Synth.stream(Synth.tone(900, 100, 0.2, 3, 0.3))
	s["float"] = Synth.seq([520, 660, 780], 0.05, 1)
	s["warn_red"] = Synth.seq([880, 0, 880], 0.07, 0)
	s["fuse"] = Synth.stream(Synth.tone(1500, 1500, 0.04, 4, 0.2))
	s["pop"] = Synth.stream(Synth.tone(900, 30, 0.6, 3, 0.55))
	s["splash"] = Synth.stream(Synth.tone(500, 90, 0.4, 3, 0.35))
	s["fell"] = Synth.stream(Synth.tone(700, 60, 0.7, 1, 0.35))
	s["buzz"] = Synth.stream(Synth.tone(180, 140, 0.45, 2, 0.35))
	s["win"] = Synth.seq([523, 659, 784, 1047, 784, 1047, 1318], 0.09, 0)
	s["extra_life"] = Synth.seq([784, 988, 1175, 1568, 1175, 1568, 1975], 0.07, 4)
	s["start"] = Synth.seq([392, 523, 659, 784], 0.07, 0)
	s["go"] = Synth.seq([784, 1047], 0.07, 0)
	s["blip"] = Synth.stream(Synth.tone(880, 1100, 0.05, 0, 0.2))
	s["game_over"] = Synth.seq([392, 349, 330, 262, 0, 196], 0.18, 5)
	s["crush"] = Synth.stream(Synth.tone(400, 100, 0.08, 3, 0.2))
	sounds = s
	# music: original bouncy tunes, composed for this game
	var C := 261.63; var D := 293.66; var E := 329.63; var G := 392.0; var A := 440.0; var Hc := 523.25; var Hd := 587.33; var He := 659.25; var Hg := 783.99
	var lead: Array = [[E,0.5],[G,0.5],[A,0.5],[G,0.5],[E,1],[D,1],[C,0.5],[D,0.5],[E,0.5],[G,0.5],[A,1],[Hc,1],
		[A,0.5],[G,0.5],[E,0.5],[D,0.5],[C,1],[0,1],[D,0.5],[E,0.5],[G,0.5],[A,0.5],[Hc,0.5],[Hd,0.5],[Hc,1],[G,1],
		[E,0.5],[G,0.5],[A,0.5],[Hc,0.5],[Hd,1],[He,1],[Hd,0.5],[Hc,0.5],[A,0.5],[G,0.5],[E,1],[C,1]]
	var bass: Array = []
	for rep in 4:
		for nb in [[C/2,1],[G/2,1],[A/2,1],[E/2,1]]:
			bass.append(nb)
	songs["play"] = Synth.song([{"notes": lead, "wave": 4, "vol": 0.16}, {"notes": bass, "wave": 5, "vol": 0.22, "gate": 0.6}], 150.0)
	var title: Array = [[Hc,0.5],[He,0.5],[Hg,0.5],[He,0.5],[Hc,1],[Hg,1],[A,0.5],[Hc,0.5],[He,0.5],[Hc,0.5],[A,1],[G,1],[0,1]]
	var tbass: Array = [[C/2,2],[G/2,2],[A/2,2],[E/2,2]]
	songs["title"] = Synth.song([{"notes": title, "wave": 4, "vol": 0.16}, {"notes": tbass, "wave": 5, "vol": 0.22, "gate": 0.6}], 132.0)
	ready_flag = true

func sfx(name: String) -> void:
	if muted or not ready_flag or not sounds.has(name):
		return
	var p: AudioStreamPlayer = players[pi]
	pi = (pi + 1) % players.size()
	p.stream = sounds[name]
	p.play()

func play_music(name: String) -> void:
	if muted or not ready_flag or not songs.has(name):
		return
	if music_player.stream == songs[name] and music_player.playing:
		return
	music_player.stream = songs[name]
	music_player.play()

func stop_music() -> void:
	if music_player:
		music_player.stop()

func _exit_tree() -> void:
	if thread and thread.is_started():
		thread.wait_to_finish()
