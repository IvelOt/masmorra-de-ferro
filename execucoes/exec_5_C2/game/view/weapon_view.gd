extends CanvasLayer
## Espada e escudo 2D em primeira pessoa (CanvasLayer 1). Somente leitura do núcleo:
## anima por transformação a partir de get_player_status() e da velocidade.

const SCALE: int = 4
const SPRITE_PX: int = 32
const SWORD_REST: Vector2 = Vector2(448, 212)     # borda inferior em y = 340
const SHIELD_REST: Vector2 = Vector2(32, 244)     # borda inferior em y = 372
const WINDUP_END: Vector3 = Vector3(24, -40, -25)     # (dx, dy, graus)
const ACTIVE_END: Vector3 = Vector3(-200, -8, 50)
const SHIELD_UP: Vector2 = Vector2(72, -96)
const SHIELD_STUN: Vector2 = Vector2(0, 32)
const SHIELD_FRAMES: float = 4.0
const TERMINAL_VEL: float = 139.0

@onready var sword: TextureRect = $Sword
@onready var shield: TextureRect = $Shield

var _status: Dictionary = {}
var _shield_t: float = 0.0          # 0 = repouso, 1 = levantado
var _bob_phase: float = 0.0
var _speed: float = 0.0
var _last_pos: Array = []
var _blink_t: float = 0.0


func _ready() -> void:
	_setup(sword, "weapon.sword")
	_setup(shield, "weapon.shield")
	sword.pivot_offset = Vector2(SPRITE_PX * SCALE, SPRITE_PX * SCALE)
	shield.pivot_offset = Vector2(0, SPRITE_PX * SCALE)
	sword.position = SWORD_REST
	shield.position = SHIELD_REST


static func _setup(r: TextureRect, id: String) -> void:
	r.texture = AssetResolver.texture(id)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.size = Vector2(SPRITE_PX * SCALE, SPRITE_PX * SCALE)


func refresh(world: WorldSim) -> void:
	_status = world.get_player_status()
	var pos: Array = world.get_player_pos()
	var vel: Array = world.get_player_vel()
	_speed = Vector2(vel[0], vel[1]).length()
	if not _last_pos.is_empty():
		_bob_phase += Vector2(pos[0] - _last_pos[0], pos[1] - _last_pos[1]).length() / 1024.0 * PI
	_last_pos = pos


func _sword_pose() -> Vector3:
	var st: String = _status.get("swing_state", "IDLE")
	var t: int = _status.get("swing_ticks", 0)
	match st:
		"WINDUP":
			return Vector3.ZERO.lerp(WINDUP_END, t / float(Combat.WINDUP_TICKS))
		"ACTIVE":
			return WINDUP_END.lerp(ACTIVE_END, t / float(Combat.ACTIVE_TICKS))
		"RECOVERY":
			return ACTIVE_END.lerp(Vector3.ZERO, t / float(Combat.RECOVERY_TICKS))
	return Vector3.ZERO


func _process(delta: float) -> void:
	if _status.is_empty():
		return
	var bob: float = round(4.0 * _speed / TERMINAL_VEL * sin(_bob_phase))
	var pose: Vector3 = _sword_pose()
	sword.position = (SWORD_REST + Vector2(pose.x, pose.y + bob)).round()
	sword.rotation_degrees = pose.z
	var stunned: bool = _status.get("stun_ticks", 0) > 0
	var target: float = 1.0 if _status.get("blocking", false) else 0.0
	var step: float = 1.0 / SHIELD_FRAMES
	_shield_t = move_toward(_shield_t, target, step)
	var off: Vector2 = SHIELD_REST.lerp(SHIELD_REST + SHIELD_UP, _shield_t) - SHIELD_REST
	if stunned:
		off = SHIELD_STUN
		_blink_t += delta
		shield.modulate = Color(1.0, 0.45, 0.45) if int(_blink_t * 16.0) % 2 == 0 else Color.WHITE
	else:
		_blink_t = 0.0
		shield.modulate = Color.WHITE
	shield.position = (SHIELD_REST + off + Vector2(0, bob)).round()
