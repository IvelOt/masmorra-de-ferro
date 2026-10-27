extends SceneTree
## Runner headless (GDD §5.6, plano §7).
## godot --headless --path game -s res://scripts/headless_runner.gd -- \
##   --seed=1337 --ticks=600 --mode=pilot|replay|escape --map=dungeon|test|test_door \
##   --trace=in.jsonl --record=out.jsonl --output=runs/tmp/report.json [--with-view]
## --mode=escape usa o piloto de fuga (plano R4 §4.9); sem --ticks, roda K_MAX ticks.
## O laço continua depois do terminal (cadeia de comprimento fixo).
## Saída: 0 ok; 1 erro/guarda de tipos; 2 invariante violado.
## Classes do projeto só por preload: roda em clone limpo, sem cache de class_name.
##
## A simulação roda no primeiro _process, e não em _initialize, para que a cena de
## --with-view já tenha recebido _ready() quando o laço começar.

const PCG32 = preload("res://sim/rng_pcg32.gd")
const IntInput = preload("res://sim/int_input.gd")
const Grid = preload("res://sim/grid.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const StateHash = preload("res://sim/state_hash.gd")
const TraceIO = preload("res://input/trace_io.gd")
const PilotEscape = preload("res://scripts/pilot_escape.gd")

var _done: bool = false


func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		quit(_run())
	return false


func _parse_args() -> Dictionary:
	var a: Dictionary = {
		"seed": "1337", "ticks": "", "mode": "pilot", "map": "dungeon",
		"trace": "", "record": "", "output": "runs/tmp/report.json", "with-view": false,
	}
	for arg: String in OS.get_cmdline_user_args():
		if not arg.begins_with("--"):
			continue
		var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
		if kv.size() == 2:
			a[kv[0]] = kv[1]
		else:
			a[kv[0]] = true
	return a


func _run() -> int:
	var args: Dictionary = _parse_args()
	var seed_v: int = int(args["seed"])
	var mode: String = args["mode"]
	var ticks: int = int(args["ticks"])
	if String(args["ticks"]).is_empty():
		ticks = WorldSim.K_MAX if mode == "escape" else 600
	var with_view: bool = args["with-view"] == true
	if mode != "pilot" and mode != "replay" and mode != "escape":
		push_error("runner: modo inválido %s" % mode)
		return 1
	var world := WorldSim.new(seed_v, args["map"])
	if world.generation_failed:
		push_error("runner: geração falhou para a semente %d" % seed_v)
		return 1
	var trace: Array = []
	if mode == "replay":
		if String(args["trace"]).is_empty():
			push_error("runner: --mode=replay exige --trace")
			return 1
		trace = TraceIO.read_trace(args["trace"])
	var pilot := PCG32.new(seed_v, PCG32.STREAM_PILOT)
	var escape := PilotEscape.new(seed_v)
	var view: Node = null
	if with_view:
		var scene: PackedScene = load("res://view/main.tscn")
		view = scene.instantiate()
		view.attach_world(world)
		root.add_child(view)
		if not view.is_node_ready():
			push_error("runner: cena de --with-view não ficou pronta")
			return 1

	var code: int = 0
	var hashes: Array = []
	var recorded: Array = []
	var violation_tick: Variant = null
	for k in range(ticks):
		var inp: IntInput
		if mode == "replay":
			inp = trace[k] if k < trace.size() else IntInput.new()
		elif mode == "escape":
			inp = escape.next_input(world)
		else:
			inp = IntInput.from_pilot_combat(pilot)
		recorded.append(inp)
		world.step(inp)
		if world.type_error:
			code = 1
			break
		hashes.append(world.last_hash)
		if view != null:
			view.sync_view()
		if world.player_intersects_solid() or world.enemy_intersects_solid():
			code = 2
			violation_tick = world.tick
			push_error("runner: invariante violado no tick %d" % world.tick)
			break

	if not String(args["record"]).is_empty():
		TraceIO.write_trace(args["record"], recorded)
	var rows: Array = []
	for z in range(Grid.SIZE):
		var row: String = ""
		for x in range(Grid.SIZE):
			row += str(world.grid.get_cell(x, z))
		rows.append(row)
	var report: Dictionary = {
		"schema_version": StateHash.SCHEMA_VERSION,
		"godot_version": Engine.get_version_info()["string"],
		"seed": seed_v,
		"ticks": world.tick,
		"map": args["map"],
		"mode": mode,
		"with_view": with_view,
		"terminal": world.terminal,
		"terminal_tick": world.terminal_tick,
		"violation_tick": violation_tick,
		"grid": rows,
		"hashes": hashes,
		"chain_final": world.chain,
		"final_state": world.canonical_state(),
		"enemies": world.get_enemies(),
		"items": world.get_items(),
		"level": world.player.level,
		"gold": world.player.gold,
		"xp": world.player.xp,
		"exit_code": code,
	}
	var out: String = TraceIO.resolve(args["output"])
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		push_error("runner: não gravou %s" % out)
		return 1
	f.store_string(JSON.stringify(report, "  ", true))
	f.close()
	if view != null:
		view.queue_free()
	print("[runner] seed=%d ticks=%d terminal=%s chain_final=%s exit=%d" % [seed_v, world.tick, world.terminal, world.chain, code])
	return code
