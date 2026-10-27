extends RefCounted
## Gate M4 (inimigos): M4-A1..A6 e X1..X7 no núcleo; M4-A7 (cena em headless) em run_vis().
## Salvo indicação: setup_test("room"), jogador no spawn (7168, 15360), angle = 0, input zero.

const Grid = preload("res://sim/grid.gd")
const DungeonGen = preload("res://sim/dungeon_gen.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
const GateM3 = preload("res://tests/gates/gate_m3.gd")
const Report = preload("res://tests/gates/gate_report.gd")

const MAIN_SCENE: String = "res://view/main.tscn"
const A2_MAX_TICKS: int = 1200
## pixel_size esperado por tipo (plano §8.1).
const PIXEL_SIZE: Dictionary = {"rat": 0.03, "skeleton": 0.05, "guardian": 0.065, "dummy": 0.05}


static func new_world() -> WorldSim:
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	return w


static func _note_error(r: Report, w: WorldSim) -> void:
	if w.hash_error:
		r.runtime_error = true


static func _wake(e: Dictionary) -> void:
	e.awake = true
	e.state = "CHASE"
	e.state_ticks = 0


static func _open_all_doors(w: WorldSim) -> void:
	for d: Dictionary in w.grid.doors():
		w.grid.set_cell(d.cx, d.cz, Grid.DOOR_OPEN)


static func run(r: Report) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)
	_x1(r)
	_x2(r)
	_x3(r)
	_x4(r)
	_x5(r)
	_x6(r)
	_x7(r)


static func _a1(r: Report) -> void:
	var w: WorldSim = new_world()
	w.spawn_enemy("skeleton", Grid.cell_center(6), Grid.cell_center(7))
	for z in range(2, 14):
		w.grid.set_cell(5, z, Grid.SOLID)
	var ok: bool = true
	for _t in range(120):
		w.step(IntInput.new())
		if w.enemies[0].state != "IDLE" or w.enemies[0].awake:
			ok = false
	var c: WorldSim = new_world()
	c.spawn_enemy("skeleton", Grid.cell_center(6), Grid.cell_center(7))
	c.step(IntInput.new())
	var ctrl: bool = (c.enemies[0].state == "CHASE" or c.enemies[0].state == "WINDUP") and c.enemies[0].awake
	_note_error(r, w)
	_note_error(r, c)
	r.check("M4-A1", ok and ctrl, "com parede: IDLE em 120 ticks=%s; sem parede no tick 1: %s awake=%s" % [
		ok, c.enemies[0].state, c.enemies[0].awake])


## Centro da primeira célula (índice crescente) não sólida, fora de sala e 4-adjacente à sala rid.
static func _cell_next_to_room(g: Grid, rid: int) -> Array:
	for i in range(Grid.GRID_W * Grid.GRID_H):
		var cx: int = i % Grid.GRID_W
		var cz: int = i / Grid.GRID_W
		if g.cells[i] == Grid.SOLID or g.room_id[i] >= 0:
			continue
		for dv: Array in DungeonGen.DIRS:
			if g.get_room_id(cx + int(dv[0]), cz + int(dv[1])) == rid:
				return [cx, cz]
	return []


static func _a2(r: Report) -> void:
	var worst: int = 0
	var bad: Array = []
	var pairs: int = 0
	for s in range(1, 21):
		var probe: WorldSim = WorldSim.new()
		probe.setup_seed(s)
		var n: int = probe.grid.rooms.size()
		for rid in range(1, n):
			var w: WorldSim = WorldSim.new()
			w.setup_seed(s)
			var e: Dictionary = w.enemies[rid - 1]
			w.enemies = [e]
			_open_all_doors(w)
			_wake(e)
			var c: Array = _cell_next_to_room(w.grid, rid)
			w.player.pos_x = Grid.cell_center(c[0])
			w.player.pos_z = Grid.cell_center(c[1])
			var got: int = -1
			for t in range(1, A2_MAX_TICKS + 1):
				w.step(IntInput.new())
				if e.state == "WINDUP":
					got = t
					break
			pairs += 1
			_note_error(r, w)
			if got < 0:
				bad.append("%d/%d" % [s, rid])
			else:
				worst = maxi(worst, got)
	r.check("M4-A2", bad.is_empty(), "%d pares; máximo observado=%d ticks (limite %d); falhas: %s" % [
		pairs, worst, A2_MAX_TICKS, str(bad)])


