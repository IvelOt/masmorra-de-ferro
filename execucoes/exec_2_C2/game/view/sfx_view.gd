extends Node3D
## Áudio procedural (só apresentação, fora do hash). Eventos detectados comparando snapshots.
## Usa RandomNumberGenerator próprio da view (semente fixa), nunca o PCG do núcleo.
## Rodada 3 (plano §10): inimigos (acordar, preparação, abate; atenuados pela distância), itens,
## poções, porta destrancada, subida de nível e fim de partida.

const MIX_RATE: int = 22050
const STEP_EVERY: int = 20
const STEP_SPEED: int = 40
const BUMP_SPEED: int = 60
const CELL: float = 2048.0
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _step_player: AudioStreamPlayer = null
var _bump_player: AudioStreamPlayer = null
var _click_player: AudioStreamPlayer = null
var _door_player: AudioStreamPlayer3D = null
var _step_count: int = 0
var _swish_player: AudioStreamPlayer = null
var _thud_player: AudioStreamPlayer = null
var _break_player: AudioStreamPlayer = null
var _clang_player: AudioStreamPlayer = null
var _guard_break_player: AudioStreamPlayer = null
var _hurt_player: AudioStreamPlayer = null
var _denied_player: AudioStreamPlayer = null
var _map_player: AudioStreamPlayer = null
## Rodada 3: tipo -> [stream, dB base]
var _wake_sfx: Dictionary = {}
var _death_sfx: Dictionary = {}
var _windup_sfx: Array = []
var _enemy_players: Array = []
var _potion_player: AudioStreamPlayer = null
var _gold_player: AudioStreamPlayer = null
var _key_player: AudioStreamPlayer = null
var _quaff_player: AudioStreamPlayer = null
var _unlock_player: AudioStreamPlayer = null
var _level_player: AudioStreamPlayer = null
var _escaped_player: AudioStreamPlayer = null
var _dead_player: AudioStreamPlayer = null


func _ready() -> void:
	_rng.seed = 12345
	_step_player = _make_player(_gen_step(), -12.0)
	_bump_player = _make_player(_gen_tone(90.0, 0.08), -10.0)
	_click_player = _make_player(_gen_tone(2000.0, 0.03), -10.0)
	_door_player = AudioStreamPlayer3D.new()
	_door_player.stream = _gen_creak()
	_door_player.volume_db = -8.0
	add_child(_door_player)
	# combate (M3) e automapa (M5)
	_swish_player = _make_player(_gen_swish(), -8.0)
	_thud_player = _make_player(_gen_thud(140.0, 0.09), -6.0)
	_break_player = _make_player(_gen_wood_break(), -6.0)
	_clang_player = _make_player(_gen_clang(0.12, 0.0), -6.0)
	_guard_break_player = _make_player(_gen_clang(0.25, 70.0), -4.0)
	_hurt_player = _make_player(_gen_saw_sweep(180.0, 120.0, 0.15), -8.0)
	_denied_player = _make_player(_gen_tone(600.0, 0.03), -14.0)
	_map_player = _make_player(_gen_rustle(), -16.0)
	# rodada 3: inimigos (volume ajustado a cada disparo pela distância)
	_wake_sfx = {
		"rat": [_gen_chirp(1800.0, 2600.0, 0.08), -10.0],
		"skeleton": [_gen_rattle(5, 0.015, 0.03), -10.0],
		"guardian": [_gen_roar(80.0, 0.4), -6.0],
	}
	_death_sfx = {
		"rat": [_gen_chirp(2000.0, 600.0, 0.25), -8.0],
		"skeleton": [_gen_rattle(8, 0.015, 0.03), -8.0],
		"guardian": [_gen_roar(60.0, 0.6), -8.0],
	}
	_windup_sfx = [_gen_band_sweep(300.0, 900.0, 0.25), -12.0]
	for _i in range(4):
		var pl: AudioStreamPlayer = AudioStreamPlayer.new()
		add_child(pl)
		_enemy_players.append(pl)
	_potion_player = _make_player(_gen_chime(880.0, 1320.0, 0.1), -10.0)
	_gold_player = _make_player(_gen_coin_clicks(), -10.0)
	_key_player = _make_player(_gen_notes([660.0, 880.0, 1320.0], 0.06), -8.0)
	_quaff_player = _make_player(_gen_bubbles(), -10.0)
	_unlock_player = _make_player(_gen_tone(1500.0, 0.02), -8.0)
	_level_player = _make_player(_gen_notes([523.0, 659.0, 784.0], 0.1), -6.0)
	_escaped_player = _make_player(_gen_notes([523.0, 659.0, 784.0, 1047.0, 1319.0], 0.12), -4.0)
	_dead_player = _make_player(_gen_chirp(400.0, 80.0, 0.8), -4.0)


