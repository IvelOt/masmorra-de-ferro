class_name AudioView
extends Node
## Áudio procedural (só apresentação, fora do hash). Sem arquivos de áudio:
## AudioStreamWAV 16 bits mono 22050 Hz gerados em memória no _ready().

const RATE: int = 22050
const STEP_SPEED: int = 40       # u/tick
const STEP_INTERVAL: int = 27    # ticks (~0,45 s)
## Pico máximo dos sons de progressão (UI-7).
const PEAK_MAX: float = 0.85
## Sons de M5/M6 (plano da iteração 4 §4.6).
const PROGRESS_SOUNDS: Array = ["pick_potion", "pick_gold", "pick_key", "quaff", "unlock",
	"level_up", "paper", "end_ESCAPED", "end_DEAD", "end_TIMEOUT"]

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _step_player: AudioStreamPlayer = null
var _door_player: AudioStreamPlayer = null
var _thunk_player: AudioStreamPlayer = null
var _amb_player: AudioStreamPlayer = null
## Sons de combate (2D) e de inimigos (tocados em 3D pelo EnemyView), por nome.
var _streams: Dictionary = {}
var _combat_players: Dictionary = {}
var _step_counter: int = 0
var _step_alt: bool = false


func _ready() -> void:
	_rng.seed = 12345
	_ensure_bus("SFX")
	_ensure_bus("Ambience")
	_step_player = _make_player(_gen_step(), "SFX", -6.0)
	_door_player = _make_player(_gen_door(), "SFX", -4.0)
	_thunk_player = _make_player(_gen_thunk(), "SFX", -6.0)
	var amb: AudioStreamWAV = _gen_ambience()
	amb.loop_mode = AudioStreamWAV.LOOP_FORWARD
	amb.loop_begin = 0
	amb.loop_end = RATE * 4
	_amb_player = _make_player(amb, "Ambience", -30.0)
	# Começa depois de alguns quadros: um --quit no 1º quadro não deixa playback vivo
	# (evita o aviso de ObjectDB vazado na checagem de sintaxe).
	get_tree().create_timer(0.25).timeout.connect(_amb_player.play)
	_build_combat_streams()
	for n: String in ["whoosh", "clang", "guard_break", "grunt", "puff"]:
		_combat_players[n] = _make_player(_streams[n], "SFX", -6.0)
	_build_progress_streams()
	for n: String in PROGRESS_SOUNDS:
		_combat_players[n] = _make_player(_streams[n], "SFX", -6.0)


## Stream por nome (usado pelo EnemyView para os players 3D). null se não existe.
func get_stream(stream_name: String) -> AudioStream:
	return _streams.get(stream_name, null)


