class_name ItemView
extends Node3D
## M6: um Sprite3D billboard por item (Main/Items/Item_<id>), escrito a partir de
## get_state().items. Item coletado fica invisível (o nó permanece). Só apresentação.

## Altura visível alvo (m) e base (m) por tipo: POTION_HP, POTION_SP, KEY, GOLD.
const TARGET_M: Array = [0.40, 0.40, 0.25, 0.30]
const BASE_M: Array = [0.0, 0.0, 0.35, 0.0]
const KEY_FLOAT_M: float = 0.05
const KEY_FLOAT_S: float = 1.5

var _sprites: Dictionary = {}   # id -> Sprite3D
var _base_y: Dictionary = {}    # id -> Y do centro com a base no alvo
var _types: Dictionary = {}     # id -> tipo


func build(items: Array) -> void:
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_sprites.clear()
	_base_y.clear()
	_types.clear()
	for it: Dictionary in items:
		_add_sprite(it)
	push_state(items)


func _add_sprite(it: Dictionary) -> void:
	var id: int = int(it["id"])
	var t: int = int(it["type"])
	var s: Sprite3D = Sprite3D.new()
	s.name = "Item_%d" % id
	s.texture = AssetResolver.resolve(String(ItemsSim.TEX_IDS[t]))
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.centered = true
	var used: Rect2i = Rect2i(0, 0, 32, 32)
	if s.texture != null:
		used = s.texture.get_image().get_used_rect()
	s.pixel_size = float(TARGET_M[t]) / float(used.size.y)
	var by: float = float(BASE_M[t]) + float(used.end.y - 16) * s.pixel_size
	var c: Vector3 = PlayerView.sim_to_world(int(it["cell_x"]) * Grid.CELL + Grid.CELL / 2,
		int(it["cell_z"]) * Grid.CELL + Grid.CELL / 2)
	s.position = Vector3(c.x, by, c.z)
	add_child(s)
	_sprites[id] = s
	_base_y[id] = by
	_types[id] = t


func sprite_count() -> int:
	return _sprites.size()


func push_state(items: Array) -> void:
	for it: Dictionary in items:
		var id: int = int(it["id"])
		if not _sprites.has(id):
			_add_sprite(it)
		(_sprites[id] as Sprite3D).visible = not bool(it["taken"])


func _process(_dt: float) -> void:
	var t: float = float(Time.get_ticks_msec()) / 1000.0
	for id: int in _sprites.keys():
		if int(_types[id]) != ItemsSim.KEY:
			continue
		var s: Sprite3D = _sprites[id]
		s.position.y = float(_base_y[id]) + KEY_FLOAT_M * sin(TAU * t / KEY_FLOAT_S)
