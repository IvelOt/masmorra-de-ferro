extends Node3D
## Um Sprite3D billboard por item (Items/item_<id>), lido de get_items(). Coletado -> invisível no mesmo
## quadro (o nó não é destruído). Bob e brilho são só visuais; nada é escrito no núcleo.

## tipo -> [identificador, pixel_size, y da base (metade da altura), amplitude do bob (m), pulso de brilho]
const SPEC: Dictionary = {
	"potion_hp": ["item.potion_hp", 0.0125, 0.20, 0.03, 0.0],
	"potion_sp": ["item.potion_sp", 0.0125, 0.20, 0.03, 0.0],
	"gold": ["item.gold", 0.0125, 0.20, 0.0, 0.2],
	"key": ["item.key", 0.015625, 0.25, 0.05, 0.4],
}
const BOB_HZ: float = 1.0
const GLOW_HZ_GOLD: float = 2.0
const GLOW_HZ_KEY: float = 1.0

var _sprites: Dictionary = {}     # id -> Sprite3D
var _types: Dictionary = {}       # id -> tipo
var _time: float = 0.0


func build(world: WorldSim) -> void:
	for c in get_children():
		remove_child(c)
		c.free()
	_sprites.clear()
	_types.clear()
	for it: Dictionary in world.get_items():
		var spec: Array = SPEC[it["type"]]
		var s := Sprite3D.new()
		s.name = "item_%d" % it["id"]
		s.texture = AssetResolver.texture(spec[0])
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.shaded = false
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.pixel_size = spec[1]
		s.position = Vector3((it["cell_x"] * 2048 + 1024) / 1024.0, spec[2], -(it["cell_z"] * 2048 + 1024) / 1024.0)
		add_child(s)
		_sprites[it["id"]] = s
		_types[it["id"]] = it["type"]
	refresh(world)


func refresh(world: WorldSim) -> void:
	for it: Dictionary in world.get_items():
		var s: Sprite3D = _sprites.get(it["id"])
		if s != null:
			s.visible = not it["taken"]


func _process(delta: float) -> void:
	_time += delta
	for id: int in _sprites:
		var s: Sprite3D = _sprites[id]
		if not s.visible:
			continue
		var spec: Array = SPEC[_types[id]]
		s.position.y = spec[2] + spec[3] * sin(_time * TAU * BOB_HZ)
		if spec[4] > 0.0:
			var hz: float = GLOW_HZ_KEY if _types[id] == "key" else GLOW_HZ_GOLD
			var g: float = 1.0 + spec[4] * (0.5 + 0.5 * sin(_time * TAU * hz))
			s.modulate = Color(g, g, g)