## Sons 2D do jogador a partir dos eventos de HudDaggerfall.events().
func on_combat(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	if ev["swing_start"]:
		_play2d("whoosh")
	if ev["guard_break"]:
		_play2d("guard_break")
	elif ev["blocked"]:
		_play2d("clang")
	if ev["hurt"]:
		_play2d("grunt")
	if ev["no_stamina"]:
		_play2d("puff")


## Sons de itens, progressão e terminal a partir de HudDaggerfall.events().
func on_progress(ev: Dictionary) -> void:
	if ev.is_empty():
		return
	var picked: Array = ev.get("picked", [])
	if picked.has(ItemsSim.KEY):
		_play2d("pick_key")
	if picked.has(ItemsSim.POTION_HP) or picked.has(ItemsSim.POTION_SP):
		_play2d("pick_potion")
	if picked.has(ItemsSim.GOLD):
		_play2d("pick_gold")
	if int(ev.get("quaffed", 0)) > 0:
		_play2d("quaff")
	if bool(ev.get("unlocked", false)):
		_play2d("unlock")
	if int(ev.get("level_up", 0)) > 0:
		_play2d("level_up")
	var term: String = String(ev.get("terminal", ""))
	if term != "":
		_play2d("end_" + term)


## Sons de interface (ex.: "paper" ao abrir/fechar o automapa).
func play_ui(n: String) -> void:
	_play2d(n)


func _play2d(n: String) -> void:
	var p: AudioStreamPlayer = _combat_players.get(n, null)
	if p != null:
		p.play()


## Chamado pela cena a cada tick, com o estado já avançado.
func on_tick(player: Dictionary, opened_doors: Array, use_on_locked: bool) -> void:
	var speed: int = maxi(absi(int(player["vel_x"])), absi(int(player["vel_z"])))
	if speed > STEP_SPEED:
		_step_counter += 1
		if _step_counter >= STEP_INTERVAL:
			_step_counter = 0
			_step_alt = not _step_alt
			_step_player.pitch_scale = 1.05 if _step_alt else 0.95
			_step_player.play()
	else:
		_step_counter = STEP_INTERVAL - 6
	if not opened_doors.is_empty():
		_door_player.play()
	if use_on_locked:
		_thunk_player.play()


func _ensure_bus(bus_name: String) -> void:
	if AudioServer.get_bus_index(bus_name) == -1:
		AudioServer.add_bus()
		AudioServer.set_bus_name(AudioServer.bus_count - 1, bus_name)
		AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _make_player(stream: AudioStream, bus: String, db: float) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.stream = stream
	p.bus = bus
	p.volume_db = db
	add_child(p)
	return p


## Reescala para o pico `peak` se passar dele (evita saturar).
func _normalize(s: PackedFloat32Array, peak: float) -> PackedFloat32Array:
	var m: float = 0.0
	for v: float in s:
		m = maxf(m, absf(v))
	if m > peak:
		for i: int in range(s.size()):
			s[i] *= peak / m
	return s


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i: int in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	return w


func _gen_step() -> AudioStreamWAV:
	var n: int = int(RATE * 0.07)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var lp: float = 0.0
	for i: int in range(n):
		lp += 0.15 * (_rng.randf_range(-1.0, 1.0) - lp)
		s[i] = lp * 2.5 * exp(-float(i) / (RATE * 0.015))
	return _to_wav(s)


func _gen_door() -> AudioStreamWAV:
	var n: int = int(RATE * 0.4)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var lp: float = 0.0
	var phase: float = 0.0
	for i: int in range(n):
		var t: float = float(i) / RATE
		var f: float = lerpf(90.0, 60.0, t / 0.4) * (1.0 + 0.06 * sin(TAU * 11.0 * t))
		phase += TAU * f / RATE
		lp += 0.05 * (_rng.randf_range(-1.0, 1.0) - lp)
		var env: float = minf(1.0, t / 0.02) * (1.0 - t / 0.4)
		s[i] = (0.5 * sin(phase) + 1.2 * lp) * env
	return _to_wav(s)


func _gen_thunk() -> AudioStreamWAV:
	var n: int = int(RATE * 0.08)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i: int in range(n):
		var t: float = float(i) / RATE
		s[i] = 0.8 * sin(TAU * 140.0 * t) * exp(-t / 0.02)
	return _to_wav(s)


func _gen_ambience() -> AudioStreamWAV:
	var n: int = RATE * 4
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var brown: float = 0.0
	for i: int in range(n):
		brown = clampf(brown + _rng.randf_range(-1.0, 1.0) * 0.02, -1.0, 1.0) * 0.998
		s[i] = brown
	return _to_wav(s)


func _buf(seconds: float) -> PackedFloat32Array:
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(int(RATE * seconds))
	return s


func _build_combat_streams() -> void:
	_streams["whoosh"] = _gen_whoosh()
	_streams["hit"] = _gen_hit()
	_streams["clang"] = _to_wav(_clang_samples(0.25))
	_streams["guard_break"] = _gen_guard_break()
	_streams["grunt"] = _gen_grunt()
	_streams["puff"] = _gen_puff()
	_streams["die"] = _gen_die()
	_streams["wake_%d" % EnemySim.RAT] = _gen_chirp()
	_streams["wake_%d" % EnemySim.SKELETON] = _gen_clicks()
	_streams["wake_%d" % EnemySim.GUARDIAN] = _gen_roar()
	for t: int in [EnemySim.RAT, EnemySim.SKELETON, EnemySim.GUARDIAN]:
		var secs: float = minf(float(EnemySim.WINDUP_TICKS[t]) / 60.0, 0.5)
		_streams["warn_%d" % t] = _gen_rise(secs)


## Ruído com passa-banda (ressonador de 2 polos) varrendo 400 -> 2000 Hz.
func _gen_whoosh() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.15)
	var y1: float = 0.0
	var y2: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		var f: float = lerpf(400.0, 2000.0, k)
		var r: float = 0.97
		var c: float = 2.0 * r * cos(TAU * f / RATE)
		var x: float = _rng.randf_range(-1.0, 1.0)
		var y: float = (1.0 - r) * x + c * y1 - r * r * y2
		y2 = y1
		y1 = y
		s[i] = y * 6.0 * sin(PI * k)
	return _to_wav(s)


