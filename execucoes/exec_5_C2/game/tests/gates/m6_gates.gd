class_name M6Gates
extends RefCounted
## Acceptance Gate de M6 (plano 5 §5.1): itens, poções, XP/nível, porta trancada, saída, terminais e piloto.
## Fixtures podem ajustar campos do mundo antes ou entre ticks. "Teleportar" = centro da célula, vel = 0.

const R1_CHAIN: String = "523fef79264724d26ba78e7b53b623a8f32de0157ef9eb7a95f50e058f8553d6"
const DOOR_TRACE: String = "res://tests/traces/m2_door.jsonl"
const PILOT_SEEDS: int = 50
const PILOT_MIN_ESCAPED: int = 40


static func run(tree: SceneTree = null) -> Array:
	var out: Array = []
	out.append(_a1())
	out.append(_a2())
	out.append(_a3())
	out.append(_a4())
	out.append(_a5())
	out.append(_a6())
	out.append(_aux1())
	out.append(_aux2())
	out.append(_aux3())
	out.append(_aux4())
	out.append(_aux5())
	out.append(_aux6())
	out.append(_aux7(tree))
	out.append(_pilot_aux1())
	out.append(_pilot_aux2())
	out.append(_pilot_aux3())
	return out


static func teleport(w: WorldSim, cx: int, cz: int, angle: int = -1) -> void:
	w.player.pos_x = DungeonGen.cell_center_u(cx)
	w.player.pos_z = DungeonGen.cell_center_u(cz)
	w.player.vel_x = 0
	w.player.vel_z = 0
	if angle >= 0:
		w.player.angle = angle


static func kill_all(w: WorldSim) -> void:
	for i in range(w.enemies.size()):
		var e: EntitySim = w.enemies[i]
		e.hp = 0
		e.state = "DEAD"


static func q(quaff: int, use: bool = false) -> IntInput:
	var i := IntInput.make(0, 0, 0, use)
	i.quaff = quaff
	return i


static func canon_no_tick(w: WorldSim) -> String:
	var s: Dictionary = StateHash.canon(w)
	s.erase("tick")
	return StateHash.to_json(s)


static func room_of(d: DungeonGen.Dungeon, cx: int, cz: int) -> int:
	for i in range(d.rooms.size()):
		var r: Dictionary = d.rooms[i]
		if cx >= r["x"] and cx < r["x"] + r["w"] and cz >= r["z"] and cz < r["z"] + r["h"]:
			return r["id"]
	return -1


## M6-A1: posicionamento em 100 sementes.
static func _a1() -> Dictionary:
	for s in range(1, 101):
		var w := WorldSim.create(s, false)
		var d: DungeonGen.Dungeon = w.dungeon
		var keys: int = 0
		var start_items: Array = []
		var seen: Dictionary = {}
		var reach: PackedInt32Array = ItemsSim.bfs_no_locked(d.grid, w.player.cell_x(), w.player.cell_z())
		for it: Dictionary in w.items:
			var cx: int = it["cell_x"]
			var cz: int = it["cell_z"]
			if d.grid.get_cell(cx, cz) != Grid.FLOOR:
				return GateUtil.res("M6-A1", false, "s=%d item %d em célula %d" % [s, it["id"], d.grid.get_cell(cx, cz)])
			if cx == w.player.cell_x() and cz == w.player.cell_z():
				return GateUtil.res("M6-A1", false, "s=%d item %d na célula inicial" % [s, it["id"]])
			for e: EntitySim in w.enemies:
				if FixedMath.div_floor(e.pos_x, Grid.CELL) == cx and FixedMath.div_floor(e.pos_z, Grid.CELL) == cz:
					return GateUtil.res("M6-A1", false, "s=%d item %d sobre inimigo %d" % [s, it["id"], e.id])
			if seen.has(cz * Grid.W + cx):
				return GateUtil.res("M6-A1", false, "s=%d dois itens em (%d,%d)" % [s, cx, cz])
			seen[cz * Grid.W + cx] = true
			var room: int = room_of(d, cx, cz)
			if room == d.start_room:
				start_items.append(it["type"])
			if it["type"] == "key":
				keys += 1
				if room == d.start_room or room == d.exit_room or room < 0:
					return GateUtil.res("M6-A1", false, "s=%d chave na sala %d" % [s, room])
				if reach[cz * Grid.W + cx] < 0:
					return GateUtil.res("M6-A1", false, "s=%d chave inalcançável sem porta trancada" % s)
		if keys != 1 or start_items != ["potion_hp"]:
			return GateUtil.res("M6-A1", false, "s=%d chaves=%d sala inicial=%s" % [s, keys, str(start_items)])
		if JSON.stringify(WorldSim.create(s, false).get_items()) != JSON.stringify(w.get_items()):
			return GateUtil.res("M6-A1", false, "s=%d lista de itens não determinística" % s)
	var w1 := WorldSim.create(1, false)
	return GateUtil.res("M6-A1", true, "100 sementes; s=1: %d itens" % w1.items.size())


