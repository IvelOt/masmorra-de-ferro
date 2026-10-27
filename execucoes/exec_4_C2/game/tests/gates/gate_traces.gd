class_name GateTraces
extends RefCounted
## Trilhas douradas dos gates: geração determinística e leitura.

const DIR: String = "res://tests/traces/"
## Ticks de move=1 na demo do boneco antes de parar (o resto dos 40 ticks é deslize).
const DEMO_APPROACH: int = 22
## Trilha da demonstração da rodada 5 (plano §3.2).
const DEMO4: String = "demo_iter4.jsonl"
const DEMO4_TICKS: int = 600
const DEMO4_NEUTRAL_END: int = 20
const DEMO4_PILOT_END: int = 140
const DEMO4_TURN_TICKS: int = 64
const DEMO4_TURN: int = 16
const DEMO4_SPIN_END: int = 210
const DEMO4_MAX_SEED: int = 50
const R4_TRACE: String = "r4_pilot_seed1337.jsonl"
const R4_SEED: int = 1337
const R4_TICKS: int = 3000

## Trilhas caras (piloto, demonstração) geradas uma vez por processo.
static var _cache: Dictionary = {}


static func repeat(n: int, inp: IntInput) -> Array:
	var out: Array = []
	for i: int in range(n):
		out.append(inp)
	return out


## Input aleatório do fluxo piloto/teste (PCG32 stream 3). Com `with_combat`,
## cada tick sorteia ainda `attack` (p = 1/8) e `block` (p = 1/4), nessa ordem.
static func random_inputs(p_seed: int, n: int, with_use: bool, with_combat: bool = false) -> Array:
	return random_inputs_rng(RngPcg32.new(p_seed, DungeonGen.STREAM_PILOT), n, with_use, with_combat)


static func random_inputs_rng(rng: RngPcg32, n: int, with_use: bool, with_combat: bool) -> Array:
	var out: Array = []
	for i: int in range(n):
		var mv: int = rng.range_i(-1, 1)
		var st: int = rng.range_i(-1, 1)
		var tn: int = rng.range_i(-128, 128)
		var use: bool = false
		if with_use:
			use = rng.range_i(0, 15) == 0
		var atk: bool = false
		var blk: bool = false
		if with_combat:
			atk = rng.range_i(0, 7) == 0
			blk = rng.range_i(0, 3) == 0
		out.append(IntInput.new(mv, st, tn, atk, blk, use, 0))
	return out


## M3-A6: block mantido em T=1..T+20, attack (com block) em T+20, attack sem block em T+21.
static func m3_a6_inputs() -> Array:
	return repeat(20, IntInput.new(0, 0, 0, false, true)) \
		+ [IntInput.new(0, 0, 0, true, true), IntInput.new(0, 0, 0, true, false)] \
		+ repeat(10, IntInput.new())


## Demonstração da sala de teste com o boneco (--test-room --dummy), ~600 ticks.
static func demo_dummy_inputs() -> Array:
	var out: Array = repeat(128, IntInput.new(0, 0, 32)) + repeat(128, IntInput.new(0, 0, 32))
	out += repeat(DEMO_APPROACH, IntInput.new(1, 0, 0)) + repeat(40 - DEMO_APPROACH, IntInput.new())
	for _i: int in range(4):
		out += [IntInput.new(0, 0, 0, true)] + repeat(29, IntInput.new())
	out += repeat(60, IntInput.new(0, 0, 0, false, true))
	out += repeat(60, IntInput.new(0, 1, 0))
	return out


## Demonstração da masmorra da semente 1: pose de m2_a6, use na porta, 120 ticks
## atravessando, giro para leste, corredor até a porta da sala 1, use, espera o
## esqueleto chegar, bloqueio + golpes e giros de 64 ticks (bússola).
static func demo_dungeon_inputs() -> Array:
	var out: Array = [IntInput.new(0, 0, 0, false, false, true)] + repeat(120, IntInput.new(1, 0, 0))
	out += repeat(32, IntInput.new(0, 0, 32)) + repeat(160, IntInput.new(1, 0, 0))
	out += [IntInput.new(0, 0, 0, false, false, true)] + repeat(140, IntInput.new())
	for _i: int in range(3):
		out += repeat(30, IntInput.new(0, 0, 0, false, true)) + [IntInput.new(0, 0, 0, true)] + repeat(23, IntInput.new())
	out += repeat(64, IntInput.new(0, 0, 32)) + repeat(64, IntInput.new(0, 0, -32))
	return out