func _gen_hit() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.12)
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		var n: float = _rng.randf_range(-1.0, 1.0) * exp(-t / 0.01)
		s[i] = 0.8 * sin(TAU * 110.0 * t) * exp(-t / 0.04) + 0.4 * n
	return _to_wav(s)


func _clang_samples(seconds: float) -> PackedFloat32Array:
	var s: PackedFloat32Array = _buf(seconds)
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		s[i] = (0.4 * sin(TAU * 520.0 * t) + 0.3 * sin(TAU * 1230.0 * t)
			+ 0.2 * sin(TAU * 1870.0 * t)) * exp(-t / 0.06)
	return s


func _gen_guard_break() -> AudioStreamWAV:
	var s: PackedFloat32Array = _clang_samples(0.4)
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		s[i] = 0.7 * s[i] + 0.6 * sin(TAU * 60.0 * t) * exp(-t / 0.12)
	return _to_wav(s)


func _gen_grunt() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.2)
	var phase: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		phase = fmod(phase + lerpf(180.0, 120.0, k) / RATE, 1.0)
		s[i] = 0.5 * (2.0 * phase - 1.0) * sin(PI * k)
	return _to_wav(s)


func _gen_puff() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.08)
	var lp: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		lp += 0.08 * (_rng.randf_range(-1.0, 1.0) - lp)
		s[i] = lp * 3.0 * sin(PI * k)
	return _to_wav(s)


## Ruído descendente: passa-baixa cada vez mais fechado.
func _gen_die() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.3)
	var lp: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		lp += lerpf(0.3, 0.02, k) * (_rng.randf_range(-1.0, 1.0) - lp)
		s[i] = lp * 2.0 * (1.0 - k)
	return _to_wav(s)


func _gen_chirp() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.08)
	var phase: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		phase += TAU * lerpf(1800.0, 2400.0, k) / RATE
		s[i] = 0.4 * sin(phase) * sin(PI * k)
	return _to_wav(s)


## Seis cliques de 2 ms em 150 ms (ossos).
func _gen_clicks() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.15)
	var len: int = int(RATE * 0.002)
	for c: int in range(6):
		var start: int = int(RATE * 0.025 * c)
		for j: int in range(len):
			if start + j < s.size():
				s[start + j] = _rng.randf_range(-0.8, 0.8) * (1.0 - float(j) / len)
	return _to_wav(s)


func _gen_roar() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.6)
	var lp: float = 0.0
	var phase: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		lp += 0.1 * (_rng.randf_range(-1.0, 1.0) - lp)
		phase = fmod(phase + 70.0 / RATE, 1.0)
		s[i] = (0.6 * lp * 3.0 + 0.4 * (2.0 * phase - 1.0)) * sin(PI * k)
	return _to_wav(s)


func _gen_rise(seconds: float) -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(seconds)
	var phase: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		phase += TAU * lerpf(300.0, 600.0, k) / RATE
		s[i] = 0.3 * sin(phase) * minf(1.0, k * 10.0) * (1.0 - k * 0.5)
	return _to_wav(s)


func _build_progress_streams() -> void:
	_streams["pick_potion"] = _gen_tones([880.0, 1320.0], 0.12, 0.03)
	_streams["pick_key"] = _gen_tones([660.0, 880.0, 1320.0], 0.4, 0.15)
	_streams["pick_gold"] = _gen_coins()
	_streams["quaff"] = _gen_gulp()
	_streams["unlock"] = _gen_unlock()
	_streams["level_up"] = _gen_arpeggio([523.0, 659.0, 784.0, 1047.0], 0.09, true)
	_streams["paper"] = _gen_paper()
	_streams["end_ESCAPED"] = _gen_escaped()
	_streams["end_DEAD"] = _gen_dead()
	_streams["end_TIMEOUT"] = _gen_timeout()


## Senoides somadas com decaimento exponencial (constante `tau` em s).
func _gen_tones(freqs: Array, seconds: float, tau: float) -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(seconds)
	var g: float = 0.6 / float(freqs.size())
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		var v: float = 0.0
		for f: float in freqs:
			v += sin(TAU * f * t)
		s[i] = g * v * exp(-t / tau) * minf(1.0, t / 0.002)
	return _to_wav(s)


## Duas moedas (2000 e 2600 Hz) com 30 ms de intervalo.
func _gen_coins() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.09)
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		var v: float = 0.4 * sin(TAU * 2000.0 * t) * exp(-t / 0.015)
		if t >= 0.03:
			var t2: float = t - 0.03
			v += 0.4 * sin(TAU * 2600.0 * t2) * exp(-t2 / 0.02)
		s[i] = v
	return _to_wav(s)


