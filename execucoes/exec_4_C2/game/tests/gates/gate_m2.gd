class_name GateM2
extends RefCounted
## M2-A1..A6 (sementes 1..100) e invariante de colisão na masmorra da semente 7.

const SEEDS: int = 100
const A6_TRACE: String = "m2_a6_door_seed1.jsonl"


static func run(r: GateReport, record: bool) -> void:
	var gen: DungeonGen = DungeonGen.new()
	var hashes: Dictionary = {}
	var f1: Array = []
	var f2: Array = []
	var f3: Array = []
	var f4: Array = []
	var f5_same: Array = []
	for s: int in range(1, SEEDS + 2):
		var g: Grid = gen.generate(s)
		var h: String = g.grid_sha256()
		hashes[s] = h
		if gen.generate(s).grid_sha256() != h:
			f5_same.append(s)
		if s > SEEDS:
			continue
		if not _a1(g):
			f1.append(s)
		if not _a2(g):
			f2.append(s)
		if not _a3(g):
			f3.append(s)
		if not _a4(g):
			f4.append(s)
	r.check("M2-A1", f1.is_empty(), "salas em [6,9], sem sobreposição, margem>=2; falhas=%s" % str(f1))
	r.check("M2-A2", f2.is_empty(), "todo não-SOLID alcançável da sala 0; falhas=%s" % str(f2))
	r.check("M2-A3", f3.is_empty(), "saída != 0 e distância BFS >= 20; falhas=%s" % str(f3))
	r.check("M2-A4", f4.is_empty(), "forma de porta; falhas=%s" % str(f4))
	var diff: int = 0
	for s: int in range(1, SEEDS + 1):
		if hashes[s] != hashes[s + 1]:
			diff += 1
	r.check("M2-A5", f5_same.is_empty() and diff >= 99,
		"mesma semente estável (falhas=%s); pares (s,s+1) diferentes=%d/100" % [str(f5_same), diff])
	_a6(r, record)
	_invariant_seed7(r)


static func _a1(g: Grid) -> bool:
	var n: int = g.rooms.size()
	if n < 6 or n > 9:
		return false
	for i: int in range(n):
		var a: Dictionary = g.rooms[i]
		if int(a["id"]) != i or int(a["x"]) < 1 or int(a["z"]) < 1 \
				or int(a["x"]) + int(a["w"]) > 63 or int(a["z"]) + int(a["h"]) > 63:
			return false
		for j: int in range(i + 1, n):
			var b: Dictionary = g.rooms[j]
			var sep: bool = int(a["x"]) + int(a["w"]) + 2 <= int(b["x"]) \
				or int(b["x"]) + int(b["w"]) + 2 <= int(a["x"]) \
				or int(a["z"]) + int(a["h"]) + 2 <= int(b["z"]) \
				or int(b["z"]) + int(b["h"]) + 2 <= int(a["z"])
			if not sep:
				return false
	return true


static func _a2(g: Grid) -> bool:
	var c: Array = DungeonGen.room_center(g.rooms[0])
	var dist: PackedInt32Array = DungeonGen.bfs(g, int(c[0]), int(c[1]))
	for i: int in range(Grid.W * Grid.H):
		if g.cells[i] != Grid.SOLID and dist[i] < 0:
			return false
	return true


static func _a3(g: Grid) -> bool:
	if g.exit_room == 0:
		return false
	var c0: Array = DungeonGen.room_center(g.rooms[0])
	var ce: Array = DungeonGen.room_center(g.rooms[g.exit_room])
	var dist: PackedInt32Array = DungeonGen.bfs(g, int(c0[0]), int(c0[1]))
	return dist[int(ce[1]) * Grid.W + int(ce[0])] >= 20 and g.get_cell(int(ce[0]), int(ce[1])) == Grid.EXIT


static func _a4(g: Grid) -> bool:
	var any: bool = false
	for d: Dictionary in g.doors():
		any = true
		if not DungeonGen.door_shape_ok(g, int(d["cell_x"]), int(d["cell_z"])):
			return false
	return any


