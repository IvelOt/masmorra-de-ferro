class_name M4Gates
extends RefCounted
## Acceptance Gate de M4 (plano 4 §5.1): inimigos rato/esqueleto/guardião, percepção, IA, golpes.
## Cenário base: test_room, jogador em (5120, 15360) célula (2,7), angle = 0, input nulo.

const BIG_HP: int = 100000


static func run(tree: SceneTree = null) -> Array:
	var out: Array = []
	out.append(_a1())
	out.append(_a2())
	out.append(_a3())
	out.append(_a4())
	out.append(_a5())
	out.append(_a6())
	out.append(_a7(tree))
	out.append_array(_aux(tree))
	return out


static func base(big_hp: bool = true) -> WorldSim:
	var w := WorldSim.create(1, true)
	if big_hp:
		w.player.hp = BIG_HP
		w.player.hp_max = BIG_HP
	return w


static func inp(attack: bool = false, block: bool = false, use: bool = false) -> IntInput:
	var i := IntInput.make(0, 0, 0, use)
	i.attack = attack
	i.block = block
	return i


static func open_doors(w: WorldSim, locked_too: bool) -> void:
	var g: Grid = w.dungeon.grid
	for dr: Dictionary in w.dungeon.doors:
		var c: int = g.get_cell(dr["cx"], dr["cz"])
		if c == Grid.DOOR_CLOSED or (locked_too and c == Grid.DOOR_LOCKED):
			g.set_cell(dr["cx"], dr["cz"], Grid.DOOR_OPEN)
	w.flow_dirty = true


static func wake_all(w: WorldSim) -> void:
	for e: EntitySim in w.enemies:
		e.awake = true
		e.state = "CHASE"
		e.state_ticks = 0


## Invariantes de M4-A5: nenhuma caixa viva em célula bloqueante e nenhum par vivo sobreposto.
static func invariant_violation(w: WorldSim) -> String:
	var g: Grid = w.dungeon.grid
	for i in range(w.enemies.size()):
		var e: EntitySim = w.enemies[i]
		if e.state == "DEAD":
			continue
		var h: int = EntitySim.HALF[e.type]
		if g.box_hits_solid(e.pos_x - h, e.pos_z - h, e.pos_x + h, e.pos_z + h):
			return "inimigo %d em sólido" % e.id
		for j in range(i + 1, w.enemies.size()):
			var o: EntitySim = w.enemies[j]
			if o.state == "DEAD":
				continue
			var s: int = h + int(EntitySim.HALF[o.type])
			if absi(e.pos_x - o.pos_x) < s and absi(e.pos_z - o.pos_z) < s:
				return "par (%d,%d) sobreposto" % [e.id, o.id]
	return ""


static func _a1() -> Dictionary:
	# (a) parede x = 15 entre jogador (13,4) e esqueleto (16,4)
	var w := base()
	w.player.pos_x = 27648
	w.player.pos_z = 9216
	w.add_enemy("skeleton", 33792, 9216)
	var e: EntitySim = w.enemies[0]
	for t in range(1, 301):
		w.step(inp())
		if e.state != "IDLE" or e.awake or e.pos_x != 33792 or e.pos_z != 9216:
			return GateUtil.res("M4-A1", false, "(a) tick %d: state=%s awake=%s" % [t, e.state, e.awake])
	# (b) controle na mesma câmara
	var wb := base()
	wb.player.pos_x = 27648
	wb.player.pos_z = 9216
	wb.add_enemy("skeleton", 21504, 9216)
	wb.step(inp())
	var eb: EntitySim = wb.enemies[0]
	if not eb.awake or eb.state != "CHASE":
		return GateUtil.res("M4-A1", false, "(b) após tick 1: state=%s awake=%s" % [eb.state, eb.awake])
	# (c) porta (15,7) aberta no tick 121
	var wc := base()
	wc.player.pos_x = 29696
	wc.player.pos_z = 15360
	wc.add_enemy("skeleton", 34816, 15360)
	var ec: EntitySim = wc.enemies[0]
	for t in range(1, 121):
		wc.step(inp())
		if ec.state != "IDLE":
			return GateUtil.res("M4-A1", false, "(c) tick %d: %s antes da porta" % [t, ec.state])
	wc.step(inp(false, false, true))
	var c_ok: bool = wc.get_cell(15, 7) == Grid.DOOR_OPEN and ec.awake and ec.state == "CHASE"
	return GateUtil.res("M4-A1", c_ok, "(a) IDLE 300 ticks atrás da parede; (b) CHASE no tick 1; (c) porta=%d awake=%s state=%s no tick 121" % [wc.get_cell(15, 7), ec.awake, ec.state])


