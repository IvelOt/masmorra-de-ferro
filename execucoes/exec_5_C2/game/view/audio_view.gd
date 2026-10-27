extends Node
## Áudio procedural somente de apresentação (passos, porta, batida, combate, inimigos, automapa, zumbido,
## itens/poções/nível/destranca e sons terminais de M6).
## Nenhum valor daqui entra no núcleo; o ruído usa RNG próprio da view.

const MIX_RATE: float = 22050.0
const STEP_DIST_M: float = 0.9
const AMBIENT_DB: float = -24.0
const SFX_DB: float = -10.0
const FAR_M: float = 12.0
const WAKE_SFX: Dictionary = {"rat": ["squeak", 0.09], "skeleton": ["rattle", 0.108], "guardian": ["roar", 0.4]}

var _player: AudioStreamPlayer
var _playback: AudioStreamGeneratorPlayback
var _noise := RandomNumberGenerator.new()
var _events: Array = []          # [{kind, t, dur}]
var _phase: float = 0.0
var _walked: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _has_last: bool = false
var _last_vel: Array = [0, 0]
var _last_status: Dictionary = {}
var _last_enemy: Dictionary = {}  # id -> último dicionário de get_enemies()
var _last_terminal: String = "NONE"


func _ready() -> void:
	_noise.seed = 4242
	AudioServer.set_bus_volume_db(0, -6.0)
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = MIX_RATE
	gen.buffer_length = 0.15
	_player = AudioStreamPlayer.new()
	_player.name = "Generator"
	_player.stream = gen
	add_child(_player)
	# Em --headless não há saída de áudio: não criar o playback evita o vazamento de ObjectDB
	# (AudioStreamGeneratorPlayback liberado de forma diferida pelo servidor depois do quit()).
	if DisplayServer.get_name() == "headless":
		return
	_player.play()
	_playback = _player.get_stream_playback() as AudioStreamGeneratorPlayback


## Solta o playback ao sair da árvore.
func _exit_tree() -> void:
	if _player != null:
		_player.stop()
	_playback = null


## Chamado pela main após cada tick com valores lidos do núcleo.
func on_tick(pos: Array, vel: Array, opened_doors: int) -> void:
	var p := Vector2(pos[0] / 1024.0, pos[1] / 1024.0)
	if _has_last:
		_walked += p.distance_to(_last_pos)
		if _walked >= STEP_DIST_M:
			_walked = 0.0
			_events.append({"kind": "step", "t": 0.0, "dur": 0.04})
	_last_pos = p
	_has_last = true
	for k in range(2):
		if absi(_last_vel[k]) >= 60 and vel[k] == 0:
			_events.append({"kind": "bump", "t": 0.0, "dur": 0.06})
	_last_vel = [vel[0], vel[1]]
	for _d in range(opened_doors):
		_events.append({"kind": "door", "t": 0.0, "dur": 0.25})


## Eventos de combate por diferença entre leituras consecutivas (sem sinais do núcleo).
func on_combat(status: Dictionary, enemies: Array, input: IntInput) -> void:
	var prev: Dictionary = _last_status
	var struck: Array = []
	for e: Dictionary in enemies:
		var pe: Dictionary = _last_enemy.get(e["id"], e)
		_last_enemy[e["id"]] = e
		if e["hp"] < pe["hp"]:
			_add("thud", 0.1)
		if not WAKE_SFX.has(e["type"]):
			continue
		var g: float = gain_at(e)
		if e["awake"] and not pe["awake"]:
			_add(WAKE_SFX[e["type"]][0], WAKE_SFX[e["type"]][1], g)
		if e["state"] == "WINDUP" and pe["state"] != "WINDUP":
			_add("tell_low" if e["type"] == "guardian" else "tell", 0.12, g)
		if e["state"] == "STRIKE" and pe["state"] != "STRIKE":
			struck.append(g)
		if e["state"] == "DEAD" and pe["state"] != "DEAD":
			_add("death", 0.2, g)
	_last_status = status
	if prev.is_empty():
		return
	if status["hp"] >= prev["hp"]:
		for g: float in struck:
			_add("whiff", 0.06, g)
	if prev["swing_state"] == "WINDUP" and status["swing_state"] == "ACTIVE":
		_add("whoosh", 0.12)
	var broke: bool = prev["stun_ticks"] == 0 and status["stun_ticks"] > 0
	if broke:
		_add("clank_low", 0.2)
	if status["hp"] < prev["hp"]:
		if status["blocking"] and not broke:
			_add("clank", 0.15)
		elif not broke:
			_add("grunt", 0.15)
	if input != null and input.attack and prev["swing_state"] == "IDLE" \
			and status["swing_state"] == "IDLE" and prev["stamina"] < Combat.SWING_COST:
		_add("click", 0.03)


