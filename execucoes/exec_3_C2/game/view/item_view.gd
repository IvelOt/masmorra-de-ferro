extends Node3D
## M6: um Sprite3D (billboard Y) por item não coletado, lido de world.get_items()
## (plano R4 §4.10).

const AssetLib = preload("res://view/asset_lib.gd")

## Por tipo: asset, pixel_size e b (última linha opaca + 1 no PNG 32x32).
const SPRITES: Dictionary = {
	"potion_hp": {"asset": "item.potion_hp", "pixel_size": 0.016, "b": 29},
	"potion_sp": {"asset": "item.potion_sp", "pixel_size": 0.016, "b": 29},
	"key": {"asset": "item.key", "pixel_size": 0.016, "b": 21},
	"gold": {"asset": "item.gold", "pixel_size": 0.012, "b": 31},
}
const BOB_AMPLITUDE: float = 0.03
const BOB_PERIOD_TICKS: float = 60.0

var _sprites: Dictionary = {}


## Altura do centro do sprite para o pé tocar o piso (y = 0).
static func foot_y(type: String) -> float:
	var s: Dictionary = SPRITES[type]
	return float(int(s["b"]) - 16) * float(s["pixel_size"])


func _make_sprite(it: Dictionary) -> Sprite3D:
	var s: Dictionary = SPRITES[it["type"]]
	var sp := Sprite3D.new()
	sp.name = "Item_%d" % int(it["id"])
	sp.texture = AssetLib.load_texture(s["asset"])
	sp.pixel_size = s["pixel_size"]
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.centered = true
	add_child(sp)
	return sp


func apply_state(items: Array, tick: int) -> void:
	var bob: float = BOB_AMPLITUDE * sin(TAU * float(tick) / BOB_PERIOD_TICKS)
	for it: Dictionary in items:
		var id: int = it["id"]
		var sp: Sprite3D = _sprites.get(id)
		if sp == null:
			sp = _make_sprite(it)
			_sprites[id] = sp
		sp.visible = not it["taken"]
		var x: float = (float(it["cell_x"]) + 0.5) * 2.0
		var z: float = -(float(it["cell_z"]) + 0.5) * 2.0
		sp.position = Vector3(x, foot_y(it["type"]) + bob, z)
