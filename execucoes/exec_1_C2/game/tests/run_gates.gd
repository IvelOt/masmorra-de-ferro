extends SceneTree
## Atalho para res://tests/gates/run_gates.gd.
## Uso: godot --headless --path game -s res://tests/run_gates.gd

const RunGates = preload("res://tests/gates/run_gates.gd")


var _done: bool = false


func _process(_dt: float) -> bool:
	if not _done:
		_done = true
		var results: Array[Dictionary] = RunGates.run_all()
		RunGates.print_results(results)
		quit(0 if RunGates.all_passed(results) else 1)
	return false