## M6-A2: poções (cura limitada, consumo com barra cheia, inventário vazio, vigor, invariante).
static func _a2() -> Dictionary:
	var w := WorldSim.create(1, true)
	w.player.potion_hp = 2
	w.player.potion_sp = 1
	w.player.hp = 80
	w.player.stamina = 30
	w.step(q(1))
	var t1: bool = w.player.hp == 100 and w.player.potion_hp == 1
	w.step(q(1))
	var t2: bool = w.player.hp == 100 and w.player.potion_hp == 0
	var twin := WorldSim.create(1, true)
	twin.player.potion_hp = 2
	twin.player.potion_sp = 1
	twin.player.hp = 80
	twin.player.stamina = 30
	twin.step(q(1))
	twin.step(q(1))
	w.step(q(1))
	twin.step(q(0))
	var t3: bool = w.player.potion_hp == 0 and StateHash.to_json(StateHash.canon(w)) == StateHash.to_json(StateHash.canon(twin)) \
		and w.get_events() == ["quaff_empty:1"]
	var sp0: int = w.player.stamina
	w.step(q(2))
	var t4: bool = w.player.stamina == mini(sp0 + 50, 100) and w.player.potion_sp == 0
	# invariante em 600 ticks com quaff aleatório e dano leve
	var inv := WorldSim.create(1, true)
	inv.player.potion_hp = 300
	inv.player.potion_sp = 300
	var rng := RngPcg32.create(61, 9)
	var bad: int = -1
	for k in range(600):
		if rng.bounded(4) == 0:
			inv.inject_hit(inv.player.pos_x + 1000, inv.player.pos_z, 3)
		var i := IntInput.make(rng.bounded(3) - 1, rng.bounded(3) - 1, rng.bounded(65) - 32)
		i.attack = rng.bounded(6) == 0
		i.quaff = rng.bounded(3)
		inv.step(i)
		if inv.player.hp > inv.player.hp_max or inv.player.stamina > inv.player.stamina_max:
			bad = k + 1
			break
	var ok: bool = t1 and t2 and t3 and t4 and bad < 0 and inv.terminal == "NONE"
	return GateUtil.res("M6-A2", ok, "t1=%s t2=%s t3=%s t4=%s(sp %d->%d) invariante=%s" % [
		t1, t2, t3, t4, sp0, w.player.stamina, "ok" if bad < 0 else "falha t%d" % bad])


static func _locked_door(w: WorldSim) -> Array:
	var d: DungeonGen.Dungeon = w.dungeon
	var er: Dictionary = d.rooms[d.exit_room]
	var dirs: Array = [[1, 0, 2048], [-1, 0, 0], [0, 1, 3072], [0, -1, 1024]]   # outside offset, angle para a porta
	for dr: Dictionary in d.doors:
		if d.grid.get_cell(dr["cx"], dr["cz"]) != Grid.DOOR_LOCKED:
			continue
		for dd: Array in dirs:
			var ox: int = dr["cx"] + dd[0]
			var oz: int = dr["cz"] + dd[1]
			if d.grid.get_cell(ox, oz) == Grid.FLOOR and room_of(d, ox, oz) != er["id"] \
					and not DungeonGen._adjacent_to_room(er, ox, oz):
				return [dr, ox, oz, dd[2]]
	return []


