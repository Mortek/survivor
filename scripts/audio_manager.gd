extends Node
## Synthesises all game sounds procedurally at startup — no audio files required.
## Registered as an Autoload in project.godot.

const RATE := 22050

var _players: Dictionary = {}

func _ready() -> void:
	_add("hit",           _sine(480.0,  0.07, 0.25, 6.0))
	_add("shoot",         _sine(900.0,  0.05, 0.18, 8.0))
	_add("melee",         _sine(220.0,  0.10, 0.30, 5.0))
	_add("coin",          _sine(1320.0, 0.06, 0.14, 5.0))
	_add("die",           _sweep(560.0,  160.0, 0.22, 0.38))
	_add("boss_die",      _sweep(280.0,   70.0, 0.55, 0.40))
	_add("levelup",       _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.11, 0.42))
	_add("lightning",     _lightning_sound())
	_add("explode",       _sweep(80.0,  30.0,  0.45, 0.55))
	_add("combo",         _arpeggio([659.25, 783.99, 1046.5, 1318.5], 0.06, 0.32))
	_add("achievement",   _arpeggio([523.25, 783.99, 1046.5, 1318.5, 1567.98], 0.09, 0.38))
	_add("curse_accept",  _curse_chord())
	_add("shield_break",  _sweep(1200.0, 400.0, 0.18, 0.30))
	_add("boss_music",    _boss_sting())

func play(sound: String) -> void:
	if _players.has(sound) and not _players[sound].playing:
		_players[sound].play()

func play_any(sound: String) -> void:
	if _players.has(sound):
		_players[sound].play()

# ── Private helpers ────────────────────────────────────────────────────────────
func _add(snd: String, wav: AudioStreamWAV) -> void:
	var p        := AudioStreamPlayer.new()
	p.stream     = wav
	p.volume_db  = -6.0
	add_child(p)
	_players[snd] = p

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var w        := AudioStreamWAV.new()
	w.format     = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate   = RATE
	w.data       = data
	return w

func _write_sample(d: PackedByteArray, i: int, value: float) -> void:
	var s     := clampi(int(value * 32767.0), -32768, 32767)
	d[i * 2]     = s & 0xFF
	d[i * 2 + 1] = (s >> 8) & 0xFF

func _sine(freq: float, dur: float, vol: float, decay: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var d := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		_write_sample(d, i, sin(TAU * freq * t) * vol * exp(-decay * t / maxf(dur, 0.001)))
	return _make_wav(d)

func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n   := int(RATE * dur)
	var inv := 1.0 / maxf(dur, 0.001)
	var d   := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t    := float(i) / RATE
		var freq := f0 + (f1 - f0) * (t * inv)
		_write_sample(d, i, sin(TAU * freq * t) * vol * (1.0 - t * inv))
	return _make_wav(d)

func _arpeggio(notes: Array, note_dur: float, vol: float) -> AudioStreamWAV:
	var n   := int(RATE * note_dur * notes.size())
	var inv := 1.0 / maxf(note_dur, 0.001)
	var d   := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t     := float(i) / RATE
		var idx   := mini(int(t * inv), notes.size() - 1)
		var local := fmod(t, note_dur)
		_write_sample(d, i, sin(TAU * notes[idx] * t) * vol * (1.0 - local * inv))
	return _make_wav(d)

## Electric crackle: noise burst with high-frequency component.
func _lightning_sound() -> AudioStreamWAV:
	var dur := 0.14
	var n   := int(RATE * dur)
	var d   := PackedByteArray(); d.resize(n * 2)
	var inv := 1.0 / maxf(dur, 0.001)
	for i in n:
		var t := float(i) / RATE
		# Mix a high sine with white noise
		var noise := randf_range(-1.0, 1.0) * 0.5
		var tone  := sin(TAU * 2200.0 * t) * 0.4
		_write_sample(d, i, (noise + tone) * 0.28 * (1.0 - t * inv))
	return _make_wav(d)

## Low boom for exploder death.
func _curse_chord() -> AudioStreamWAV:
	# Minor triad descending
	var notes := [261.63, 311.13, 369.99, 261.63]
	var dur   := 0.12
	var n     := int(RATE * dur * notes.size())
	var inv   := 1.0 / maxf(dur, 0.001)
	var d     := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t     := float(i) / RATE
		var idx   := mini(int((t * inv)), notes.size() - 1)
		var local := fmod(t, dur)
		var fade  := (1.0 - local * inv)
		_write_sample(d, i, sin(TAU * notes[idx] * t) * 0.35 * fade)
	return _make_wav(d)

## Short dramatic sting for boss wave.
func _boss_sting() -> AudioStreamWAV:
	var notes := [110.0, 87.31, 73.42, 65.41]
	var dur   := 0.18
	var n     := int(RATE * dur * notes.size())
	var inv   := 1.0 / maxf(dur, 0.001)
	var d     := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t   := float(i) / RATE
		var idx := mini(int(t * inv), notes.size() - 1)
		_write_sample(d, i, sin(TAU * notes[idx] * t) * 0.45 * (1.0 - fmod(t, dur) * inv))
	return _make_wav(d)
