class_name GateM6
extends RefCounted
## M6-A1..A6, M6-A1b, R2 e R4: itens, progressão e terminal (plano da iteração 5 §5.2).

const A3_TRACE: String = "m6_a3_exit_seed1.jsonl"
const SEEDS: int = 100
const SPAWN_X: int = 9216
const SPAWN_Z: int = 15360
const FRONT_X: int = SPAWN_X + 1229
const A4_FROZEN_TICKS: int = 300
const A6_SEEDS: int = 50
const A6_MIN_ESCAPED: int = 40
const R2_TRACE: String = "res://tests/traces/r_seed1337_combat.jsonl"
const R2_PILOT_SEED: int = 7
const R2_PILOT_TICKS: int = 3000


static func run(r: GateReport) -> void:
	_a1(r)
	_a1b(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)
	_r4(r)
	_r2(r)


static func _room_of(g: Grid, cx: int, cz: int) -> int:
	for room: Dictionary in g.rooms:
		if DungeonGen.in_room(room, cx, cz):
			return int(room["id"])
	return -1


static func _a1(r: GateReport) -> void:
	var fails: Array = []
	for s: int in range(1, SEEDS + 1):
		var sim: WorldSim = WorldSim.new(s)
		var g: Grid = sim.grid
		var why: String = ""
		var keys: Array = []
		var cells: Dictionary = {}
		for it: ItemsSim.Item in sim.items:
			var rid: int = _room_of(g, it.cell_x, it.cell_z)
			if g.get_cell(it.cell_x, it.cell_z) != Grid.FLOOR or rid < 0:
				why = "item %d fora de FLOOR de sala" % it.id
			if cells.has(it.cell_z * Grid.W + it.cell_x):
				why = "itens na mesma célula (%d,%d)" % [it.cell_x, it.cell_z]
			cells[it.cell_z * Grid.W + it.cell_x] = true
			if rid == g.start_room and (it.id != 0 or it.type != ItemsSim.POTION_HP):
				why = "item %d na sala inicial" % it.id
			if it.type == ItemsSim.KEY:
				keys.append(it)
		var it0: ItemsSim.Item = sim.items[0] if not sim.items.is_empty() else null
		if it0 == null or it0.type != ItemsSim.POTION_HP or _room_of(g, it0.cell_x, it0.cell_z) != g.start_room:
			why = "item 0 não é a poção da sala inicial"
		if keys.size() != 1:
			why = "%d chaves" % keys.size()
		else:
			var k: ItemsSim.Item = keys[0]
			var kr: int = _room_of(g, k.cell_x, k.cell_z)
			var reach: PackedInt32Array = ItemsSim.bfs_lock(g, PilotSim.cell_of(g.spawn_x), PilotSim.cell_of(g.spawn_z))
			if kr == g.start_room or kr == g.exit_room:
				why = "chave na sala %d" % kr
			elif reach[k.cell_z * Grid.W + k.cell_x] < 0:
				why = "chave inalcançável sem a porta trancada"
		if why != "":
			fails.append("%d: %s" % [s, why])
	r.check("M6-A1", fails.is_empty(), "sementes 1..%d: 1 chave alcançável fora de início/saída, itens em FLOOR de salas, sem repetição, sala 0 só com o item 0; falhas=%s" % [
		SEEDS, str(fails)])


static func _dicts(arr: Array) -> Array:
	var out: Array = []
	for o: Variant in arr:
		out.append(o.call("to_dict"))
	return out


