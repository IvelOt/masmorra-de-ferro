class_name Sfx
extends Node
## Sons procedurais (PCM 16 bits, 22050 Hz, mono), gerados em memória: portas
## (M2), combate do jogador (2D), inimigos (streams tocados em 3D pelo EnemyView),
## itens, progressão, automapa e terminais (M5/M6).
## Com o driver de áudio dummy do headless, tocar é inofensivo.

const MIX_RATE: int = 22050

const ENEMY_SOUNDS: Array[String] = ["hit_flesh", "rat_windup", "skel_windup", "guard_windup", "enemy_death"]

var _players: Dictionary = {}
var _streams: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _ready() -> void:
	_rng.seed = 4242
	_players["door_open"] = _make_player(_door_open())
	_players["door_bump"] = _make_player(_door_bump())
	_players["swing"] = _make_player(_swing())
	_players["block"] = _make_player(_block())
	_players["guard_break"] = _make_player(_guard_break())
	_players["player_hurt"] = _make_player(_player_hurt())
	_players["pickup_item"] = _make_player(_pickup_item())
	_players["pickup_key"] = _make_player(_arpeggio([523.0, 659.0, 784.0], 0.10, true))
	_players["pickup_gold"] = _make_player(_pickup_gold())
	_players["quaff"] = _make_player(_quaff())
	_players["door_unlock"] = _make_player(_door_unlock())
	_players["level_up"] = _make_player(_level_up())
	_players["automap_toggle"] = _make_player(_paper())
	_players["escape"] = _make_player(_arpeggio([523.0, 659.0, 784.0, 1047.0], 0.12, false))
	_players["death"] = _make_player(_sweep(330.0, 55.0, 0.8, 0.4))
	_players["timeout"] = _make_player(_beeps())
	_streams["hit_flesh"] = _hit_flesh()
	_streams["rat_windup"] = _tone(1200.0, 0.08, 0.5)
	_streams["skel_windup"] = _rattle()
	_streams["guard_windup"] = _tone(70.0, 0.30, 0.8)
	_streams["enemy_death"] = _enemy_death()


## Sons do jogador (AudioStreamPlayer 2D).
func play(id: String) -> void:
	var p: AudioStreamPlayer = _players.get(id)
	if p != null:
		p.play()


## Stream de um som de inimigo, para um AudioStreamPlayer3D preso ao nó.
func stream(id: String) -> AudioStream:
	return _streams.get(id)


func _noise() -> float:
	return _rng.randf_range(-1.0, 1.0)


## 0,15 s de ruído com passa-baixa móvel (400 -> 3000 Hz) e envelope em sino.
func _swing() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.15)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var y: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		var fc: float = lerpf(400.0, 3000.0, t)
		var a: float = 1.0 - exp(-TAU * fc / MIX_RATE)
		y += a * (_noise() - y)
		samples[i] = clampf(y * 1.6 * sin(PI * t), -1.0, 1.0)
	return _wav(samples)


## 0,10 s: seno de 90 Hz com decaimento rápido + 20% de ruído.
func _hit_flesh() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.10)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var t: float = float(i) / float(n)
		var v: float = 0.8 * sin(TAU * 90.0 * float(i) / MIX_RATE) + 0.2 * _noise()
		samples[i] = clampf(v * exp(-6.0 * t), -1.0, 1.0)
	return _wav(samples)


## 0,12 s: quadradas de 880 + 1320 Hz com decaimento exponencial (tau = 30 ms).
func _block() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.12)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var ts: float = float(i) / MIX_RATE
		var a: float = 1.0 if fmod(880.0 * ts, 1.0) < 0.5 else -1.0
		var b: float = 1.0 if fmod(1320.0 * ts, 1.0) < 0.5 else -1.0
		samples[i] = 0.3 * (a + b) * exp(-ts / 0.03)
	return _wav(samples)


## 0,30 s: varredura descendente 440 -> 110 Hz em dente de serra.
func _guard_break() -> AudioStreamWAV:
	return _sweep(440.0, 110.0, 0.30, 0.0)


## 0,12 s: ruído com passa-baixa em 800 Hz.
func _player_hurt() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.12)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var a: float = 1.0 - exp(-TAU * 800.0 / MIX_RATE)
	var y: float = 0.0
	for i in range(n):
		y += a * (_noise() - y)
		samples[i] = clampf(y * 2.5 * (1.0 - float(i) / float(n)), -1.0, 1.0)
	return _wav(samples)


## 3 pulsos de ruído de 20 ms (chocalho do esqueleto).
func _rattle() -> AudioStreamWAV:
	var pulse: int = int(MIX_RATE * 0.02)
	var n: int = pulse * 5
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var k: int = i / pulse
		samples[i] = 0.7 * _noise() if k % 2 == 0 else 0.0
	return _wav(samples)


## 0,25 s: varredura 300 -> 60 Hz + ruído decrescente.
func _enemy_death() -> AudioStreamWAV:
	return _sweep(300.0, 60.0, 0.25, 0.3)


