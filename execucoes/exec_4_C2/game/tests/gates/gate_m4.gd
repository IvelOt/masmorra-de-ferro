class_name GateM4
extends RefCounted
## M4-A1..A7 (plano da iteração 2 §5.2). M4-A7 roda dentro de GateRepro, com a cena.

const SEEDS: int = 20
const SPAWN_X: int = 9216
const SPAWN_Z: int = 15360


static func run(r: GateReport) -> void:
	_a1(r)
	_a1b(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)


static func center(c: int) -> int:
	return c * Grid.CELL + Grid.CELL / 2


static func _a1(r: GateReport) -> void:
	var sim: WorldSim = WorldSim.new(1, true)
	sim.set_player_pose(center(19), center(11), 0)
	var id: int = sim.add_enemy(EnemySim.SKELETON, center(22), center(11))
	var e: EnemySim.Enemy = sim.enemies[id]
	var asleep: bool = true
	for _i: int in range(120):
		sim.step(IntInput.new())
		if e.state != EnemySim.IDLE or e.awake:
			asleep = false
	var ctl: WorldSim = WorldSim.new(1, true)
	ctl.set_player_pose(center(19), center(11), 0)
	var cid: int = ctl.add_enemy(EnemySim.SKELETON, center(16), center(11))
	ctl.step(IntInput.new())
	var c: EnemySim.Enemy = ctl.enemies[cid]
	r.check("M4-A1", asleep and c.awake,
		"atrás do pilar a 3 células: IDLE e dormindo por 120 ticks=%s; controle a oeste acordou no tick 1=%s" % [asleep, c.awake])


static func _a1b(r: GateReport) -> void:
	var g: Grid = DungeonGen.test_room()
	var cases: Array = [
		["reta livre (16,11)->(19,11)", g, [16, 11], [19, 11], true],
		["através do pilar (22,11)->(19,11)", g, [22, 11], [19, 11], false],
		["quina exata do pilar (21,9)->(22,10)", g, [21, 9], [22, 10], false],
		["quina livre (22,9)->(23,10)", g, [22, 9], [23, 10], true],
		["mesma célula", g, [5, 5], [5, 5], true],
	]
	var dg: Grid = DungeonGen.new().generate(1)
	var setup: Dictionary = GateM2.a6_setup(dg)
	var door: Array = setup["door"]
	var dir: Array = setup["dir"]
	var dx: int = int(door[0])
	var dz: int = int(door[1])
	var before: Array = [dx - int(dir[0]), dz - int(dir[1])]
	var after: Array = [dx + int(dir[0]), dz + int(dir[1])]
	cases.append(["porta fechada semente 1 %s->%s" % [str(after), str(before)], dg, after, before, false])
	var opened: Grid = dg.duplicate_grid()
	opened.set_cell(dx, dz, Grid.DOOR_OPEN)
	cases.append(["mesma porta aberta", opened, after, before, true])
	var fails: Array = []
	for c: Array in cases:
		var a: Array = c[2]
		var b: Array = c[3]
		var got: bool = EnemySim.los(c[1], center(int(a[0])), center(int(a[1])), center(int(b[0])), center(int(b[1])))
		if got != bool(c[4]):
			fails.append(c[0])
	r.check("M4-A1b", fails.is_empty(), "%d casos de LOS; falhas=%s" % [cases.size(), str(fails)])


static func _open_all(sim: WorldSim) -> void:
	for cz: int in range(Grid.H):
		for cx: int in range(Grid.W):
			var t: int = sim.grid.get_cell(cx, cz)
			if t == Grid.DOOR_CLOSED or t == Grid.DOOR_LOCKED:
				sim.grid.set_cell(cx, cz, Grid.DOOR_OPEN)
	sim.invalidate_flow()