## Pose da demonstração (§3.2, passo 1): primeira (semente, inimigo, célula) em
## que um rato/esqueleto e um item (não chave) da mesma sala ficam à frente.
## Devolve {"seed", "enemy", "item", "cell", "header"} ou {} se nenhuma semente serve.
static func demo_iter4_pose() -> Dictionary:
	for s: int in range(1, DEMO4_MAX_SEED + 1):
		var sim: WorldSim = WorldSim.new(s)
		for e: EnemySim.Enemy in sim.enemies:
			if e.type != EnemySim.RAT and e.type != EnemySim.SKELETON:
				continue
			var ecx: int = EnemySim.cell_of(e.pos_x)
			var ecz: int = EnemySim.cell_of(e.pos_z)
			var room: Dictionary = {}
			for r: Dictionary in sim.grid.rooms:
				if DungeonGen.in_room(r, ecx, ecz):
					room = r
					break
			if room.is_empty():
				continue
			var cands: Array = []
			for it: ItemsSim.Item in sim.items:
				if not it.taken and it.type != ItemsSim.KEY and DungeonGen.in_room(room, it.cell_x, it.cell_z):
					cands.append(it)
			if cands.is_empty():
				continue
			for cz: int in range(int(room["z"]), int(room["z"]) + int(room["h"])):
				for cx: int in range(int(room["x"]), int(room["x"]) + int(room["w"])):
					var it2: ItemsSim.Item = _demo_cell_ok(sim, e, cands, cx, cz)
					if it2 == null:
						continue
					var px: int = PilotSim.center(cx)
					var pz: int = PilotSim.center(cz)
					return {"seed": s, "enemy": e.id, "item": it2.id, "cell": [cx, cz],
						"header": {"seed": s, "pos_x": px, "pos_z": pz,
							"angle": best_angle(e.pos_x - px, e.pos_z - pz)}}
	return {}


## Critérios da célula c para o inimigo `e` e os itens candidatos (o primeiro que
## passa); a célula não pode ter item (seria coletado no tick 1).
static func _demo_cell_ok(sim: WorldSim, e: EnemySim.Enemy, cands: Array, cx: int, cz: int) -> ItemsSim.Item:
	if sim.grid.get_cell(cx, cz) != Grid.FLOOR:
		return null
	var ecx: int = EnemySim.cell_of(e.pos_x)
	var ecz: int = EnemySim.cell_of(e.pos_z)
	var de: int = maxi(absi(ecx - cx), absi(ecz - cz))
	if de < 4 or de > 5:
		return null
	var px: int = PilotSim.center(cx)
	var pz: int = PilotSim.center(cz)
	if not EnemySim.los(sim.grid, px, pz, e.pos_x, e.pos_z):
		return null
	for it: ItemsSim.Item in sim.items:
		if it.cell_x == cx and it.cell_z == cz:
			return null
	var ax: int = ecx - cx
	var az: int = ecz - cz
	for it: ItemsSim.Item in cands:
		var bx: int = it.cell_x - cx
		var bz: int = it.cell_z - cz
		if (bx == 0 and bz == 0) or maxi(absi(bx), absi(bz)) > 4:
			continue
		var dot: int = ax * bx + az * bz
		if dot <= 0 or absi(ax * bz - az * bx) > dot:
			continue
		if not EnemySim.los(sim.grid, px, pz, PilotSim.center(it.cell_x), PilotSim.center(it.cell_z)):
			continue
		return it
	return null


## Múltiplo de 128 BAM que maximiza dx·cos + dz·sin (TrigTable); empate: o menor.
static func best_angle(dx: int, dz: int) -> int:
	var best: int = 0
	var best_v: int = 0
	for k: int in range(32):
		var a: int = k * 128
		var v: int = dx * TrigTable.cos_q16(a) + dz * TrigTable.sin_q16(a)
		if k == 0 or v > best_v:
			best = a
			best_v = v
	return best