static func _a1b(r: GateReport) -> void:
	var fails: Array = []
	var gen: DungeonGen = DungeonGen.new()
	for s: int in range(1, SEEDS + 1):
		var a: WorldSim = WorldSim.new(s)
		var b: WorldSim = WorldSim.new(s)
		var g: Grid = gen.generate(s)
		var rng: RngPcg32 = RngPcg32.new(s, DungeonGen.STREAM_DUNGEON)
		rng.state = gen.rng_state
		var alone: Array = EnemySim.spawn_for_dungeon(g, rng)
		if _dicts(a.items) != _dicts(b.items):
			fails.append("%d: itens diferem" % s)
		if _dicts(a.enemies) != _dicts(alone):
			fails.append("%d: inimigos diferem" % s)
	var digest: String = GateRepro.grid_digest()
	r.check("M6-A1b", fails.is_empty() and digest == GateRepro.GRID_DIGEST_R1,
		"sementes 1..%d: itens iguais entre instâncias e inimigos iguais a spawn_for_dungeon sozinho; PRES-grid=%s; falhas=%s" % [
			SEEDS, digest == GateRepro.GRID_DIGEST_R1, str(fails)])


static func _room() -> WorldSim:
	return WorldSim.new(1, true)


## Um tick com `quaff` a partir de (hp, stamina, poções); devolve o jogador depois.
static func _quaff_case(hp: int, sp: int, php: int, psp: int, which: int) -> PlayerSim:
	var sim: WorldSim = _room()
	sim.player.hp = hp
	sim.player.stamina = sp
	sim.player.potion_hp = php
	sim.player.potion_sp = psp
	sim.step(IntInput.new(0, 0, 0, false, false, false, which))
	return sim.player


static func _a2(r: GateReport) -> void:
	var errs: Array = []
	# (a) sem poção: igual ao tick sem quaff.
	var ref: WorldSim = _room()
	ref.player.hp = 50
	ref.player.stamina = 50
	ref.step(IntInput.new())
	for w: int in [1, 2]:
		var p: PlayerSim = _quaff_case(50, 50, 0, 0, w)
		if p.hp != ref.player.hp or p.stamina != ref.player.stamina or p.potion_hp != 0 or p.potion_sp != 0:
			errs.append("a%d" % w)
	# (b)..(d) vida; (e) vigor nos mesmos casos.
	var hp_cases: Array = [[100, 100, 1], [30, 70, 0], [90, 100, 0]]
	for c: Array in hp_cases:
		var p2: PlayerSim = _quaff_case(int(c[0]), 50, 1, 0, 1)
		if p2.hp != int(c[1]) or p2.potion_hp != int(c[2]):
			errs.append("hp %d -> %d (poções %d)" % [int(c[0]), p2.hp, p2.potion_hp])
	var sp_cases: Array = [[100, 100, 1], [30, 80, 0], [90, 100, 0]]
	for c: Array in sp_cases:
		var p3: PlayerSim = _quaff_case(50, int(c[0]), 0, 1, 2)
		if p3.stamina != int(c[1]) or p3.potion_sp != int(c[2]):
			errs.append("vigor %d -> %d (poções %d)" % [int(c[0]), p3.stamina, p3.potion_sp])
	# (f) coleta no tick em que o jogador entra na célula.
	var sim: WorldSim = _room()
	var pcx: int = PilotSim.cell_of(sim.player.pos_x)
	var pcz: int = PilotSim.cell_of(sim.player.pos_z)
	sim.add_item(ItemsSim.POTION_HP, pcx + 1, pcz)
	var enter_tick: int = -1
	var pick_tick: int = -1
	for _t: int in range(60):
		sim.step(IntInput.new(1, 0, 0))
		if enter_tick < 0 and PilotSim.cell_of(sim.player.pos_x) == pcx + 1:
			enter_tick = sim.tick
		if pick_tick < 0 and sim.player.potion_hp == 1:
			pick_tick = sim.tick
	if enter_tick < 0 or enter_tick != pick_tick or not (sim.items[0] as ItemsSim.Item).taken:
		errs.append("coleta: entrou no tick %d, inventário no tick %d" % [enter_tick, pick_tick])
	r.check("M6-A2", errs.is_empty(), "quaff sem poção/cheio/30/90 para vida e vigor e coleta no tick de entrada (tick %d); erros=%s" % [
		enter_tick, str(errs)])