static func _a2(r: GateReport) -> void:
	var worst: Dictionary = {}
	var fails_a: Array = []
	var fails_b: Array = []
	var total: int = 0
	for s: int in range(1, SEEDS + 1):
		var n: int = WorldSim.new(s, false, true).enemies.size()
		for i: int in range(n):
			var sim: WorldSim = WorldSim.new(s, false, true)
			_open_all(sim)
			var e: EnemySim.Enemy = sim.enemies[i]
			sim.enemies = [e]
			e.awake = true
			e.state = EnemySim.CHASE
			e.state_ticks = 0
			var dist: PackedInt32Array = DungeonGen.bfs(sim.grid,
				EnemySim.cell_of(sim.player.pos_x), EnemySim.cell_of(sim.player.pos_z))
			var cells: int = dist[EnemySim.cell_of(e.pos_z) * Grid.W + EnemySim.cell_of(e.pos_x)]
			var spd: int = int(EnemySim.SPEED[e.type])
			var reached: int = -1
			for _k: int in range(6000):
				sim.step(IntInput.new())
				if e.state == EnemySim.WINDUP:
					reached = sim.tick
					break
			total += 1
			var key: String = String(EnemySim.NAMES[e.type])
			worst[key] = maxi(int(worst.get(key, 0)), reached if reached > 0 else 999999)
			if reached < 0:
				fails_b.append("s%d#%d" % [s, i])
			elif cells * Grid.CELL <= 1000 * spd and reached > 1200:
				fails_a.append("s%d#%d(%d células, %d ticks)" % [s, i, cells, reached])
	r.check("M4-A2", fails_a.is_empty() and fails_b.is_empty() and total > 0,
		"%d inimigos (um por vez, portas abertas); máximo de ticks até WINDUP por tipo=%s; falhas<=1200=%s; travados=%s. Interpretação: 1200 ticks onde fisicamente possível (bfs*2048/speed<=1000), vivacidade (<=6000) para todos" % [
			total, str(worst), str(fails_a), str(fails_b)])


## Sala de teste com um rato acordado 2 células à frente do spawn.
static func rat_world() -> WorldSim:
	var sim: WorldSim = WorldSim.new(1, true)
	var id: int = sim.add_enemy(EnemySim.RAT, 10240 + 1024, SPAWN_Z)
	var e: EnemySim.Enemy = sim.enemies[id]
	e.awake = true
	e.state = EnemySim.CHASE
	return sim


## Trilha de esquiva: neutro até o rato entrar em WINDUP, depois 12 ticks de ré.
static func dodge_inputs() -> Array:
	var sim: WorldSim = rat_world()
	var out: Array = []
	var e: EnemySim.Enemy = sim.enemies[0]
	while e.state != EnemySim.WINDUP and out.size() < 200:
		var inp: IntInput = IntInput.new()
		out.append(inp)
		sim.step(inp)
	return out + GateTraces.repeat(12, IntInput.new(-1, 0, 0))


static func _a3(r: GateReport) -> void:
	var a: WorldSim = rat_world()
	var ea: EnemySim.Enemy = a.enemies[0]
	var strike_a: int = -1
	var drop_tick: int = -1
	var drop: int = 0
	for _i: int in range(60):
		var hp0: int = a.player.hp
		a.step(IntInput.new())
		if a.player.hp != hp0 and drop_tick < 0:
			drop_tick = a.tick
			drop = hp0 - a.player.hp
		if ea.state == EnemySim.STRIKE and strike_a < 0:
			strike_a = a.tick
	r.check("M4-A3a", strike_a > 0 and drop_tick == strike_a and drop == 5,
		"parado: STRIKE no tick %d, dano %d no tick %d" % [strike_a, drop, drop_tick])
	var inputs: Array = GateTraces.load_inputs("m4_a3_dodge.jsonl")
	var trace_ok: bool = GateTraces.same_inputs(inputs, dodge_inputs())
	var b: WorldSim = rat_world()
	var eb: EnemySim.Enemy = b.enemies[0]
	var strike_b: int = -1
	for inp: IntInput in inputs:
		b.step(inp)
		if eb.state == EnemySim.STRIKE and strike_b < 0:
			strike_b = b.tick
	r.check("M4-A3b", trace_ok and strike_b > 0 and b.player.hp == PlayerSim.HP_MAX,
		"recuando no WINDUP: STRIKE no tick %d, hp=%d" % [strike_b, b.player.hp])


