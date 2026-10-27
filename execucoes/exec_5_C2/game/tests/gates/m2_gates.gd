class_name M2Gates
extends RefCounted
## Acceptance Gate de M2 (plano §6.3), sementes 1..100, mais testes auxiliares de portas.

const DOOR_TRACE: String = "res://tests/traces/m2_door.jsonl"


static func run() -> Array:
	var out: Array = []
	var dungeons: Dictionary = {}
	for s in range(1, 102):
		dungeons[s] = DungeonGen.generate(s)
	out.append(_a1(dungeons))
	out.append(_a2(dungeons))
	out.append(_a3(dungeons))
	out.append(_a4(dungeons))
	out.append(_a5(dungeons))
	out.append(_a6())
	out.append_array(_aux())
	return out


static func _a1(ds: Dictionary) -> Dictionary:
	for s in range(1, 101):
		var d: DungeonGen.Dungeon = ds[s]
		if not d.valid:
			return GateUtil.res("M2-A1", false, "semente %d: geração inválida" % s)
		for e: String in DungeonGen.validation_errors(d):
			if e.begins_with("A1"):
				return GateUtil.res("M2-A1", false, "semente %d: %s" % [s, e])
	return GateUtil.res("M2-A1", true, "100 sementes com 6..9 salas sem sobreposição")


static func _a2(ds: Dictionary) -> Dictionary:
	for s in range(1, 101):
		var d: DungeonGen.Dungeon = ds[s]
		var c: Array = DungeonGen.room_center(d.rooms[0])
		var dist: PackedInt32Array = DungeonGen.bfs(d.grid, c[0], c[1])
		for idx in range(Grid.W * Grid.H):
			if d.grid.cells[idx] != Grid.SOLID and dist[idx] < 0:
				return GateUtil.res("M2-A2", false, "semente %d: célula %d inalcançável" % [s, idx])
	return GateUtil.res("M2-A2", true, "todas as células não-SOLID alcançáveis")


static func _a3(ds: Dictionary) -> Dictionary:
	var min_d: int = 1 << 30
	for s in range(1, 101):
		var d: DungeonGen.Dungeon = ds[s]
		if d.exit_room == 0:
			return GateUtil.res("M2-A3", false, "semente %d: saída == sala inicial" % s)
		var c: Array = DungeonGen.room_center(d.rooms[0])
		var ce: Array = DungeonGen.room_center(d.rooms[d.exit_room])
		var dist: PackedInt32Array = DungeonGen.bfs(d.grid, c[0], c[1])
		var dd: int = dist[ce[1] * Grid.W + ce[0]]
		min_d = mini(min_d, dd)
		if dd < 20:
			return GateUtil.res("M2-A3", false, "semente %d: distância %d" % [s, dd])
	return GateUtil.res("M2-A3", true, "distância mínima %d" % min_d)


static func _a4(ds: Dictionary) -> Dictionary:
	var total: int = 0
	for s in range(1, 101):
		var d: DungeonGen.Dungeon = ds[s]
		for dr: Dictionary in d.doors:
			total += 1
			if not DungeonGen.door_pattern_ok(d.grid, dr["cx"], dr["cz"]):
				return GateUtil.res("M2-A4", false, "semente %d: porta (%d,%d)" % [s, dr["cx"], dr["cz"]])
	return GateUtil.res("M2-A4", total > 0, "%d portas válidas" % total)


static func _a5(ds: Dictionary) -> Dictionary:
	for s in range(1, 101):
		var again: DungeonGen.Dungeon = DungeonGen.generate(s)
		if again.grid.sha256() != (ds[s] as DungeonGen.Dungeon).grid.sha256():
			return GateUtil.res("M2-A5", false, "semente %d não reproduz" % s)
	var differ: int = 0
	for s in range(1, 101):
		if (ds[s] as DungeonGen.Dungeon).grid.sha256() != (ds[s + 1] as DungeonGen.Dungeon).grid.sha256():
			differ += 1
	return GateUtil.res("M2-A5", differ >= 99, "reprodutível; %d/100 pares diferem" % differ)


static func _a6() -> Dictionary:
	var tr: Dictionary = TraceIO.read(DOOR_TRACE)
	if tr["error"] != "":
		return GateUtil.res("M2-A6", false, tr["error"])
	var ins: Array = tr["inputs"]
	if ins.size() != 261:
		return GateUtil.res("M2-A6", false, "trilha com %d ticks" % ins.size())
	var w := WorldSim.create(1, true)
	var bad: int = GateUtil.run_checked(w, ins.slice(0, 200))
	var a_ok: bool = w.player.pos_x == 30336 and w.player.vel_x == 0
	var a_txt: String = "(a) pos_x=%d vel_x=%d" % [w.player.pos_x, w.player.vel_x]
	var b2: int = GateUtil.run_checked(w, ins.slice(200, 201))
	var b_ok: bool = w.get_cell(15, 7) == Grid.DOOR_OPEN
	var c3: int = GateUtil.run_checked(w, ins.slice(201, 261))
	var c_ok: bool = w.player.pos_x > 32768 + 384
	var inv: bool = bad < 0 and b2 < 0 and c3 < 0
	var ok: bool = a_ok and b_ok and c_ok and inv
	return GateUtil.res("M2-A6", ok, "%s (b) porta=%d (c) pos_x=%d invariante=%s" % [a_txt, w.get_cell(15, 7), w.player.pos_x, inv])


static func _aux() -> Array:
	var out: Array = []
	# de costas para a porta (angle = 2048): não abre
	var w := WorldSim.create(1, true)
	GateUtil.run(w, GateUtil.repeat(200, 1, 0, 0))
	GateUtil.run(w, GateUtil.repeat(32, 0, 0, 64))   # 32 * 64 = 2048
	var ang: int = w.player.angle
	w.step(IntInput.make(0, 0, 0, true))
	out.append(GateUtil.res("AUX-DOOR-BACK", ang == 2048 and w.get_cell(15, 7) == Grid.DOOR_CLOSED, "angle=%d porta=%d" % [ang, w.get_cell(15, 7)]))
	# a 2 células de distância: não abre
	var w2 := WorldSim.create(1, true)
	GateUtil.run(w2, GateUtil.repeat(200, 1, 0, 0))
	GateUtil.run(w2, GateUtil.repeat(60, -1, 0, 0))
	var pcx: int = w2.player.cell_x()
	w2.step(IntInput.make(0, 0, 0, true))
	out.append(GateUtil.res("AUX-DOOR-FAR", pcx <= 13 and w2.get_cell(15, 7) == Grid.DOOR_CLOSED, "célula=%d porta=%d" % [pcx, w2.get_cell(15, 7)]))
	# trancada: não abre
	var w3 := WorldSim.create(1, true)
	w3.dungeon.grid.set_cell(15, 7, Grid.DOOR_LOCKED)
	GateUtil.run(w3, GateUtil.repeat(200, 1, 0, 0))
	w3.step(IntInput.make(0, 0, 0, true))
	var lk: bool = w3.get_cell(15, 7) == Grid.DOOR_LOCKED and w3.player.pos_x == 30336
	out.append(GateUtil.res("AUX-DOOR-LOCKED", lk, "porta=%d pos_x=%d" % [w3.get_cell(15, 7), w3.player.pos_x]))
	return out