## Trilha de M6-A3: pose no centro do EXIT da semente 1; use, neutro (coleta), use.
static func a3_setup() -> Dictionary:
	var g: Grid = DungeonGen.new().generate(1)
	var ex: Array = DungeonGen.room_center(g.rooms[g.exit_room])
	return {
		"header": {"seed": 1, "pos_x": PilotSim.center(int(ex[0])), "pos_z": PilotSim.center(int(ex[1])), "angle": 0},
		"inputs": [IntInput.new(0, 0, 0, false, false, true), IntInput.new(), IntInput.new(0, 0, 0, false, false, true)],
	}


## Pose de frente para a primeira DOOR_LOCKED (varredura), na vizinha FLOOR.
static func _locked_pose(sim: WorldSim) -> Array:
	var angles: Dictionary = {"1,0": 0, "0,1": 1024, "-1,0": 2048, "0,-1": 3072}
	for d: Dictionary in sim.grid.doors():
		if int(d["state"]) != Grid.DOOR_LOCKED:
			continue
		var dx: int = int(d["cell_x"])
		var dz: int = int(d["cell_z"])
		for dir: Array in DungeonGen.DIRS:
			var nx: int = dx - int(dir[0])
			var nz: int = dz - int(dir[1])
			if sim.grid.get_cell(nx, nz) == Grid.FLOOR:
				sim.set_player_pose(PilotSim.center(nx), PilotSim.center(nz), int(angles["%d,%d" % [dir[0], dir[1]]]))
				return [dx, dz]
	return []


static func _key_of(sim: WorldSim) -> ItemsSim.Item:
	for it: ItemsSim.Item in sim.items:
		if it.type == ItemsSim.KEY:
			return it
	return null


static func _a3(r: GateReport) -> void:
	var setup: Dictionary = a3_setup()
	var tr: Variant = GateTraces.load_trace(A3_TRACE)
	var trace_ok: bool = tr != null and GateTraces.same_inputs(tr["inputs"], setup["inputs"]) \
		and tr["header"] == setup["header"]
	if not trace_ok:
		r.check("M6-A3", false, "trilha %s não confere com a geração" % A3_TRACE)
		return
	var h: Dictionary = tr["header"]
	var inputs: Array = tr["inputs"]
	var sim: WorldSim = WorldSim.new(1)
	sim.set_player_pose(int(h["pos_x"]), int(h["pos_z"]), int(h["angle"]))
	sim.step(inputs[0])
	var a_ok: bool = sim.terminal == "" and sim.on_exit_cell()
	var key: ItemsSim.Item = _key_of(sim)
	key.cell_x = PilotSim.cell_of(sim.player.pos_x)
	key.cell_z = PilotSim.cell_of(sim.player.pos_z)
	sim.step(inputs[1])
	var got: bool = sim.player.has_key
	sim.step(inputs[2])
	var b_ok: bool = got and sim.terminal == WorldSim.ESCAPED and sim.terminal_tick == sim.tick
	# (c) porta trancada
	var w: WorldSim = WorldSim.new(1)
	var door: Array = _locked_pose(w)
	var c_ok: bool = false
	var detail_c: String = "sem DOOR_LOCKED"
	if not door.is_empty():
		var v0: int = w.grid_version
		w.step(IntInput.new(0, 0, 0, false, false, true))
		var still: bool = w.grid.get_cell(int(door[0]), int(door[1])) == Grid.DOOR_LOCKED and w.grid_version == v0
		var k2: ItemsSim.Item = _key_of(w)
		k2.cell_x = PilotSim.cell_of(w.player.pos_x)
		k2.cell_z = PilotSim.cell_of(w.player.pos_z)
		w.step(IntInput.new())
		var v1: int = w.grid_version
		w.step(IntInput.new(0, 0, 0, false, false, true))
		var opened: bool = w.grid.get_cell(int(door[0]), int(door[1])) == Grid.DOOR_OPEN and w.grid_version > v1
		c_ok = still and w.player.has_key and opened
		detail_c = "porta (%d,%d): sem chave trancada=%s, com chave aberta=%s, chave mantida=%s" % [
			int(door[0]), int(door[1]), still, opened, w.player.has_key]
	r.check("M6-A3", a_ok and b_ok and c_ok, "use sem chave no EXIT sem terminal=%s; com chave: %s no tick %d (terminal_tick %d); %s" % [
		a_ok, sim.terminal, sim.tick, sim.terminal_tick, detail_c])


