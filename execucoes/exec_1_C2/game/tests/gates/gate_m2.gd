extends RefCounted
## Acceptance Gate de M2 (plano §5.4), M2-PRES (rodada 2), vetor de teste do PCG32 (§4.3) e R1.
##
## Trilha m2_door_test_room.jsonl (449 ticks), contagem ajustada pelo Desenvolvedor:
##   16 x turn=-64 (angle 3072) | 44 x move=1 + 32 x vazio (para em pos_z = 9244, linha 4)
##   16 x turn=+64 (angle 0)    | 220 x move=1 (bloqueado em pos_x = 30336)
##   1 x use (abre a porta (15,4)) | 120 x move=1 (atravessa para o anexo)
## O plano sugeria 150 x move=1 no trecho bloqueado, mas partindo de pos_x = 5120 o
## jogador só chega à porta perto do tick 190 desse trecho; 220 garante o contato.

const GateM1 = preload("res://tests/gates/gate_m1.gd")
const SEEDS: int = 100
const SHA_R1: String = "res://tests/gates/m2_grid_sha_r1.json"
const DOOR_TRACE: String = "res://tests/traces/m2_door_test_room.jsonl"
const DOOR_BLOCK_X: int = 15 * 2048 - 384
const USE_TICK: int = 16 + 44 + 32 + 16 + 220 + 1


static func run(results: Array[Dictionary]) -> void:
	_pcg(results)
	var gens: Array[DungeonGen] = []
	for s in range(1, SEEDS + 1):
		gens.append(DungeonGen.generate(s))
	_a1(results, gens)
	_a2(results, gens)
	_a3(results, gens)
	_a4(results, gens)
	_a5(results, gens)
	_pres(results, gens)
	_a6(results)
	_r1(results)


static func _pcg(results: Array[Dictionary]) -> void:
	var r: RngPcg32 = RngPcg32.create(42, 54)
	var got: Array[int] = []
	for i in range(6):
		got.append(r.next_u32())
	var exp: Array[int] = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	r = RngPcg32.create(1, 1)
	var got2: Array[int] = [r.next_u32(), r.next_u32(), r.next_u32()]
	var exp2: Array[int] = [3380776849, 361947764, 3223725655]
	GateM1.check(results, "PCG32", got == exp and got2 == exp2, [exp, exp2], [got, got2])


static func _a1(results: Array[Dictionary], gens: Array[DungeonGen]) -> void:
	var bad: String = ""
	for i in range(gens.size()):
		var d: DungeonGen = gens[i]
		var n: int = d.rooms.size()
		if not d.ok or n < 6 or n > 9:
			bad = "semente %d: ok=%s N=%d" % [i + 1, d.ok, n]
			break
		for a in range(n):
			for b in range(a + 1, n):
				var ra: Dictionary = d.rooms[a]
				var rb: Dictionary = d.rooms[b]
				if ra.x < rb.x + rb.w and rb.x < ra.x + ra.w and ra.z < rb.z + rb.h and rb.z < ra.z + ra.h:
					bad = "semente %d: salas %d e %d sobrepostas" % [i + 1, a, b]
		if bad != "":
			break
	GateM1.check(results, "M2-A1", bad == "", "6 <= N <= 9 e interiores disjuntos (sementes 1-100)", bad)


static func _start_cell(d: DungeonGen) -> Array[int]:
	return [d.start_pos[0] >> 11, d.start_pos[1] >> 11]


static func _a2(results: Array[Dictionary], gens: Array[DungeonGen]) -> void:
	var bad: String = ""
	for i in range(gens.size()):
		var d: DungeonGen = gens[i]
		var sc: Array[int] = _start_cell(d)
		var dist: PackedInt32Array = DungeonGen.bfs(d.grid, sc[0], sc[1])
		for idx in range(Grid.SIZE * Grid.SIZE):
			if d.grid.cells[idx] == Grid.FLOOR and dist[idx] < 0:
				bad = "semente %d: FLOOR (%d, %d) inalcançável" % [i + 1, idx % Grid.SIZE, idx / Grid.SIZE]
				break
		if bad != "":
			break
	GateM1.check(results, "M2-A2", bad == "", "todo FLOOR alcançável da sala 0", bad)


