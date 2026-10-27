class_name AssetResolver
extends RefCounted
## Resolve identificadores lógicos -> Texture2D via res://assets/asset_map.json.
## Nenhum caminho de textura é escrito à mão fora do asset_map.json.

const MAP_PATH: String = "res://assets/asset_map.json"
const DEFAULT_PROFILE: String = "free"

static var profile: String = DEFAULT_PROFILE
static var _map: Dictionary = {}
static var _cache: Dictionary = {}


static func asset_map() -> Dictionary:
	if _map.is_empty():
		var f: FileAccess = FileAccess.open(MAP_PATH, FileAccess.READ)
		if f == null:
			push_error("AssetResolver: %s ausente" % MAP_PATH)
			return {}
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		f.close()
		if typeof(parsed) == TYPE_DICTIONARY:
			_map = parsed
	return _map


static func path_for(id: String) -> String:
	var entry: Variant = asset_map().get(id, null)
	if typeof(entry) != TYPE_DICTIONARY:
		push_error("AssetResolver: id desconhecido '%s'" % id)
		return ""
	var e: Dictionary = entry
	if e.has(profile):
		return String(e[profile])
	if profile != DEFAULT_PROFILE:
		push_warning("AssetResolver: perfil '%s' ausente para '%s'; usando '%s'" % [profile, id, DEFAULT_PROFILE])
	return String(e.get(DEFAULT_PROFILE, ""))


static func resolve(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var path: String = path_for(id)
	if path == "":
		return null
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null and FileAccess.file_exists(path):
		# Projeto ainda não importado (ex.: checkout limpo em headless): lê o PNG direto.
		var img: Image = Image.load_from_file(path)
		if img != null and not img.is_empty():
			tex = ImageTexture.create_from_image(img)
	if tex == null:
		push_error("AssetResolver: falha ao carregar '%s' (%s)" % [id, path])
		return null
	_cache[id] = tex
	return tex


## Libera texturas e mapa em cache (fim dos gates; evita vazamento no ObjectDB).
static func clear_cache() -> void:
	_cache.clear()
	_map.clear()