## M6-A3: saída com/sem chave e porta trancada com/sem chave.
static func _a3() -> Dictionary:
	var w := WorldSim.create(1, false)
	kill_all(w)
	var ec: Dictionary = w.get_exit_cell()
	teleport(w, ec["cx"], ec["cz"])
	w.step(q(0, true))
	var ta: String = w.terminal
	var a: bool = ta == "NONE"
	w.player.key = true
	w.step(q(0, true))
	var b: bool = w.terminal == "ESCAPED"
	var tb: int = w.tick
	var w2 := WorldSim.create(1, false)
	kill_all(w2)
	var ld: Array = _locked_door(w2)
	if ld.is_empty():
		return GateUtil.res("M6-A3", false, "sem porta trancada com lado de fora")
	var dr: Dictionary = ld[0]
	teleport(w2, ld[1], ld[2], ld[3])
	w2.step(q(0, true))
	var c1: bool = w2.get_cell(dr["cx"], dr["cz"]) == Grid.DOOR_LOCKED and w2.get_events().has("locked_no_key")
	w2.player.key = true
	w2.step(q(0, true))
	var c2: bool = w2.get_cell(dr["cx"], dr["cz"]) == Grid.DOOR_OPEN and w2.player.key \
		and w2.get_events().has("unlock:%d" % dr["id"])
	return GateUtil.res("M6-A3", a and b and c1 and c2, "(a) sem chave=%s (b) ESCAPED no tick %d=%s (c) porta %d trancada=%s aberta=%s" % [
		ta, tb, b, dr["id"], c1, c2])


## M6-A4: morte congela o estado.
static func _a4() -> Dictionary:
	var w := WorldSim.create(1, true)
	w.inject_hit(w.player.pos_x + 1000, w.player.pos_z, 100)
	w.step(IntInput.new())
	if w.player.hp != 0 or w.terminal != "DEAD":
		return GateUtil.res("M6-A4", false, "tick 1: hp=%d terminal=%s" % [w.player.hp, w.terminal])
	var s1: String = canon_no_tick(w)
	var rng := RngPcg32.create(44, 3)
	var prev_chain: String = w.chain
	for k in range(2, 122):
		var i := IntInput.make(rng.bounded(3) - 1, rng.bounded(3) - 1, rng.bounded(97) - 48, rng.bounded(4) == 0)
		i.attack = rng.bounded(3) == 0
		i.quaff = rng.bounded(3)
		w.step(i)
		if canon_no_tick(w) != s1 or w.tick != k or w.chain == prev_chain:
			return GateUtil.res("M6-A4", false, "tick %d: estado mudou/cadeia parada" % k)
		prev_chain = w.chain
	return GateUtil.res("M6-A4", true, "DEAD no tick 1; 120 ticks congelados; tick=%d" % w.tick)


## Abate com fixture: inimigo `type` com 1 de vida à frente; devolve [mundo, tick do abate ou -1].
static func _kill_scene(type: String, xp: int, level: int) -> Array:
	var w := WorldSim.create(1, true)
	w.player.xp = xp
	w.player.level = level
	w.player.hp_max = 100 + 20 * (level - 1)
	w.player.hp = w.player.hp_max
	w.player.stamina_max = 100 + 10 * (level - 1)
	w.player.stamina = w.player.stamina_max
	var id: int = w.add_dummy(6020, 15360) if type == "dummy" else w.add_enemy(type, 6020, 15360)
	w.enemies[id].hp = 1 if type != "rat" else w.enemies[id].hp
	w.add_dummy(DungeonGen.cell_center_u(8), DungeonGen.cell_center_u(4))
	var i := IntInput.new()
	i.attack = true
	for _k in range(20):
		w.step(i)
		i = IntInput.new()
		if w.enemies[id].state == "DEAD":
			return [w, w.tick]
	return [w, -1]


## Golpe no boneco (8,4) depois de esperar o golpe atual terminar; devolve o dano.
static func _dummy_damage(w: WorldSim) -> int:
	for _k in range(30):
		w.step(IntInput.new())
	var dummy: EntitySim = w.enemies[w.enemies.size() - 1]
	teleport(w, 8, 4, 0)
	w.player.pos_x = dummy.pos_x - 1000
	var hp0: int = dummy.hp
	var i := IntInput.new()
	i.attack = true
	for _k in range(14):
		w.step(i)
		i = IntInput.new()
	return hp0 - dummy.hp