func on_tick(prev: Dictionary, cur: Dictionary, inp: RefCounted) -> void:
	var p0: Dictionary = prev.player
	var p1: Dictionary = cur.player
	# passos
	if absi(p1.vel_x) + absi(p1.vel_z) > STEP_SPEED:
		_step_count += 1
		if _step_count >= STEP_EVERY:
			_step_count = 0
			_step_player.play()
	else:
		_step_count = 0
	# batida em parede
	if (absi(p0.vel_x) > BUMP_SPEED and p1.vel_x == 0) or (absi(p0.vel_z) > BUMP_SPEED and p1.vel_z == 0):
		_bump_player.play()
	# porta abrindo
	var before: Dictionary = {}
	for d: Dictionary in prev.doors:
		before[d.id] = d.type
	var opened: bool = false
	for d: Dictionary in cur.doors:
		if d.type == DOOR_OPEN and before.get(d.id, DOOR_OPEN) != DOOR_OPEN:
			opened = true
			_door_player.position = Vector3(d.cx * 2.0 + 1.0, 1.5, -(d.cz * 2.0 + 1.0))
			_door_player.play()
	# use em porta trancada de frente
	if inp.use and not opened and _facing_locked(p1, cur.doors):
		_click_player.play()
	_combat_events(prev, cur)
	_enemy_events(prev, cur)
	_item_events(prev, cur)


## Acordar, preparação (aviso para bloquear) e abate, atenuados pela distância ao jogador.
func _enemy_events(prev: Dictionary, cur: Dictionary) -> void:
	var p: Dictionary = cur.player
	var before: Dictionary = {}
	for e: Dictionary in prev.get("enemies", []):
		before[e.id] = e
	for e: Dictionary in cur.get("enemies", []):
		if e.type == "dummy":
			continue
		var old: Dictionary = before.get(e.id, e)
		var dist_m: float = Vector2(float(e.pos_x) - float(p.pos_x), float(e.pos_z) - float(p.pos_z)).length() / 1024.0
		if e.awake and not old.awake and _wake_sfx.has(e.type):
			_play_at(_wake_sfx[e.type], dist_m)
		if e.state == "WINDUP" and old.state != "WINDUP":
			_play_at(_windup_sfx, dist_m)
		if e.state == "DEAD" and old.state != "DEAD" and _death_sfx.has(e.type):
			_play_at(_death_sfx[e.type], dist_m)


## vol_db = base − 20·log10(max(1, dist_m / 2)), num dos tocadores livres (ou no primeiro).
func _play_at(sfx: Array, dist_m: float) -> void:
	var pl: AudioStreamPlayer = _enemy_players[0]
	for c: AudioStreamPlayer in _enemy_players:
		if not c.playing:
			pl = c
			break
	pl.stream = sfx[0]
	pl.volume_db = float(sfx[1]) - 20.0 * log(maxf(1.0, dist_m / 2.0)) / log(10.0)
	pl.play()


