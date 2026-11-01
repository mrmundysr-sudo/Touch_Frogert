extends RefCounted
## Procedural chip-style audio (adapted from the original project's synth). Everything is generated at runtime.
const RATE := 22050

static func tone(f0: float, f1: float, dur: float, wave := 0, vol := 0.3, attack := 40.0) -> PackedByteArray:
	var n := int(RATE * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in n:
		var k := float(i) / n
		phase += lerpf(f0, f1, k) / RATE
		var s := 0.0
		match wave:
			0: s = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			1: s = sin(phase * TAU)
			2: s = fmod(phase, 1.0) * 2.0 - 1.0
			3: s = rng.randf() * 2.0 - 1.0
			4: s = 1.0 if fmod(phase, 1.0) < 0.25 else -1.0          # thin pulse
			_: s = absf(fmod(phase, 1.0) * 4.0 - 2.0) - 1.0           # triangle
		var env := (1.0 - k) * minf(1.0, k * attack)
		data.encode_s16(i * 2, int(clampf(s * env * vol, -1.0, 1.0) * 32767.0))
	return data

static func stream(data: PackedByteArray, loop := false) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if loop:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_end = data.size() / 2
	return w

static func seq(freqs: Array, step_len: float, wave := 0, vol := 0.28) -> AudioStreamWAV:
	var d := PackedByteArray()
	for f in freqs:
		if float(f) <= 0.0:
			var silent := PackedByteArray()
			silent.resize(int(RATE * step_len) * 2)
			d.append_array(silent)
		else:
			d.append_array(tone(f, f, step_len, wave, vol))
	return stream(d)

## Mix several note tracks ([[freq, beats], ...] each) into one buffer. bpm sets the tempo.
static func song(tracks: Array, bpm: float, loop := true) -> AudioStreamWAV:
	var spb := 60.0 / bpm
	var total := 0.0
	for tr in tracks:
		var tt := 0.0
		for n in tr["notes"]:
			tt += float(n[1]) * spb
		total = maxf(total, tt)
	var samples := int(total * RATE)
	var mix := PackedFloat32Array()
	mix.resize(samples)
	for tr in tracks:
		var pos := 0.0
		for n in tr["notes"]:
			var dur: float = float(n[1]) * spb
			if float(n[0]) > 0.0:
				var nd := tone(n[0], n[0], dur * float(tr.get("gate", 0.9)), int(tr["wave"]), float(tr["vol"]), 80.0)
				var start := int(pos * RATE)
				for i in nd.size() / 2:
					if start + i < samples:
						mix[start + i] += float(nd.decode_s16(i * 2)) / 32767.0
			pos += dur
	var data := PackedByteArray()
	data.resize(samples * 2)
	for i in samples:
		data.encode_s16(i * 2, int(clampf(mix[i], -1.0, 1.0) * 32767.0))
	return stream(data, loop)
