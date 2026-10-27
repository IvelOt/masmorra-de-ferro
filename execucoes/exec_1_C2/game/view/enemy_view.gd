class_name EnemyView
extends Sprite3D
## Inimigo em billboard (M4): só lê os dicionários do snapshot. Retorno visual
## por estado via modulate/posição/escala, contado em quadros de render.

const TEXTURES: Array[String] = ["enemy.dummy", "enemy.rat", "enemy.skeleton", "enemy.guardian"]
const PIXEL_SIZE: Array[float] = [0.0625, 0.030, 0.055, 0.070]
const BASE_Y: Array[float] = [0.875, 0.240, 0.880, 1.120]
const WINDUP_TINT: Color = Color(1.0, 0.6, 0.6)
const HURT_TINT: Color = Color(1.0, 0.3, 0.3)
const LUNGE_M: float = 0.15
const LUNGE_FRAMES: int = 6
const HURT_FRAMES: int = 6
const DEATH_FRAMES: int = 18

var enemy_id: int = 0
var enemy_type: int = 0
var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _frame: int = 0
var _hurt: int = 0
var _lunge: int = 0
var _death: int = -1

@onready var _audio: AudioStreamPlayer3D = $Audio


func setup(d: Dictionary) -> void:
	enemy_id = int(d.id)
	enemy_type = int(d.type)
	name = "Enemy%d" % enemy_id
	billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	shaded = false
	alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	centered = true
	texture = AssetResolver.texture(TEXTURES[enemy_type])
	pixel_size = PIXEL_SIZE[enemy_type]
	_prev = d
	_cur = d
	if int(d.state) == EnemySim.DEAD:
		_death = DEATH_FRAMES
		visible = false
	apply(1.0, Vector3.ZERO)


## Novo par de estados após um step(); dispara os efeitos de transição.
func push_state(d: Dictionary) -> void:
	_prev = _cur
	_cur = d
	if int(_cur.hp) < int(_prev.hp):
		_hurt = HURT_FRAMES
	if int(_cur.state) == EnemySim.STRIKE and int(_prev.state) != EnemySim.STRIKE:
		_lunge = LUNGE_FRAMES
	if int(_cur.state) == EnemySim.DEAD and _death < 0:
		_death = 0


func play_stream(stream: AudioStream) -> void:
	if _audio != null and stream != null:
		_audio.stream = stream
		_audio.play()


## Interpola a posição e aplica o retorno visual; cam_pos orienta o lunge.
func apply(frac: float, cam_pos: Vector3) -> void:
	_frame += 1
	var px: float = lerpf(float(_prev.pos_x), float(_cur.pos_x), frac) / 1024.0
	var pz: float = lerpf(float(_prev.pos_z), float(_cur.pos_z), frac) / 1024.0
	var pos: Vector3 = Vector3(px, 0.0, -pz)
	if _lunge > 0:
		var to_cam: Vector3 = Vector3(cam_pos.x - pos.x, 0.0, cam_pos.z - pos.z)
		if to_cam.length() > 0.001:
			pos += to_cam.normalized() * LUNGE_M
		_lunge -= 1
	var sy: float = 1.0
	var c: Color = Color(1, 1, 1, 1)
	if _death >= 0:
		var t: float = minf(float(_death) / float(DEATH_FRAMES), 1.0)
		sy = lerpf(1.0, 0.2, t)
		c.a = 1.0 - t
		if _death >= DEATH_FRAMES:
			visible = false
		_death += 1
	elif _hurt > 0:
		c = HURT_TINT
		_hurt -= 1
	elif int(_cur.state) == EnemySim.WINDUP and (_frame / 4) % 2 == 1:
		c = WINDUP_TINT
	modulate = c
	scale = Vector3(1.0, sy, 1.0)
	pos.y = BASE_Y[enemy_type] * sy
	position = pos
