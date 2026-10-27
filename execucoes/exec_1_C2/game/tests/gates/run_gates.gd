extends SceneTree
## Executa os gates M1 a M6 e imprime uma linha por asserção
## (PASS <id> | FAIL <id>: esperado X, obtido Y). Sai com 0 só se todas passarem.
## Uso direto: godot --headless --path game -s res://tests/gates/run_gates.gd

const GateM1 = preload("res://tests/gates/gate_m1.gd")
const GateM2 = preload("res://tests/gates/gate_m2.gd")
const GateM3 = preload("res://tests/gates/gate_m3.gd")
const GateM4 = preload("res://tests/gates/gate_m4.gd")
const GateM5 = preload("res://tests/gates/gate_m5.gd")
const GateM6 = preload("res://tests/gates/gate_m6.gd")

var _done: bool = false


## M4-A7, M5-A4 e M5-A5 instanciam cenas; por isso os gates rodam no 1º quadro.
func _process(_dt: float) -> bool:
	if not _done:
		_done = true
		var results: Array[Dictionary] = run_all()
		print_results(results)
		quit(0 if all_passed(results) else 1)
	return false


static func run_all() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	GateM1.run(results)
	GateM2.run(results)
	GateM3.run(results)
	GateM4.run(results)
	GateM5.run(results)
	GateM6.run(results)
	return results


static func print_results(results: Array[Dictionary]) -> void:
	for r in results:
		if r.pass:
			print("PASS %s" % r.id)
		else:
			print("FAIL %s: %s" % [r.id, r.detail])


static func all_passed(results: Array[Dictionary]) -> bool:
	for r in results:
		if not r.pass:
			return false
	return true

