extends SceneTree
## Runner headless (GDD §5.6, plano da rodada 3 §7.2):
##   godot --headless --path game -s res://scripts/headless_runner.gd -- \
##         --seed=N --ticks=K --mode=zero|replay|pilot [--trace=in.jsonl] [--record=out.jsonl] \
##         [--test-room|--combat-room|--arena] [--with-view] --output=report.json
## zero: input zero; replay: trilha (linhas faltantes = input zero); pilot: input/pilot.gd (semente N).
## A simulação para no terminal, mas a cadeia continua com o comprimento K pedido (depois do
## terminal step() só conta ticks). --with-view alimenta também main.tscn com o mesmo input e
## compara as cadeias (R3).
## Saída: 0 sucesso; 1 erro de execução/guarda de tipos; 2 violação de invariante ou chain_view != chain_final.

const WorldSim = preload("res://sim/world_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const TraceIO = preload("res://input/trace_io.gd")
const Pilot = preload("res://input/pilot.gd")
const MAIN_SCENE: String = "res://view/main.tscn"


func _initialize() -> void:
	var code: int = await _run()
	quit(code)


func _run() -> int:
	var seed_arg: int = 1
	var ticks: int = 600
	var mode: String = "zero"
	var trace_path: String = ""
	var record_path: String = ""
	var output: String = ""
	var room: String = ""
	var with_view: bool = false
	for arg: String in OS.get_cmdline_user_args():
		var val: String = arg.get_slice("=", 1)
		if arg.begins_with("--seed="):
			seed_arg = val.to_int()
		elif arg.begins_with("--ticks="):
			ticks = val.to_int()
		elif arg.begins_with("--mode="):
			mode = val
		elif arg.begins_with("--trace="):
			trace_path = val
		elif arg.begins_with("--record="):
			record_path = val
		elif arg.begins_with("--output="):
			output = val
		elif arg == "--test-room":
			room = "room"
		elif arg == "--combat-room":
			room = "combat"
		elif arg == "--arena":
			room = "arena"
		elif arg == "--with-view":
			with_view = true
		else:
			push_error("headless_runner: argumento desconhecido %s" % arg)
			return 1
	if mode != "zero" and mode != "replay" and mode != "pilot":
		push_error("headless_runner: modo '%s' não suportado" % mode)
		return 1
	var trace: Array = []
	if mode == "replay":
		if trace_path == "" or not FileAccess.file_exists(trace_path):
			push_error("headless_runner: --trace ausente ou inexistente")
			return 1
		trace = TraceIO.read_trace(trace_path)

	var w: WorldSim = WorldSim.new()
	if room != "":
		w.setup_test(room)
	else:
		w.setup_seed(seed_arg)
	var pilot: Pilot = Pilot.new(seed_arg) if mode == "pilot" else null
	var main: Node = null
	if with_view:
		await process_frame
		main = (load(MAIN_SCENE) as PackedScene).instantiate()
		main.set("start_override", room if room != "" else "seed:%d" % seed_arg)
		main.set("driven_externally", true)
		root.add_child(main)
	var report: Dictionary = {
		"schema_version": WorldSim.SCHEMA_VERSION,
		"godot_version": Engine.get_version_info().string,
		"seed": w.seed_value,
		"ticks": ticks,
		"grid": w.grid.sha256(),
	}
	var hashes: Array = []
	var recorded: Array = []
	var code: int = 0
	for k in range(ticks):
		var inp: IntInput = IntInput.new()
		if mode == "replay" and k < trace.size():
			inp = trace[k]
		elif pilot != null and w.terminal == "NONE":
			inp = pilot.next_input(w)
		recorded.append(inp)
		w.step(inp)
		if main != null:
			main.call("tick_once", inp)
		if w.hash_error:
			code = 1
			report["error_tick"] = w.tick
			break
		hashes.append(w.last_hash)
		if w.player_box_hits_solid():
			code = 2
			report["violation_tick"] = w.tick
			break
	report["terminal"] = w.terminal
	report["terminal_tick"] = w.terminal_tick
	report["hashes"] = hashes
	report["chain_final"] = w.chain
	report["final_state"] = w.canonical_state()
	if main != null:
		var vw: WorldSim = main.get("world")
		report["chain_view"] = vw.chain
		if vw.chain != w.chain and code == 0:
			code = 2
		root.remove_child(main)
		main.free()
	if record_path != "" and not TraceIO.write_trace(record_path, recorded):
		return 1
	print("[RUNNER] seed=%d ticks=%d terminal=%s terminal_tick=%d chain_final=%s" % [
		w.seed_value, w.tick, w.terminal, w.terminal_tick, w.chain])
	if output != "":
		DirAccess.make_dir_recursive_absolute(output.get_base_dir())
		var f: FileAccess = FileAccess.open(output, FileAccess.WRITE)
		if f == null:
			push_error("headless_runner: não foi possível gravar %s" % output)
			return 1
		f.store_string(JSON.stringify(report, "  ", true))
	return code
