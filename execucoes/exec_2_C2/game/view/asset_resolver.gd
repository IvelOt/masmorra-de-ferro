extends RefCounted
## Resolve identificador lógico -> Texture2D via res://assets/asset_map.json (GDD §7.4.2).
## Perfil ativo: `free` por padrão, ou `--art-profile=<nome>` nos argumentos de usuário.

const MAP_PATH: String = "res://assets/asset_map.json"
const DEFAULT_PROFILE: String = "free"

var profile: String = DEFAULT_PROFILE
var _map: Dictionary = {}
var _cache: Dictionary = {}


func _init() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--art-profile="):
			profile = arg.get_slice("=", 1)
	var f: FileAccess = FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		push_error("asset_resolver: não foi possível abrir %s" % MAP_PATH)
		return
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		_map = parsed


func path_of(id: String) -> String:
	var entry: Dictionary = _map.get(id, {})
	if entry.has(profile) and ResourceLoader.exists(entry[profile]):
		return entry[profile]
	if profile != DEFAULT_PROFILE:
		push_warning("asset_resolver: '%s' sem caminho no perfil '%s'; usando '%s'" % [id, profile, DEFAULT_PROFILE])
	return entry.get(DEFAULT_PROFILE, "")


func texture(id: String) -> Texture2D:
	if _cache.has(id):
		return _cache[id]
	var p: String = path_of(id)
	var tex: Texture2D = null
	if p != "":
		tex = load(p) as Texture2D
	if tex == null:
		push_warning("asset_resolver: textura ausente para '%s'" % id)
	_cache[id] = tex
	return tex
