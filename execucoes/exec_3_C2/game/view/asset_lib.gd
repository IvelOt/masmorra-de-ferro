extends RefCounted
## Resolução compartilhada de identificadores lógicos de assets/asset_map.json (perfil free).

const ASSET_MAP_PATH: String = "res://assets/asset_map.json"
const ASSET_PROFILE: String = "free"

static var _asset_map: Dictionary = {}


static func asset_path(id: String) -> String:
	if _asset_map.is_empty():
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(ASSET_MAP_PATH))
		if typeof(parsed) == TYPE_DICTIONARY:
			_asset_map = parsed
	return _asset_map.get(id, {}).get(ASSET_PROFILE, "")


static func load_texture(id: String) -> Texture2D:
	var path: String = asset_path(id)
	if path.is_empty() or not FileAccess.file_exists(path):
		push_warning("AssetLib: asset ausente %s" % id)
		return null
	if DirAccess.dir_exists_absolute("res://.godot/imported"):
		return load(path) as Texture2D
	# clone limpo, sem importação: lê o PNG direto
	var img := Image.load_from_file(path)
	return ImageTexture.create_from_image(img) if img != null else null