static func _a2() -> Dictionary:
	var total: int = 0
	var worst: String = ""
	var worst_ratio: int = -1
	for s in range(1, 21):
		var spawned: Array = WorldSim.create(s, false).enemies
		for k in range(spawned.size()):
			var src: EntitySim = spawned[k]
			var w := WorldSim.create(s, false)
			w.enemies = []
			w.add_enemy(src.type, src.pos_x, src.pos_z)
			open_doors(w, true)
			wake_all(w)
			var e: EntitySim = w.enemies[0]
			var dist: PackedInt32Array = DungeonGen.bfs(w.dungeon.grid, w.player.cell_x(), w.player.cell_z())
			var d: int = dist[FixedMath.div_floor(e.pos_z, Grid.CELL) * Grid.W + FixedMath.div_floor(e.pos_x, Grid.CELL)]
			var speed: int = EnemySim.TYPES[e.type]["speed"]
			var tpc: int = FixedMath.div_trunc(Grid.CELL + speed - 1, speed)
			var limit: int = maxi(1200, FixedMath.div_trunc((d + 2) * tpc * 3, 2) + 120)
			var reached: int = -1
			for t in range(1, limit + 1):
				w.step(inp())
				if e.state == "WINDUP":
					reached = t
					break
			if d < 0 or reached < 0:
				return GateUtil.res("M4-A2", false, "semente %d id %d (%s) d=%d: sem WINDUP até o tick %d" % [s, src.id, src.type, d, limit])
			total += 1
			var ratio: int = FixedMath.div_trunc(reached * 1000, limit)
			if ratio > worst_ratio:
				worst_ratio = ratio
				worst = "s%d id%d %s d=%d tick=%d/%d" % [s, src.id, src.type, d, reached, limit]
	return GateUtil.res("M4-A2", true, "%d inimigos (sementes 1-20) chegam a WINDUP; pior caso %s" % [total, worst])


static func _a3() -> Dictionary:
	var w := base()
	w.add_enemy("skeleton", 6220, 15360)
	var e: EntitySim = w.enemies[0]
	for t in range(1, 26):
		w.step(inp())
		var want: String = "CHASE" if t == 1 else ("WINDUP" if t <= 19 else ("STRIKE" if t == 20 else "COOLDOWN"))
		var want_hp: int = BIG_HP if t < 20 else BIG_HP - 12
		if e.state != want or w.player.hp != want_hp:
			return GateUtil.res("M4-A3", false, "(a) tick %d: %s hp=%d (esperado %s hp=%d)" % [t, e.state, w.player.hp, want, want_hp])
	var wb := base()
	wb.add_enemy("skeleton", 6220, 15360)
	var eb: EntitySim = wb.enemies[0]
	var strike_t: int = -1
	for t in range(1, 26):
		if t == 10:
			wb.player.pos_x = 3072
		wb.step(inp())
		if eb.state == "STRIKE":
			strike_t = t
		if not wb.pending_hits.is_empty():
			return GateUtil.res("M4-A3", false, "(b) pending_hits não vazio no tick %d" % t)
	var ok: bool = strike_t == 20 and wb.player.hp == BIG_HP
	return GateUtil.res("M4-A3", ok, "(a) CHASE 1, WINDUP 2-19, STRIKE 20 (hp -12), COOLDOWN 21; (b) STRIKE %d fora do alcance, hp=%d" % [strike_t, wb.player.hp])


static func _a4() -> Dictionary:
	var cases: Array = [["rat", 6020, 10], ["skeleton", 6220, 20], ["guardian", 6420, 32]]
	var details: Array = []
	var ok: bool = true
	for c: Array in cases:
		var type: String = c[0]
		var t_def: Dictionary = EnemySim.TYPES[type]
		var gap: int = int(t_def["windup"]) + int(t_def["cooldown"]) + 1
		var w := base()
		w.add_enemy(type, c[1], 15360)
		var e: EntitySim = w.enemies[0]
		var strikes: Array = []
		var bad: String = ""
		for t in range(1, 601):
			var hp0: int = w.player.hp
			w.step(inp())
			var lost: int = hp0 - w.player.hp
			if e.state == "STRIKE":
				strikes.append(t)
				if lost != int(t_def["dmg"]):
					bad = "tick %d: -%d" % [t, lost]
			elif lost != 0:
				bad = "dano fora do STRIKE no tick %d" % t
			if bad != "":
				break
		if bad == "" and (strikes.is_empty() or strikes[0] != c[2]):
			bad = "primeiro STRIKE em %s" % (str(strikes[0]) if strikes else "nunca")
		for i in range(1, strikes.size()):
			if bad == "" and strikes[i] - strikes[i - 1] != gap:
				bad = "intervalo %d entre %d e %d" % [strikes[i] - strikes[i - 1], strikes[i - 1], strikes[i]]
		ok = ok and bad == ""
		details.append("%s: 1º=%d n=%d Δ=%d %s" % [type, strikes[0] if strikes else -1, strikes.size(), gap, bad if bad != "" else "ok"])
	return GateUtil.res("M4-A4", ok, "; ".join(details))


