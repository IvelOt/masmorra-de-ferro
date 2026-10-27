extends SceneTree
## Runner headless (GDD §5.6, plano iteração 1 §5.1).
##   godot --headless --path game -s res://scripts/headless_runner.gd -- \
##     --seed=1337 --ticks=600 --mode=replay --trace=res://tests/traces/x.jsonl \
##     [--test-room] [--record=out.jsonl] --output=runs/tmp/report.json [--with-view]
##     [--no-enemies] [--dummy] [--check-invariants] [--stop-at-terminal]
## --mode=pilot: PilotSim (stream 3 da semente) gera o input; --record grava a trilha (R4).
## --stop-at-terminal: para no tick do terminal (só gates/calibração; marcado no relatório).
## --no-enemies: masmorra sem inimigos; --dummy: boneco de treino na sala de teste;
## --check-invariants: também as invariantes de M3-A7 (vigor, hp, golpe,
## atordoamento), M4-A5 (inimigos fora de sólidos, sem sobreposição) e M5/M6
## (automapa monotônico, hp <= hp_max, stamina <= stamina_max, poções >= 0).
## Saída: 0 ok; 1 erro/guarda de tipos; 2 invariante violado (tick registrado).

const MAIN_SCENE: String = "res://view/main.tscn"


## Caminho relativo -> relativo ao diretório do projeto.
static func resolve_path(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("user://"):
		return ProjectSettings.globalize_path(p)
	if p.is_absolute_path():
		return p
	return ProjectSettings.globalize_path("res://").path_join(p)


var _done: bool = false
var _exit_code: int = 0
## Quadros a esperar antes do quit(), para a cena liberada não vazar no ObjectDB.
var _quit_frames: int = -1


## Roda no primeiro quadro (a árvore precisa estar pronta para --with-view).
func _process(_dt: float) -> bool:
	if _quit_frames > 0:
		_quit_frames -= 1
	elif _quit_frames == 0:
		_quit_frames = -1
		quit(_exit_code)
	if _done:
		return false
	_done = true
	_main()
	return false


func _main() -> void:
	var args: Dictionary = {"seed": "1", "ticks": "600", "mode": "replay", "trace": "",
		"record": "", "output": "runs/tmp/report.json"}
	var flags: Dictionary = {}
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--") and a.contains("="):
			var kv: PackedStringArray = a.substr(2).split("=", true, 1)
			args[kv[0]] = kv[1]
		elif a.begins_with("--"):
			flags[a.substr(2)] = true
	_exit_code = run(int(args["seed"]), int(args["ticks"]), String(args["mode"]), String(args["trace"]),
		String(args["record"]), String(args["output"]), flags.has("test-room"), flags.has("with-view"),
		flags)
	_quit_frames = 10


func run(p_seed: int, ticks: int, mode: String, trace: String, record: String, output: String,
		test_room: bool, with_view: bool, flags: Dictionary = {}) -> int:
	var spawn: bool = not flags.has("no-enemies")
	var check: bool = flags.has("check-invariants")
	var stop_at_terminal: bool = flags.has("stop-at-terminal")
	var inputs: Array = []
	var header: Dictionary = {}
	var pilot: PilotSim = null
	if mode == "replay":
		if trace != "":
			var tr: Variant = TraceIO.read(resolve_path(trace))
			if tr == null:
				return 1
			inputs = tr["inputs"]
			header = tr["header"]
	elif mode == "pilot":
		pilot = PilotSim.new(p_seed)
	else:
		push_error("runner: modo desconhecido '%s'" % mode)
		return 1
	var sim: WorldSim = null
	var main: Node = null
	if with_view:
		main = (load(MAIN_SCENE) as PackedScene).instantiate()
		main.call("configure", p_seed, test_room, true, flags.has("dummy"))
		main.set("spawn_enemies", spawn)
		root.add_child(main)
		sim = main.get("sim")
	else:
		sim = WorldSim.new(p_seed, test_room, spawn)
		if flags.has("dummy") and test_room:
			sim.add_training_dummy()
	if not header.is_empty():
		sim.set_player_pose(int(header["pos_x"]), int(header["pos_z"]), int(header["angle"]))
	var used: Array = []
	var hashes: Array = []
	var code: int = 0
	var violation_tick: int = -1
	var stopped: bool = false
	for k: int in range(ticks):
		if stop_at_terminal and sim.terminal != "":
			stopped = true
			break
		var inp: IntInput = IntInput.new()
		if pilot != null:
			inp = pilot.next_input(sim)
		elif k < inputs.size():
			inp = inputs[k]
		used.append(inp)
		var before: Array = []
		for e: EnemySim.Enemy in sim.enemies:
			before.append([e.pos_x, e.pos_z])
		var visited_before: PackedByteArray = sim.automap.visited.duplicate() if check else PackedByteArray()
		if with_view:
			main.call("advance", inp)
		else:
			sim.step(inp)
		hashes.append(sim.last_hash)
		if sim.guard_failed:
			code = 1
			violation_tick = sim.tick
			break
		if sim.player.box_hits(sim.grid):
			push_error("runner: invariante violado no tick %d (caixa ∩ bloqueante)" % sim.tick)
			code = 2
			violation_tick = sim.tick
			break
		if check:
			var why: String = invariant_violation(sim, before)
			if why == "":
				why = progression_violation(sim, visited_before)
			if why != "":
				push_error("runner: invariante violado no tick %d (%s)" % [sim.tick, why])
				code = 2
				violation_tick = sim.tick
				break
	var report: Dictionary = {
		"schema_version": WorldSim.SCHEMA_VERSION,
		"godot_version": String(Engine.get_version_info()["string"]),
		"seed": p_seed,
		"ticks": sim.tick,
		"terminal": sim.terminal,
		"terminal_tick": sim.terminal_tick,
		"stopped_at_terminal": stopped,
		"level": sim.player.level,
		"xp": sim.player.xp,
		"gold": sim.player.gold,
		"has_key": sim.player.has_key,
		"grid": sim.grid.rows(),
		"hashes": hashes,
		"chain_final": sim.chain,
		"final_state": sim.get_state(),
	}
	if violation_tick >= 0:
		report["violation_tick"] = violation_tick
	var out_path: String = resolve_path(output)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	var f: FileAccess = FileAccess.open(out_path, FileAccess.WRITE)
	if f == null:
		push_error("runner: não abriu %s" % out_path)
		return 1
	f.store_string(JSON.stringify(report, "", true))
	f.close()
	if record != "":
		TraceIO.write(resolve_path(record), used, header)
	print("runner: seed=%d ticks=%d terminal=%s chain_final=%s code=%d" % [p_seed, sim.tick, sim.terminal, sim.chain, code])
	if main != null:
		root.remove_child(main)
		main.free()
	AssetResolver.clear_cache()
	return code


## Invariantes de M5/M6: automapa monotônico, máximos e inventário.
static func progression_violation(sim: WorldSim, visited_before: PackedByteArray) -> String:
	var p: PlayerSim = sim.player
	if p.hp > p.hp_max:
		return "hp=%d > hp_max=%d" % [p.hp, p.hp_max]
	if p.stamina > p.stamina_max:
		return "stamina=%d > stamina_max=%d" % [p.stamina, p.stamina_max]
	if p.potion_hp < 0 or p.potion_sp < 0:
		return "poções=(%d,%d)" % [p.potion_hp, p.potion_sp]
	for i: int in range(visited_before.size()):
		if visited_before[i] == 1 and sim.automap.visited[i] == 0:
			return "automapa: célula %d voltou a 0" % i
	return ""


## Invariantes de M3-A7 e M4-A5; `before` = posições dos inimigos antes do step.
static func invariant_violation(sim: WorldSim, before: Array) -> String:
	var p: PlayerSim = sim.player
	if p.stamina < 0 or p.stamina > p.stamina_max:
		return "stamina=%d" % p.stamina
	if p.hp < 0:
		return "hp=%d" % p.hp
	if p.swing_ticks < 0 or p.swing_ticks > Combat.SWING_TOTAL:
		return "swing_ticks=%d" % p.swing_ticks
	if p.stun_ticks < 0 or p.stun_ticks > Combat.STUN_TICKS:
		return "stun_ticks=%d" % p.stun_ticks
	var alive: Array = []
	for e: EnemySim.Enemy in sim.enemies:
		if e.state != EnemySim.DEAD:
			alive.append(e)
	for i: int in range(alive.size()):
		var a: EnemySim.Enemy = alive[i]
		var h: int = EnemySim.half_of(a.type)
		if sim.grid.box_hits_solid(a.pos_x - h, a.pos_z - h, a.pos_x + h, a.pos_z + h):
			return "inimigo %d em célula bloqueante" % a.id
		var idx: int = sim.enemies.find(a)
		var moved: bool = idx < before.size() and (int(before[idx][0]) != a.pos_x or int(before[idx][1]) != a.pos_z)
		if moved and Combat.boxes_overlap(a.pos_x, a.pos_z, h, p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF):
			return "inimigo %d moveu-se para dentro do jogador" % a.id
		for j: int in range(i + 1, alive.size()):
			var b: EnemySim.Enemy = alive[j]
			if Combat.boxes_overlap(a.pos_x, a.pos_z, h, b.pos_x, b.pos_z, EnemySim.half_of(b.type)):
				return "inimigos %d e %d sobrepostos" % [a.id, b.id]
	return ""