## M6-A5: XP, subida de nível e dano por nível.
static func _a5() -> Dictionary:
	var a: Array = _kill_scene("rat", 95, 1)
	var w: WorldSim = a[0]
	var p: PlayerSim = w.player
	var ok_a: bool = a[1] > 0 and p.level == 2 and p.xp == 105 and p.hp_max == 120 and p.hp == 120 \
		and p.stamina_max == 110 and p.stamina < 100
	var det: String = "A: t%d nível=%d xp=%d hp=%d/%d vigor=%d/%d" % [a[1], p.level, p.xp, p.hp, p.hp_max, p.stamina, p.stamina_max]
	var dmg_a: int = _dummy_damage(w)
	ok_a = ok_a and dmg_a == 30
	det += " dano=%d" % dmg_a
	var b: Array = _kill_scene("skeleton", 240, 1)
	var wb: WorldSim = b[0]
	var ok_b: bool = b[1] > 0 and wb.player.level == 3 and wb.player.hp_max == 140 and wb.player.stamina_max == 120
	var dmg_b: int = _dummy_damage(wb)
	ok_b = ok_b and dmg_b == 35
	det += " | B: nível=%d hp_max=%d vigor_max=%d dano=%d" % [wb.player.level, wb.player.hp_max, wb.player.stamina_max, dmg_b]
	var c: Array = _kill_scene("rat", 1000, 3)
	var wc: WorldSim = c[0]
	var ok_c: bool = c[1] > 0 and wc.player.level == 3 and wc.player.xp == 1010
	det += " | C: nível=%d xp=%d" % [wc.player.level, wc.player.xp]
	var dd: Array = _kill_scene("dummy", 0, 1)
	var wd: WorldSim = dd[0]
	var ok_d: bool = dd[1] > 0 and wd.player.xp == 0 and wd.player.level == 1
	det += " | D: boneco abatido xp=%d" % wd.player.xp
	return GateUtil.res("M6-A5", ok_a and ok_b and ok_c and ok_d, det)


## Simula o piloto até o terminal (ou K_MAX); devolve [terminal, terminal_tick].
static func run_pilot(p_seed: int, max_ticks: int = ItemsSim.K_MAX) -> Array:
	var w := WorldSim.create(p_seed, false)
	var pilot := Pilot.create(p_seed)
	while w.tick < max_ticks and w.terminal == "NONE":
		w.step(pilot.next_input(w))
	return [w.terminal, w.tick if w.terminal != "NONE" else -1]


## M6-A6: fim a fim com o piloto nas sementes 1..50.
static func _a6() -> Dictionary:
	var count: Dictionary = {"ESCAPED": 0, "DEAD": 0, "TIMEOUT": 0, "NONE": 0}
	var failed: Array = []
	var sum_t: int = 0
	var n_t: int = 0
	for s in range(1, PILOT_SEEDS + 1):
		var r: Array = run_pilot(s)
		count[r[0]] += 1
		if r[1] >= 0:
			sum_t += r[1]
			n_t += 1
		if r[0] != "ESCAPED":
			failed.append("%d:%s" % [s, r[0]])
	var mean: int = sum_t / n_t if n_t > 0 else -1
	return GateUtil.res("M6-A6", count["ESCAPED"] >= PILOT_MIN_ESCAPED,
		"ESCAPED=%d/%d DEAD=%d TIMEOUT=%d média terminal_tick=%d falhas=[%s]" % [
		count["ESCAPED"], PILOT_SEEDS, count["DEAD"], count["TIMEOUT"], mean, ",".join(failed)])


## M6-AUX-1: coleta de cada tipo e nada muda sobre item já coletado.
static func _aux1() -> Dictionary:
	var w := WorldSim.create(1, true)
	var types: Array = ["potion_hp", "potion_sp", "key", "gold"]
	for k in range(4):
		w.items.append(ItemsSim.make(k, types[k], 3 + k, 7))
	for _k in range(120):
		w.step(IntInput.make(1, 0, 0))
	var p: PlayerSim = w.player
	var all_taken: bool = true
	for it: Dictionary in w.items:
		all_taken = all_taken and it["taken"]
	var ok: bool = all_taken and p.potion_hp == 1 and p.potion_sp == 1 and p.key and p.gold == 10
	teleport(w, 3, 7)
	var items_before: String = JSON.stringify(w.get_items())
	var quiet: bool = true
	for _k in range(5):
		w.step(IntInput.new())
		quiet = quiet and w.get_events().is_empty()
	var inv_same: bool = w.get_inventory() == {"potion_hp": 1, "potion_sp": 1, "key": true, "gold": 10, "level": 1, "xp": 0}
	ok = ok and quiet and inv_same and JSON.stringify(w.get_items()) == items_before
	return GateUtil.res("M6-AUX-1", ok, "taken=%s inv=%s parado=%s" % [all_taken, JSON.stringify(w.get_inventory()), quiet])


