class_name TraceIO
extends RefCounted
## Leitura e gravação de trilhas de IntInput em JSON Lines (uma linha por tick).


## Devolve a trilha; linhas vazias são ignoradas. Em erro, push_error e [].
static func load_trace(path: String) -> Array[IntInput]:
	var out: Array[IntInput] = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("TraceIO: não foi possível abrir %s" % path)
		return out
	var n: int = 0
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		n += 1
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("TraceIO: linha %d inválida em %s" % [n, path])
			return []
		out.append(IntInput.from_dict(parsed))
	return out


static func save_trace(path: String, inputs: Array[IntInput]) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("TraceIO: não foi possível gravar %s" % path)
		return false
	for inp in inputs:
		f.store_line(JSON.stringify(inp.to_dict()))
	return true