## Coleta, poções, porta destrancada, nível e fim de partida.
func _item_events(prev: Dictionary, cur: Dictionary) -> void:
	var p0: Dictionary = prev.player
	var p1: Dictionary = cur.player
	var taken_before: Dictionary = {}
	for it: Dictionary in prev.get("items", []):
		taken_before[it.id] = it.taken
	for it: Dictionary in cur.get("items", []):
		if it.taken and not taken_before.get(it.id, true):
			if it.type == "gold":
				_gold_player.play()
			elif it.type == "key":
				_key_player.play()
			else:
				_potion_player.play()
	var inv0: Dictionary = p0.get("inventory", {})
	var inv1: Dictionary = p1.get("inventory", {})
	if int(inv1.get("potion_hp", 0)) < int(inv0.get("potion_hp", 0)) \
			or int(inv1.get("potion_sp", 0)) < int(inv0.get("potion_sp", 0)):
		_quaff_player.play()
	var doors_before: Dictionary = {}
	for d: Dictionary in prev.get("doors", []):
		doors_before[d.id] = d.type
	for d: Dictionary in cur.get("doors", []):
		if d.type == DOOR_OPEN and doors_before.get(d.id, DOOR_OPEN) == DOOR_LOCKED:
			_unlock_player.play()
	if int(p1.get("level", 1)) > int(p0.get("level", 1)):
		_level_player.play()
	if prev.get("terminal", "NONE") == "NONE":
		if cur.get("terminal", "NONE") == "ESCAPED":
			_escaped_player.play()
		elif cur.get("terminal", "NONE") == "DEAD":
			_dead_player.play()


func _combat_events(prev: Dictionary, cur: Dictionary) -> void:
	var p0: Dictionary = prev.player
	var p1: Dictionary = cur.player
	if p1.swing_state == "ACTIVE" and p0.swing_state != "ACTIVE":
		_swish_player.play()
	var before: Dictionary = {}
	for e: Dictionary in prev.get("enemies", []):
		before[e.id] = e
	for e: Dictionary in cur.get("enemies", []):
		var old: Dictionary = before.get(e.id, e)
		if e.state == "DEAD" and old.state != "DEAD":
			if e.type == "dummy":
				_break_player.play()
		elif int(e.hp) < int(old.hp):
			_thud_player.play()
	if int(p0.stun_ticks) == 0 and int(p1.stun_ticks) == 20:
		_guard_break_player.play()
	elif int(p1.hp) < int(p0.hp):
		if p1.blocking:
			_clang_player.play()
		else:
			_hurt_player.play()
	var li: Dictionary = cur.get("last_input", {})
	if li.get("attack", false) and p0.swing_state == "IDLE" and p1.swing_state == "IDLE":
		_denied_player.play()


## Abrir/fechar o automapa (evento só de UI, vindo do overlay).
func play_map_toggle(_open: bool = true) -> void:
	_map_player.play()


func _facing_locked(p: Dictionary, doors: Array) -> bool:
	var pcx: int = floori(p.pos_x / CELL)
	var pcz: int = floori(p.pos_z / CELL)
	var a: float = TAU * float(p.angle) / 4096.0
	var f: Vector2 = Vector2(cos(a), sin(a))
	for d: Dictionary in doors:
		if d.type != DOOR_LOCKED or absi(d.cx - pcx) > 1 or absi(d.cz - pcz) > 1:
			continue
		var dv: Vector2 = Vector2((d.cx + 0.5) * CELL - p.pos_x, (d.cz + 0.5) * CELL - p.pos_z)
		var along: float = dv.dot(f)
		if along > 0.0 and absf(dv.cross(f)) <= along:
			return true
	return false


func _make_player(stream: AudioStreamWAV, db: float) -> AudioStreamPlayer:
	var pl: AudioStreamPlayer = AudioStreamPlayer.new()
	pl.stream = stream
	pl.volume_db = db
	add_child(pl)
	return pl