## Mundo gerado sem ItemsSim.spawn (mesma sequência de create até EnemySim.spawn).
static func world_without_items(s: int) -> WorldSim:
	var w := WorldSim.new()
	w.seed_value = s
	w.dungeon = DungeonGen.generate(s)
	w.automap = AutomapSim.new()
	w.rng_dungeon = w.dungeon.rng
	w.rng_ai = RngPcg32.create(s, RngPcg32.STREAM_AI)
	w.player = PlayerSim.new()
	w.player.pos_x = w.dungeon.player_start["pos_x"]
	w.player.pos_z = w.dungeon.player_start["pos_z"]
	w.player.angle = w.dungeon.player_start["angle"]
	EnemySim.spawn(w)
	return w


## M6-AUX-2: isolamento de RNG (inimigos/grade iguais; rng_dungeon parado depois do create; piloto não consome).
static func _aux2() -> Dictionary:
	for s in range(1, 21):
		var w := WorldSim.create(s, false)
		var ref: WorldSim = world_without_items(s)
		if JSON.stringify(w.get_enemies()) != JSON.stringify(ref.get_enemies()):
			return GateUtil.res("M6-AUX-2", false, "s=%d inimigos diferentes" % s)
		if w.dungeon.grid.sha256() != DungeonGen.generate(s).grid.sha256():
			return GateUtil.res("M6-AUX-2", false, "s=%d grade diferente" % s)
	var walker := WorldSim.create(1, false)
	var st0: String = walker.rng_dungeon.state_hex()
	GateUtil.run(walker, GateUtil.walker_inputs(900))
	var walk_ok: bool = walker.rng_dungeon.state_hex() == st0
	var pw := WorldSim.create(2, false)
	var d0: String = pw.rng_dungeon.state_hex()
	var a0: String = pw.rng_ai.state_hex()
	var pilot := Pilot.create(2)
	for _k in range(900):
		pw.step(pilot.next_input(pw))
	var pilot_ok: bool = pw.rng_dungeon.state_hex() == d0 and pw.rng_ai.state_hex() == a0
	return GateUtil.res("M6-AUX-2", walk_ok and pilot_ok, "20 sementes: inimigos e grade iguais; walker 900 rng_dungeon=%s; piloto 900 rng=%s" % [
		"parado" if walk_ok else "MUDOU", "parados" if pilot_ok else "MUDOU"])


## M6-AUX-3: fixtures sem itens e cadeia fixa de R1.
static func _aux3() -> Dictionary:
	var empty: bool = true
	for s in range(1, 6):
		empty = empty and WorldSim.create(s, true).items.is_empty() and WorldSim.create(s, false, "automap").items.is_empty()
	var w := WorldSim.create(1, true)
	var tr: Array = TraceIO.read(DOOR_TRACE)["inputs"]
	for k in range(600):
		w.step(tr[k] if k < tr.size() else IntInput.new())
	return GateUtil.res("M6-AUX-3", empty and w.chain == R1_CHAIN, "fixtures sem itens=%s R1=%s" % [empty, w.chain.left(16)])


## M6-AUX-4: TIMEOUT exatamente no tick K_MAX.
static func _aux4() -> Dictionary:
	var w := WorldSim.create(1, true)
	w.tick = ItemsSim.K_MAX - 5
	var early: bool = false
	var at: int = -1
	for _k in range(10):
		w.step(IntInput.new())
		if w.terminal != "NONE" and at < 0:
			at = w.tick
		if w.tick < ItemsSim.K_MAX and w.terminal != "NONE":
			early = true
	return GateUtil.res("M6-AUX-4", w.terminal == "TIMEOUT" and at == ItemsSim.K_MAX and not early,
		"terminal=%s no tick %d" % [w.terminal, at])


## M6-AUX-5: fuga e morte no mesmo tick -> DEAD.
static func _aux5() -> Dictionary:
	var w := WorldSim.create(1, false)
	kill_all(w)
	var ec: Dictionary = w.get_exit_cell()
	teleport(w, ec["cx"], ec["cz"])
	w.player.key = true
	w.inject_hit(w.player.pos_x + 1000, w.player.pos_z, 1000)
	w.step(q(0, true))
	return GateUtil.res("M6-AUX-5", w.exit_used and w.terminal == "DEAD", "exit_used=%s terminal=%s" % [w.exit_used, w.terminal])


