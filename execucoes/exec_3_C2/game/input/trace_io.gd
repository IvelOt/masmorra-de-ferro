class_name TraceIO
extends RefCounted
## Trilhas de IntInput em JSON Lines (uma linha por tick).

const IntInput = preload("res://sim/int_input.gd")


## Caminho relativo é resolvido a partir de res:// (diretório game/).
static func resolve(path: String) -> String:
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)


static func read_trace(path: String) -> Array:
	var out: Array = []
	var f := FileAccess.open(resolve(path), FileAccess.READ)
	if f == null:
		push_error("TraceIO: não abriu %s" % path)
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line.is_empty():
			continue
		var d: Variant = JSON.parse_string(line)
		if typeof(d) != TYPE_DICTIONARY:
			push_error("TraceIO: linha inválida em %s" % path)
			continue
		out.append(IntInput.from_dict(d))
	return out


static func write_trace(path: String, inputs: Array) -> bool:
	var full: String = resolve(path)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	var f := FileAccess.open(full, FileAccess.WRITE)
	if f == null:
		push_error("TraceIO: não gravou %s" % path)
		return false
	for inp: IntInput in inputs:
		f.store_line(JSON.stringify(inp.to_dict(), "", true))
	return true