## Gole: 3 rajadas de ruído com passa-baixa (~600 Hz), 60 ms cada, intervalo de 40 ms.
func _gen_gulp() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.26)
	var a: float = 1.0 - exp(-TAU * 600.0 / RATE)
	var lp: float = 0.0
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		var k: float = fmod(t, 0.1)
		lp += a * (_rng.randf_range(-1.0, 1.0) - lp)
		s[i] = (lp * 2.5 * sin(PI * k / 0.06)) if k < 0.06 else 0.0
	return _to_wav(_normalize(s, PEAK_MAX))


## Clank metálico (520 e 1230 Hz) seguido de rangido (dente de serra 90 -> 140 Hz).
func _gen_unlock() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.45)
	var phase: float = 0.0
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		var v: float = (0.4 * sin(TAU * 520.0 * t) + 0.3 * sin(TAU * 1230.0 * t)) * exp(-t / 0.05)
		if t > 0.1:
			var k: float = (t - 0.1) / 0.35
			phase = fmod(phase + lerpf(90.0, 140.0, k) / RATE, 1.0)
			v += 0.25 * (2.0 * phase - 1.0) * sin(PI * k)
		s[i] = v
	return _to_wav(s)


## Arpejo de notas de `note_s` cada (onda quadrada ou senoide).
func _gen_arpeggio(freqs: Array, note_s: float, square: bool) -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(note_s * freqs.size())
	var n: int = int(RATE * note_s)
	for i: int in range(s.size()):
		var j: int = mini(i / n, freqs.size() - 1)
		var t: float = float(i - j * n) / RATE
		var w: float = sin(TAU * float(freqs[j]) * t)
		if square:
			w = 1.0 if w >= 0.0 else -1.0
		s[i] = 0.25 * w * exp(-t / (note_s * 0.8))
	return _to_wav(s)


## Farfalhar de papel: ruído com passa-banda 2–6 kHz e envelope curto.
func _gen_paper() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.1)
	var hp_a: float = exp(-TAU * 2000.0 / RATE)
	var lp_a: float = 1.0 - exp(-TAU * 6000.0 / RATE)
	var prev_x: float = 0.0
	var hp: float = 0.0
	var lp: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		var x: float = _rng.randf_range(-1.0, 1.0)
		hp = hp_a * (hp + x - prev_x)
		prev_x = x
		lp += lp_a * (hp - lp)
		s[i] = lp * 1.2 * sin(PI * k) * (0.6 + 0.4 * sin(TAU * 40.0 * k))
	return _to_wav(s)


## Arpejo ascendente de senoides com eco de 120 ms (ganho 0,3).
func _gen_escaped() -> AudioStreamWAV:
	var notes: Array = [392.0, 523.0, 659.0, 784.0, 1047.0]
	var s: PackedFloat32Array = _buf(1.2)
	var n: int = int(RATE * 0.18)
	for i: int in range(s.size()):
		var j: int = mini(i / n, notes.size() - 1)
		var t: float = float(i - j * n) / RATE
		s[i] = 0.35 * sin(TAU * float(notes[j]) * t) * exp(-t / 0.25)
	var d: int = int(RATE * 0.12)
	for i: int in range(s.size() - 1, d - 1, -1):
		s[i] += 0.3 * s[i - d]
	return _to_wav(s)


## Dente de serra descendente 200 -> 50 Hz com ruído grave.
func _gen_dead() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(1.0)
	var phase: float = 0.0
	var lp: float = 0.0
	for i: int in range(s.size()):
		var k: float = float(i) / s.size()
		phase = fmod(phase + lerpf(200.0, 50.0, k) / RATE, 1.0)
		lp += 0.03 * (_rng.randf_range(-1.0, 1.0) - lp)
		s[i] = (0.35 * (2.0 * phase - 1.0) + 1.5 * lp) * (1.0 - k)
	return _to_wav(s)


## Dois toques graves de 220 Hz.
func _gen_timeout() -> AudioStreamWAV:
	var s: PackedFloat32Array = _buf(0.6)
	for i: int in range(s.size()):
		var t: float = float(i) / RATE
		var k: float = fmod(t, 0.3)
		s[i] = 0.5 * sin(TAU * 220.0 * t) * exp(-k / 0.08)
	return _to_wav(s)


## Para os players antes de sair da árvore: playbacks ativos não vazam no ObjectDB.
func _exit_tree() -> void:
	for c: Node in get_children():
		if c is AudioStreamPlayer:
			(c as AudioStreamPlayer).stop()