## Pose em frente à primeira porta da sala 0 e trilha: 30 frente, 10 ré, use, 60 frente.
static func a6_setup(g: Grid) -> Dictionary:
	var room: Dictionary = g.rooms[0]
	var doors: Array = DungeonGen._room_doors(g, room)
	if doors.is_empty():
		return {}
	var dc: Array = doors[0]
	var dx: int = int(dc[0])
	var dz: int = int(dc[1])
	var angles: Dictionary = {"1,0": 0, "0,1": 1024, "-1,0": 2048, "0,-1": 3072}
	for d: Array in DungeonGen.DIRS:
		var rx: int = dx - int(d[0])
		var rz: int = dz - int(d[1])
		if DungeonGen.in_room(room, rx, rz):
			var inputs: Array = GateTraces.repeat(30, IntInput.new(1, 0, 0)) \
				+ GateTraces.repeat(10, IntInput.new(-1, 0, 0)) \
				+ [IntInput.new(0, 0, 0, false, false, true)] \
				+ GateTraces.repeat(60, IntInput.new(1, 0, 0))
			return {
				"door": [dx, dz], "dir": [int(d[0]), int(d[1])],
				"header": {"seed": 1, "pos_x": rx * Grid.CELL + Grid.CELL / 2,
					"pos_z": rz * Grid.CELL + Grid.CELL / 2, "angle": angles["%d,%d" % [d[0], d[1]]]},
				"inputs": inputs,
			}
	return {}


static func _box_hits_cell(p: PlayerSim, cx: int, cz: int) -> bool:
	var x0: int = p.pos_x - PlayerSim.PLAYER_HALF
	var x1: int = p.pos_x + PlayerSim.PLAYER_HALF
	var z0: int = p.pos_z - PlayerSim.PLAYER_HALF
	var z1: int = p.pos_z + PlayerSim.PLAYER_HALF
	return x0 < (cx + 1) * Grid.CELL and cx * Grid.CELL < x1 and z0 < (cz + 1) * Grid.CELL and cz * Grid.CELL < z1


static func _a6(r: GateReport, record: bool) -> void:
	var sim: WorldSim = WorldSim.new(1, false, false)
	var setup: Dictionary = a6_setup(sim.grid)
	if setup.is_empty():
		r.check("M2-A6", false, "sala 0 sem porta")
		return
	var header: Dictionary = setup["header"]
	var inputs: Array = setup["inputs"]
	if record:
		TraceIO.write(ProjectSettings.globalize_path(GateTraces.DIR + A6_TRACE), inputs, header)
	var tr: Variant = GateTraces.load_trace(A6_TRACE)
	var trace_ok: bool = tr != null and GateTraces.same_inputs(tr["inputs"], inputs) and tr["header"] == header
	r.check("M2-A6-trace", trace_ok, "trilha %s confere com a geração programática" % A6_TRACE)
	if not trace_ok:
		return
	inputs = tr["inputs"]
	sim.set_player_pose(int(header["pos_x"]), int(header["pos_z"]), int(header["angle"]))
	var door: Array = setup["door"]
	var dir: Array = setup["dir"]
	var dx: int = int(door[0])
	var dz: int = int(door[1])
	var blocked_ok: bool = true
	for i: int in range(30):
		sim.step(inputs[i])
		if _box_hits_cell(sim.player, dx, dz):
			blocked_ok = false
	blocked_ok = blocked_ok and sim.grid.get_cell(dx, dz) == Grid.DOOR_CLOSED
	r.check("M2-A6-blocked", blocked_ok, "porta (%d,%d) fechada bloqueia após 30 ticks, pos=(%d,%d)" % [
		dx, dz, sim.player.pos_x, sim.player.pos_z])
	for i: int in range(30, inputs.size()):
		sim.step(inputs[i])
	var p: PlayerSim = sim.player
	var crossed: bool = false
	var dxi: int = int(dir[0])
	var dzi: int = int(dir[1])
	if dxi > 0:
		crossed = p.pos_x - PlayerSim.PLAYER_HALF >= (dx + 1) * Grid.CELL
	elif dxi < 0:
		crossed = p.pos_x + PlayerSim.PLAYER_HALF <= dx * Grid.CELL
	elif dzi > 0:
		crossed = p.pos_z - PlayerSim.PLAYER_HALF >= (dz + 1) * Grid.CELL
	else:
		crossed = p.pos_z + PlayerSim.PLAYER_HALF <= dz * Grid.CELL
	r.check("M2-A6", sim.grid.get_cell(dx, dz) == Grid.DOOR_OPEN and crossed,
		"porta aberta e atravessada, pos final=(%d,%d)" % [p.pos_x, p.pos_z])


static func _invariant_seed7(r: GateReport) -> void:
	var sim: WorldSim = WorldSim.new(7, false, false)
	var inputs: Array = GateTraces.random_inputs(7, 600, true)
	var bad: int = -1
	for inp: IntInput in inputs:
		sim.step(inp)
		if sim.player.box_hits(sim.grid):
			bad = sim.tick
			break
	r.check("M2-INV", bad < 0, "600 ticks aleatórios na semente 7, tick violado=%d" % bad)
