extends SceneTree
## Runner headless (plano §6.1). Códigos: 0 sucesso; 1 erro de execução/guarda de tipos; 2 invariante/gate.
## Suíte completa de gates em checkout limpo: tools/run_gates.sh
##   godot --headless --path game -s res://scripts/headless_runner.gd -- --seed=1 --ticks=600 \
##     --mode=replay|idle|pilot --trace=res://tests/traces/x.jsonl [--test-room] [--record=out.jsonl] \
##     [--output=runs/tmp/report.json] [--with-view] [--fixture=automap] [--dummy] [--enemies=tipo:cx:cz,...] [--gates=M1,M2,M3,M4,M5,M6]
##   --mode=pilot: o piloto (Pilot, fluxo STREAM_PILOT) gera o input de cada tick; --ticks padrão 18000.

const MAIN_SCENE: String = "res://view/main.tscn"
const Main = preload("res://view/main.gd")


var _done: bool = false


## Executa no primeiro quadro (em _initialize os nós adicionados ainda não recebem _ready).
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		quit(run(OS.get_cmdline_user_args()))
	return false


func run(argv: PackedStringArray) -> int:
	var args: Dictionary = parse_args(argv)
	if args.has("gates"):
		return run_gates(String(args["gates"]).split(","))
	var p_seed: int = int(args.get("seed", "1"))
	var mode: String = args.get("mode", "idle")
	var ticks: int = int(args.get("ticks", str(ItemsSim.K_MAX) if mode == "pilot" else "600"))
	var inputs: Array = []
	var pilot: Pilot = null
	if mode == "pilot":
		pilot = Pilot.create(p_seed)
	elif mode == "replay":
		if not args.has("trace"):
			printerr("--mode=replay exige --trace")
			return 1
		var tr: Dictionary = TraceIO.read(_res_path(args["trace"]))
		if tr["error"] != "":
			printerr(tr["error"])
			return 1
		inputs = tr["inputs"]
	elif mode != "idle":
		printerr("modo desconhecido: %s" % mode)
		return 1
	if args.has("dummy") and not args.has("test-room"):
		printerr("--dummy exige --test-room")
		return 1
	if args.has("enemies") and not args.has("test-room"):
		printerr("--enemies exige --test-room")
		return 1
	var enemies: Array = Main.parse_enemies(args.get("enemies", ""))
	if enemies.size() == 1 and enemies[0] is String:
		printerr(enemies[0])
		return 1
	var result: Dictionary = simulate(p_seed, ticks, inputs, args.has("test-room"), args.has("with-view"),
		args.get("fixture", ""), args.has("dummy"), enemies, pilot)
	if result["exit"] != 0:
		_write_report(args, result["report"])
		return result["exit"]
	if args.has("record"):
		TraceIO.write(_res_path(args["record"]), result["used_inputs"], {"seed": p_seed, "schema_version": StateHash.SCHEMA_VERSION})
	_write_report(args, result["report"])
	print("chain_final=%s" % result["report"]["chain_final"])
	return 0


static func parse_args(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in argv:
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


static func _res_path(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path():
		return p
	return "res://" + p


## Executa a partida; com with_view instancia main.tscn e avança pelo mesmo laço (sem tempo real).
func simulate(p_seed: int, ticks: int, inputs: Array, test_room: bool, with_view: bool,
		fixture: String = "", dummy: bool = false, enemies: Array = [], pilot: Pilot = null) -> Dictionary:
	var world := WorldSim.create(p_seed, test_room, fixture)
	if dummy:
		world.add_dummy(DungeonGen.cell_center_u(8), DungeonGen.cell_center_u(4))
	Main.add_enemies(world, enemies)
	if not world.dungeon.valid:
		return {"exit": 1, "report": {"error": "geração inválida"}, "used_inputs": []}
	var main: Node = null
	if with_view:
		main = (load(MAIN_SCENE) as PackedScene).instantiate()
		main.attach_world(world)
		root.add_child(main)
	var grid_codes: Array = world.dungeon.grid.to_codes()
	var hashes: Array = []
	var used: Array = []
	var exit_code: int = 0
	var violated: int = -1
	var terminal_tick: int = -1
	for k in range(ticks):
		var inp: IntInput = null
		if pilot != null:
			inp = pilot.next_input(world)
		else:
			inp = inputs[k] if k < inputs.size() else IntInput.new()
		used.append(inp)
		if main != null:
			main.advance(inp)
		else:
			world.step(inp)
		if world.type_error:
			exit_code = 1
			violated = world.tick
			break
		hashes.append(world.last_hash)
		if terminal_tick < 0 and world.terminal != "NONE":
			terminal_tick = world.tick
		if world.player.box_hits(world.dungeon.grid):
			exit_code = 2
			violated = world.tick
			break
	var final_state: Dictionary = StateHash.canon(world)
	var report: Dictionary = {
		"schema_version": StateHash.SCHEMA_VERSION,
		"godot_version": Engine.get_version_info()["string"],
		"seed": p_seed,
		"ticks": world.tick,
		"terminal": world.terminal,
		"terminal_tick": terminal_tick,
		"grid": grid_codes,
		"hashes": hashes,
		"chain_final": world.chain,
		"final_state": final_state,
	}
	if violated >= 0:
		report["violation_tick"] = violated
	if main != null:
		main.queue_free()
	return {"exit": exit_code, "report": report, "used_inputs": used}


func _write_report(args: Dictionary, report: Dictionary) -> void:
	if not args.has("output"):
		return
	var path: String = _res_path(args["output"])
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(path.get_base_dir()))
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		printerr("não foi possível gravar %s" % path)
		return
	f.store_string(JSON.stringify(report, "", true))


func run_gates(ids: PackedStringArray) -> int:
	var results: Array = []
	for id: String in ids:
		match id.strip_edges().to_upper():
			"M1":
				results.append_array(M1Gates.run())
			"M2":
				results.append_array(M2Gates.run())
			"M3":
				results.append_array(M3Gates.run())
			"M4":
				results.append_array(M4Gates.run(self))
			"M5":
				results.append_array(M5Gates.run(self))
			"M6":
				results.append_array(M6Gates.run(self))
			_:
				printerr("gate desconhecido: %s" % id)
				return 1
	return 2 if GateUtil.print_results(results) > 0 else 0