## M6: sons a partir de get_events() e da borda de get_terminal() (só leitura).
func on_items(events: Array, items: Array, terminal: String) -> void:
	for ev: String in events:
		var parts: PackedStringArray = ev.split(":")
		match parts[0]:
			"pickup":
				match String(items[parts[1].to_int()]["type"]):
					"gold":
						_add("tlim", 0.15)
					"key":
						_add("key_arp", 0.27)
					_:
						_add("pickup_potion", 0.12)
			"quaff":
				_add("glup", 0.23)
			"quaff_empty", "locked_no_key":
				_add("dry_click", 0.06)
			"level":
				_add("level_arp", 0.57)
			"unlock":
				_add("unlock", 0.15)
	if terminal != _last_terminal:
		match terminal:
			"ESCAPED":
				_add("chord", 1.2)
			"DEAD":
				_add("fall_saw", 1.0)
			"TIMEOUT":
				_add("gong", 1.2)
		_last_terminal = terminal


func on_map_toggled(_open: bool) -> void:
	_add("paper", 0.08)


## Ganho posicional: clamp(1 - d/12 m, 0,2, 1), d = distância jogador-inimigo (lida do último tick).
func gain_at(e: Dictionary) -> float:
	var d: float = _last_pos.distance_to(Vector2(e["pos_x"] / 1024.0, e["pos_z"] / 1024.0))
	return clampf(1.0 - d / FAR_M, 0.2, 1.0)


func _add(kind: String, dur: float, gain: float = 1.0) -> void:
	_events.append({"kind": kind, "t": 0.0, "dur": dur, "lp": 0.0, "g": gain})


## Filtro passa-baixa de um polo com estado no próprio evento.
static func _lowpass(e: Dictionary, x: float, cutoff: float, key: String = "lp") -> float:
	var a: float = 1.0 - exp(-TAU * cutoff / MIX_RATE)
	e[key] = e.get(key, 0.0) + a * (x - e.get(key, 0.0))
	return e[key]


## Seno com fase acumulada no próprio evento (frequência pode variar no tempo).
static func _osc(e: Dictionary, f: float, dt: float) -> float:
	e["ph"] = fmod(e.get("ph", 0.0) + f * dt, 1.0)
	return sin(e["ph"] * TAU)


## Nota i de um arpejo com notas de `step` s (a última dura até o fim do evento).
static func _arp_freq(notes: Array, step: float, t: float) -> float:
	return notes[mini(int(t / step), notes.size() - 1)]


