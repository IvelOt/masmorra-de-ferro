extends SceneTree
## Runner headless (plano §7). Saída: 0 = sucesso; 1 = erro de execução,
## guarda de tipos ou gate reprovado; 2 = violação de invariante.
## Opções: --seed= --ticks= --room=test|combat|arena|vault|dungeon --mode=idle|replay|pilot
## --trace= --record= --output= --tab-every=N (só com --with-view) --with-view --gates.
## --mode=pilot exige --room=dungeon; o piloto continua sendo chamado depois do terminal.

const RunGates = preload("res://tests/gates/run_gates.gd")
const MAIN_SCENE: String = "res://view/main.tscn"


var _setup_code: int = -1
var _started: bool = false
var _sim: WorldSim
var _main: Node = null
var _opts: Dictionary = {}
var _mode: String = ""
var _trace: Array[IntInput] = []
var _with_view: bool = false
var _gates: bool = false
var _pilot: Pilot = null
var _tab_every: int = 0


## A cena (--with-view) só recebe _ready() depois do primeiro quadro; por isso
## a configuração fica aqui e o laço de ticks roda no primeiro _process().
func _initialize() -> void:
	_setup_code = _setup()
	if _setup_code != 0:
		quit(_setup_code)


func _process(_dt: float) -> bool:
	if _setup_code == 0 and not _started:
		_started = true
		quit(_run())
	return false


func _setup() -> int:
	var opts: Dictionary = {
		"seed": "1337", "ticks": "600", "room": "dungeon", "mode": "",
		"trace": "", "record": "", "output": "", "tab-every": "0",
	}
	var with_view: bool = false
	var gates: bool = false
	for arg in OS.get_cmdline_user_args():
		if arg == "--with-view":
			with_view = true
		elif arg == "--gates":
			gates = true
		elif arg.begins_with("--") and arg.contains("="):
			var kv: PackedStringArray = arg.substr(2).split("=", true, 1)
			if not opts.has(kv[0]):
				printerr("runner: opção desconhecida %s" % arg)
				return 1
			opts[kv[0]] = kv[1]
		else:
			printerr("runner: argumento desconhecido %s" % arg)
			return 1
	var mode: String = opts.mode
	if mode == "":
		mode = "replay" if opts.trace != "" else "idle"
	if mode != "idle" and mode != "replay" and mode != "pilot":
		printerr("runner: modo inválido %s" % mode)
		return 1
	if not (opts.room in ["test", "combat", "arena", "vault", "dungeon"]):
		printerr("runner: sala inválida %s" % opts.room)
		return 1
	if mode == "pilot" and opts.room != "dungeon":
		printerr("runner: --mode=pilot exige --room=dungeon")
		return 1
	var tab_every: int = int(opts["tab-every"])
	if tab_every > 0 and not with_view:
		printerr("runner: --tab-every exige --with-view")
		return 1
	var seed_value: int = int(opts.seed)
	var ticks: int = int(opts.ticks)

	var trace: Array[IntInput] = []
	if mode == "replay":
		if opts.trace == "":
			printerr("runner: --mode=replay exige --trace=")
			return 1
		trace = TraceIO.load_trace(_resolve(opts.trace))
		if trace.is_empty():
			return 1

	_sim = WorldSim.create(seed_value, opts.room)
	if not _sim.dungeon.ok:
		return 1
	if with_view:
		_main = (load(MAIN_SCENE) as PackedScene).instantiate()
		_main.call("attach_sim", _sim)
		root.add_child(_main)
	_opts = opts
	_mode = mode
	_trace = trace
	_with_view = with_view
	_gates = gates
	_tab_every = tab_every
	if mode == "pilot":
		_pilot = Pilot.create(seed_value)
	return 0


