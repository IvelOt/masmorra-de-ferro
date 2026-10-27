extends CanvasLayer
## M3: espada e escudo 2D em primeira pessoa sobre a câmera (plano R3 §3.8).
## Só lê o estado do jogador (dicionário de get_player()).

const AssetLib = preload("res://view/asset_lib.gd")

const SCALE: int = 4
const SIZE_PX: int = 32 * SCALE
## Topo da barra da HUD: a arma é recortada acima dela.
const HUD_TOP: int = 312
const SWORD_REST: Vector2 = Vector2(440, 184)
const SWORD_WINDUP: Vector2 = Vector2(472, 160)
const SWORD_ACTIVE_END: Vector2 = Vector2(296, 196)
const SWORD_PIVOT: Vector2 = Vector2(24, 104)
const SWORD_WINDUP_DEG: float = -35.0
const SWORD_ACTIVE_END_DEG: float = 55.0
## O plano dá (56, 200), mas 200 + 128 > 312 sobreporia a HUD; a regra
## "inteiramente acima da HUD em repouso" prevalece: y = 312 - 128.
const SHIELD_REST: Vector2 = Vector2(56, HUD_TOP - SIZE_PX)
const SHIELD_BLOCK: Vector2 = Vector2(224, 168)
const BOB_SPEED_REF: float = 139.0

var sword: TextureRect
var shield: TextureRect
var _clip: Control
var _bob_phase: float = 0.0
var _last_pos: Vector2 = Vector2.ZERO
var _has_last: bool = false


func _ready() -> void:
	layer = 1
	_clip = Control.new()
	_clip.name = "WeaponClip"
	_clip.position = Vector2.ZERO
	_clip.size = Vector2(640, HUD_TOP)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	shield = _make_rect("Shield", "weapon.shield")
	shield.position = SHIELD_REST
	sword = _make_rect("Sword", "weapon.sword")
	sword.position = SWORD_REST
	sword.pivot_offset = SWORD_PIVOT


func _make_rect(node_name: String, asset_id: String) -> TextureRect:
	var r := TextureRect.new()
	r.name = node_name
	r.texture = AssetLib.load_texture(asset_id)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.size = Vector2(SIZE_PX, SIZE_PX)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clip.add_child(r)
	return r


## Pose da espada: função pura do estado do golpe -> [posição, graus].
static func sword_pose(swing_state: String, swing_ticks: int) -> Array:
	match swing_state:
		"WINDUP":
			var t: float = clampf(float(swing_ticks) / 6.0, 0.0, 1.0)
			return [SWORD_REST.lerp(SWORD_WINDUP, t), lerpf(0.0, SWORD_WINDUP_DEG, t)]
		"ACTIVE":
			var t: float = clampf(float(swing_ticks - 6) / 6.0, 0.0, 1.0)
			return [SWORD_WINDUP.lerp(SWORD_ACTIVE_END, t), lerpf(SWORD_WINDUP_DEG, SWORD_ACTIVE_END_DEG, t)]
		"RECOVERY":
			var t: float = clampf(float(swing_ticks - 12) / 12.0, 0.0, 1.0)
			return [SWORD_ACTIVE_END.lerp(SWORD_REST, t), lerpf(SWORD_ACTIVE_END_DEG, 0.0, t)]
	return [SWORD_REST, 0.0]


func apply_state(p: Dictionary) -> void:
	var pos := Vector2(float(p["pos_x"]), float(p["pos_z"]))
	if _has_last:
		_bob_phase += pos.distance_to(_last_pos) / 1024.0 * PI
	_last_pos = pos
	_has_last = true
	var speed: float = Vector2(float(p["vel_x"]), float(p["vel_z"])).length()
	var amp: float = minf(1.0, speed / BOB_SPEED_REF)
	var bob := Vector2(roundf(4.0 * sin(_bob_phase) * amp), roundf(3.0 * absf(cos(_bob_phase)) * amp))
	var pose: Array = sword_pose(p["swing_state"], p["swing_ticks"])
	sword.position = (pose[0] as Vector2) + bob
	sword.rotation_degrees = pose[1]
	shield.position = (SHIELD_BLOCK if p["blocking"] else SHIELD_REST) + bob
