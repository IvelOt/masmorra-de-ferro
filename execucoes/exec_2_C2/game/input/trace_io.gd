extends RefCounted
## Leitura/gravação de trilhas de IntInput em JSON Lines (uma linha por tick).

const IntInput = preload("res://sim/int_input.gd")


## Converte números do JSON (lidos como float pelo motor) para int antes de entrar no núcleo.
static func line_to_input(line: String) -> IntInput:
	var parsed: Variant = JSON.parse_string(line)
	if typeof(parsed) != TYPE_DICTIONARY:
		return IntInput.new()
	var d: Dictionary = parsed
	var clean: Dictionary = {}
	for k: String in ["move", "strafe", "turn", "quaff"]:
		clean[k] = int(d.get(k, 0))
	for k: String in ["attack", "block", "use"]:
		clean[k] = bool(d.get(k, false))
	return IntInput.from_dict(clean)


## Lê a trilha; retorna [] se o arquivo não existir.
static func read_trace(path: String) -> Array:
	var out: Array = []
	var f: FileAccess = FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("trace_io: não foi possível abrir %s" % path)
		return out
	while not f.eof_reached():
		var line: String = f.get_line().strip_edges()
		if line == "":
			continue
		out.append(line_to_input(line))
	return out


static func write_trace(path: String, inputs: Array) -> bool:
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("trace_io: não foi possível gravar %s" % path)
		return false
	for inp: IntInput in inputs:
		f.store_line(JSON.stringify(inp.to_dict(), "", true))
	return true
