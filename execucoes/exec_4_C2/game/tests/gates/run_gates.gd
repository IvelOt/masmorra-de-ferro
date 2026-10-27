extends SceneTree
## Gates da rodada: godot --headless --path game -s res://tests/gates/run_gates.gd
## Imprime "PASS|FAIL <ID> <detalhe>" e sai 0 só se tudo passar.
## Com "-- --record-traces" (re)grava as trilhas douradas antes de verificar.
## Verificação num checkout limpo (game/.godot/ não é versionado):
##   godot --headless --path game --import
##   python3 tools/lint_sim.py
##   godot --headless --path game -s res://tests/run_gates.gd


var _done: bool = false
var _exit_code: int = 0
## Quadros a esperar antes do quit(), para a cena liberada não vazar no ObjectDB.
var _quit_frames: int = -1


## Roda no primeiro quadro (a árvore precisa estar pronta para instanciar main.tscn);
## _run() é corrotina (M5-A6 espera quadros para a overlay desenhar).
func _process(_dt: float) -> bool:
	if _quit_frames > 0:
		_quit_frames -= 1
	elif _quit_frames == 0:
		_quit_frames = -1
		quit(_exit_code)
	if _done:
		return false
	_done = true
	_run()
	return false


func _run() -> void:
	var record: bool = OS.get_cmdline_user_args().has("--record-traces")
	if record:
		var fixed: Dictionary = GateTraces.fixed()
		var heads: Dictionary = GateTraces.headers()
		for name: String in fixed.keys():
			TraceIO.write(ProjectSettings.globalize_path(GateTraces.DIR + name), fixed[name],
				heads.get(name, {}))
	var r: GateReport = GateReport.new()
	GateM1.run(r)
	GateM2.run(r, record)
	GateM3.run(r)
	GateM4.run(r)
	await GateM5.run(r, self)
	GateM6.run(r)
	GateUI.run(r, self)
	GateRepro.run(r, self)
	print("[gates] %d PASS, %d FAIL" % [r.passed, r.failed])
	AssetResolver.clear_cache()
	_exit_code = 0 if r.failed == 0 else 1
	_quit_frames = 10
