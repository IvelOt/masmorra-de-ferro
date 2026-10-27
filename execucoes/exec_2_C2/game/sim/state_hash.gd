extends RefCounted
## Serialização canônica, guarda de tipos, H_k = SHA256(JSON canônico) e cadeia C_k (GDD §5.3).


## Só int, bool, String, Array e Dictionary (com chaves String) são aceitos.
static func types_ok(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for e: Variant in v:
				if not types_ok(e):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not types_ok(v[k]):
					return false
			return true
	return false


static func canonical_json(s: Dictionary) -> String:
	return JSON.stringify(s, "", true)


## Retorna "" (e registra erro) se a guarda de tipos falhar.
static func hash_state(s: Dictionary) -> String:
	if not types_ok(s):
		push_error("state_hash: tipo proibido no estado canônico")
		return ""
	return canonical_json(s).sha256_text()


static func chain_init(seed_value: int, schema_version: int) -> String:
	return (str(seed_value) + ":" + str(schema_version)).sha256_text()


static func chain_next(prev: String, h: String) -> String:
	return (prev + h).sha256_text()
