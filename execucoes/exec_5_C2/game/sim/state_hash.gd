class_name StateHash
extends RefCounted
## Estado canônico s_k, guarda de tipos, H_k = SHA256(JSON_canon(s_k)) e cadeia C_k.

const SCHEMA_VERSION: int = 1


static func canon(world: WorldSim) -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": world.tick,
		"terminal": world.terminal,
		"player": world.player.to_canon(),
		"dungeon": {"grid_sha256": world.dungeon.grid.sha256(), "doors": world.get_doors()},
		"enemies": world.get_enemies(),
		"items": world.get_items(),
		"automap": {"visited_sha256": world.automap.sha256()},
		"rng": {"dungeon_state": world.rng_dungeon.state_hex(), "ai_state": world.rng_ai.state_hex()},
	}


## Aceita só int, bool, String, Array e Dictionary (recursivo).
static func assert_types(v: Variant, path: String = "s") -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_ARRAY:
			var arr: Array = v
			for i in range(arr.size()):
				if not assert_types(arr[i], "%s[%d]" % [path, i]):
					return false
			return true
		TYPE_DICTIONARY:
			var dict: Dictionary = v
			var keys: Array = dict.keys()
			keys.sort()
			for k: Variant in keys:
				if typeof(k) != TYPE_STRING:
					push_error("StateHash: chave não-String em %s" % path)
					return false
				if not assert_types(dict[k], "%s.%s" % [path, k]):
					return false
			return true
	push_error("StateHash: tipo proibido (%s) em %s" % [type_string(typeof(v)), path])
	return false


static func to_json(s: Dictionary) -> String:
	return JSON.stringify(s, "", true)


static func hash_state(s: Dictionary) -> String:
	return to_json(s).sha256_text()


static func chain_init(p_seed: int) -> String:
	return (str(p_seed) + "|" + str(SCHEMA_VERSION)).sha256_text()


static func chain_next(prev: String, h: String) -> String:
	return (prev + h).sha256_text()