static func _skeleton_front(w: WorldSim) -> Dictionary:
	w.spawn_enemy("skeleton", 8368, 15360)
	var e: Dictionary = w.enemies[0]
	_wake(e)
	return e


static func _a3(r: Report) -> void:
	var w: WorldSim = new_world()
	var e: Dictionary = _skeleton_front(w)
	var states: Array = []
	var hp_ok: bool = true
	for t in range(1, 20):
		w.step(IntInput.new())
		states.append(e.state)
		if t <= 18 and w.player.hp != 100:
			hp_ok = false
	var a_ok: bool = states[0] == "WINDUP" and states[18] == "STRIKE" and states[17] == "WINDUP" and hp_ok \
		and w.player.hp == 88
	var w2: WorldSim = new_world()
	var e2: Dictionary = _skeleton_front(w2)
	var st2: Array = []
	for t in range(1, 20):
		w2.step(IntInput.new(-1 if t <= 18 else 0, 0, 0))
		st2.append(e2.state)
	var b_ok: bool = st2[0] == "WINDUP" and st2[18] == "STRIKE" and w2.player.hp == 100
	_note_error(r, w)
	_note_error(r, w2)
	r.check("M4-A3", a_ok and b_ok, "(a) tick1=%s tick19=%s hp=%d; (b) tick19=%s hp=%d pos_x=%d" % [
		states[0], states[18], w.player.hp, st2[18], w2.player.hp, w2.player.pos_x])


static func _drops(w: WorldSim, ticks: int) -> Array:
	var out: Array = []
	var prev: int = w.player.hp
	for t in range(1, ticks + 1):
		w.step(IntInput.new())
		if w.player.hp < prev:
			out.append([t, prev - w.player.hp])
		prev = w.player.hp
	return out


static func _a4(r: Report) -> void:
	var w: WorldSim = new_world()
	_skeleton_front(w)
	var da: Array = _drops(w, 400)
	var ta: Array = []
	for d: Array in da:
		ta.append(d[0])
	var wb: WorldSim = new_world()
	wb.spawn_enemy("rat", 8068, 15360)
	_wake(wb.enemies[0])
	var db: Array = _drops(wb, 200)
	var tb: Array = []
	var fives: bool = true
	for d: Array in db:
		tb.append(d[0])
		fives = fives and int(d[1]) == 5
	var gap_ok: bool = true
	for i in range(1, ta.size()):
		gap_ok = gap_ok and int(ta[i]) - int(ta[i - 1]) >= 63
	for i in range(1, tb.size()):
		gap_ok = gap_ok and int(tb[i]) - int(tb[i - 1]) >= 38
	_note_error(r, w)
	_note_error(r, wb)
	r.check("M4-A4", ta == [19, 83, 147, 211, 275, 339] and w.player.hp == 28 and tb == [9, 48, 87, 126, 165] \
		and fives and gap_ok, "(a) quedas=%s hp=%d; (b) quedas=%s de 5=%s; intervalos>=windup+cooldown=%s" % [
			str(ta), w.player.hp, str(tb), fives, gap_ok])


## Invariantes de M4-A5 (e M1-A4) no estado atual; devolve "" se tudo vale.
static func invariant_violation(w: WorldSim) -> String:
	if w.player_box_hits_solid():
		return "jogador em célula bloqueante"
	var alive: Array = []
	for e: Dictionary in w.enemies:
		if e.state != "DEAD":
			alive.append(e)
	for e: Dictionary in alive:
		var x: int = e.pos_x
		var z: int = e.pos_z
		var h: int = e.half
		if w.grid.box_hits_solid(x - h, z - h, x + h, z + h):
			return "entidade %d em célula bloqueante" % int(e.id)
		if EnemySim.overlaps(x, z, h, w.player.pos_x, w.player.pos_z, PlayerSim.PLAYER_HALF):
			return "entidade %d sobre o jogador" % int(e.id)
	for i in range(alive.size()):
		for j in range(i + 1, alive.size()):
			var a: Dictionary = alive[i]
			var b: Dictionary = alive[j]
			if EnemySim.overlaps(a.pos_x, a.pos_z, a.half, b.pos_x, b.pos_z, b.half):
				return "entidades %d e %d sobrepostas" % [int(a.id), int(b.id)]
	return ""