static func _a5() -> Dictionary:
	var walk: Array = GateUtil.walker_inputs(900)
	for s in range(1, 6):
		var w := WorldSim.create(s, false)
		wake_all(w)
		open_doors(w, false)
		for k in range(walk.size()):
			w.step(walk[k])
			var v: String = invariant_violation(w)
			if v != "":
				return GateUtil.res("M4-A5", false, "(a) semente %d tick %d: %s" % [s, w.tick, v])
	var moved: int = 0
	for s in range(1, 21):
		var w := WorldSim.create(s, false)
		wake_all(w)
		open_doors(w, true)
		var start: Array = []
		for e: EntitySim in w.enemies:
			start.append([e.pos_x, e.pos_z])
		for _t in range(1200):
			w.step(inp())
			var v: String = invariant_violation(w)
			if v != "":
				return GateUtil.res("M4-A5", false, "(b) semente %d tick %d: %s" % [s, w.tick, v])
		for i in range(w.enemies.size()):
			if w.enemies[i].pos_x != start[i][0] or w.enemies[i].pos_z != start[i][1]:
				moved += 1
	return GateUtil.res("M4-A5", true, "(a) sementes 1-5 x 900 ticks; (b) sementes 1-20 x 1200 ticks: sem sólido nem sobreposição (%d inimigos se moveram em (b))" % moved)


static func _a6() -> Dictionary:
	var w := base(false)
	w.add_enemy("rat", 6020, 15360)
	var e: EntitySim = w.enemies[0]
	var snap: Array = []
	for t in range(1, 121):
		w.step(inp(t == 1))
		if t == 7:
			if e.hp != 0 or e.state != "DEAD":
				return GateUtil.res("M4-A6", false, "após tick 7: hp=%d state=%s" % [e.hp, e.state])
			snap = [e.pos_x, e.pos_z, e.state, e.state_ticks]
		elif t > 7 and [e.pos_x, e.pos_z, e.state, e.state_ticks] != snap:
			return GateUtil.res("M4-A6", false, "cadáver mudou no tick %d" % t)
	var e2 := EntitySim.make(99, "skeleton", 6020, 15360)
	var free_ok: bool = not EnemySim.box_blocked(w, e2, 6020, 15360)
	var ok: bool = w.player.hp == 100 and free_ok
	return GateUtil.res("M4-A6", ok, "rato DEAD no tick 7, inerte até 120; hp jogador=%d; cadáver não colide=%s" % [w.player.hp, free_ok])


## Sprites de inimigo: Sprite3D billboard, um por entidade, pixel_size e textura 32x32 por tipo (plano §4.1).
static func _a7(tree: SceneTree) -> Dictionary:
	if tree == null:
		return GateUtil.res("M4-A7", false, "sem SceneTree")
	var px: Dictionary = {"rat": 0.03125, "skeleton": 0.05, "guardian": 0.0625}
	var gen := WorldSim.create(1, false)
	var tr := WorldSim.create(1, true)
	tr.add_enemy("rat", _c(5), _c(4))
	tr.add_enemy("skeleton", _c(8), _c(4))
	var details: Array = []
	var ok: bool = true
	for w: WorldSim in [gen, tr]:
		var main: Node = (load("res://view/main.tscn") as PackedScene).instantiate()
		main.attach_world(w)
		tree.root.add_child(main)
		var en: Node = main.get_node("Enemies")
		var n: int = en.get_child_count()
		var good: bool = n == w.enemies.size() and n > 0
		for e: EntitySim in w.enemies:
			var sp: Sprite3D = en.get_node_or_null("enemy_%d" % e.id) as Sprite3D
			var tex_ok: bool = sp != null and sp.texture != null and sp.texture.get_size() == Vector2(32, 32) \
				and sp.texture.resource_path == AssetResolver.path_of("enemy." + e.type)
			good = good and tex_ok and sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y \
				and is_equal_approx(sp.pixel_size, px[e.type])
		for c: Node in en.get_children():
			good = good and c is Sprite3D
		ok = ok and good
		details.append("%s: %d sprites %s" % ["gerada s1" if w == gen else "test_room", n, "ok" if good else "ERRO"])
		tree.root.remove_child(main)
		main.free()
	return GateUtil.res("M4-A7", ok, "; ".join(details))


