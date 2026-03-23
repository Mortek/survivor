extends Node
## Synthesises all game sounds procedurally at startup — no audio files required.
## Registered as an Autoload in project.godot.

const RATE := 22050   # sample rate (Hz)

var _players: Dictionary = {}

func _ready() -> void:
	_add("hit",      _sine(480.0,  0.07, 0.25, 6.0))
	_add("shoot",    _sine(900.0,  0.05, 0.18, 8.0))
	_add("melee",    _sine(220.0,  0.10, 0.30, 5.0))
	_add("coin",     _sine(1320.0, 0.06, 0.14, 5.0))
	_add("die",      _sweep(560.0, 160.0, 0.22, 0.38))
	_add("boss_die", _sweep(280.0,  70.0, 0.55, 0.40))
	_add("levelup",  _arpeggio([523.25, 659.25, 783.99, 1046.5], 0.11, 0.42))

## Play a sound (won't re-trigger if already playing – good for rapid hits).
func play(sound: String) -> void:
	if _players.has(sound) and not _players[sound].playing:
		_players[sound].play()

## Play a sound regardless of current state (good for one-off events).
func play_any(sound: String) -> void:
	if _players.has(sound):
		_players[sound].play()

# ── Private helpers ────────────────────────────────────────────────────────────
func _add(snd: String, wav: AudioStreamWAV) -> void:
	var p := AudioStreamPlayer.new()
	p.stream    = wav
	p.volume_db = -6.0
	add_child(p)
	_players[snd] = p

func _make_wav(data: PackedByteArray) -> AudioStreamWAV:
	var w := AudioStreamWAV.new()
	w.format   = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.data     = data
	return w

## Write a single 16-bit PCM sample into a PackedByteArray at index i.
func _write_sample(d: PackedByteArray, i: int, value: float) -> void:
	var s := clampi(int(value * 32767.0), -32768, 32767)
	d[i * 2]     = s & 0xFF
	d[i * 2 + 1] = (s >> 8) & 0xFF

## Sine tone with exponential amplitude decay.
func _sine(freq: float, dur: float, vol: float, decay: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var d := PackedByteArray()
	d.resize(n * 2)
	for i in n:
		var t := float(i) / RATE
		_write_sample(d, i, sin(TAU * freq * t) * vol * exp(-decay * t / maxf(dur, 0.001)))
	return _make_wav(d)

## Frequency-swept sine (death / whoosh sounds).
func _sweep(f0: float, f1: float, dur: float, vol: float) -> AudioStreamWAV:
	var n   := int(RATE * dur)
	var inv := 1.0 / maxf(dur, 0.001)
	var d   := PackedByteArray(); d.resize(n * 2)
	for i in n:
		var t    := float(i) / RATE
		var freq := f0 + (f1 - f0) * (t * inv)
		_write_sample(d, i, sin(TAU * freq * t) * vol * (1.0 - t * inv))
	return _make_wav(d)

## Ascending arpeggio for level-up jingle.
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
