extends RefCounted
## Coleta asserções de gate e imprime `[GATE] <id> PASS|FAIL <detalhe>`.

var n_pass: int = 0
var n_total: int = 0
var runtime_error: bool = false


func check(id: String, ok: bool, detail: String = "") -> bool:
	n_total += 1
	if ok:
		n_pass += 1
	print("[GATE] %s %s %s" % [id, "PASS" if ok else "FAIL", detail])
	return ok


func all_passed() -> bool:
	return n_pass == n_total
