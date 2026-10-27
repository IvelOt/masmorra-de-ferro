class_name TraceIO
extends RefCounted
## Trilhas de IntInput em JSON Lines (uma linha por tick; cabeçalho opcional com "seed").


static func read(path: String) -> Dictionary:
	var out: Dictionary = {"header": {}, "inputs": [], "error": ""}
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		out["error"] = "não foi possível abrir %s" % path
		return out
	var first: bool = true
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty():
			continue
		var v: Variant = JSON.parse_string(line)
		if typeof(v) != TYPE_DICTIONARY:
			out["error"] = "linha inválida: %s" % line
			return out
		var d: Dictionary = v
		if first and d.has("seed") and not d.has("move"):
			out["header"] = d
		else:
			out["inputs"].append(IntInput.from_dict(d))
		first = false
	return out


static func write(path: String, inputs: Array, header: Dictionary = {}) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	if not header.is_empty():
		f.store_line(JSON.stringify(header, "", true))
	for i: IntInput in inputs:
		f.store_line(JSON.stringify(i.to_dict(), "", true))
	return true