static func _a4(r: GateReport) -> void:
	var sim: WorldSim = WorldSim.new(1, true)
	var id: int = sim.add_enemy(EnemySim.RAT, SPAWN_X + PlayerSim.PLAYER_HALF + EnemySim.half_of(EnemySim.RAT), SPAWN_Z)
	var e: EnemySim.Enemy = sim.enemies[id]
	var strikes: Array = []
	for _i: int in range(600):
		sim.step(IntInput.new())
		if e.state == EnemySim.STRIKE:
			strikes.append(sim.tick)
	var gaps: Array = []
	var ok: bool = strikes.size() >= 2
	for i: int in range(1, strikes.size()):
		var g: int = int(strikes[i]) - int(strikes[i - 1])
		gaps.append(g)
		if g < 8 + 30 or g != 40:
			ok = false
	r.check("M4-A4", ok, "%d STRIKEs; intervalos=%s (mínimo 38, esperado 40)" % [strikes.size(), str(gaps)])


## Primeira violação de M4-A5 no tick corrente ("" se nenhuma). `before` = posições pré-step.
static func a5_violation(sim: WorldSim, before: Array) -> String:
	var alive: Array = []
	for e: EnemySim.Enemy in sim.enemies:
		if e.state != EnemySim.DEAD:
			alive.append(e)
	for e: EnemySim.Enemy in alive:
		var h: int = EnemySim.half_of(e.type)
		if sim.grid.box_hits_solid(e.pos_x - h, e.pos_z - h, e.pos_x + h, e.pos_z + h):
			return "inimigo %d em célula bloqueante" % e.id
		var moved: bool = before.is_empty() or int(before[e.id][0]) != e.pos_x or int(before[e.id][1]) != e.pos_z
		if moved and not before.is_empty() and Combat.boxes_overlap(e.pos_x, e.pos_z, h,
				sim.player.pos_x, sim.player.pos_z, PlayerSim.PLAYER_HALF):
			return "inimigo %d moveu-se para dentro do jogador" % e.id
	for i: int in range(alive.size()):
		for j: int in range(i + 1, alive.size()):
			var a: EnemySim.Enemy = alive[i]
			var b: EnemySim.Enemy = alive[j]
			if Combat.boxes_overlap(a.pos_x, a.pos_z, EnemySim.half_of(a.type), b.pos_x, b.pos_z, EnemySim.half_of(b.type)):
				return "inimigos %d e %d sobrepostos" % [a.id, b.id]
	return ""


static func positions(sim: WorldSim) -> Array:
	var out: Array = []
	for e: EnemySim.Enemy in sim.enemies:
		out.append([e.pos_x, e.pos_z])
	return out


static func _a5(r: GateReport) -> void:
	var plain: Array = _a5_pass(false)
	r.check("M4-A5", (plain[0] as Array).is_empty(),
		"sementes 1..%d, 1200 ticks aleatórios: %d acordaram, %d se moveram; falhas=%s" % [
			SEEDS, plain[1], plain[2], str(plain[0])])
	# Estresse (mesma trilha): portas abertas e todos acordados, para exercitar a colisão.
	var stress: Array = _a5_pass(true)
	r.check("M4-A5-stress", (stress[0] as Array).is_empty() and int(stress[2]) > 0,
		"mesma trilha com portas abertas e todos acordados: %d acordados, %d se moveram; falhas=%s" % [
			stress[1], stress[2], str(stress[0])])


## Devolve [falhas, acordados, que se moveram].
static func _a5_pass(stress: bool) -> Array:
	var fails: Array = []
	var woke: int = 0
	var moved_total: int = 0
	for s: int in range(1, SEEDS + 1):
		var sim: WorldSim = WorldSim.new(s, false, true)
		if stress:
			_open_all(sim)
			for e: EnemySim.Enemy in sim.enemies:
				e.awake = true
				e.state = EnemySim.CHASE
		var start: Array = positions(sim)
		for inp: IntInput in GateTraces.random_inputs(s, 1200, true):
			var before: Array = positions(sim)
			sim.step(inp)
			var v: String = a5_violation(sim, before)
			if v != "":
				fails.append("s%d t%d: %s" % [s, sim.tick, v])
				break
		for e: EnemySim.Enemy in sim.enemies:
			if e.awake:
				woke += 1
			if int(start[e.id][0]) != e.pos_x or int(start[e.id][1]) != e.pos_z:
				moved_total += 1
	return [fails, woke, moved_total]