static func _aux(tree: SceneTree) -> Array:
	return [_aux1(), _aux2(), _aux3(), _aux4(), _aux5(tree), _aux6()]


static func _aux1() -> Dictionary:
	var counts: Dictionary = {"rat": 0, "skeleton": 0, "guardian": 0}
	for s in range(1, 101):
		var w := WorldSim.create(s, false)
		var d: DungeonGen.Dungeon = w.dungeon
		var fail: String = ""
		if w.enemies.size() != d.rooms.size() - 1:
			fail = "%d inimigos para %d salas" % [w.enemies.size(), d.rooms.size()]
		var guardians: int = 0
		for e: EntitySim in w.enemies:
			if not EnemySim.TYPES.has(e.type):
				fail = "tipo %s" % e.type
			counts[e.type] = counts.get(e.type, 0) + 1
			var room: int = DungeonGen._in_room(d.rooms, FixedMath.div_floor(e.pos_x, Grid.CELL), FixedMath.div_floor(e.pos_z, Grid.CELL))
			if room == d.start_room:
				fail = "inimigo %d na sala inicial" % e.id
			if e.type == "guardian":
				guardians += 1
				if room != d.exit_room:
					fail = "guardião fora da sala da saída"
		if guardians != 1:
			fail = "%d guardiões" % guardians
		var inv: String = invariant_violation(w)
		if inv != "":
			fail = inv
		if JSON.stringify(w.get_enemies()) != JSON.stringify(WorldSim.create(s, false).get_enemies()):
			fail = "spawn não determinístico"
		if d.grid.sha256() != DungeonGen.generate(s).grid.sha256():
			fail = "grade mudou"
		if not WorldSim.create(s, true).enemies.is_empty() or not WorldSim.create(s, false, "automap").enemies.is_empty():
			fail = "test_room/fixture com inimigos"
		if fail != "":
			return GateUtil.res("M4-AUX-1", false, "semente %d: %s" % [s, fail])
	return GateUtil.res("M4-AUX-1", true, "sementes 1-100: rooms-1 inimigos, 1 guardião na saída; total rat=%d skeleton=%d guardian=%d" % [counts["rat"], counts["skeleton"], counts["guardian"]])


static func _c(c: int) -> int:
	return DungeonGen.cell_center_u(c)


static func _aux2() -> Dictionary:
	var w := WorldSim.create(1, true)
	var g: Grid = w.dungeon.grid
	var r: Array = []
	r.append(EnemySim.los(g, _c(2), _c(7), _c(13), _c(7)))
	r.append(not EnemySim.los(g, _c(13), _c(4), _c(16), _c(4)))
	r.append(not EnemySim.los(g, _c(13), _c(7), _c(17), _c(7)))
	g.set_cell(15, 7, Grid.DOOR_OPEN)
	r.append(EnemySim.los(g, _c(13), _c(7), _c(17), _c(7)))
	# canto exato entre duas células sólidas: (5,5) -> (6,6) com (6,5) e (5,6) sólidas
	var gc := Grid.new()
	for z in range(4, 9):
		for x in range(4, 9):
			gc.set_cell(x, z, Grid.FLOOR)
	gc.set_cell(6, 5, Grid.SOLID)
	gc.set_cell(5, 6, Grid.SOLID)
	r.append(not EnemySim.los(gc, _c(5), _c(5), _c(6), _c(6)))
	gc.set_cell(6, 5, Grid.FLOOR)
	gc.set_cell(5, 6, Grid.FLOOR)
	r.append(EnemySim.los(gc, _c(5), _c(5), _c(6), _c(6)))
	return GateUtil.res("M4-AUX-2", not r.has(false), "(2,7)->(13,7) livre, parede bloqueia, porta fechada/aberta, canto sólido bloqueia: %s" % str(r))


