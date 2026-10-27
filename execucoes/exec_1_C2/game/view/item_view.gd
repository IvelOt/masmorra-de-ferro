class_name ItemView
extends Sprite3D
## Item no piso (M6) em billboard: só lê o dicionário do item no snapshot.
## A oscilação, o giro da chave e o sumiço ao coletar são só visuais.

const TEXTURES: Array[String] = ["item.potion_hp", "item.potion_sp", "item.key", "item.gold"]
const PIXEL_SIZE: Array[float] = [0.016, 0.016, 0.016, 0.0125]
# pé do conteúdo opaco no piso: (16 - linhas vazias abaixo) x pixel_size; a chave flutua 0,25 m
const BASE_Y: Array[float] = [0.208, 0.208, 0.330, 0.1875]
const BOB_M: float = 0.04
const BOB_PERIOD_S: float = 1.5
const KEY_SPIN_DEG_S: float = 90.0
const TAKE_FRAMES: int = 12
const TAKE_RISE_M: float = 0.3

var item_id: int = 0
var item_type: int = 0
var _taken_frame: int = -1
var _t: float = 0.0


func setup(d: Dictionary) -> void:
	item_id = int(d.id)
	item_type = int(d.type)
	name = "Item%d" % item_id
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shaded = false
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	centered = true
	texture = AssetResolver.texture(TEXTURES[item_type])
	pixel_size = PIXEL_SIZE[item_type]
	position = Vector3(int(d.cell_x) * 2 + 1, BASE_Y[item_type], -(int(d.cell_z) * 2 + 1))
	if bool(d.taken):
		_taken_frame = TAKE_FRAMES
		visible = false


func push_state(d: Dictionary) -> void:
	if bool(d.taken) and _taken_frame < 0:
		_taken_frame = 0


func _process(dt: float) -> void:
	if not visible:
		return
	_t += dt
	var y: float = BASE_Y[item_type] + BOB_M * sin(TAU * _t / BOB_PERIOD_S + float(item_id) * 0.7)
	if item_type == ItemsSim.KEY:
		rotation.y = deg_to_rad(fmod(_t * KEY_SPIN_DEG_S, 360.0))
	if _taken_frame >= 0:
		var k: float = float(_taken_frame) / float(TAKE_FRAMES)
		y += TAKE_RISE_M * k
		modulate.a = 1.0 - k
		_taken_frame += 1
		if _taken_frame > TAKE_FRAMES:
			visible = false
	position.y = y
