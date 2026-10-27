extends Node
## C9/C11 (plano R5 §3): efeitos sonoros procedurais do jogador (M3) e dos inimigos (M4).
## Só apresentação: lê get_player()/get_enemies(), compara com o quadro anterior e toca.
## Síntese determinística em código (sem arquivo de áudio), com PCG32 local no fluxo 7.
## C14/C17 (plano R6 §4): pickup e level_up (M6, pela diferença de estado) e map (M5,
## pela mudança de visibilidade da overlay), no fim de IDS.

const PCG32 = preload("res://sim/rng_pcg32.gd")

const MIX_RATE: int = 22050
const PEAK: int = 22937
const ATTACK_S: float = 0.002
const POOL_SIZE: int = 6
const NOISE_SEED: int = 0xA0D10
const NOISE_STREAM: int = 7

## Ordem das tabelas R5 §3.3 e R6 §4.2: é também a ordem de despacho num quadro.
const IDS: Array = ["swing", "hit", "block", "guard_break", "hurt", "enemy_windup", "enemy_strike", "enemy_death",
	"pickup", "level_up", "map"]
const DURATION: Dictionary = {
	"swing": 0.18, "hit": 0.12, "block": 0.25, "guard_break": 0.30,
	"hurt": 0.20, "enemy_windup": 0.30, "enemy_strike": 0.10, "enemy_death": 0.45,
	"pickup": 0.15, "level_up": 0.45, "map": 0.12,
}
const VOLUME_DB: Dictionary = {
	"swing": -8.0, "hit": -6.0, "block": -6.0, "guard_break": -4.0,
	"hurt": -6.0, "enemy_windup": -10.0, "enemy_strike": -8.0, "enemy_death": -6.0,
	"pickup": -8.0, "level_up": -6.0, "map": -12.0,
}
const NO_INVENTORY: Dictionary = {"potion_hp": 0, "potion_sp": 0, "key": false}
const LEVEL_UP_NOTES: Array = [523.0, 659.0, 784.0]
const ENEMY_EVENT: Dictionary = {"WINDUP": "enemy_windup", "STRIKE": "enemy_strike", "DEAD": "enemy_death"}

var played_log: Array = []
var _streams: Dictionary = {}
var _players: Array = []
var _next: int = 0
var _prev_p: Dictionary = {}
var _prev_en: Array = []
var _has_prev: bool = false
var _prev_map: bool = false


func _ready() -> void:
	_build_streams()
	for i in range(POOL_SIZE):
		var ap := AudioStreamPlayer.new()
		ap.name = "Sfx%d" % i
		ap.bus = "Master"
		add_child(ap)
		_players.append(ap)


## Para os sons em curso: o servidor de áudio não retém playbacks de nós já liberados.
func _exit_tree() -> void:
	for ap: AudioStreamPlayer in _players:
		ap.stop()


func get_stream(id: String) -> AudioStreamWAV:
	_build_streams()
	return _streams.get(id)


# ---------------------------------------------------------------- detecção

static func _by_id(en: Array) -> Dictionary:
	var out: Dictionary = {}
	for e: Dictionary in en:
		out[int(e["id"])] = e
	return out


## Ids da tabela §3.3 disparados pela diferença prev → cur, em ordem e sem repetição.
static func detect_events(prev_p: Dictionary, p: Dictionary, prev_en: Array, en: Array) -> Array:
	var hit_set: Dictionary = {}
	if prev_p.is_empty() or p.is_empty():
		return []
	if prev_p.get("swing_state", "") == "IDLE" and p.get("swing_state", "") == "WINDUP":
		hit_set["swing"] = true
	var prev_by_id: Dictionary = _by_id(prev_en)
	var enemy_hp_drop: bool = false
	for e: Dictionary in en:
		var pe: Dictionary = prev_by_id.get(int(e["id"]), {})
		if pe.is_empty():
			continue
		if int(e["hp"]) < int(pe["hp"]):
			enemy_hp_drop = true
		var st: String = e["state"]
		if st != pe["state"] and ENEMY_EVENT.has(st):
			hit_set[ENEMY_EVENT[st]] = true
	if enemy_hp_drop and p.get("swing_state", "") == "ACTIVE":
		hit_set["hit"] = true
	var stun_rose: bool = int(p.get("stun_ticks", 0)) > int(prev_p.get("stun_ticks", 0))
	var blocked: bool = bool(p.get("blocking", false)) and int(p["stamina"]) < int(prev_p["stamina"]) and not stun_rose
	if blocked:
		hit_set["block"] = true
	if int(prev_p.get("stun_ticks", 0)) == 0 and int(p.get("stun_ticks", 0)) > 0:
		hit_set["guard_break"] = true
	if int(p["hp"]) < int(prev_p["hp"]) and not blocked:
		hit_set["hurt"] = true
	var inv: Dictionary = p.get("inventory", NO_INVENTORY)
	var pinv: Dictionary = prev_p.get("inventory", NO_INVENTORY)
	if int(inv.get("potion_hp", 0)) > int(pinv.get("potion_hp", 0)) \
			or int(inv.get("potion_sp", 0)) > int(pinv.get("potion_sp", 0)) \
			or (bool(inv.get("key", false)) and not bool(pinv.get("key", false))) \
			or int(p.get("gold", 0)) > int(prev_p.get("gold", 0)):
		hit_set["pickup"] = true
	if int(p.get("level", 1)) > int(prev_p.get("level", 1)):
		hit_set["level_up"] = true
	var out: Array = []
	for id: String in IDS:
		if hit_set.has(id):
			out.append(id)
	return out


