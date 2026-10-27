class_name AssetResolver
extends RefCounted
## Identificador lógico -> Texture2D, pelo perfil de arte (padrão "free").

const MAP_PATH: String = "res://assets/asset_map.json"

static var profile: String = "free"
static var _map: Dictionary = {}
static var _cache: Dictionary = {}


static func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	if _map.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_map = parsed
	var tex: Texture2D = null
	var entry: Variant = _map.get(id)
	if typeof(entry) == TYPE_DICTIONARY and (entry as Dictionary).has(profile):
		tex = _load(str(entry[profile]))
	if tex == null:
		push_warning("AssetResolver: '%s' ausente no perfil '%s'; usando placeholder" % [id, profile])
		tex = _placeholder()
	_cache[id] = tex
	return tex


static func _load(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res: Resource = load(path)
		if res is Texture2D:
			return res
	# projeto ainda não importado: lê o PNG direto
	var img: Image = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


static func _placeholder() -> Texture2D:
	var img: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 0, 1))
	return ImageTexture.create_from_image(img)
