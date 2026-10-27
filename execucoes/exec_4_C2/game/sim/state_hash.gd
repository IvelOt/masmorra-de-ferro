class_name StateHash
extends RefCounted
## Serialização canônica, guarda de tipos e SHA-256 (GDD §5.3).

## true se a estrutura só contém int, bool, String, Array e Dictionary.
static func type_guard(v: Variant, path: String = "$") -> bool:
	var t: int = typeof(v)
	if t == TYPE_INT or t == TYPE_BOOL or t == TYPE_STRING:
		return true
	if t == TYPE_ARRAY:
		var arr: Array = v
		for i: int in range(arr.size()):
			if not type_guard(arr[i], "%s[%d]" % [path, i]):
				return false
		return true
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort()
		for k: Variant in keys:
			if typeof(k) != TYPE_STRING:
				push_error("StateHash: chave não-String em %s" % path)
				return false
			if not type_guard(d[k], "%s.%s" % [path, k]):
				return false
		return true
	push_error("StateHash: tipo proibido (%s) em %s" % [type_string(t), path])
	return false


static func canon(d: Dictionary) -> String:
	return JSON.stringify(d, "", true)


static func sha256_bytes(b: PackedByteArray) -> String:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()


static func sha256_text(s: String) -> String:
	return sha256_bytes(s.to_utf8_buffer())


static func state_hash(d: Dictionary) -> String:
	return sha256_text(canon(d))


static func chain_start(p_seed: int, schema_version: int) -> String:
	return sha256_text(str(p_seed) + "|" + str(schema_version))


static func chain_next(prev: String, h: String) -> String:
	return sha256_text(prev + h)