func _to_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var data: PackedByteArray = PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32767.0))
	var w: AudioStreamWAV = AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = MIX_RATE
	w.stereo = false
	w.data = data
	return w


func _gen_step() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.06)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var lp: float = 0.0
	for i in range(n):
		lp = lp * 0.7 + _rng.randf_range(-1.0, 1.0) * 0.3
		s[i] = lp * exp(-float(i) / (n * 0.25)) * 1.5
	return _to_wav(s)


func _gen_tone(freq: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / MIX_RATE
		s[i] = sin(TAU * freq * t) * exp(-float(i) / (n * 0.4))
	return _to_wav(s)


func _gen_creak() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.4)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var k: float = float(i) / n
		phase += TAU * lerpf(300.0, 180.0, k) / MIX_RATE
		var saw: float = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		s[i] = (saw * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.15) * sin(PI * k)
	return _to_wav(s)


## Ruído filtrado com varredura de 1200 para 300 Hz (corte do ar), 150 ms.
func _gen_swish() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.15)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var lp: float = 0.0
	for i in range(n):
		var k: float = float(i) / n
		var fc: float = lerpf(1200.0, 300.0, k)
		var a: float = clampf(TAU * fc / MIX_RATE, 0.0, 1.0)
		lp += a * (_rng.randf_range(-1.0, 1.0) - lp)
		s[i] = lp * 2.5 * sin(PI * k)
	return _to_wav(s)


## Baque: seno grave + ruído, decaimento exponencial.
func _gen_thud(freq: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-float(i) / (n * 0.25))
		s[i] = (sin(TAU * freq * t) * 0.8 + _rng.randf_range(-1.0, 1.0) * 0.3) * env
	return _to_wav(s)


## Estalo de madeira: 3 rajadas de ruído de 20 ms espaçadas 40 ms.
func _gen_wood_break() -> AudioStreamWAV:
	var burst: int = int(MIX_RATE * 0.02)
	var gap: int = int(MIX_RATE * 0.04)
	var n: int = gap * 2 + burst
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for b in range(3):
		for i in range(burst):
			s[b * gap + i] = _rng.randf_range(-1.0, 1.0) * exp(-float(i) / (burst * 0.3))
	return _to_wav(s)


