extends RefCounted
## Acceptance Gate de M4 (plano da rodada 2, §8.2): M4-A1 a M4-A7 e Spawn.
## M4-A7 instancia view/main.tscn: precisa de uma SceneTree já rodando
## (chamar a partir de _process, não de _initialize).

const GateM1 = preload("res://tests/gates/gate_m1.gd")
const TRACES: String = "res://tests/traces/"
const MAIN_SCENE: String = "res://view/main.tscn"


static func run(results: Array[Dictionary]) -> void:
	_a1(results)
	_a2(results)
	_a3(results)
	_a4(results)
	_a5(results)
	_a6(results)
	_a7(results)
	_spawn(results)


static func _center(cx: int, cz: int) -> Array[int]:
	return [cx * Grid.CELL + 1024, cz * Grid.CELL + 1024]


static func _place_player(w: WorldSim, cx: int, cz: int) -> void:
	var c: Array[int] = _center(cx, cz)
	w.player.pos_x = c[0]
	w.player.pos_z = c[1]


static func _wake(e: EnemySim) -> void:
	e.awake = true
	e.state = EnemySim.CHASE
	e.state_ticks = 0


static func _attack_input() -> IntInput:
	var i: IntInput = IntInput.new()
	i.attack = true
	return i


static func _a1(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "test")
	_place_player(w, 9, 10)
	var c: Array[int] = _center(12, 10)
	w.add_enemy(EnemySim.SKELETON, c[0], c[1])
	for k in range(300):
		w.step(IntInput.new())
	var blind_ok: bool = w.enemies[0].state == EnemySim.IDLE and not w.enemies[0].awake
	var ctl: WorldSim = WorldSim.create(1, "test")
	_place_player(ctl, 9, 8)
	c = _center(12, 8)
	ctl.add_enemy(EnemySim.SKELETON, c[0], c[1])
	ctl.step(IntInput.new())
	var ctl_ok: bool = ctl.enemies[0].awake and ctl.enemies[0].state != EnemySim.IDLE
	GateM1.check(results, "M4-A1", blind_ok and ctl_ok, "sem visão: IDLE no tick 300; controle: CHASE no tick 1",
		"sem visão: state=%d awake=%s; controle: state=%d" % [w.enemies[0].state, w.enemies[0].awake, ctl.enemies[0].state])


static func _isolate(w: WorldSim, keep: int) -> void:
	for e in w.enemies:
		if e.id == keep:
			_wake(e)
		else:
			e.state = EnemySim.DEAD


static func _room_of(d: DungeonGen, e: EnemySim) -> Dictionary:
	for r: Dictionary in d.rooms:
		if e.cell_x() >= r.x and e.cell_x() < r.x + r.w and e.cell_z() >= r.z and e.cell_z() < r.z + r.h:
			return r
	return {}


## Roda até o inimigo sair de CHASE (WINDUP ou além); devolve o tick ou -1.
static func _ticks_to_windup(w: WorldSim, id: int, limit: int) -> int:
	for k in range(limit):
		w.step(IntInput.new())
		var s: int = w.enemies[id].state
		if s == EnemySim.WINDUP or s == EnemySim.STRIKE or s == EnemySim.COOLDOWN:
			return w.tick
	return -1


static func _a2(results: Array[Dictionary]) -> void:
	var bad: String = ""
	var cases_a: int = 0
	var cases_b: int = 0
	var excluded: int = 0
	for s in range(1, 21):
		var probe: WorldSim = WorldSim.create(s, "dungeon")
		for i in range(probe.enemies.size()):
			# (a) jogador no canto da sala do próprio inimigo
			var w: WorldSim = WorldSim.create(s, "dungeon")
			var r: Dictionary = _room_of(w.dungeon, w.enemies[i])
			if r.is_empty():
				bad = "semente %d: inimigo %d fora de sala" % [s, i]
				break
			_place_player(w, r.x, r.z)
			_isolate(w, i)
			cases_a += 1
			if _ticks_to_windup(w, i, 1200) < 0:
				bad = "(a) semente %d: inimigo %d não chegou ao WINDUP" % [s, i]
				break
			# (b) portas abertas, jogador no start_pos
			var e0: EnemySim = probe.enemies[i]
			if e0.type != EnemySim.RAT and e0.type != EnemySim.SKELETON:
				continue
			var wb: WorldSim = WorldSim.create(s, "dungeon")
			for door: Dictionary in wb.dungeon.doors:
				wb.grid.set_cell(door.cx, door.cz, Grid.DOOR_OPEN)
			var dist: PackedInt32Array = EnemySim.flow_field(wb.grid, wb.player.cell_x(), wb.player.cell_z())
			var l: int = dist[e0.cell_z() * Grid.SIZE + e0.cell_x()]
			if l < 0 or l * Grid.CELL > 1000 * EnemySim.SPEED[e0.type]:
				excluded += 1
				continue
			_isolate(wb, i)
			cases_b += 1
			if _ticks_to_windup(wb, i, 1200) < 0:
				bad = "(b) semente %d: inimigo %d (L=%d) não chegou ao WINDUP" % [s, i, l]
				break
		if bad != "":
			break
	print("M4-A2: casos (a)=%d, (b)=%d, (b) excluídos pelo filtro=%d" % [cases_a, cases_b, excluded])
	GateM1.check(results, "M4-A2", bad == "" and cases_b > 0, "todo inimigo isolado entra em WINDUP em <= 1200 ticks", bad)