func _process(_delta: float) -> void:
	if _playback == null:
		return
	var n: int = _playback.get_frames_available()
	var amb: float = db_to_linear(AMBIENT_DB)
	var sfx: float = db_to_linear(SFX_DB)
	var dt: float = 1.0 / MIX_RATE
	for _i in range(n):
		_phase = fmod(_phase + dt * 55.0, 1.0)
		var s: float = amb * sin(_phase * TAU)
		for e: Dictionary in _events:
			var t: float = e["t"]
			var k: float = 1.0 - t / e["dur"]
			match e["kind"]:
				"step":
					s += 0.35 * k * sin(t * TAU * 90.0)
				"bump":
					s += 0.3 * k * _noise.randf_range(-1.0, 1.0) * 0.5 + 0.2 * k * sin(t * TAU * 60.0)
				"door":
					s += 0.25 * k * _noise.randf_range(-1.0, 1.0) * (0.3 + 0.7 * t / e["dur"])
				"whoosh":
					var u: float = t / e["dur"]
					var cut: float = lerpf(2000.0, 400.0, u)
					s += sfx * 1.6 * sin(PI * u) * _lowpass(e, _noise.randf_range(-1.0, 1.0), cut)
				"thud":
					s += sfx * (exp(-t / 0.025) * sin(t * TAU * 90.0) \
						+ (0.6 * _noise.randf_range(-1.0, 1.0) if t < 0.02 else 0.0))
				"clank":
					s += sfx * 0.5 * exp(-t / 0.04) * (sin(t * TAU * 900.0) + sin(t * TAU * 1350.0))
				"clank_low":
					s += sfx * 0.5 * exp(-t / 0.06) * (sin(t * TAU * 450.0) + sin(t * TAU * 680.0))
				"grunt":
					s += sfx * 2.5 * k * _lowpass(e, _noise.randf_range(-1.0, 1.0), 250.0)
				"click":
					s += sfx * 0.4 * k * sin(t * TAU * 1800.0)
				"squeak":
					var f_sq: float = lerpf(1600.0, 2400.0, t / e["dur"])
					e["ph"] = fmod(e.get("ph", 0.0) + f_sq * dt, 1.0)
					s += e["g"] * sfx * 0.8 * k * sin(e["ph"] * TAU)
				"rattle":
					var in_click: bool = fmod(t, 0.025) < 0.008
					s += e["g"] * sfx * (1.2 * _noise.randf_range(-1.0, 1.0) if in_click else 0.0)
				"roar":
					var saw: float = 2.0 * fmod(t * 70.0, 1.0) - 1.0
					var env: float = minf(t / 0.05, 1.0) * k
					s += e["g"] * sfx * env * (0.6 * saw + 1.5 * _lowpass(e, _noise.randf_range(-1.0, 1.0), 300.0))
				"tell", "tell_low":
					var base: float = 150.0 if e["kind"] == "tell_low" else 300.0
					var f_t: float = lerpf(base, base * 2.0, t / e["dur"])
					e["ph"] = fmod(e.get("ph", 0.0) + f_t * dt, 1.0)
					s += e["g"] * sfx * 0.7 * k * sin(e["ph"] * TAU)
				"whiff":
					s += e["g"] * sfx * 0.8 * sin(PI * t / e["dur"]) * _lowpass(e, _noise.randf_range(-1.0, 1.0), 1500.0)
				"death":
					var cut_d: float = lerpf(1200.0, 150.0, t / e["dur"])
					s += e["g"] * sfx * k * (sin(t * TAU * 70.0) + 0.7 * _lowpass(e, _noise.randf_range(-1.0, 1.0), cut_d))
				"pickup_potion":
					s += sfx * 0.8 * k * _osc(e, 880.0 if t < 0.06 else 1320.0, dt)
				"tlim":
					s += sfx * 0.6 * exp(-t / 0.04) * (sin(t * TAU * 2000.0) + sin(t * TAU * 3000.0))
				"key_arp":
					s += sfx * 0.8 * _osc(e, _arp_freq([523.0, 659.0, 784.0], 0.09, t), dt) * (1.0 - fmod(t, 0.09) / 0.09 * 0.5)
				"glup":
					var in_burst: bool = fmod(t, 0.09) < 0.05
					s += sfx * 3.0 * (_lowpass(e, _noise.randf_range(-1.0, 1.0), 300.0) if in_burst else 0.0)
				"dry_click":
					s += sfx * ((0.8 * _noise.randf_range(-1.0, 1.0) if t < 0.02 else 0.0) + 0.7 * k * sin(t * TAU * 120.0))
				"level_arp":
					var f_l: float = _arp_freq([523.0, 659.0, 784.0, 1047.0], 0.09, t)
					var env_l: float = 1.0 if t < 0.27 else clampf(1.0 - (t - 0.27) / 0.3, 0.0, 1.0)
					s += sfx * 0.8 * env_l * _osc(e, f_l, dt)
				"unlock":
					var wn_u: float = _noise.randf_range(-1.0, 1.0)
					var band: float = _lowpass(e, wn_u, 2000.0, "lp_hi") - _lowpass(e, wn_u, 1000.0, "lp_lo")
					s += sfx * (2.5 * k * band if t < 0.12 else 0.0) + sfx * exp(-t / 0.04) * sin(t * TAU * 200.0)
				"chord":
					s += sfx * 0.4 * k * (sin(t * TAU * 262.0) + sin(t * TAU * 330.0) + sin(t * TAU * 392.0))
				"fall_saw":
					var f_d: float = lerpf(220.0, 55.0, t / e["dur"])
					e["ph"] = fmod(e.get("ph", 0.0) + f_d * dt, 1.0)
					s += sfx * 0.6 * k * (2.0 * e["ph"] - 1.0)
				"gong":
					var tg: float = fmod(t, 0.6)
					s += sfx * 0.9 * exp(-tg / 0.2) * (sin(tg * TAU * 110.0) + 0.4 * sin(tg * TAU * 277.0))
				"paper":
					var wn: float = _noise.randf_range(-1.0, 1.0)
					s += db_to_linear(-12.0) * sfx * 2.0 * k * (wn - _lowpass(e, wn, 3000.0))
			e["t"] = minf(t + dt, e["dur"])
		_playback.push_frame(Vector2(s, s))
	_events = _events.filter(func(e: Dictionary) -> bool: return e["t"] < e["dur"])