static func _a5(r: Report) -> void:
	var bad: Array = []
	var trace: Array = GateM3.a7_trace(GateM3.A7_SEED_FROM)
	for s in range(1, 11):
		var w: WorldSim = WorldSim.new()
		w.setup_seed(s)
		for e: Dictionary in trace:
			w.step(e.inp)
			var v: String = invariant_violation(w)
			if v != "":
				bad.append("%d@%d: %s" % [s, w.tick, v])
				break
		_note_error(r, w)
	r.check("M4-A5", bad.is_empty(), "sementes 1..10, 600 ticks (trilha de M3-A7 sem golpes injetados); falhas: %s" % str(bad))


static func _a6(r: Report) -> void:
	var w: WorldSim = new_world()
	w.spawn_enemy("rat", 8068, 15360)
	var e: Dictionary = w.enemies[0]
	var dead_tick: int = -1
	var xp7: int = -1
	for t in range(1, 31):
		w.step(GateM3.atk() if t == 1 else IntInput.new())
		if dead_tick < 0 and e.state == "DEAD":
			dead_tick = t
		if t == 7:
			xp7 = w.player.xp
	var swing7: bool = dead_tick == 7
	for _t in range(60):
		w.step(IntInput.new(1, 0, 0))
	_note_error(r, w)
	r.check("M4-A6", swing7 and int(e.hp) == 0 and w.player.hp == 100 and xp7 == 10 and w.player.pos_x > 8068 + 640,
		"DEAD no tick %d hp=%d; jogador hp=%d xp(t7)=%d; pos_x final=%d" % [
			dead_tick, e.hp, w.player.hp, xp7, w.player.pos_x])


static func _x1(r: Report) -> void:
	var g: Grid = DungeonGen.test_room()
	var c: Callable = func(ax: int, az: int, bx: int, bz: int) -> bool:
		return EnemySim.los(g, Grid.cell_center(ax), Grid.cell_center(az), Grid.cell_center(bx), Grid.cell_center(bz))
	var open_ok: bool = c.call(3, 7, 10, 7)
	var corner_open: bool = c.call(3, 3, 5, 5)
	g.set_cell(6, 7, Grid.SOLID)
	var wall_ok: bool = not c.call(3, 7, 10, 7)
	g.set_cell(6, 7, Grid.FLOOR)
	g.set_cell(4, 3, Grid.SOLID)
	var corner_blocked: bool = not c.call(3, 3, 5, 5)
	r.check("M4-X1", open_ok and wall_ok and corner_blocked and corner_open,
		"livre=%s parede=%s canto bloqueado=%s canto livre=%s" % [open_ok, wall_ok, corner_blocked, corner_open])


static func _x2(r: Report) -> void:
	var g: Grid = DungeonGen.test_door_room()
	var closed: PackedInt32Array = EnemySim.flow_field(g, 12, 4)
	g.set_cell(8, 4, Grid.DOOR_OPEN)
	var f: PackedInt32Array = EnemySim.flow_field(g, 12, 4)
	var a: int = f[Grid.index_of(4, 4)]
	var b: int = f[Grid.index_of(8, 4)]
	var c: int = f[Grid.index_of(2, 2)]
	var d: int = closed[Grid.index_of(4, 4)]
	r.check("M4-X2", a == 8 and b == 4 and c == 12 and d == -1,
		"aberta: (4,4)=%d (8,4)=%d (2,2)=%d; fechada: (4,4)=%d" % [a, b, c, d])


static func _x3(r: Report) -> void:
	var bad: Array = []
	var worst: String = ""
	var worst_ratio: int = -1
	for s in range(1, 21):
		var w: WorldSim = WorldSim.new()
		w.setup_seed(s)
		_open_all_doors(w)
		var er: Dictionary = w.grid.rooms[w.grid.exit_room]
		# só o rato perseguidor (guardião e demais inimigos removidos, para medir a perseguição)
		w.enemies = []
		w.spawn_enemy("rat", Grid.cell_center(er.cx), Grid.cell_center(er.cz))
		var e: Dictionary = w.enemies[0]
		_wake(e)
		var dist: PackedInt32Array = DungeonGen.bfs(w.grid, er.cx, er.cz)
		var dd: int = dist[Grid.index_of(Grid.cell_of(w.player.pos_x), Grid.cell_of(w.player.pos_z))]
		var limit: int = (dd * 2048 * 5) / (4 * 100) + 120
		var got: int = -1
		for t in range(1, limit + 1):
			w.step(IntInput.new())
			if e.state == "WINDUP":
				got = t
				break
		_note_error(r, w)
		if got < 0:
			bad.append("%d(D=%d)" % [s, dd])
		elif got * 1000 / limit > worst_ratio:
			worst_ratio = got * 1000 / limit
			worst = "semente %d: %d/%d ticks (D=%d)" % [s, got, limit, dd]
	r.check("M4-X3", bad.is_empty(), "pior: %s; falhas: %s" % [worst, str(bad)])


