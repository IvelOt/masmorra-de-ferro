class_name EnemyView
extends Node3D
## Inimigos em billboard 2.5D (M4): um Sprite3D por inimigo, nomeado Enemy_<id>,
## escrito a partir do estado inteiro. Animações e áudio são só apresentação.

## Altura visível alvo em metros por tipo (DUMMY, RAT, SKELETON, GUARDIAN).
const TARGET_M: Array = [1.60, 0.50, 1.75, 2.30]
const TEX_IDS: Array = ["enemy.dummy", "enemy.rat", "enemy.skeleton", "enemy.guardian"]
const WINDUP_TINT: Color = Color(1.0, 0.6, 0.3)
const HURT_FRAMES: int = 6
const STRIKE_FRAMES: int = 4
const STRIKE_LUNGE_M: float = 0.15
const DEATH_TIME: float = 0.3

var audio: Node = null
var _sprites: Dictionary = {}    # id -> Sprite3D
var _base_y: Dictionary = {}     # id -> float
var _prev: Dictionary = {}       # id -> dict do estado anterior
var _curr: Dictionary = {}       # id -> dict do estado corrente
var _hurt: Dictionary = {}       # id -> quadros restantes de flash vermelho
var _lunge: Dictionary = {}      # id -> quadros restantes de avanço
var _death_t: Dictionary = {}    # id -> segundos desde a morte
var _sounds: Dictionary = {}     # id -> AudioStreamPlayer3D
var _player_pos: Vector3 = Vector3.ZERO


## Cria os sprites a partir de get_state().enemies.
func build(enemies: Array, p_audio: Node) -> void:
	audio = p_audio
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_sprites.clear()
	_prev.clear()
	_curr.clear()
	for e: Dictionary in enemies:
		_add_sprite(e)
	push_state(enemies, Vector3.ZERO, true)


func _add_sprite(e: Dictionary) -> void:
	var id: int = int(e["id"])
	var t: int = int(e["type"])
	var s: Sprite3D = Sprite3D.new()
	s.name = "Enemy_%d" % id
	s.texture = AssetResolver.resolve(String(TEX_IDS[t]))
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	# Limiar baixo: o morto (modulate.a = 0,35) continua visível, escurecido.
	s.alpha_scissor_threshold = 0.1
	s.centered = true
	# Escala pela área opaca (os sprites têm margens transparentes) e base no piso.
	var used: Rect2i = Rect2i(0, 0, 32, 32)
	if s.texture != null:
		used = s.texture.get_image().get_used_rect()
	s.pixel_size = float(TARGET_M[t]) / float(used.size.y)
	var by: float = float(used.end.y - 16) * s.pixel_size
	s.position = PlayerView.sim_to_world(int(e["pos_x"]), int(e["pos_z"])) + Vector3(0, by, 0)
	add_child(s)
	_sprites[id] = s
	_base_y[id] = by
	if audio != null:
		var p: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
		p.name = "Voice"
		p.bus = "SFX"
		p.unit_size = 4.0
		p.max_distance = 24.0
		p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE
		s.add_child(p)
		_sounds[id] = p


func sprite_count() -> int:
	return _sprites.size()


## Novo estado dos inimigos; dispara efeitos por diferença de estados.
func push_state(enemies: Array, player_pos: Vector3, snap: bool = false) -> void:
	_player_pos = player_pos
	for e: Dictionary in enemies:
		var id: int = int(e["id"])
		if not _sprites.has(id):
			_add_sprite(e)
		var old: Dictionary = _curr.get(id, e)
		_prev[id] = e if snap else old
		_curr[id] = e
		if snap:
			continue
		var st: int = int(e["state"])
		var t: int = int(e["type"])
		if int(e["hp"]) < int(old["hp"]):
			_hurt[id] = HURT_FRAMES
			_play(id, "hit")
		if bool(e["awake"]) and not bool(old["awake"]):
			_play(id, "wake_%d" % t)
		if st == EnemySim.WINDUP and int(old["state"]) != EnemySim.WINDUP:
			_play(id, "warn_%d" % t)
		if st == EnemySim.STRIKE and int(old["state"]) != EnemySim.STRIKE:
			_lunge[id] = STRIKE_FRAMES
		if st == EnemySim.DEAD and int(old["state"]) != EnemySim.DEAD:
			_death_t[id] = 0.0
			_play(id, "die")
	_apply(1.0, 0.0)


func _play(id: int, stream_name: String) -> void:
	if audio == null or not _sounds.has(id):
		return
	var st: AudioStream = audio.call("get_stream", stream_name)
	if st == null:
		return
	var p: AudioStreamPlayer3D = _sounds[id]
	p.stream = st
	p.play()


func _process(dt: float) -> void:
	if _curr.is_empty():
		return
	_apply(Engine.get_physics_interpolation_fraction(), dt)


func _apply(t: float, dt: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	var f: int = Engine.get_frames_drawn()
	for id: int in _curr.keys():
		var s: Sprite3D = _sprites[id]
		var e: Dictionary = _curr[id]
		var p: Dictionary = _prev[id]
		var a0: Vector3 = PlayerView.sim_to_world(int(p["pos_x"]), int(p["pos_z"]))
		var a1: Vector3 = PlayerView.sim_to_world(int(e["pos_x"]), int(e["pos_z"]))
		var pos: Vector3 = a0.lerp(a1, t)
		# flip_h quando anda para a esquerda da tela.
		if cam != null and a1 != a0:
			var right: Vector3 = cam.global_basis.x
			var side: float = (a1 - a0).dot(right)
			if absf(side) > 0.001:
				s.flip_h = side < 0.0
		var st: int = int(e["state"])
		var col: Color = Color(1, 1, 1, 1)
		var sc: Vector3 = Vector3.ONE
		if st == EnemySim.WINDUP:
			var k: float = 0.5 + 0.5 * sin(float(f) * 0.6)
			col = Color(1, 1, 1).lerp(WINDUP_TINT, k)
			sc.y = 1.06
		elif st == EnemySim.IDLE and not bool(e["awake"]):
			sc.y = 1.0 + 0.02 * sin(float(f) * 0.05 + float(id))
		if _lunge.get(id, 0) > 0:
			var dir: Vector3 = _player_pos - pos
			dir.y = 0.0
			if dir.length() > 0.001:
				pos += dir.normalized() * STRIKE_LUNGE_M
			if dt > 0.0:
				_lunge[id] = int(_lunge[id]) - 1
		if _hurt.get(id, 0) > 0:
			col = Color(1.0, 0.25, 0.25)
			if dt > 0.0:
				_hurt[id] = int(_hurt[id]) - 1
		if st == EnemySim.DEAD:
			# Tombar: achatado sobre o piso e translúcido (o nó permanece).
			var d: float = clampf(float(_death_t.get(id, DEATH_TIME)) / DEATH_TIME, 0.0, 1.0)
			_death_t[id] = float(_death_t.get(id, DEATH_TIME)) + dt
			sc = Vector3(1.0 + 0.3 * d, 1.0 - 0.7 * d, 1.0)
			col = Color(0.6, 0.55, 0.5, lerpf(1.0, 0.35, d))
		s.modulate = col
		s.scale = sc
		# A escala é em torno do centro do quadro: corrige Y para a base ficar no piso.
		s.position = Vector3(pos.x, float(_base_y[id]) * sc.y, pos.z)


func _exit_tree() -> void:
	for p: AudioStreamPlayer3D in _sounds.values():
		p.stop()
