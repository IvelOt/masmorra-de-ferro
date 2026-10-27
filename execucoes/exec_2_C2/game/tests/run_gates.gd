extends SceneTree
## Entrada única dos gates: godot --headless --path game -s res://tests/run_gates.gd
## Executa o núcleo de M1, M2, M3, M5, M4 e M6, depois os gates de cena (M3-V1, M5-A4, M5-A5,
## M4-A7, M6-V1, M6-V2) e, por último, o fim a fim M6-A6 (o mais longo). Os gates de cena precisam
## da árvore pronta, por isso tudo roda em _initialize() (não em _init()), e os gates de cena
## esperam o primeiro quadro (a raiz só entra na árvore depois de _initialize começar).
## Saída: 0 = todos passam; 2 = alguma asserção falhou; 1 = erro de execução/guarda de tipos.

const Report = preload("res://tests/gates/gate_report.gd")
const GateM1 = preload("res://tests/gates/gate_m1.gd")
const GateM2 = preload("res://tests/gates/gate_m2.gd")
const GateM3 = preload("res://tests/gates/gate_m3.gd")
const GateM4 = preload("res://tests/gates/gate_m4.gd")
const GateM5 = preload("res://tests/gates/gate_m5.gd")
const GateM6 = preload("res://tests/gates/gate_m6.gd")


func _initialize() -> void:
	var r: Report = Report.new()
	GateM1.run(r)
	GateM2.run(r)
	GateM3.run(r)
	GateM5.run(r)
	GateM4.run(r)
	GateM6.run(r)
	await process_frame
	GateM3.run_vis(r, root)
	GateM5.run_vis(r, root)
	GateM4.run_vis(r, root)
	GateM6.run_vis(r, root)
	GateM6.run_e2e(r)
	print("[GATES] %d/%d" % [r.n_pass, r.n_total])
	if r.runtime_error:
		quit(1)
	elif r.all_passed():
		quit(0)
	else:
		quit(2)