## Demonstração da rodada 5 (§3.2): {"header", "inputs"} ou {} sem cena em 1..50.
static func demo_iter4() -> Dictionary:
	if _cache.has(DEMO4):
		return _cache[DEMO4]
	var pose: Dictionary = demo_iter4_pose()
	if pose.is_empty():
		_cache[DEMO4] = {}
		return {}
	var h: Dictionary = pose["header"]
	var s: int = int(h["seed"])
	var sim: WorldSim = WorldSim.new(s)
	sim.set_player_pose(int(h["pos_x"]), int(h["pos_z"]), int(h["angle"]))
	var it: ItemsSim.Item = sim.items[int(pose["item"])]
	var pilot: PilotSim = PilotSim.new(s)
	pilot.goal_override = [it.cell_x, it.cell_z]
	var out: Array = []
	for t: int in range(1, DEMO4_TICKS + 1):
		var inp: IntInput = IntInput.new()
		if t <= DEMO4_NEUTRAL_END:
			pass
		elif t <= DEMO4_PILOT_END:
			inp = pilot.next_input(sim)
		elif t <= DEMO4_PILOT_END + DEMO4_TURN_TICKS:
			inp = IntInput.new(0, 0, DEMO4_TURN)
		elif t <= DEMO4_SPIN_END:
			pass
		else:
			pilot.goal_override = []
			inp = pilot.next_input(sim)
		out.append(inp)
		sim.step(inp)
	var res: Dictionary = {"header": h, "inputs": out}
	_cache[DEMO4] = res
	return res


## Piloto da semente 1337 por 3000 ticks no núcleo (R4).
static func r4_pilot_inputs() -> Array:
	if _cache.has(R4_TRACE):
		return _cache[R4_TRACE]
	var sim: WorldSim = WorldSim.new(R4_SEED)
	var pilot: PilotSim = PilotSim.new(R4_SEED)
	var out: Array = []
	for _t: int in range(R4_TICKS):
		var inp: IntInput = pilot.next_input(sim)
		out.append(inp)
		sim.step(inp)
	_cache[R4_TRACE] = out
	return out


## Trilhas fixas de M1 e R1/R2/R3 (nome -> inputs).
static func fixed() -> Dictionary:
	var a3: Array = repeat(64, IntInput.new(0, 0, 64)) + repeat(64, IntInput.new(0, 0, -64))
	var a5: Array = repeat(40, IntInput.new(1, 0, 0)) + repeat(40, IntInput.new())
	return {
		"m1_a1_forward.jsonl": repeat(120, IntInput.new(1, 0, 0)),
		"m1_a2_strafe.jsonl": repeat(60, IntInput.new(0, 1, 0)),
		"m1_a3_turn.jsonl": a3,
		"m1_a4_random.jsonl": random_inputs(4242, 600, false),
		"m1_a5_stop.jsonl": a5,
		"r_seed1337_random.jsonl": random_inputs(1337, 600, true),
		"m3_a1_swing.jsonl": [IntInput.new(0, 0, 0, true)] + repeat(30, IntInput.new()),
		"m3_a6_guardbreak.jsonl": m3_a6_inputs(),
		"m3_a7_random.jsonl": random_inputs(4343, 600, false, true),
		"m4_a3_dodge.jsonl": GateM4.dodge_inputs(),
		"r_seed1337_combat.jsonl": random_inputs(1337, 600, true, true),
		"demo_iter2_dummy.jsonl": demo_dummy_inputs(),
		"demo_iter2_dungeon.jsonl": demo_dungeon_inputs(),
		DEMO4: demo_iter4().get("inputs", []),
		GateM5.A2_TRACE: GateM5.corridor_setup()["inputs"],
		GateM6.A3_TRACE: GateM6.a3_setup()["inputs"],
		R4_TRACE: r4_pilot_inputs(),
	}


## Cabeçalhos de pose das trilhas fixas que os têm (nome -> cabeçalho).
static func headers() -> Dictionary:
	var g: Grid = DungeonGen.new().generate(1)
	return {
		"demo_iter2_dungeon.jsonl": GateM2.a6_setup(g)["header"],
		DEMO4: demo_iter4().get("header", {}),
		GateM5.A2_TRACE: GateM5.corridor_setup()["header"],
		GateM6.A3_TRACE: GateM6.a3_setup()["header"],
	}


static func load_inputs(name: String) -> Array:
	var tr: Variant = TraceIO.read(DIR + name)
	if tr == null:
		return []
	return tr["inputs"]


static func load_trace(name: String) -> Variant:
	return TraceIO.read(DIR + name)


static func same_inputs(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i: int in range(a.size()):
		if (a[i] as IntInput).to_dict() != (b[i] as IntInput).to_dict():
			return false
	return true
