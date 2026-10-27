extends Node3D
## M4: um Sprite3D (billboard Y) por inimigo, lido de world.get_enemies() (plano R3 §4.8).

const AssetLib = preload("res://view/asset_lib.gd")

## Por tipo: asset, pixel_size e b (última linha opaca + 1 no PNG 32x32).
const SPRITES: Dictionary = {
	"dummy": {"asset": "enemy.dummy", "pixel_size": 0.05, "b": 30},
	"rat": {"asset": "enemy.rat", "pixel_size": 0.035, "b": 24},
	"skeleton": {"asset": "enemy.skeleton", "pixel_size": 0.05, "b": 32},
	"guardian": {"asset": "enemy.guardian", "pixel_size": 0.0625, "b": 32},
}
const PAIN_FRAMES: int = 6
const DEAD_SCALE_Y: float = 0.3

var _sprites: Dictionary = {}
var _last: Dictionary = {}
var _pain: Dictionary = {}


## Altura do centro do sprite para o pé tocar o piso (y = 0).
static func foot_y(type: String, scale_y: float = 1.0) -> float:
	var s: Dictionary = SPRITES[type]
	return float(int(s["b"]) - 16) * float(s["pixel_size"]) * scale_y


func _make_sprite(e: Dictionary) -> Sprite3D:
	var s: Dictionary = SPRITES[e["type"]]
	var sp := Sprite3D.new()
	sp.name = "Enemy_%d" % int(e["id"])
	sp.texture = AssetLib.load_texture(s["asset"])
	sp.pixel_size = s["pixel_size"]
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.centered = true
	add_child(sp)
	return sp


func apply_state(enemies: Array, player: Dictionary, tick: int) -> void:
	var ang: float = TAU * float(player["angle"]) / 4096.0
	# direita da câmera no plano da simulação (x, z): ângulo - 90°
	var right := Vector2(cos(ang - PI / 2.0), sin(ang - PI / 2.0))
	for e: Dictionary in enemies:
		var id: int = e["id"]
		var sp: Sprite3D = _sprites.get(id)
		if sp == null:
			sp = _make_sprite(e)
			_sprites[id] = sp
		var type: String = e["type"]
		var ps: float = SPRITES[type]["pixel_size"]
		var state: String = e["state"]
		var prev: Dictionary = _last.get(id, e)
		var delta := Vector2(float(e["pos_x"] - prev["pos_x"]), float(e["pos_z"] - prev["pos_z"]))
		if delta != Vector2.ZERO:
			sp.flip_h = delta.dot(right) < 0.0
		if int(e["hp"]) < int(prev["hp"]):
			_pain[id] = PAIN_FRAMES
		var y: float = foot_y(type)
		var scale_v := Vector3.ONE
		var tint := Color(1, 1, 1)
		match state:
			"CHASE":
				if (tick >> 3) & 1 == 1:
					y += ps
			"WINDUP":
				tint = Color(1.0, 0.85, 0.5)
			"STRIKE":
				scale_v = Vector3(1.1, 1.1, 1.1)
				y = foot_y(type, 1.1)
			"DEAD":
				tint = Color(0.35, 0.1, 0.1)
				scale_v = Vector3(1.0, DEAD_SCALE_Y, 1.0)
				y = foot_y(type, DEAD_SCALE_Y)
		var pain: int = _pain.get(id, 0)
		if pain > 0 and state != "DEAD":
			tint = Color(1.0, 0.3, 0.3)
			_pain[id] = pain - 1
		sp.modulate = tint
		sp.scale = scale_v
		sp.position = Vector3(float(e["pos_x"]) / 1024.0, y, -float(e["pos_z"]) / 1024.0)
		_last[id] = e