func _run() -> int:
	var sim: WorldSim = _sim
	var main: Node = _main
	var opts: Dictionary = _opts
	var mode: String = _mode
	var trace: Array[IntInput] = _trace
	var with_view: bool = _with_view
	var gates: bool = _gates
	var ticks: int = int(opts.ticks)
	var seed_value: int = int(opts.seed)
	var hashes: Array = []
	var recorded: Array[IntInput] = []
	var exit_code: int = 0
	var violation: Dictionary = {}
	var enemy_count: int = sim.enemies.size()
	var mon: Dictionary = {"visited": sim.automap.visited.duplicate(), "taken": _taken(sim), "frozen": ""}
	for k in range(ticks):
		var inp: IntInput
		if _pilot != null:
			inp = _pilot.next_input(sim)
		else:
			inp = trace[k] if k < trace.size() else IntInput.new()
		recorded.append(inp)
		sim.step(inp)
		if sim.type_error:
			printerr("runner: guarda de tipos falhou no tick %d" % sim.tick)
			exit_code = 1
			break
		hashes.append(sim.last_hash())
		if main != null:
			main.call("refresh_from_sim")
			if _tab_every > 0 and sim.tick % _tab_every == 0:
				main.call("toggle_automap")
		var bad: String = _check_invariants(sim, enemy_count)
		if bad == "":
			bad = _check_v3(sim, mon)
		if bad != "":
			violation = {"tick": sim.tick, "invariant": bad}
			printerr("runner: invariante violado no tick %d: %s" % [sim.tick, bad])
			exit_code = 2
			break

	var report: Dictionary = {
		"schema_version": StateHash.SCHEMA_VERSION,
		"godot_version": Engine.get_version_info().string,
		"seed": seed_value,
		"room": opts.room,
		"mode": mode,
		"ticks": sim.tick,
		"terminal": sim.terminal,
		"terminal_tick": sim.terminal_tick,
		"grid": sim.grid.to_digit_string(),
		"hashes": hashes,
		"chain_final": sim.chain(),
		"final_state": sim.snapshot(),
		"with_view": with_view,
	}
	if not violation.is_empty():
		report["violation"] = violation
	if gates:
		var results: Array[Dictionary] = RunGates.run_all()
		RunGates.print_results(results)
		report["gates"] = results
		if exit_code == 0 and not RunGates.all_passed(results):
			exit_code = 1
	if opts.record != "":
		TraceIO.save_trace(_resolve(opts.record), recorded)
	if opts.output != "":
		var path: String = _resolve(opts.output)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			printerr("runner: não foi possível gravar %s" % path)
			return 1
		f.store_string(JSON.stringify(report, "  ", true))
	print("chain_final=%s ticks=%d exit=%d" % [sim.chain(), sim.tick, exit_code])
	return exit_code


static func _check_invariants(sim: WorldSim, enemy_count: int) -> String:
	if sim.player.angle < 0 or sim.player.angle >= 4096:
		return "angle fora de [0, 4096): %d" % sim.player.angle
	if sim.player.box_hits(sim.grid):
		return "caixa do jogador intersecta célula bloqueante em (%d, %d)" % [sim.player.pos_x, sim.player.pos_z]
	if sim.enemies.size() != enemy_count:
		return "tamanho de enemies mudou: %d -> %d" % [enemy_count, sim.enemies.size()]
	return sim.entity_violation()


static func _taken(sim: WorldSim) -> Array[bool]:
	var out: Array[bool] = []
	for it: Dictionary in sim.items:
		out.append(bool(it.taken))
	return out


## Invariantes de M5/M6 (plano §9.4); mon guarda o estado do tick anterior.
static func _check_v3(sim: WorldSim, mon: Dictionary) -> String:
	# a comparação célula a célula só roda quando o bitmap mudou
	var sha: String = sim.automap.sha256()
	if sha != mon.get("visited_sha", ""):
		var v0: PackedByteArray = mon.visited
		var v1: PackedByteArray = sim.automap.visited
		for i in range(v1.size()):
			if v0[i] == 1 and v1[i] == 0:
				return "automapa desmarcou a célula %d" % i
		mon.visited = v1.duplicate()
		mon.visited_sha = sha
	var p: PlayerSim = sim.player
	if p.level < 1 or p.level > ItemsSim.LEVEL_MAX:
		return "level fora de [1, 3]: %d" % p.level
	if p.hp_max != Combat.HP_MAX + ItemsSim.LEVEL_HP * (p.level - 1) \
			or p.stamina_max != Combat.STAMINA_MAX + ItemsSim.LEVEL_SP * (p.level - 1):
		return "hp_max/stamina_max incoerentes com o nível %d: %d/%d" % [p.level, p.hp_max, p.stamina_max]
	if p.potion_hp < 0 or p.potion_sp < 0 or p.gold < 0:
		return "inventário negativo: %d/%d/%d" % [p.potion_hp, p.potion_sp, p.gold]
	var t0: Array[bool] = mon.taken
	var t1: Array[bool] = _taken(sim)
	if t1.size() != t0.size():
		return "tamanho de items mudou: %d -> %d" % [t0.size(), t1.size()]
	for i in range(t1.size()):
		if t0[i] and not t1[i]:
			return "item %d voltou a não coletado" % i
	mon.taken = t1
	if sim.terminal != "NONE":
		var s: Dictionary = sim.snapshot()
		s.erase("tick")
		var c: String = StateHash.canon(s)
		if mon.frozen == "":
			mon.frozen = c
		elif c != mon.frozen:
			return "estado mudou depois do terminal %s" % sim.terminal
	return ""


## Caminhos relativos são resolvidos a partir do diretório do projeto (game/).
static func _resolve(p: String) -> String:
	if p.contains("://") or p.is_absolute_path():
		return ProjectSettings.globalize_path(p) if p.begins_with("res://") or p.begins_with("user://") else p
	return ProjectSettings.globalize_path("res://").path_join(p)