static func _a6(r: GateReport) -> void:
	var sim: WorldSim = WorldSim.new(1, true)
	var id: int = sim.add_enemy(EnemySim.SKELETON, SPAWN_X + 1229, SPAWN_Z)
	var e: EnemySim.Enemy = sim.enemies[id]
	var seq: Array = [IntInput.new(0, 0, 0, true)] + GateTraces.repeat(23, IntInput.new()) \
		+ [IntInput.new(0, 0, 0, true)] + GateTraces.repeat(23, IntInput.new())
	var death_tick: int = -1
	var same_tick: bool = false
	var prev_hp: int = e.hp
	for inp: IntInput in seq:
		sim.step(inp)
		if e.hp == 0 and prev_hp > 0:
			death_tick = sim.tick
			same_tick = e.state == EnemySim.DEAD
		prev_hp = e.hp
	var hp_after: int = sim.player.hp
	var struck: bool = false
	for _i: int in range(200):
		sim.step(IntInput.new())
		if e.state != EnemySim.DEAD:
			struck = true
	var quiet: bool = not struck and sim.player.hp == hp_after
	# Outra entidade no lugar exato do morto: não colide e consegue andar.
	var rid: int = sim.add_enemy(EnemySim.RAT, e.pos_x, e.pos_z)
	var rat: EnemySim.Enemy = sim.enemies[rid]
	var free_spot: bool = not EnemySim.blocked_at(sim.grid, sim.enemies, sim.player, rat, rat.pos_x, rat.pos_z)
	var x0: int = rat.pos_x
	sim.step(IntInput.new())
	sim.step(IntInput.new())
	r.check("M4-A6", death_tick > 0 and same_tick and quiet and free_spot and rat.pos_x != x0,
		"hp 0 e DEAD no tick %d (mesmo tick=%s); 200 ticks sem STRIKE nem dano=%s; posição livre=%s, rato andou %d u" % [
			death_tick, same_tick, quiet, free_spot, x0 - rat.pos_x])


## M4-A7: inspeção da cena main.tscn (chamada por GateRepro com a cena já montada).
static func scene_check(r: GateReport, main: Node) -> void:
	var sim: WorldSim = main.get("sim")
	var holder: Node = main.get_node_or_null("Enemies")
	var errs: Array = []
	if holder == null:
		errs.append("Main/Enemies ausente")
	elif holder.get_child_count() != sim.enemies.size() or sim.enemies.is_empty():
		errs.append("%d filhos para %d inimigos" % [holder.get_child_count(), sim.enemies.size()])
	else:
		for e: EnemySim.Enemy in sim.enemies:
			var s: Sprite3D = holder.get_node_or_null("Enemy_%d" % e.id) as Sprite3D
			if s == null:
				errs.append("Enemy_%d não é Sprite3D" % e.id)
				continue
			if s.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y or s.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST \
					or s.alpha_cut != SpriteBase3D.ALPHA_CUT_DISCARD or s.texture == null:
				errs.append("Enemy_%d propriedades" % e.id)
				continue
			var used: Rect2i = s.texture.get_image().get_used_rect()
			var h: float = used.size.y * s.pixel_size
			var base: float = s.position.y + (16 - used.end.y) * s.pixel_size * s.scale.y
			var want: float = float(EnemyView.TARGET_M[e.type])
			if absf(h - want) > 0.02 or absf(base) > 0.01:
				errs.append("Enemy_%d altura=%.3f (alvo %.2f) base=%.3f" % [e.id, h, want, base])
	r.check("M4-A7", errs.is_empty(), "%d sprites billboard FIXED_Y/NEAREST/DISCARD com altura e base conferidas; erros=%s" % [
		sim.enemies.size(), str(errs)])
