extends RefCounted
## Gate M2 (sementes 1 a 100): M2-A1..A6, X1 e Preservation Gate (X2 = M1-A1..A6).

const Grid = preload("res://sim/grid.gd")
const DungeonGen = preload("res://sim/dungeon_gen.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const TraceIO = preload("res://input/trace_io.gd")
const GateM1 = preload("res://tests/gates/gate_m1.gd")
const Report = preload("res://tests/gates/gate_report.gd")

const SEED_FROM: int = 1
const SEED_TO: int = 100
const DOOR_TRACE: String = "res://tests/traces/m2_a6_door.jsonl"


static func run(r: Report) -> void:
	var grids: Array = []
	var shas: Array = []
	var repeat_ok: bool = true
	var bad_repeat: Array = []
	for s in range(SEED_FROM, SEED_TO + 1):
		var g: Grid = DungeonGen.new().generate(s)
		var g2: Grid = DungeonGen.new().generate(s)
		grids.append(g)
		shas.append(g.sha256())
		if g.sha256() != g2.sha256():
			repeat_ok = false
			bad_repeat.append(s)
	_a1(r, grids)
	_a2(r, grids)
	_a3(r, grids)
	_a4(r, grids)
	_a5(r, shas, repeat_ok, bad_repeat)
	_a6(r)
	_x1(r)
	_x2(r)


static func _a1(r: Report, grids: Array) -> void:
	var bad: Array = []
	for i in range(grids.size()):
		var g: Grid = grids[i]
		var rooms: Array = g.rooms
		var ok: bool = rooms.size() >= 6 and rooms.size() <= 9
		for a in range(rooms.size()):
			var ra: Dictionary = rooms[a]
			for b in range(a + 1, rooms.size()):
				var rb: Dictionary = rooms[b]
				# margem >= 2: retângulos expandidos em 2 não se intersectam
				if int(ra.x) - 2 < int(rb.x) + int(rb.w) and int(rb.x) < int(ra.x) + int(ra.w) + 2 \
						and int(ra.z) - 2 < int(rb.z) + int(rb.h) and int(rb.z) < int(ra.z) + int(ra.h) + 2:
					ok = false
			for cz in range(int(ra.z), int(ra.z) + int(ra.h)):
				for cx in range(int(ra.x), int(ra.x) + int(ra.w)):
					if g.get_room_id(cx, cz) != a or g.get_cell(cx, cz) == Grid.SOLID:
						ok = false
		if not ok:
			bad.append(SEED_FROM + i)
	r.check("M2-A1", bad.is_empty(), "sementes com falha: %s" % str(bad))


static func _a2(r: Report, grids: Array) -> void:
	var bad: Array = []
	for i in range(grids.size()):
		var g: Grid = grids[i]
		var r0: Dictionary = g.rooms[0]
		var dist: PackedInt32Array = DungeonGen.bfs(g, r0.cx, r0.cz)
		for c in range(Grid.GRID_W * Grid.GRID_H):
			if g.cells[c] != Grid.SOLID and dist[c] < 0:
				bad.append(SEED_FROM + i)
				break
	r.check("M2-A2", bad.is_empty(), "sementes com célula inalcançável: %s" % str(bad))


static func _a3(r: Report, grids: Array) -> void:
	var bad: Array = []
	var min_d: int = 1 << 30
	for i in range(grids.size()):
		var g: Grid = grids[i]
		var r0: Dictionary = g.rooms[0]
		var ok: bool = g.exit_room > 0 and g.exit_room < g.rooms.size()
		if ok:
			var er: Dictionary = g.rooms[g.exit_room]
			var dist: PackedInt32Array = DungeonGen.bfs(g, r0.cx, r0.cz)
			var d: int = dist[Grid.index_of(er.cx, er.cz)]
			min_d = mini(min_d, d)
			ok = d >= 20 and g.get_cell(er.cx, er.cz) == Grid.EXIT
		if not ok:
			bad.append(SEED_FROM + i)
	r.check("M2-A3", bad.is_empty(), "distância mínima=%d; falhas: %s" % [min_d, str(bad)])


static func _a4(r: Report, grids: Array) -> void:
	var bad: Array = []
	var n_doors: int = 0
	for i in range(grids.size()):
		var g: Grid = grids[i]
		for d: Dictionary in g.doors():
			n_doors += 1
			if not DungeonGen.door_pattern_ok(g, d.cx, d.cz):
				bad.append("%d:(%d,%d)" % [SEED_FROM + i, d.cx, d.cz])
	r.check("M2-A4", bad.is_empty() and n_doors > 0, "%d portas; falhas: %s" % [n_doors, str(bad)])


static func _a5(r: Report, shas: Array, repeat_ok: bool, bad_repeat: Array) -> void:
	var consecutive: int = 0
	for i in range(shas.size() - 1):
		if shas[i] != shas[i + 1]:
			consecutive += 1
	var all_pairs: int = 0
	var total_pairs: int = 0
	for i in range(shas.size()):
		for j in range(i + 1, shas.size()):
			total_pairs += 1
			if shas[i] != shas[j]:
				all_pairs += 1
	r.check("M2-A5", repeat_ok and consecutive >= 99,
		"repetição=%s %s; pares consecutivos distintos=%d/99; todos os pares distintos=%d/%d" % [
			repeat_ok, str(bad_repeat), consecutive, all_pairs, total_pairs])


static func _a6(r: Report) -> void:
	var trace: Array = TraceIO.read_trace(DOOR_TRACE)
	var w: WorldSim = WorldSim.new()
	w.setup_test("door")
	var blocked_ok: bool = false
	var opened_ok: bool = false
	var crossed_ok: bool = false
	var t: int = 0
	var bx: int = 0
	var bv: int = 0
	for inp: IntInput in trace:
		w.step(inp)
		t += 1
		if t == 90:
			bx = w.player.pos_x
			bv = w.player.vel_x
			blocked_ok = bx == 16000 and bv == 0 and w.grid.get_cell(8, 4) == Grid.DOOR_CLOSED
		elif t == 91:
			opened_ok = w.grid.get_cell(8, 4) == Grid.DOOR_OPEN
	crossed_ok = Grid.cell_of(w.player.pos_x) >= 10
	if w.hash_error:
		r.runtime_error = true
	r.check("M2-A6", trace.size() == 241 and blocked_ok and opened_ok and crossed_ok,
		"ticks=%d bloqueio pos_x=%d vel_x=%d; porta aberta=%s; final pos_x=%d célula=%d" % [
			trace.size(), bx, bv, opened_ok, w.player.pos_x, Grid.cell_of(w.player.pos_x)])


static func _x1(r: Report) -> void:
	# de costas para a porta (angle = 2048): não abre
	var w: WorldSim = WorldSim.new()
	w.setup_test("door")
	for _t in range(90):
		w.step(IntInput.new(1, 0, 0))
	w.player.angle = 2048
	w.step(IntInput.new(0, 0, 0, true))
	var back_ok: bool = w.grid.get_cell(8, 4) == Grid.DOOR_CLOSED
	# DOOR_LOCKED de frente: nada muda
	var w2: WorldSim = WorldSim.new()
	w2.setup_test("door")
	w2.grid.set_cell(8, 4, Grid.DOOR_LOCKED)
	for _t in range(90):
		w2.step(IntInput.new(1, 0, 0))
	var sha_before: String = w2.grid.sha256()
	w2.step(IntInput.new(0, 0, 0, true))
	var locked_ok: bool = w2.grid.get_cell(8, 4) == Grid.DOOR_LOCKED and w2.grid.sha256() == sha_before \
		and w2.player.pos_x == 16000
	r.check("M2-X1", back_ok and locked_ok, "de costas fechada=%s; trancada inalterada=%s" % [back_ok, locked_ok])


static func _x2(r: Report) -> void:
	var sub: Report = Report.new()
	print("[GATE] M2-X2 reexecutando M1-A1..A6 (Preservation Gate)")
	GateM1._a1(sub)
	GateM1._a2(sub)
	GateM1._a3(sub)
	GateM1._a4(sub)
	GateM1._a5(sub)
	GateM1._a6(sub)
	if sub.runtime_error:
		r.runtime_error = true
	r.check("M2-X2", sub.all_passed() and sub.n_total == 6, "%d/%d" % [sub.n_pass, sub.n_total])