static func _a3(results: Array[Dictionary], gens: Array[DungeonGen]) -> void:
	var bad: String = ""
	for i in range(gens.size()):
		var d: DungeonGen = gens[i]
		var sc: Array[int] = _start_cell(d)
		var dist: PackedInt32Array = DungeonGen.bfs(d.grid, sc[0], sc[1])
		var de: int = dist[d.exit_cell[1] * Grid.SIZE + d.exit_cell[0]]
		var exit_ok: bool = d.grid.get_cell(d.exit_cell[0], d.exit_cell[1]) == Grid.EXIT
		if d.exit_room == 0 or de < 20 or not exit_ok:
			bad = "semente %d: exit_room=%d dist=%d" % [i + 1, d.exit_room, de]
			break
	GateM1.check(results, "M2-A3", bad == "", "exit_room != 0 e distância BFS >= 20", bad)


static func _a4(results: Array[Dictionary], gens: Array[DungeonGen]) -> void:
	var bad: String = ""
	var total: int = 0
	for i in range(gens.size()):
		var d: DungeonGen = gens[i]
		for door: Dictionary in d.doors:
			total += 1
			if not DungeonGen.door_shape_ok(d.grid, door.cx, door.cz):
				bad = "semente %d: porta %d em (%d, %d)" % [i + 1, door.id, door.cx, door.cz]
				break
		if bad != "":
			break
	if bad == "" and total == 0:
		bad = "nenhuma porta gerada"
	GateM1.check(results, "M2-A4", bad == "", "toda porta: passável em lados opostos, SOLID nos outros", bad)


static func _a5(results: Array[Dictionary], gens: Array[DungeonGen]) -> void:
	var bad: String = ""
	for i in range(gens.size()):
		if DungeonGen.generate(i + 1).grid.sha256() != gens[i].grid.sha256():
			bad = "semente %d gerou grades diferentes" % (i + 1)
			break
	var differ: int = 0
	for s in range(1, SEEDS + 1):
		var next: String = gens[s].grid.sha256() if s < SEEDS else DungeonGen.generate(s + 1).grid.sha256()
		if gens[s - 1].grid.sha256() != next:
			differ += 1
	if bad == "" and differ < 99:
		bad = "só %d de 100 pares (s, s+1) diferentes" % differ
	GateM1.check(results, "M2-A5", bad == "", "mesma semente = mesma grade; >= 99/100 pares diferentes", bad)


## M2-PRES: grid_sha256 das sementes 1-100 igual ao gravado na rodada 1.
static func _pres(results: Array[Dictionary], gens: Array[DungeonGen]) -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHA_R1))
	var bad: String = ""
	if typeof(parsed) != TYPE_DICTIONARY:
		bad = "não foi possível ler %s" % SHA_R1
	else:
		var ref: Dictionary = parsed
		for i in range(gens.size()):
			var got: String = gens[i].grid.sha256()
			if str(ref.get(str(i + 1), "")) != got:
				bad = "semente %d: esperado %s, obtido %s" % [i + 1, ref.get(str(i + 1), ""), got]
				break
	GateM1.check(results, "M2-PRES", bad == "", "grid_sha256 das sementes 1-100 iguais à rodada 1", bad)


static func _a6(results: Array[Dictionary]) -> void:
	var trace: Array[IntInput] = TraceIO.load_trace(DOOR_TRACE)
	var w: WorldSim = WorldSim.create(1, "test")
	var max_x_closed: int = 0
	var x_at_use: int = -1
	var state_after_use: int = -1
	for k in range(trace.size()):
		w.step(trace[k])
		if w.tick < USE_TICK:
			max_x_closed = maxi(max_x_closed, w.player.pos_x)
			if w.grid.get_cell(15, 4) != Grid.DOOR_CLOSED:
				break
		elif w.tick == USE_TICK:
			x_at_use = w.player.pos_x
			state_after_use = w.grid.get_cell(15, 4)
	var ok: bool = trace.size() == 449 and max_x_closed == DOOR_BLOCK_X and x_at_use == DOOR_BLOCK_X \
		and state_after_use == Grid.DOOR_OPEN and w.player.pos_x > 16 * 2048
	GateM1.check(results, "M2-A6", ok,
		"bloqueado em pos_x=%d, porta DOOR_OPEN após use, pos_x final > %d" % [DOOR_BLOCK_X, 16 * 2048],
		"max pos_x fechada=%d, pos_x no use=%d, estado=%d, pos_x final=%d, ticks=%d" % [max_x_closed, x_at_use, state_after_use, w.player.pos_x, trace.size()])


## R1: duas WorldSim no mesmo processo, semente 7, idle, 600 ticks.
static func _r1(results: Array[Dictionary]) -> void:
	var a: WorldSim = WorldSim.create(7)
	var b: WorldSim = WorldSim.create(7)
	for k in range(600):
		a.step(IntInput.new())
		b.step(IntInput.new())
	GateM1.check(results, "R1", a.chain() == b.chain() and a.tick == 600, a.chain(), b.chain())