static func _state_wo_tick(sim: WorldSim) -> String:
	var s: Dictionary = sim.get_state()
	s.erase("tick")
	return StateHash.canon(s)


static func _a4(r: GateReport) -> void:
	var sim: WorldSim = _room()
	sim.queue_hit(sim.player.pos_x - 1024, sim.player.pos_z, 100)
	sim.step(IntInput.new())
	var dead_ok: bool = sim.terminal == WorldSim.DEAD and sim.terminal_tick == 1 and sim.player.hp == 0
	var frozen: String = _state_wo_tick(sim)
	var rng: RngPcg32 = RngPcg32.new(4545, DungeonGen.STREAM_PILOT)
	var froze_ok: bool = true
	for inp: IntInput in GateTraces.random_inputs(4545, A4_FROZEN_TICKS, true, true):
		var t0: int = sim.tick
		var q: IntInput = IntInput.new(inp.move, inp.strafe, inp.turn, inp.attack, inp.block, inp.use, rng.range_i(0, 2))
		sim.step(q)
		if sim.tick != t0 + 1 or _state_wo_tick(sim) != frozen:
			froze_ok = false
	var tsim: WorldSim = _room()
	var neutral: IntInput = IntInput.new()
	while tsim.terminal == "" and tsim.tick < WorldSim.K_MAX + 1:
		tsim.step(neutral)
	var to_ok: bool = tsim.terminal == WorldSim.TIMEOUT and tsim.terminal_tick == WorldSim.K_MAX
	r.check("M6-A4", dead_ok and froze_ok and to_ok, "DEAD no tick do golpe=%s; %d ticks congelados (só tick muda)=%s; TIMEOUT=%s terminal_tick=%d" % [
		dead_ok, A4_FROZEN_TICKS, froze_ok, tsim.terminal, tsim.terminal_tick])


## Golpe completo contra um inimigo novo à frente com `hp` dado; true se morreu.
static func _kill(sim: WorldSim, type: int, hp: int) -> bool:
	var id: int = sim.add_enemy(type, FRONT_X, SPAWN_Z)
	var e: EnemySim.Enemy = sim.enemies[id]
	e.hp = hp
	_swing(sim)
	return e.state == EnemySim.DEAD


static func _swing(sim: WorldSim) -> void:
	sim.step(IntInput.new(0, 0, 0, true))
	for _t: int in range(Combat.SWING_TOTAL + 12):
		sim.step(IntInput.new())


## Dano real da espada medido num boneco novo (depois retirado de cena).
static func _measure_damage(sim: WorldSim) -> int:
	var id: int = sim.add_enemy(EnemySim.DUMMY, FRONT_X, SPAWN_Z)
	var e: EnemySim.Enemy = sim.enemies[id]
	_swing(sim)
	var dmg: int = int(EnemySim.HP[EnemySim.DUMMY]) - e.hp
	e.hp = 0
	e.state = EnemySim.DEAD
	return dmg


static func _snap(p: PlayerSim, dmg: int) -> Array:
	return [p.xp, p.level, p.hp_max, p.stamina_max, p.hp, dmg]


