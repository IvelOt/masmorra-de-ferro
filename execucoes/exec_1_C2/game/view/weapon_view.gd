class_name WeaponView
extends CanvasLayer
## Espada e escudo em primeira pessoa (M3), escala inteira 4x sobre a tela
## interna de 640x360. Pose lida de swing_state/swing_ticks/blocking/stun_ticks.

const SWORD_REST: Vector2 = Vector2(600 - 128, 336 - 128)    # canto inferior direito em (600, 336)
const SWORD_PIVOT: Vector2 = Vector2(24, 104)
const SHIELD_REST: Vector2 = Vector2(-8, 372 - 128)          # canto inferior esquerdo em (-8, 372)
const SHIELD_UP: Vector2 = Vector2(176, 300 - 128)           # canto inferior esquerdo em (176, 300)
const SHIELD_PIVOT: Vector2 = Vector2(0, 128)               # gira em torno do canto inferior esquerdo
const SHIELD_REST_DEG: float = -8.0
const SHIELD_REST_TINT: Color = Color(0.85, 0.85, 0.85)
const SHIELD_FRAMES: float = 5.0
const BOB_PX: float = 6.0
const BOB_STEP: float = 0.18
const BOB_VEL_REF: float = 139.0

var _shield_t: float = 0.0
var _phi: float = 0.0
var _frame: int = 0

@onready var _sword: TextureRect = $Sword
@onready var _shield: TextureRect = $Shield


func _ready() -> void:
	_setup_rect(_sword, "weapon.sword")
	_setup_rect(_shield, "weapon.shield")
	_sword.pivot_offset = SWORD_PIVOT
	_sword.position = SWORD_REST
	_shield.pivot_offset = SHIELD_PIVOT
	_shield.position = SHIELD_REST
	_shield.rotation_degrees = SHIELD_REST_DEG
	_shield.modulate = SHIELD_REST_TINT


func _setup_rect(r: TextureRect, id: String) -> void:
	r.texture = AssetResolver.texture(id)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.size = Vector2(128, 128)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE


## [rotação em graus, deslocamento] para um estado do golpe.
static func sword_pose(state: int, ticks: int) -> Array:
	match state:
		Combat.S_WINDUP:
			var t: float = float(ticks) / float(Combat.SWING_WINDUP)
			return [lerpf(0.0, -35.0, t), Vector2.ZERO.lerp(Vector2(24, -24), t)]
		Combat.S_ACTIVE:
			var t: float = float(ticks - Combat.SWING_WINDUP) / float(Combat.SWING_ACTIVE)
			return [lerpf(-35.0, 70.0, t), Vector2(24, -24).lerp(Vector2(-180, -8), t)]
		Combat.S_RECOVERY:
			var t: float = float(ticks - Combat.SWING_WINDUP - Combat.SWING_ACTIVE) / float(Combat.SWING_RECOVERY)
			return [lerpf(70.0, 0.0, t), Vector2(-180, -8).lerp(Vector2.ZERO, t)]
	return [0.0, Vector2.ZERO]


## prev/cur: dicionários "player" do snapshot; frac: fração de interpolação.
func apply(prev: Dictionary, cur: Dictionary, frac: float) -> void:
	_frame += 1
	var a: Array = sword_pose(int(prev.swing_state), int(prev.swing_ticks))
	var b: Array = sword_pose(int(cur.swing_state), int(cur.swing_ticks))
	# um golpe novo não interpola a partir do fim do anterior
	if int(cur.swing_ticks) == 1 or int(cur.swing_state) == Combat.S_IDLE:
		a = b
	var rot: float = lerpf(float(a[0]), float(b[0]), frac)
	var off: Vector2 = (a[1] as Vector2).lerp(b[1] as Vector2, frac)
	var vel: float = float(maxi(absi(int(cur.vel_x)), absi(int(cur.vel_z))))
	var bob: float = 0.0
	if vel > 0.0:
		_phi += BOB_STEP
		bob = BOB_PX * minf(1.0, vel / BOB_VEL_REF) * absf(sin(_phi))
	_sword.rotation_degrees = rot
	_sword.position = SWORD_REST + off + Vector2(0, bob)
	var stunned: bool = int(cur.stun_ticks) > 0
	if bool(cur.blocking) and not stunned:
		_shield_t = minf(1.0, _shield_t + 1.0 / SHIELD_FRAMES)
	else:
		_shield_t = maxf(0.0, _shield_t - 1.0 / SHIELD_FRAMES)
	var sp: Vector2 = SHIELD_REST.lerp(SHIELD_UP, _shield_t) + Vector2(0, bob)
	if stunned:
		sp += Vector2(2.0 if _frame % 2 == 0 else -2.0, 0)
	_shield.position = sp
	_shield.rotation_degrees = lerpf(SHIELD_REST_DEG, 0.0, _shield_t)
	_shield.modulate = SHIELD_REST_TINT.lerp(Color(1, 1, 1), _shield_t)