## Lê o estado, toca os eventos do quadro e guarda cópias para o próximo.
## map_open é estado de interface: "map" toca quando muda em relação ao quadro anterior.
func apply_state(p: Dictionary, enemies: Array, terminal: String, map_open: bool = false) -> void:
	if _has_prev and terminal == "NONE":
		var rat_only: bool = _windup_only_rats(_prev_en, enemies)
		for id: String in detect_events(_prev_p, p, _prev_en, enemies):
			_play(id, 2.0 if id == "enemy_windup" and rat_only else 1.0)
		if map_open != _prev_map:
			_play("map", 1.0)
	_prev_map = map_open
	_prev_p = p.duplicate(true)
	_prev_en = enemies.duplicate(true)
	_has_prev = true


## true quando todos os inimigos que entraram em WINDUP no quadro são ratos (frequência ×2).
static func _windup_only_rats(prev_en: Array, en: Array) -> bool:
	var prev_by_id: Dictionary = _by_id(prev_en)
	var any: bool = false
	for e: Dictionary in en:
		var pe: Dictionary = prev_by_id.get(int(e["id"]), {})
		if pe.is_empty() or e["state"] != "WINDUP" or pe["state"] == "WINDUP":
			continue
		if e["type"] != "rat":
			return false
		any = true
	return any


func _play(id: String, pitch: float) -> void:
	played_log.append(id)
	if _players.is_empty():
		return
	var ap: AudioStreamPlayer = null
	for cand: AudioStreamPlayer in _players:
		if not cand.playing:
			ap = cand
			break
	if ap == null:
		ap = _players[_next % POOL_SIZE]
		_next += 1
	ap.stream = get_stream(id)
	ap.volume_db = VOLUME_DB[id]
	ap.pitch_scale = pitch
	ap.play()


# ---------------------------------------------------------------- síntese

func _build_streams() -> void:
	if not _streams.is_empty():
		return
	var rng := PCG32.new(NOISE_SEED, NOISE_STREAM)
	for id: String in IDS:
		_streams[id] = _make_wav(_synth(id, rng))


static func _sample_count(id: String) -> int:
	return roundi(float(DURATION[id]) * MIX_RATE)


static func _noise(rng: PCG32) -> float:
	return float(rng.next_u32()) / 2147483648.0 - 1.0


static func _square(phase: float) -> float:
	return 1.0 if fposmod(phase, 1.0) < 0.5 else -1.0


static func _saw(phase: float) -> float:
	return 2.0 * fposmod(phase, 1.0) - 1.0


## Ataque linear de 2 ms e decaimento exponencial com constante tau (s).
static func _env(t: float, tau: float) -> float:
	var a: float = minf(t / ATTACK_S, 1.0)
	return a * exp(-maxf(t - ATTACK_S, 0.0) / tau)


static func _lp_alpha(fc: float) -> float:
	return 1.0 - exp(-TAU * fc / float(MIX_RATE))


func _synth(id: String, rng: PCG32) -> PackedFloat32Array:
	var n: int = _sample_count(id)
	var dur: float = DURATION[id]
	var out := PackedFloat32Array()
	out.resize(n)
	var phase: float = 0.0
	var lp: float = 0.0
	for i in range(n):
		var t: float = float(i) / MIX_RATE
		var u: float = t / dur
		var v: float = 0.0
		match id:
			"swing":
				lp += _lp_alpha(lerpf(3000.0, 600.0, u)) * (_noise(rng) - lp)
				v = lp * _env(t, dur / 2.5)
			"hit":
				phase += 140.0 / MIX_RATE
				v = (0.5 * _square(phase) + 0.5 * _noise(rng)) * _env(t, 0.030)
			"block":
				v = (0.5 * sin(TAU * 880.0 * t) + 0.5 * sin(TAU * 1320.0 * t)) * _env(t, 0.080)
			"guard_break":
				phase += lerpf(220.0, 110.0, u) / MIX_RATE
				v = (0.7 * _square(phase) + 0.3 * _noise(rng)) * _env(t, dur / 3.0)
			"hurt":
				phase += 180.0 * (1.0 + 0.08 * sin(TAU * 12.0 * t)) / MIX_RATE
				v = _square(phase) * _env(t, 0.060)
			"enemy_windup":
				phase += lerpf(90.0, 130.0, u) / MIX_RATE
				v = _saw(phase) * _env(t, dur / 2.0)
			"enemy_strike":
				lp += _lp_alpha(1200.0) * (_noise(rng) - lp)
				v = lp * _env(t, 0.040)
			"enemy_death":
				phase += lerpf(200.0, 60.0, u) / MIX_RATE
				v = _saw(phase) * _env(t, 0.150)
			"pickup":
				var half: float = dur / 2.0
				var f: float = 988.0 if t < half else 1319.0
				v = sin(TAU * f * t) * _env(fmod(t, half), 0.060)
			"level_up":
				var note_len: float = dur / 3.0
				var k: int = mini(int(t / note_len), 2)
				var tn: float = t - float(k) * note_len
				v = 0.5 * _square(float(LEVEL_UP_NOTES[k]) * tn) * _env(tn, 0.120)
			"map":
				lp += _lp_alpha(2500.0) * (_noise(rng) - lp)
				v = lp * _env(t, 0.050)
		out[i] = v
	return out


## Normaliza o pico para PEAK (≤ 0,7 da escala) e grava PCM 16 bits mono LE.
static func _make_wav(samples: PackedFloat32Array) -> AudioStreamWAV:
	var peak: float = 0.0
	for v: float in samples:
		peak = maxf(peak, absf(v))
	var k: float = float(PEAK) / peak if peak > 0.0 else 0.0
	var data := PackedByteArray()
	data.resize(samples.size() * 2)
	for i in range(samples.size()):
		data.encode_s16(i * 2, clampi(int(samples[i] * k), -PEAK, PEAK))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = data
	return wav
