class_name StateHash
extends RefCounted
## Estado canônico, guarda de tipos, SHA-256 e cadeia C_k (GDD §5.3).

const SCHEMA_VERSION: int = 3


## Guarda de tipos recursiva: só int, bool, String, Array e Dictionary (chaves String).
static func is_canonical(v: Variant) -> bool:
	match typeof(v):
		TYPE_INT, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_ARRAY:
			for e: Variant in v:
				if not is_canonical(e):
					return false
			return true
		TYPE_DICTIONARY:
			for k: Variant in v:
				if typeof(k) != TYPE_STRING or not is_canonical(v[k]):
					return false
			return true
	return false


static func canon_json(s: Dictionary) -> String:
	return JSON.stringify(s, "", true)


static func sha256_hex_bytes(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()


static func sha256_hex_text(t: String) -> String:
	return sha256_hex_bytes(t.to_utf8_buffer())


static func chain_0(seed_value: int, schema_version: int) -> String:
	return sha256_hex_text("%d:%d" % [seed_value, schema_version])


static func chain_next(prev_hex: String, h_hex: String) -> String:
	return sha256_hex_text(prev_hex + h_hex)