func _tone(freq: float, dur: float, amp: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var t: float = float(i) / float(n)
		samples[i] = amp * sin(TAU * freq * float(i) / MIX_RATE) * sin(PI * t)
	return _wav(samples)


## Dente de serra com frequência linear f0 -> f1; noise_amp de ruído decrescente.
func _sweep(f0: float, f1: float, dur: float, noise_amp: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		phase = fmod(phase + lerpf(f0, f1, t) / MIX_RATE, 1.0)
		var v: float = 0.6 * (2.0 * phase - 1.0) + noise_amp * _noise() * (1.0 - t)
		samples[i] = clampf(v * (1.0 - t), -1.0, 1.0)
	return _wav(samples)


## 0,12 s: seno de 660 Hz por 50 ms e depois 990 Hz, decaimento linear.
func _pickup_item() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.12)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var ts: float = float(i) / MIX_RATE
		phase += (660.0 if ts < 0.05 else 990.0) / MIX_RATE
		samples[i] = 0.5 * sin(TAU * phase) * (1.0 - float(i) / float(n))
	return _wav(samples)


## Notas em sequência; quadrada a 30% ou seno, cada uma com decaimento curto.
func _arpeggio(freqs: Array[float], note_s: float, square: bool) -> AudioStreamWAV:
	var per: int = int(MIX_RATE * note_s)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(per * freqs.size())
	for k in range(freqs.size()):
		for i in range(per):
			var ph: float = fmod(freqs[k] * float(i) / MIX_RATE, 1.0)
			var v: float = (1.0 if ph < 0.3 else -1.0) * 0.35 if square else 0.5 * sin(TAU * ph)
			samples[k * per + i] = v * (1.0 - 0.6 * float(i) / float(per))
	return _wav(samples)


## 0,15 s: 1568 Hz + 2093 Hz com decaimento exponencial (tau = 25 ms).
func _pickup_gold() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.15)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var ts: float = float(i) / MIX_RATE
		samples[i] = 0.35 * (sin(TAU * 1568.0 * ts) + sin(TAU * 2093.0 * ts)) * exp(-ts / 0.025)
	return _wav(samples)


## 0,25 s: 3 pulsos de ruído de 60 ms com passa-baixa em 300 Hz ("gole").
func _quaff() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.25)
	var pulse: int = int(MIX_RATE * 0.06)
	var gap: int = int(MIX_RATE * 0.0333)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var a: float = 1.0 - exp(-TAU * 300.0 / MIX_RATE)
	var y: float = 0.0
	for i in range(n):
		var k: int = i % (pulse + gap)
		y += a * (_noise() - y)
		var env: float = sin(PI * float(k) / float(pulse)) if k < pulse else 0.0
		samples[i] = clampf(y * 6.0 * env, -1.0, 1.0)
	return _wav(samples)


## 20 ms de ruído (clique) + varredura 200 -> 120 Hz por 0,3 s.
func _door_unlock() -> AudioStreamWAV:
	var click: int = int(MIX_RATE * 0.02)
	var tail: AudioStreamWAV = _sweep(200.0, 120.0, 0.3, 0.0)
	var n: int = click + tail.data.size() / 2
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(click):
		samples[i] = 0.8 * _noise() * (1.0 - float(i) / float(click))
	for i in range(tail.data.size() / 2):
		samples[click + i] = float(tail.data.decode_s16(i * 2)) / 32767.0
	return _wav(samples)


## 0,45 s: varredura quadrada 440 -> 880 Hz com trêmolo de 12 Hz.
func _level_up() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.45)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		phase = fmod(phase + lerpf(440.0, 880.0, t) / MIX_RATE, 1.0)
		var trem: float = 0.6 + 0.4 * sin(TAU * 12.0 * float(i) / MIX_RATE)
		samples[i] = (0.35 if phase < 0.5 else -0.35) * trem * (1.0 - 0.5 * t)
	return _wav(samples)


## 0,08 s de ruído com passa-alta em 2 kHz (papel).
func _paper() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.08)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var a: float = 1.0 - exp(-TAU * 2000.0 / MIX_RATE)
	var lp: float = 0.0
	for i in range(n):
		var x: float = _noise()
		lp += a * (x - lp)
		samples[i] = clampf((x - lp) * 0.7 * sin(PI * float(i) / float(n)), -1.0, 1.0)
	return _wav(samples)


## 3 bipes de 440 Hz, 100 ms com 100 ms de pausa.
func _beeps() -> AudioStreamWAV:
	var per: int = int(MIX_RATE * 0.1)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(per * 5)
	for i in range(per * 5):
		samples[i] = 0.5 * sin(TAU * 440.0 * float(i) / MIX_RATE) if (i / per) % 2 == 0 else 0.0
	return _wav(samples)


func _make_player(stream: AudioStreamWAV) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## 0,25 s de ruído filtrado (passa-baixa de um polo) com envelope decrescente.
func _door_open() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.25)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = 12345
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	var y: float = 0.0
	for i in range(n):
		var t: float = float(i) / float(n)
		y += 0.08 * (rng.randf_range(-1.0, 1.0) - y)
		var creak: float = 0.5 + 0.5 * sin(TAU * 38.0 * float(i) / MIX_RATE)
		samples[i] = clampf(y * 4.0 * creak * (1.0 - t), -1.0, 1.0)
	return _wav(samples)


## 0,08 s de onda quadrada de 110 Hz com decaimento.
func _door_bump() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.08)
	var samples: PackedFloat32Array = PackedFloat32Array()
	samples.resize(n)
	for i in range(n):
		var phase: float = fmod(110.0 * float(i) / MIX_RATE, 1.0)
		var sq: float = 1.0 if phase < 0.5 else -1.0
		samples[i] = sq * 0.6 * exp(-5.0 * float(i) / float(n))
	return _wav(samples)


func _wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(samples[i] * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w
