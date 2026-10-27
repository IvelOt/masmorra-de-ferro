class_name GateReport
extends RefCounted
## Coleta asserções e imprime "PASS|FAIL <ID> <detalhe>".

var passed: int = 0
var failed: int = 0
## true: só conta, sem imprimir (reexecuções de preservação).
var quiet: bool = false


func check(id: String, ok: bool, detail: String = "") -> bool:
	if ok:
		passed += 1
	else:
		failed += 1
	if not quiet:
		print("%s %s %s" % ["PASS" if ok else "FAIL", id, detail])
	return ok