## Clangor metálico 1200 + 1900 Hz; com `low` > 0 soma um baque grave (quebra de guarda).
func _gen_clang(dur: float, low: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / MIX_RATE
		var env: float = exp(-float(i) / (n * 0.3))
		var v: float = (sin(TAU * 1200.0 * t) + sin(TAU * 1900.0 * t)) * 0.4
		if low > 0.0:
			v = v * 0.6 + sin(TAU * low * t) * 0.6
		s[i] = v * env
	return _to_wav(s)


## Onda dente-de-serra com varredura (jogador ferido).
func _gen_saw_sweep(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var k: float = float(i) / n
		phase += TAU * lerpf(f0, f1, k) / MIX_RATE
		s[i] = (fposmod(phase / TAU, 1.0) * 2.0 - 1.0) * 0.6 * (1.0 - k)
	return _to_wav(s)


## Farfalhar de pergaminho: ruído passa-alta, 80 ms.
func _gen_rustle() -> AudioStreamWAV:
	var n: int = int(MIX_RATE * 0.08)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var prev_x: float = 0.0
	for i in range(n):
		var x: float = _rng.randf_range(-1.0, 1.0)
		s[i] = (x - prev_x) * 0.5 * sin(PI * float(i) / n)
		prev_x = x
	return _to_wav(s)


## Varredura senoidal f0 -> f1 (guinchos, tom de morte).
func _gen_chirp(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var k: float = float(i) / n
		phase += TAU * lerpf(f0, f1, k) / MIX_RATE
		s[i] = sin(phase) * 0.7 * sin(PI * minf(k * 4.0, 1.0) * 0.5) * (1.0 - k * 0.6)
	return _to_wav(s)


## Chocalho de ossos: `count` cliques de ruído de `click` s a cada `spacing` s.
func _gen_rattle(count: int, click: float, spacing: float) -> AudioStreamWAV:
	var c: int = int(MIX_RATE * click)
	var g: int = int(MIX_RATE * spacing)
	var n: int = g * (count - 1) + c
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var prev_x: float = 0.0
	for b in range(count):
		for i in range(c):
			var x: float = _rng.randf_range(-1.0, 1.0)
			s[b * g + i] = (x - prev_x) * 0.6 * exp(-float(i) / (c * 0.3))
			prev_x = x
	return _to_wav(s)


## Rugido: dente-de-serra grave + ruído.
func _gen_roar(freq: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var phase: float = 0.0
	for i in range(n):
		var k: float = float(i) / n
		phase += TAU * freq * (1.0 + 0.1 * sin(TAU * 6.0 * float(i) / MIX_RATE)) / MIX_RATE
		var saw: float = fposmod(phase / TAU, 1.0) * 2.0 - 1.0
		s[i] = (saw * 0.6 + _rng.randf_range(-1.0, 1.0) * 0.3) * sin(PI * k)
	return _to_wav(s)


## Sopro crescente: ruído em passa-banda ressonante varrendo f0 -> f1.
func _gen_band_sweep(f0: float, f1: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	var y1: float = 0.0
	var y2: float = 0.0
	var r: float = 0.97
	for i in range(n):
		var k: float = float(i) / n
		var w: float = TAU * lerpf(f0, f1, k) / MIX_RATE
		var y: float = _rng.randf_range(-1.0, 1.0) * (1.0 - r) + 2.0 * r * cos(w) * y1 - r * r * y2
		y2 = y1
		y1 = y
		s[i] = y * 6.0 * k
	return _to_wav(s)


## Tilintar de duas parciais.
func _gen_chime(f1: float, f2: float, dur: float) -> AudioStreamWAV:
	var n: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for i in range(n):
		var t: float = float(i) / MIX_RATE
		s[i] = (sin(TAU * f1 * t) + sin(TAU * f2 * t)) * 0.35 * exp(-float(i) / (n * 0.35))
	return _to_wav(s)


## Moedas: 3 cliques tonais entre 2000 e 3000 Hz.
func _gen_coin_clicks() -> AudioStreamWAV:
	var c: int = int(MIX_RATE * 0.025)
	var g: int = int(MIX_RATE * 0.04)
	var n: int = g * 2 + c
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(n)
	for b in range(3):
		var f: float = 2000.0 + 500.0 * b
		for i in range(c):
			s[b * g + i] = sin(TAU * f * float(i) / MIX_RATE) * 0.6 * exp(-float(i) / (c * 0.3))
	return _to_wav(s)


## Sequência de notas senoidais de `dur` s cada (arpejos, fanfarra).
func _gen_notes(freqs: Array, dur: float) -> AudioStreamWAV:
	var m: int = int(MIX_RATE * dur)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(m * freqs.size())
	for j in range(freqs.size()):
		var f: float = freqs[j]
		for i in range(m):
			var t: float = float(i) / MIX_RATE
			s[j * m + i] = (sin(TAU * f * t) * 0.5 + sin(TAU * f * 2.0 * t) * 0.15) * exp(-float(i) / (m * 0.6))
	return _to_wav(s)


## Três bolhas: seno de 200 Hz subindo levemente, 40 ms cada.
func _gen_bubbles() -> AudioStreamWAV:
	var m: int = int(MIX_RATE * 0.04)
	var s: PackedFloat32Array = PackedFloat32Array()
	s.resize(m * 3)
	for b in range(3):
		var phase: float = 0.0
		for i in range(m):
			var k: float = float(i) / m
			phase += TAU * 200.0 * (1.0 + 0.6 * k) / MIX_RATE
			s[b * m + i] = sin(phase) * 0.6 * sin(PI * k)
	return _to_wav(s)
