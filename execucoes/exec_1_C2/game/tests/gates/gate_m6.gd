extends RefCounted
## Acceptance Gate de M6 (plano da rodada 3, §9.3): M6-A1 a M6-A6 e M6-PRES.

const GateM1 = preload("res://tests/gates/gate_m1.gd")
const TRACES: String = "res://tests/traces/"
const SPAWN_R2: String = "res://tests/gates/m4_spawn_r2.json"
const SHA_R1: String = "res://tests/gates/m2_grid_sha_r1.json"


static func run(results: Array[Dictionary]) -> void:
	_a1(results)
	_pres(results)
	_a2(results)
	_a3(results)
	_a4(results)
	_a5(results)
	_a6(results)


static func _center(cx: int, cz: int) -> Array[int]:
	return [cx * Grid.CELL + 1024, cz * Grid.CELL + 1024]


static func _place(w: WorldSim, cx: int, cz: int) -> void:
	var c: Array[int] = _center(cx, cz)
	w.player.pos_x = c[0]
	w.player.pos_z = c[1]


static func _in_room(r: Dictionary, cx: int, cz: int) -> bool:
	return cx >= int(r.x) and cx < int(r.x) + int(r.w) and cz >= int(r.z) and cz < int(r.z) + int(r.h)


static func _a1(results: Array[Dictionary]) -> void:
	var bad: String = ""
	var fallbacks: int = 0
	for s in range(1, 101):
		var w: WorldSim = WorldSim.create(s, "dungeon")
		var d: DungeonGen = w.dungeon
		if w.key_fallback:
			fallbacks += 1
		var s_cx: int = d.start_pos[0] >> Grid.CELL_SHIFT
		var s_cz: int = d.start_pos[1] >> Grid.CELL_SHIFT
		var blocked: Grid = w.grid.duplicate_grid()
		for i in range(Grid.SIZE * Grid.SIZE):
			if blocked.cells[i] == Grid.DOOR_LOCKED:
				blocked.cells[i] = Grid.SOLID
		var reach: PackedInt32Array = DungeonGen.bfs(blocked, s_cx, s_cz)
		var keys: int = 0
		var in_start: Array[Dictionary] = []
		var cells: Dictionary = {}
		for it: Dictionary in w.items:
			var cx: int = it.cell_x
			var cz: int = it.cell_z
			var idx: int = cz * Grid.SIZE + cx
			if cells.has(idx):
				bad = "semente %d: dois itens em (%d, %d)" % [s, cx, cz]
			cells[idx] = true
			if w.grid.get_cell(cx, cz) == Grid.EXIT:
				bad = "semente %d: item %d no EXIT" % [s, it.id]
			for e in w.enemies:
				if e.cell_x() == cx and e.cell_z() == cz:
					bad = "semente %d: item %d na célula do inimigo %d" % [s, it.id, e.id]
			if _in_room(d.rooms[d.start_room], cx, cz):
				in_start.append(it)
			if int(it.type) == ItemsSim.KEY:
				keys += 1
				if _in_room(d.rooms[d.start_room], cx, cz) or _in_room(d.rooms[d.exit_room], cx, cz):
					bad = "semente %d: chave na sala inicial ou da saída" % s
				if reach[idx] < 0:
					bad = "semente %d: chave inalcançável sem porta trancada" % s
		if keys != 1:
			bad = "semente %d: %d chaves" % [s, keys]
		if in_start.size() != 1 or int(in_start[0].type) != ItemsSim.POTION_HP \
				or int(in_start[0].cell_x) != s_cx + 1 or int(in_start[0].cell_z) != s_cz:
			bad = "semente %d: sala inicial com itens %s" % [s, str(in_start)]
		if bad != "":
			break
	print("M6-A1: sementes que usaram o fallback da chave = %d" % fallbacks)
	GateM1.check(results, "M6-A1", bad == "", "1 chave alcançável fora das salas inicial/saída; só a poção 0 na sala inicial", bad)


static func _pres(results: Array[Dictionary]) -> void:
	var spawn: Variant = JSON.parse_string(FileAccess.get_file_as_string(SPAWN_R2))
	var shas: Variant = JSON.parse_string(FileAccess.get_file_as_string(SHA_R1))
	var bad: String = ""
	if typeof(spawn) != TYPE_DICTIONARY or typeof(shas) != TYPE_DICTIONARY:
		bad = "referências ausentes"
	for s in range(1, 101):
		if bad != "":
			break
		var w: WorldSim = WorldSim.create(s, "dungeon")
		var got: Array = []
		for e in w.enemies:
			got.append([e.type, e.pos_x, e.pos_z])
		var exp: Array = []
		for row: Array in spawn[str(s)]:
			exp.append([int(row[0]), int(row[1]), int(row[2])])
		if got != exp:
			bad = "semente %d: inimigos %s, esperado %s" % [s, str(got), str(exp)]
		elif w.grid.sha256() != str(shas[str(s)]):
			bad = "semente %d: grid_sha256 mudou" % s
	GateM1.check(results, "M6-PRES", bad == "", "inimigos = m4_spawn_r2.json e grade = m2_grid_sha_r1.json", bad)