static func _aux3() -> Dictionary:
	var w := WorldSim.create(1, true)
	w.step(inp())
	var d57: int = w.flow_dist[7 * Grid.W + 5]
	var ties: Array = [
		EnemySim.flow_next(w, 3, 8) == [3, 7],
		EnemySim.flow_next(w, 1, 6) == [2, 6],
		EnemySim.flow_next(w, 3, 6) == [3, 7],
		EnemySim.flow_next(w, 2, 7).is_empty(),
	]
	var rc: Array = [w.flow_recalcs]
	w.step(inp())
	rc.append(w.flow_recalcs)
	w.player.pos_x = 5420
	w.step(inp())
	rc.append(w.flow_recalcs)
	w.player.pos_x = 29696
	w.step(inp())
	rc.append(w.flow_recalcs)
	w.step(inp())
	rc.append(w.flow_recalcs)
	w.step(inp(false, false, true))
	rc.append(w.flow_recalcs)
	var ok: bool = d57 == 3 and not ties.has(false) and rc == [1, 1, 1, 2, 2, 3] and w.get_cell(15, 7) == Grid.DOOR_OPEN
	return GateUtil.res("M4-AUX-3", ok, "dist(5,7)=%d empates N,L,S,O=%s recálculos=%s" % [d57, str(ties), str(rc)])


static func _aux4() -> Dictionary:
	var w := base()
	w.add_enemy("skeleton", 6220, 15360)
	var hp_drop: int = -1
	var sp_drop: int = -1
	for t in range(1, 21):
		var hp0: int = w.player.hp
		var sp0: int = w.player.stamina
		w.step(inp(false, true))
		if t == 20:
			hp_drop = hp0 - w.player.hp
			sp_drop = sp0 - w.player.stamina
	var wg := base()
	wg.add_enemy("guardian", 3820, 15360)
	var g_drop: int = -1
	for t in range(1, 33):
		var hp0: int = wg.player.hp
		wg.step(inp(false, true))
		if t == 32:
			g_drop = hp0 - wg.player.hp
	var ok: bool = hp_drop == 3 and sp_drop == 11 and g_drop == 25 and wg.enemies[0].state == "STRIKE"
	return GateUtil.res("M4-AUX-4", ok, "esqueleto bloqueado: hp -%d vigor -%d; guardião pelas costas: hp -%d" % [hp_drop, sp_drop, g_drop])


## O walker sozinho não sai da sala inicial (R3-seed-* não acorda ninguém); aqui os inimigos são
## forçados a CHASE com portas abertas para a comparação com/sem view não ser vazia.
static func _aux5(tree: SceneTree) -> Dictionary:
	var walk: Array = GateUtil.walker_inputs(900)
	var moved: int = 0
	var strikes: int = 0
	var same_all: bool = true
	var details: Array = []
	for s in range(1, 6):
		var w := WorldSim.create(s, false)
		wake_all(w)
		open_doors(w, false)
		var wv := WorldSim.create(s, false)
		wake_all(wv)
		open_doors(wv, false)
		var main: Node = null
		if tree != null:
			main = (load("res://view/main.tscn") as PackedScene).instantiate()
			main.attach_world(wv)
			tree.root.add_child(main)
		var start: Array = []
		for e: EntitySim in w.enemies:
			start.append([e.pos_x, e.pos_z])
		var st: int = 0
		for k in range(walk.size()):
			w.step(walk[k])
			if main != null:
				main.advance(walk[k])
			else:
				wv.step(walk[k])
			for e: EntitySim in w.enemies:
				if e.state == "STRIKE":
					st += 1
		if main != null:
			tree.root.remove_child(main)
			main.free()
		var mv: int = 0
		for i in range(w.enemies.size()):
			if w.enemies[i].pos_x != start[i][0] or w.enemies[i].pos_z != start[i][1]:
				mv += 1
		moved += mv
		strikes += st
		var same: bool = w.chain == wv.chain
		same_all = same_all and same
		details.append("s%d=%d/%d%s" % [s, mv, st, "" if same else "!="])
	return GateUtil.res("M4-AUX-5", moved > 0 and strikes > 0 and same_all and tree != null,
		"walker 900 ticks com IA ativa, movidos/STRIKEs: %s; cadeias com/sem main.tscn %s" % [" ".join(details), "iguais" if same_all else "DIFERENTES"])


static func _aux6() -> Dictionary:
	var w := WorldSim.create(1, true)
	var states: Array = ["IDLE", "CHASE", "WINDUP", "STRIKE", "COOLDOWN", "DEAD"]
	var ok: bool = true
	for type: String in ["rat", "skeleton", "guardian"]:
		w.add_enemy(type, _c(4), _c(4))
	for st: String in states:
		for e: EntitySim in w.enemies:
			e.state = st
			e.awake = st != "IDLE"
		ok = ok and StateHash.assert_types(StateHash.canon(w))
	return GateUtil.res("M4-AUX-6", ok, "assert_types aceita 3 tipos x 6 estados")
