class_name AssetResolver
extends RefCounted
## Resolve identificadores lógicos de res://assets/asset_map.json pelo perfil de arte.

const MAP_PATH: String = "res://assets/asset_map.json"

static var _map: Dictionary = {}
static var profile: String = "free"


static func _load() -> void:
	if not _map.is_empty():
		return
	var f := FileAccess.open(MAP_PATH, FileAccess.READ)
	if f == null:
		push_error("AssetResolver: %s ausente" % MAP_PATH)
		return
	var v: Variant = JSON.parse_string(f.get_as_text())
	if typeof(v) == TYPE_DICTIONARY:
		_map = v


static func path_of(id: String) -> String:
	_load()
	var entry: Dictionary = _map.get(id, {})
	if entry.has(profile):
		return entry[profile]
	if profile != "free" and entry.has("free"):
		push_warning("AssetResolver: '%s' sem perfil '%s'; usando 'free'" % [id, profile])
	return entry.get("free", "")


static func exists(id: String) -> bool:
	var p: String = path_of(id)
	return p != "" and ResourceLoader.exists(p)


static func texture(id: String) -> Texture2D:
	var p: String = path_of(id)
	if p == "":
		push_error("AssetResolver: identificador desconhecido '%s'" % id)
		return null
	return load(p) as Texture2D