static func _quaff(q: int) -> IntInput:
	var i: IntInput = IntInput.new()
	i.quaff = q
	return i


static func _a2(results: Array[Dictionary]) -> void:
	var a: WorldSim = WorldSim.create(1, "vault")
	a.player.hp = 50
	a.player.potion_hp = 1
	a.step(_quaff(1))
	var b: WorldSim = WorldSim.create(1, "vault")
	b.player.hp = 80
	b.player.potion_hp = 1
	b.step(_quaff(1))
	var c: WorldSim = WorldSim.create(1, "vault")
	var before: Dictionary = c.player.to_state_dict()
	c.step(_quaff(1))
	c.step(_quaff(2))
	var after: Dictionary = c.player.to_state_dict()
	var c_ok: bool = before.hp == after.hp and before.stamina == after.stamina and before.inventory == after.inventory
	var d: WorldSim = WorldSim.create(1, "vault")
	d.player.stamina = 10
	d.player.potion_sp = 1
	d.step(_quaff(2))
	var ok: bool = a.player.hp == 90 and a.player.potion_hp == 0 and b.player.hp == 100 and c_ok \
		and d.player.stamina == 60 and d.player.potion_sp == 0
	GateM1.check(results, "M6-A2", ok, "(a) hp 90, poção 0; (b) hp 100; (c) nada muda; (d) stamina 60",
		"(a) hp %d poção %d; (b) hp %d; (c) %s; (d) stamina %d" % [a.player.hp, a.player.potion_hp, b.player.hp, c_ok, d.player.stamina])


static func _use() -> IntInput:
	var i: IntInput = IntInput.new()
	i.use = true
	return i


static func _a3(results: Array[Dictionary]) -> void:
	# (a) coleta ao longo da linha 7
	var w: WorldSim = WorldSim.create(1, "vault")
	var key_tick: int = -1
	var first_8192: int = -1
	for inp in TraceIO.load_trace(TRACES + "m1_forward_120.jsonl"):
		w.step(inp)
		if first_8192 < 0 and w.player.pos_x >= 8192:
			first_8192 = w.tick
		if key_tick < 0 and w.items[0].taken:
			key_tick = w.tick
	var taken: Array[bool] = []
	for it: Dictionary in w.items:
		taken.append(bool(it.taken))
	var a_ok: bool = w.player.pos_x == 20644 and taken == [true, true, false, true] and w.player.has_key \
		and w.player.potion_hp == 1 and w.player.gold == 25 and key_tick == first_8192 and key_tick > 0
	# (b) porta trancada em (15, 4)
	var nb: WorldSim = WorldSim.create(1, "vault")
	_place(nb, 14, 4)
	nb.step(_use())
	var kb: WorldSim = WorldSim.create(1, "vault")
	_place(kb, 14, 4)
	kb.player.has_key = true
	kb.step(_use())
	var b_ok: bool = nb.grid.get_cell(15, 4) == Grid.DOOR_LOCKED and kb.grid.get_cell(15, 4) == Grid.DOOR_OPEN and kb.tick == 1
	# (c) saída em (19, 7)
	var c: WorldSim = WorldSim.create(1, "vault")
	_place(c, 19, 7)
	c.step(_use())
	var no_key: String = c.terminal
	c.player.has_key = true
	c.step(_use())
	var c_ok: bool = no_key == "NONE" and c.terminal == "ESCAPED" and c.terminal_tick == c.tick
	GateM1.check(results, "M6-A3", a_ok and b_ok and c_ok,
		"(a) pos_x 20644, itens [T,T,F,T], chave, poção 1, ouro 25, chave no 1º tick com pos_x>=8192; (b) trancada/aberta; (c) NONE e ESCAPED",
		"(a) pos_x %d itens %s chave %s poção %d ouro %d tick chave %d/%d; (b) %s; (c) %s/%s tick %d/%d" % [
			w.player.pos_x, str(taken), w.player.has_key, w.player.potion_hp, w.player.gold, key_tick, first_8192,
			b_ok, no_key, c.terminal, c.terminal_tick, c.tick])


static func _frozen_canon(w: WorldSim) -> String:
	var s: Dictionary = w.snapshot()
	s.erase("tick")
	return StateHash.canon(s)


