class_name StateHash
extends RefCounted
## Serialização canônica, guarda de tipos, H_k e cadeia C_k (GDD §5.3).

const SCHEMA_VERSION: int = 3


## Aceita só int, bool, String, Array e Dictionary, recursivamente.
## Devolve o caminho do primeiro valor inválido, ou "" se o valor é válido.
static func type_guard(v: Variant, path: String = "$") -> String:
	var t: int = typeof(v)
	if t == TYPE_INT or t == TYPE_BOOL or t == TYPE_STRING:
		return ""
	if t == TYPE_ARRAY:
		var arr: Array = v
		for i in range(arr.size()):
			var bad: String = type_guard(arr[i], "%s[%d]" % [path, i])
			if bad != "":
				return bad
		return ""
	if t == TYPE_DICTIONARY:
		var d: Dictionary = v
		var keys: Array = d.keys()
		keys.sort()
		for k: Variant in keys:
			if typeof(k) != TYPE_STRING:
				return "%s.<chave %s>" % [path, type_string(typeof(k))]
			var bad: String = type_guard(d[k], "%s.%s" % [path, k])
			if bad != "":
				return bad
		return ""
	return "%s (%s)" % [path, type_string(t)]


static func canon(s: Dictionary) -> String:
	return JSON.stringify(s, "", true)


## H_k; devolve "" e emite push_error se a guarda de tipos falhar.
static func hash_state(s: Dictionary) -> String:
	var bad: String = type_guard(s)
	if bad != "":
		push_error("StateHash: tipo proibido no estado em %s" % bad)
		return ""
	return canon(s).sha256_text()


static func chain_seed(seed_value: int) -> String:
	return (str(seed_value) + ":" + str(SCHEMA_VERSION)).sha256_text()


static func chain_next(prev: String, h: String) -> String:
	return (prev + h).sha256_text()
