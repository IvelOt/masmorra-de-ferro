extends Node3D
## Itens do snapshot em billboard (plano da rodada 3 §8.2): um Sprite3D `Item_<id>` por item,
## centro da célula, y = 0,26 m com balanço de ±0,04 m a 1 Hz; some quando `taken`. Só lê o snapshot.

const AssetResolver = preload("res://view/asset_resolver.gd")

const UNITS_PER_M: float = 1024.0
const CELL_U: int = 2048
const HALF_CELL_U: int = 1024
const PIXEL_SIZE: float = 0.016
const CENTER_Y: float = 0.26
const BOB_AMP: float = 0.04
const BOB_HZ: float = 1.0

var _resolver: AssetResolver = null
var _t: float = 0.0


func setup(resolver: AssetResolver, snapshot: Dictionary) -> void:
	_resolver = resolver
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	for it: Dictionary in snapshot.get("items", []):
		add_child(_make_sprite(it))


func _make_sprite(it: Dictionary) -> Sprite3D:
	var sp: Sprite3D = Sprite3D.new()
	sp.name = "Item_%d" % int(it.id)
	sp.texture = _resolver.texture("item.%s" % it.type)
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.pixel_size = PIXEL_SIZE
	sp.position = Vector3(float(int(it.cell_x) * CELL_U + HALF_CELL_U) / UNITS_PER_M, CENTER_Y,
		-float(int(it.cell_z) * CELL_U + HALF_CELL_U) / UNITS_PER_M)
	sp.visible = not it.taken
	return sp


func update(cur: Dictionary) -> void:
	for it: Dictionary in cur.get("items", []):
		var sp: Sprite3D = get_node_or_null("Item_%d" % int(it.id))
		if sp == null:
			sp = _make_sprite(it)
			add_child(sp)
		sp.visible = not it.taken


func _process(delta: float) -> void:
	_t += delta
	var y: float = CENTER_Y + BOB_AMP * sin(TAU * BOB_HZ * _t)
	for c: Node in get_children():
		(c as Node3D).position.y = y