static func _a4(results: Array[Dictionary]) -> void:
	# (a) morte e congelamento
	var a: WorldSim = WorldSim.create(1, "vault")
	a.inject_hit(5120 + 1500, 15360, 200)
	a.step(IntInput.new())
	var dead1: bool = a.player.hp == 0 and a.terminal == "DEAD" and a.terminal_tick == 1
	var ref: String = _frozen_canon(a)
	var frozen: bool = true
	var chain_moves: bool = true
	var rng: RngPcg32 = RngPcg32.create(1, RngPcg32.STREAM_PILOT)
	for k in range(100):
		var prev_chain: String = a.chain()
		var inp: IntInput = IntInput.new()
		inp.move = rng.next_range(3) - 1
		inp.strafe = rng.next_range(3) - 1
		inp.turn = rng.next_range(257) - 128
		a.step(inp)
		if _frozen_canon(a) != ref:
			frozen = false
		if a.chain() == prev_chain:
			chain_moves = false
	# (b) tempo esgotado
	var b: WorldSim = WorldSim.create(1, "vault")
	b.tick = WorldSim.K_MAX - 2
	b.step(IntInput.new())
	b.step(IntInput.new())
	var b_ok: bool = b.terminal == "TIMEOUT" and b.terminal_tick == 18000
	# (c) DEAD tem prioridade sobre ESCAPED
	var c: WorldSim = WorldSim.create(1, "vault")
	_place(c, 19, 7)
	c.player.has_key = true
	c.inject_hit(c.player.pos_x + 1500, c.player.pos_z, 200)
	c.step(_use())
	var ok: bool = dead1 and frozen and chain_moves and a.tick == 101 and b_ok and c.terminal == "DEAD"
	GateM1.check(results, "M6-A4", ok, "(a) DEAD no tick 1 e estado congelado por 100 ticks; (b) TIMEOUT em 18000; (c) DEAD",
		"(a) dead1=%s congelado=%s cadeia avança=%s; (b) %s/%d; (c) %s" % [dead1, frozen, chain_moves, b.terminal, b.terminal_tick, c.terminal])


## Montagem de M4-A6: rato acordado diante do jogador, golpe no tick 1.
static func _rat_world(xp: int, level: int, hp_max: int, sp_max: int) -> WorldSim:
	var w: WorldSim = WorldSim.create(1, "test")
	w.add_enemy(EnemySim.RAT, 6349, 15360)
	w.enemies[0].hp = 20
	w.enemies[0].awake = true
	w.enemies[0].state = EnemySim.CHASE
	w.player.xp = xp
	w.player.level = level
	w.player.hp_max = hp_max
	w.player.hp = hp_max
	w.player.stamina_max = sp_max
	w.player.stamina = sp_max
	return w


static func _swing7(w: WorldSim) -> void:
	for t in range(1, 8):
		var inp: IntInput = IntInput.new()
		inp.attack = t == 1
		w.step(inp)


static func _a5(results: Array[Dictionary]) -> void:
	var a: WorldSim = _rat_world(95, 1, 100, 100)
	_swing7(a)
	var p: PlayerSim = a.player
	var a_ok: bool = a.enemies[0].state == EnemySim.DEAD and p.xp == 105 and p.level == 2 \
		and p.hp_max == 120 and p.hp == 120 and p.stamina_max == 110
	var b: WorldSim = WorldSim.create(1, "combat")
	b.player.level = 2
	_swing7(b)
	var b_ok: bool = b.enemies[0].hp == 70
	var c: WorldSim = _rat_world(245, 2, 120, 110)
	_swing7(c)
	var c_ok: bool = c.player.level == 3 and c.player.hp_max == 140 and c.player.stamina_max == 120 and c.player.hp == 140
	var d: WorldSim = _rat_world(240, 1, 100, 100)
	_swing7(d)
	var d_ok: bool = d.player.level == 3 and d.player.hp_max == 140 and d.player.stamina_max == 120
	var e: WorldSim = _rat_world(300, 3, 100, 100)
	_swing7(e)
	var e_ok: bool = e.player.level == 3 and e.player.hp_max == 100
	GateM1.check(results, "M6-A5", a_ok and b_ok and c_ok and d_ok and e_ok,
		"(a) xp 105 nível 2 hp 120/120 vg_max 110; (b) boneco 70; (c) nível 3 140/120; (d) nível 3; (e) sem mudança",
		"(a) xp %d nível %d hp %d/%d vg_max %d; (b) boneco %d; (c) %s; (d) %s; (e) %s" % [
			p.xp, p.level, p.hp, p.hp_max, p.stamina_max, b.enemies[0].hp, c_ok, d_ok, e_ok])


static func _a6(results: Array[Dictionary]) -> void:
	var escaped: int = 0
	var failed: Array[String] = []
	var rng_ok: bool = true
	for s in range(1, 51):
		var w: WorldSim = WorldSim.create(s, "dungeon")
		var pilot: Pilot = Pilot.create(s)
		w.step(pilot.next_input(w))
		var rng1: String = w.snapshot().rng.dungeon_state
		while w.terminal == "NONE" and w.tick < WorldSim.K_MAX:
			w.step(pilot.next_input(w))
		if w.snapshot().rng.dungeon_state != rng1:
			rng_ok = false
		print("M6-A6: semente %d %s terminal_tick=%d nível=%d ouro=%d" % [s, w.terminal, w.terminal_tick, w.player.level, w.player.gold])
		if w.terminal == "ESCAPED":
			escaped += 1
		else:
			failed.append("%d:%s" % [s, w.terminal])
	print("M6-A6: ESCAPED %d de 50" % escaped)
	GateM1.check(results, "M6-A6", escaped >= 40 and rng_ok, ">= 40 de 50 ESCAPED e rng.dungeon_state constante",
		"%d de 50 (falhas %s), rng constante=%s" % [escaped, str(failed), rng_ok])