## M6-AUX-6: guarda de tipos com items[] reais e os 4 valores de terminal.
static func _aux6() -> Dictionary:
	var w := WorldSim.create(1, true)
	var types: Array = ["potion_hp", "potion_sp", "key", "gold"]
	for k in range(4):
		w.items.append(ItemsSim.make(k, types[k], 3 + k, 7))
	w.items[1]["taken"] = true
	w.items[3]["taken"] = true
	w.step(IntInput.new())
	var ok: bool = not w.type_error
	for t: String in ["NONE", "DEAD", "ESCAPED", "TIMEOUT"]:
		w.terminal = t
		ok = ok and StateHash.assert_types(StateHash.canon(w))
	var s: Dictionary = StateHash.canon(w)
	ok = ok and (s["items"] as Array).size() == 4 and (s["items"][0] as Dictionary).size() == 5
	return GateUtil.res("M6-AUX-6", ok, "items=%s" % JSON.stringify(s["items"]))


## M6-AUX-7: o sampler emite quaff só na borda de subida.
static func _aux7(tree: SceneTree) -> Dictionary:
	var sampler := InputSampler.new()
	if tree != null:
		tree.root.add_child(sampler)
	Input.action_press("quaff_hp")
	var got: Array = []
	for _k in range(3):
		got.append(sampler.sample().quaff)
	Input.action_release("quaff_hp")
	got.append(sampler.sample().quaff)
	Input.action_press("quaff_hp")
	got.append(sampler.sample().quaff)
	Input.action_release("quaff_hp")
	if tree != null:
		tree.root.remove_child(sampler)
	sampler.free()
	return GateUtil.res("M6-AUX-7", got == [1, 0, 0, 0, 1], "quaff=%s" % str(got))


## PILOT-AUX-1: o sinal de turn reduz |lat| e o piloto fica de frente em <= 40 ticks.
static func _pilot_aux1() -> Dictionary:
	var w := WorldSim.create(1, true)
	teleport(w, 5, 7, 0)
	var tx: int = DungeonGen.cell_center_u(5)
	var tz: int = DungeonGen.cell_center_u(3)
	var a0: Dictionary = Pilot.aim(w.player, tx, tz)
	var lat0: int = absi(a0["lat"])
	var facing_at: int = -1
	var lat1: int = lat0
	for k in range(1, 41):
		var a: Dictionary = Pilot.aim(w.player, tx, tz)
		w.step(IntInput.make(0, 0, a["turn"]))
		if k == 1:
			lat1 = absi(Pilot.aim(w.player, tx, tz)["lat"])
		if Pilot.aim(w.player, tx, tz)["facing"]:
			facing_at = k
			break
	return GateUtil.res("PILOT-AUX-1", lat1 < lat0 and facing_at > 0,
		"turn0=%d |lat| %d->%d facing no tick %d angle=%d" % [a0["turn"], lat0, lat1, facing_at, w.player.angle])


## PILOT-AUX-2: next_input não escreve no mundo.
static func _pilot_aux2() -> Dictionary:
	var w := WorldSim.create(3, false)
	var pilot := Pilot.create(3)
	for _k in range(200):
		w.step(pilot.next_input(w))
	var before: String = StateHash.to_json(StateHash.canon(w))
	for _k in range(1000):
		pilot.next_input(w)
	var same: bool = StateHash.to_json(StateHash.canon(w)) == before
	return GateUtil.res("PILOT-AUX-2", same, "1000 chamadas sem step: canon %s" % ("idêntico" if same else "MUDOU"))


## PILOT-AUX-3: duas instâncias na mesma semente produzem trilhas idênticas (3000 ticks).
static func _pilot_aux3() -> Dictionary:
	var trails: Array = []
	for _r in range(2):
		var w := WorldSim.create(4, false)
		var pilot := Pilot.create(4)
		var lines := PackedStringArray()
		for _k in range(3000):
			var i: IntInput = pilot.next_input(w)
			lines.append(JSON.stringify(i.to_dict(), "", true))
			w.step(i)
		trails.append("\n".join(lines).sha256_text())
	return GateUtil.res("PILOT-AUX-3", trails[0] == trails[1], "trilha %s" % String(trails[0]).left(16))