static func _wakes(cx: int, cz: int) -> bool:
	var w: WorldSim = new_world()
	w.spawn_enemy("rat", Grid.cell_center(cx), Grid.cell_center(cz))
	w.step(IntInput.new())
	return w.enemies[0].awake


static func _x4(r: Report) -> void:
	var a: bool = _wakes(9, 7)
	var b: bool = _wakes(10, 7)
	var c: bool = _wakes(8, 10)
	var d: bool = _wakes(8, 11)
	r.check("M4-X4", a and not b and c and not d, "(9,7)=%s (10,7)=%s (8,10)=%s (8,11)=%s" % [a, b, c, d])


static func _x5(r: Report) -> void:
	var bad: Array = []
	for s in range(1, 101):
		var w: WorldSim = WorldSim.new()
		w.setup_seed(s)
		var g: Grid = w.grid
		var ok: bool = w.enemies.size() == g.rooms.size() - 1
		var guardians: int = 0
		for e: Dictionary in w.enemies:
			var rid: int = g.get_room_id(Grid.cell_of(e.pos_x), Grid.cell_of(e.pos_z))
			if rid == 0:
				ok = false
			if e.type == "guardian":
				guardians += 1
				ok = ok and rid == g.exit_room
			elif e.type != "rat" and e.type != "skeleton":
				ok = false
		ok = ok and guardians == 1 and invariant_violation(w) == ""
		if not ok:
			bad.append(s)
	r.check("M4-X5", bad.is_empty(), "sementes 1..100; falhas: %s" % str(bad))


static func _x6(r: Report) -> void:
	var w: WorldSim = new_world()
	w.spawn_dummy(9216, 15360)
	var ok: bool = true
	for _t in range(120):
		w.step(IntInput.new(1, 0, 0))
		if w.player.pos_x > 8448:
			ok = false
	_note_error(r, w)
	r.check("M4-X6", ok and w.player.pos_x >= 8448 - 149, "pos_x <= 8448 sempre=%s; final=%d" % [ok, w.player.pos_x])


static func _x7(r: Report) -> void:
	var trace: Array = GateM3.a7_trace(GateM3.A7_SEED_FROM)
	var bad: Array = []
	for s in range(1, 6):
		var w1: WorldSim = WorldSim.new()
		var w2: WorldSim = WorldSim.new()
		w1.setup_seed(s)
		w2.setup_seed(s)
		for e: Dictionary in trace:
			w1.step(e.inp)
		for e: Dictionary in trace:
			w2.step(e.inp)
		_note_error(r, w1)
		_note_error(r, w2)
		if w1.chain != w2.chain or w1.chain == "":
			bad.append(s)
	r.check("M4-X7", bad.is_empty(), "sementes 1..5, duas instâncias; divergências: %s" % str(bad))


## M4-A7: main.tscn em headless com a semente 1.
static func run_vis(r: Report, root: Window) -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set("start_override", "seed:1")
	main.set("driven_externally", true)
	root.add_child(main)
	var w: WorldSim = main.get("world")
	var ev: Node = main.get_node("EnemyView")
	var n_nodes: int = ev.get_child_count()
	var ok: bool = n_nodes == w.enemies.size() and w.enemies.size() == w.grid.rooms.size() - 1
	var bad: Array = []
	for c: Node in ev.get_children():
		var sp: Sprite3D = c as Sprite3D
		if sp == null or sp.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y:
			bad.append(c.name)
			continue
		var e: Dictionary = w.enemies[c.name.get_slice("_", 1).to_int()]
		if not is_equal_approx(sp.pixel_size, PIXEL_SIZE[e.type]) or sp.texture == null:
			bad.append(c.name)
	root.remove_child(main)
	main.free()
	r.check("M4-A7", ok and bad.is_empty(), "%d nós para %d entidades; fora do contrato: %s" % [
		n_nodes, w.enemies.size(), str(bad)])