static func _rat_test_world() -> WorldSim:
	var w: WorldSim = WorldSim.create(1, "test")
	w.add_enemy(EnemySim.RAT, 6020, 15360)
	_wake(w.enemies[0])
	return w


static func _a3(results: Array[Dictionary]) -> void:
	var trace: Array[IntInput] = TraceIO.load_trace(TRACES + "m4_rat_backstep.jsonl")
	var w: WorldSim = _rat_test_world()
	var windup1: bool = false
	var x9: int = -1
	var strike9: bool = false
	var hp9: int = -1
	for inp in trace:
		w.step(inp)
		if w.tick == 1:
			windup1 = w.enemies[0].state == EnemySim.WINDUP
		if w.tick == 9:
			x9 = w.player.pos_x
			strike9 = w.enemies[0].state == EnemySim.STRIKE
			hp9 = w.player.hp
	var ctl: WorldSim = _rat_test_world()
	for k in range(49):
		ctl.step(IntInput.new())
		if ctl.tick == 9:
			break
	var ok: bool = trace.size() == 49 and windup1 and strike9 and x9 == 4640 and hp9 == 100 and ctl.player.hp == 95
	GateM1.check(results, "M4-A3", ok, "WINDUP no tick 1, STRIKE no 9 com pos_x 4640 e hp 100; controle hp 95",
		"WINDUP1=%s STRIKE9=%s pos_x9=%d hp9=%d; controle hp %d" % [windup1, strike9, x9, hp9, ctl.player.hp])


static func _a4(results: Array[Dictionary]) -> void:
	var w: WorldSim = _rat_test_world()
	var drops: Array[int] = []
	var sizes_ok: bool = true
	var prev: int = w.player.hp
	for k in range(200):
		w.step(IntInput.new())
		if w.player.hp != prev:
			drops.append(w.tick)
			if prev - w.player.hp != 5:
				sizes_ok = false
			prev = w.player.hp
	var ok: bool = str(drops) == str([9, 48, 87, 126, 165]) and sizes_ok and w.player.hp == 75
	GateM1.check(results, "M4-A4", ok, "quedas de 5 nos ticks [9, 48, 87, 126, 165], hp 75",
		"quedas %s (5 cada=%s), hp %d" % [str(drops), sizes_ok, w.player.hp])


static func _violation(w: WorldSim) -> String:
	if w.player.box_hits(w.grid):
		return "jogador em célula bloqueante"
	return w.entity_violation()


static func _a5(results: Array[Dictionary]) -> void:
	var bad: String = ""
	var trace: Array[IntInput] = TraceIO.load_trace(TRACES + "m4_arena_fight.jsonl")
	var arena: WorldSim = WorldSim.create(1, "arena")
	var blocked_hits: int = 0
	for inp in trace:
		var st: int = arena.player.stamina
		arena.step(inp)
		if arena.player.blocking and arena.player.stamina < st and arena.player.hp < 100:
			blocked_hits += 1
		var v: String = _violation(arena)
		if v != "":
			bad = "arena tick %d: %s" % [arena.tick, v]
			break
	if bad == "" and (trace.size() < 600 or arena.enemies[0].state != EnemySim.DEAD):
		bad = "arena: %d ticks, rato state=%d" % [trace.size(), arena.enemies[0].state]
	if bad == "" and blocked_hits == 0:
		bad = "arena: nenhum golpe bloqueado"
	for s in range(1, 6):
		if bad != "":
			break
		var w: WorldSim = WorldSim.create(s, "dungeon")
		for e in w.enemies:
			_wake(e)
		var rng: RngPcg32 = RngPcg32.create(1, RngPcg32.STREAM_PILOT)
		for k in range(600):
			var inp: IntInput = IntInput.new()
			inp.move = rng.next_range(3) - 1
			inp.strafe = rng.next_range(3) - 1
			inp.turn = rng.next_range(257) - 128
			w.step(inp)
			var v: String = _violation(w)
			if v != "":
				bad = "semente %d tick %d: %s" % [s, w.tick, v]
				break
	GateM1.check(results, "M4-A5", bad == "", "nenhum inimigo vivo em célula opaca, em outro inimigo ou no jogador", bad)


