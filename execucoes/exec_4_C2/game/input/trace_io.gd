class_name TraceIO
extends RefCounted
## Trilhas de IntInput em JSON Lines: uma linha por tick, sem cabeçalho.
## Exceção opcional: se a PRIMEIRA linha tiver a chave "seed", ela é um
## cabeçalho de pose inicial {"seed", "pos_x", "pos_z", "angle"} (ex.: m2_a6).
## Linhas vazias (inclusive a final) são ignoradas na leitura.


static func write(path: String, inputs: Array, header: Dictionary = {}) -> bool:
	var dir: String = path.get_base_dir()
	if dir != "" and not DirAccess.dir_exists_absolute(dir):
		DirAccess.make_dir_recursive_absolute(dir)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("TraceIO: não abriu %s para escrita" % path)
		return false
	if not header.is_empty():
		f.store_line(JSON.stringify(header, "", true))
	for inp: IntInput in inputs:
		f.store_line(JSON.stringify(inp.to_dict(), "", true))
	f.close()
	return true


## Devolve {"header": Dictionary, "inputs": Array[IntInput]}; null se falhar.
static func read(path: String) -> Variant:
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("TraceIO: não abriu %s" % path)
		return null
	var header: Dictionary = {}
	var inputs: Array = []
	var first: bool = true
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line == "":
			continue
		var parsed: Variant = JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			push_error("TraceIO: linha inválida em %s: %s" % [path, line])
			return null
		var d: Dictionary = parsed
		if first and d.has("seed"):
			for k: Variant in d.keys():
				header[k] = int(d[k])
		else:
			inputs.append(IntInput.from_dict(d))
		first = false
	f.close()
	return {"header": header, "inputs": inputs}
