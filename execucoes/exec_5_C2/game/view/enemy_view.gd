extends Node3D
## Um Sprite3D billboard por entidade (Enemies/enemy_<id>). Somente leitura de get_enemies();
## animação por estado feita só com transformações (escala, cor, bob, avanço), sem escrever no núcleo.
## Limitação de arte: o perfil `free` tem um único quadro 32x32 por tipo, então a "escolha de
## 8 direções" do GDD fica reduzida a 2 (flip_h conforme o lado para onde o inimigo anda).

const PIXEL_SIZE_BY_TYPE: Dictionary = {"dummy": 0.05, "skeleton": 0.05, "rat": 0.03125, "guardian": 0.0625}
const HALF_HEIGHT_BY_TYPE: Dictionary = {"dummy": 0.8, "skeleton": 0.8, "rat": 0.5, "guardian": 1.0}
const TEX_BY_TYPE: Dictionary = {
	"dummy": "enemy.dummy", "rat": "enemy.rat", "skeleton": "enemy.skeleton", "guardian": "enemy.guardian",
}
const FLASH_S: float = 0.15
const DIE_S: float = 0.3
const STRIKE_S: float = 0.1
const STRIKE_LUNGE_M: float = 0.25
const BOB_M: float = 0.04
const BOB_HZ: float = 4.0
const IDLE_TINT := Color(0.8, 0.8, 0.8)
const WINDUP_TINT := Color(1.0, 0.7, 0.4)

var _sprites: Dictionary = {}     # id -> Sprite3D
var _info: Dictionary = {}        # id -> último dicionário de get_enemies()
var _base: Dictionary = {}        # id -> Vector3 (posição lida do núcleo)
var _last_hp: Dictionary = {}
var _flash: Dictionary = {}       # id -> segundos restantes
var _strike: Dictionary = {}      # id -> segundos restantes do avanço
var _dying: Dictionary = {}       # id -> segundos decorridos
var _cam := Vector3.ZERO
var _time: float = 0.0


func build(world: WorldSim) -> void:
	for c in get_children():
		c.queue_free()
	_sprites.clear()
	_info.clear()
	_base.clear()
	_last_hp.clear()
	_flash.clear()
	_strike.clear()
	_dying.clear()
	refresh(world)


static func half_height(type: String) -> float:
	return HALF_HEIGHT_BY_TYPE.get(type, 0.8)


func _make(e: Dictionary) -> Sprite3D:
	var s := Sprite3D.new()
	s.name = "enemy_%d" % e["id"]
	s.texture = AssetResolver.texture(TEX_BY_TYPE.get(e["type"], "enemy.dummy"))
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = PIXEL_SIZE_BY_TYPE.get(e["type"], 0.05)
	add_child(s)
	_sprites[e["id"]] = s
	_last_hp[e["id"]] = e["hp"]
	return s


func refresh(world: WorldSim) -> void:
	var pp: Array = world.get_player_pos()
	_cam = Vector3(pp[0] / 1024.0, 0.0, -pp[1] / 1024.0)
	for e: Dictionary in world.get_enemies():
		var id: int = e["id"]
		var s: Sprite3D = _sprites.get(id)
		if s == null:
			s = _make(e)
		var pos := Vector3(e["pos_x"] / 1024.0, half_height(e["type"]), -e["pos_z"] / 1024.0)
		if _base.has(id):
			var moved: Vector3 = pos - _base[id]
			if moved.length_squared() > 0.0:
				# lado do passo em relação à câmera: sinal de (câmera->inimigo) x deslocamento
				var to_e: Vector3 = pos - _cam
				s.flip_h = to_e.x * moved.z - to_e.z * moved.x > 0.0
		_base[id] = pos
		var prev: Dictionary = _info.get(id, {})
		if e["state"] == "STRIKE" and prev.get("state", "") != "STRIKE":
			_strike[id] = STRIKE_S
		_info[id] = e
		if e["hp"] < _last_hp.get(id, e["hp"]):
			_flash[id] = FLASH_S
		_last_hp[id] = e["hp"]
		if e["state"] == "DEAD" and not _dying.has(id):
			_dying[id] = 0.0
		_apply(id, 0.0)


func _process(delta: float) -> void:
	_time += delta
	for id: int in _sprites:
		_apply(id, delta)


## Compõe posição/escala/cor do sprite a partir do estado lido e dos temporizadores da view.
func _apply(id: int, delta: float) -> void:
	var s: Sprite3D = _sprites[id]
	var e: Dictionary = _info.get(id, {})
	if e.is_empty():
		return
	var hh: float = half_height(e["type"])
	var pos: Vector3 = _base[id]
	var col := Color.WHITE
	var k_scale: float = 1.0
	match e["state"]:
		"IDLE":
			if e["type"] != "dummy":
				col = IDLE_TINT
		"CHASE":
			pos.y += BOB_M * sin(_time * TAU * BOB_HZ)
		"WINDUP":
			var windup: int = EnemySim.TYPES[e["type"]]["windup"]
			var f: float = clampf(float(e["state_ticks"]) / windup, 0.0, 1.0)
			k_scale = 1.0 + 0.1 * f
			col = Color.WHITE.lerp(WINDUP_TINT, f)
	if _strike.get(id, 0.0) > 0.0:
		_strike[id] -= delta
		var to_cam: Vector3 = _cam - pos
		to_cam.y = 0.0
		if to_cam.length_squared() > 0.0:
			pos += to_cam.normalized() * STRIKE_LUNGE_M
		col = Color(2.0, 2.0, 2.0)
	if _flash.get(id, 0.0) > 0.0:
		_flash[id] -= delta
		col = Color(1.0, 0.25, 0.25)
	s.scale = Vector3(k_scale, k_scale, k_scale)
	pos.y = maxf(pos.y, hh * k_scale) if e["state"] == "WINDUP" else pos.y
	if _dying.has(id):
		_dying[id] += delta
		var k: float = clampf(1.0 - _dying[id] / DIE_S, 0.0, 1.0)
		col = col * Color(0.5, 0.5, 0.5)
		s.scale = Vector3(1.0, maxf(k, 0.01), 1.0)
		pos.y = hh * k
		s.visible = k > 0.0
	s.position = pos
	s.modulate = col