static func _a6(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "combat")
	w.enemies[0].hp = 25
	var dead7: bool = false
	for t in range(1, 128):
		var inp: IntInput = IntInput.new()
		inp.attack = t == 1
		if t >= 8:
			inp.move = 1
		w.step(inp)
		if t == 7:
			dead7 = w.enemies[0].state == EnemySim.DEAD and w.enemies[0].hp == 0
	var passed: bool = w.player.pos_x > 6349 + 384 + 384
	var r: WorldSim = WorldSim.create(1, "test")
	r.add_enemy(EnemySim.RAT, 6349, 15360)
	r.enemies[0].hp = 20
	_wake(r.enemies[0])
	var windup_tick: int = -1
	var windup_x: int = -1
	var rat_dead_tick: int = -1
	var hp_ok: bool = true
	for t in range(1, 61):
		r.step(_attack_input() if t == 1 else IntInput.new())
		var e: EnemySim = r.enemies[0]
		if windup_tick < 0 and e.state == EnemySim.WINDUP:
			windup_tick = t
			windup_x = e.pos_x
		if rat_dead_tick < 0 and e.state == EnemySim.DEAD:
			rat_dead_tick = t
		if r.player.hp != 100:
			hp_ok = false
	var ok: bool = dead7 and passed and windup_tick == 3 and windup_x == 6049 and rat_dead_tick == 7 and hp_ok
	GateM1.check(results, "M4-A6", ok,
		"boneco DEAD no tick 7 e jogador passa de 7117; rato WINDUP no tick 3 em 6049, DEAD no 7, hp 100",
		"boneco DEAD7=%s pos_x=%d; rato WINDUP tick %d em %d, DEAD tick %d, hp intacto=%s" % [dead7, w.player.pos_x, windup_tick, windup_x, rat_dead_tick, hp_ok])


static func _a7(results: Array[Dictionary]) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var sim: WorldSim = WorldSim.create(1, "dungeon")
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("attach_sim", sim)
	tree.root.add_child(main)
	var nodes: Array[Node] = tree.get_nodes_in_group("enemies")
	var all_ok: bool = nodes.size() == sim.enemies.size() and nodes.size() > 0
	for n in nodes:
		if not (n is Sprite3D) or (n as Sprite3D).billboard != BaseMaterial3D.BILLBOARD_FIXED_Y:
			all_ok = false
	var count: int = nodes.size()
	tree.root.remove_child(main)
	main.free()
	GateM1.check(results, "M4-A7", all_ok, "%d nós Sprite3D BILLBOARD_FIXED_Y" % sim.enemies.size(), "%d nós" % count)


static func _spawn(results: Array[Dictionary]) -> void:
	var bad: String = ""
	for s in range(1, 101):
		var w: WorldSim = WorldSim.create(s, "dungeon")
		var d: DungeonGen = w.dungeon
		if w.enemies.size() != d.rooms.size() - 1:
			bad = "semente %d: %d inimigos para %d salas" % [s, w.enemies.size(), d.rooms.size()]
			break
		var guardians: int = 0
		for e in w.enemies:
			var r: Dictionary = _room_of(d, e)
			if r.is_empty() or r.id == 0:
				bad = "semente %d: inimigo %d na sala inicial ou fora de sala" % [s, e.id]
				break
			if e.type == EnemySim.GUARDIAN:
				guardians += 1
				if r.id != d.exit_room:
					bad = "semente %d: guardião fora da sala da saída" % s
					break
		if bad != "":
			break
		if guardians != 1:
			bad = "semente %d: %d guardiões" % [s, guardians]
			break
		if w.grid.sha256() != DungeonGen.generate(s).grid.sha256():
			bad = "semente %d: grade mudou com o posicionamento" % s
			break
	GateM1.check(results, "Spawn", bad == "", "rooms-1 inimigos, 1 guardião na sala da saída, nenhum na sala 0, grade igual", bad)