static func _a5(r: GateReport) -> void:
	var sim: WorldSim = _room()
	var kills: bool = true
	for _i: int in range(4):
		kills = _kill(sim, EnemySim.SKELETON, 25) and kills
	var s1: Array = _snap(sim.player, _measure_damage(sim))
	kills = _kill(sim, EnemySim.GUARDIAN, 30) and kills
	var s2: Array = [sim.player.xp, sim.player.level]
	for _i: int in range(2):
		kills = _kill(sim, EnemySim.SKELETON, 30) and kills
	var s3: Array = _snap(sim.player, _measure_damage(sim))
	var j: WorldSim = _room()
	j.player.xp = 240
	var jk: bool = _kill(j, EnemySim.RAT, 20)
	var s4: Array = _snap(j.player, Combat.sword_damage(j.player))
	var ok: bool = kills and jk and s1 == [100, 2, 120, 110, 120, 30] and s2 == [200, 2] \
		and s3 == [250, 3, 140, 120, 140, 35] and s4 == [250, 3, 140, 120, 140, 35]
	r.check("M6-A5", ok, "[xp, nível, hp_max, vigor_max, hp, dano]: 4 esqueletos=%s; +Guardião [xp, nível]=%s; +2 esqueletos=%s; salto 1→3 (xp 240 + rato)=%s" % [
		str(s1), str(s2), str(s3), str(s4)])


static func _a6(r: GateReport) -> void:
	var ok: int = 0
	print("[M6-A6] seed terminal terminal_tick level gold")
	for s: int in range(1, A6_SEEDS + 1):
		var sim: WorldSim = WorldSim.new(s)
		var pilot: PilotSim = PilotSim.new(s)
		while sim.terminal == "":
			sim.step(pilot.next_input(sim))
		if sim.terminal == WorldSim.ESCAPED:
			ok += 1
		print("[M6-A6] %d %s %d %d %d" % [s, sim.terminal, sim.terminal_tick, sim.player.level, sim.player.gold])
	r.check("M6-A6", ok >= A6_MIN_ESCAPED, "piloto: ESCAPED em %d de %d sementes (mínimo %d)" % [ok, A6_SEEDS, A6_MIN_ESCAPED])


static func _r4(r: GateReport) -> void:
	var sim: WorldSim = WorldSim.new(GateTraces.R4_SEED)
	var pilot: PilotSim = PilotSim.new(GateTraces.R4_SEED)
	var live: Array = []
	for _t: int in range(GateTraces.R4_TICKS):
		var inp: IntInput = pilot.next_input(sim)
		live.append(inp)
		sim.step(inp)
	var inputs: Array = GateTraces.load_inputs(GateTraces.R4_TRACE)
	var rep: WorldSim = WorldSim.new(GateTraces.R4_SEED)
	for inp: IntInput in inputs:
		rep.step(inp)
	r.check("R4", GateTraces.same_inputs(inputs, live) and rep.chain == sim.chain,
		"%s (%d ticks): piloto C_K=%s, replay C_K=%s" % [GateTraces.R4_TRACE, inputs.size(), sim.chain, rep.chain])


## Roda o runner num processo novo e devolve chain_final ("" se falhar).
static func _runner_chain(args: Array, tag: String) -> String:
	var out_rel: String = "runs/tmp/r2_%s.json" % tag
	var full: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://scripts/headless_runner.gd", "--"] + args + ["--output=" + out_rel]
	var log: Array = []
	var code: int = OS.execute(OS.get_executable_path(), PackedStringArray(full), log, true)
	if code != 0:
		return ""
	var txt: String = FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://").path_join(out_rel))
	var rep: Variant = JSON.parse_string(txt)
	if typeof(rep) != TYPE_DICTIONARY:
		return ""
	return String((rep as Dictionary).get("chain_final", ""))


static func _r2(r: GateReport) -> void:
	var replay: Array = ["--seed=1337", "--ticks=600", "--mode=replay", "--trace=" + R2_TRACE]
	var a: String = _runner_chain(replay, "replay_a")
	var b: String = _runner_chain(replay, "replay_b")
	var pilot: Array = ["--seed=%d" % R2_PILOT_SEED, "--ticks=%d" % R2_PILOT_TICKS, "--mode=pilot"]
	var c: String = _runner_chain(pilot, "pilot_a")
	var d: String = _runner_chain(pilot, "pilot_b")
	r.check("R2", a != "" and a == b and c != "" and c == d,
		"replay r_seed1337_combat: %s / %s; piloto seed %d: %s / %s" % [a, b, R2_PILOT_SEED, c, d])
