extends CanvasLayer
## Espada e escudo em 1ª pessoa (plano §6.2), CanvasLayer layer = 1, abaixo da HUD (2).
## Só lê o snapshot: a pose da espada vem de swing_state/swing_ticks, o escudo de blocking,
## o tremor de stun_ticks e o bob da velocidade. Tudo aqui é visual (fora do hash).
## Rodada 3 (plano §8.4): escudo em escala 3 (96 × 96 px), inteiro acima da HUD (y < 312).

const AssetResolver = preload("res://view/asset_resolver.gd")

const SCALE: int = 4
const SHIELD_SCALE: int = 3
## Poses da espada: [centro (px), rotação (graus)].
const SWORD_IDLE: Array = [Vector2(500, 286), 0.0]
const SWORD_RAISED: Array = [Vector2(548, 246), 25.0]
const SWORD_END: Array = [Vector2(300, 276), -70.0]
const SHIELD_IDLE: Vector2 = Vector2(100, 258)
const SHIELD_UP: Vector2 = Vector2(220, 226)
const SHIELD_FRAMES: float = 6.0
const PHASE_LEN: Dictionary = {"WINDUP": 6, "ACTIVE": 6, "RECOVERY": 12}
## Velocidade terminal de corrida (u/tick): referência para o passo do bob.
const RUN_SPEED: float = 139.0
const BOB_HZ: float = 1.6

@onready var _sword: Sprite2D = $Sword
@onready var _shield: Sprite2D = $Shield

var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _shield_t: float = 0.0
var _phi: float = 0.0


func _ready() -> void:
	var res: AssetResolver = AssetResolver.new()
	_sword.texture = res.texture("weapon.sword")
	_shield.texture = res.texture("weapon.shield")
	for sp: Sprite2D in [_sword, _shield]:
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.centered = true
	_sword.scale = Vector2(SCALE, SCALE)
	_shield.scale = Vector2(SHIELD_SCALE, SHIELD_SCALE)
	_sword.position = SWORD_IDLE[0]
	_shield.position = SHIELD_IDLE


func update(prev: Dictionary, cur: Dictionary) -> void:
	_prev = prev.player
	_cur = cur.player


static func sword_pose(p: Dictionary) -> Array:
	var st: String = p.swing_state
	if not PHASE_LEN.has(st):
		return SWORD_IDLE
	var k: float = clampf(float(p.swing_ticks) / float(PHASE_LEN[st]), 0.0, 1.0)
	var a: Array = SWORD_IDLE
	var b: Array = SWORD_IDLE
	if st == "WINDUP":
		b = SWORD_RAISED
	elif st == "ACTIVE":
		a = SWORD_RAISED
		b = SWORD_END
	else:
		a = SWORD_END
	return [(a[0] as Vector2).lerp(b[0], k), lerpf(a[1], b[1], k)]


func _process(delta: float) -> void:
	if _cur.is_empty():
		return
	var frac: float = Engine.get_physics_interpolation_fraction()
	var p0: Array = sword_pose(_prev)
	var p1: Array = sword_pose(_cur)
	var spos: Vector2 = (p0[0] as Vector2).lerp(p1[0], frac)
	var srot: float = lerpf(p0[1], p1[1], frac)
	# bob proporcional à velocidade; zero parado e durante ACTIVE
	var speed: float = float(absi(_cur.vel_x) + absi(_cur.vel_z))
	var bob: Vector2 = Vector2.ZERO
	if speed > 0.0 and _cur.swing_state != "ACTIVE":
		_phi += TAU * BOB_HZ * (speed / RUN_SPEED) * delta
		bob = Vector2(roundf(4.0 * sin(_phi)), roundf(3.0 * absf(cos(_phi))))
	elif speed == 0.0:
		_phi = 0.0
	_sword.position = (spos + bob).round()
	_sword.rotation_degrees = srot
	# escudo: sobe/desce em 6 quadros; tremor de ±3 px a cada 2 quadros quando atordoado
	var target: float = 1.0 if _cur.blocking else 0.0
	_shield_t = move_toward(_shield_t, target, 1.0 / SHIELD_FRAMES)
	var shpos: Vector2 = SHIELD_IDLE.lerp(SHIELD_UP, _shield_t) + bob
	if int(_cur.stun_ticks) > 0:
		shpos.x += 3.0 if ((Engine.get_process_frames() >> 1) & 1) == 0 else -3.0
	_shield.position = shpos.round()
