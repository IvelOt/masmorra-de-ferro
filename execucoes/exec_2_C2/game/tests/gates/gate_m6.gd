extends RefCounted
## Gate M6 (itens, progressão, terminais): M6-A1..A5, X1..X3 no núcleo; M6-V1 e V2 (cena em
## headless) em run_vis(); M6-A6 (fim a fim, o mais longo) em run_e2e(), chamado por último.
##
## Calibração do piloto (input/pilot.gd, ESCAPE_DIST = 0: o piloto enfrenta o Guardião em vez de
## passar por ele; com 4 células o Guardião parado sobre o EXIT matava o jogador em 6 de 10
## sementes): ESCAPED em 50/50 sementes de 1 a 50 (nenhum DEAD/TIMEOUT), terminal_tick entre
## 1034 e 3013; arena ESCAPED no tick 469.

const Grid = preload("res://sim/grid.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const ItemsSim = preload("res://sim/items_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const Pilot = preload("res://input/pilot.gd")
const TraceIO = preload("res://input/trace_io.gd")
const GateM3 = preload("res://tests/gates/gate_m3.gd")
const GateM4 = preload("res://tests/gates/gate_m4.gd")
const Report = preload("res://tests/gates/gate_report.gd")

const MAIN_SCENE: String = "res://view/main.tscn"
const HUD_SCRIPT: String = "res://view/hud_daggerfall.gd"
const X2_TRACE: String = "user://m6_x2_trace.jsonl"
const E2E_SEEDS: int = 50
const E2E_MIN_ESCAPED: int = 40
const ARENA_MAX_TICKS: int = 3600


static func _note_error(r: Report, w: WorldSim) -> void:
	if w.hash_error:
		r.runtime_error = true


static func run(r: Report) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_x1(r)
	_x2(r)
	_x3(r)


static func _a1(r: Report) -> void:
	var bad: Array = []
	for s in range(1, 101):
		var w: WorldSim = WorldSim.new()
		w.setup_seed(s)
		var g: Grid = w.grid
		var keys: Array = []
		var room0: Array = []
		var ok: bool = true
		var enemy_cells: Dictionary = {}
		for e: Dictionary in w.enemies:
			enemy_cells[Grid.index_of(Grid.cell_of(e.pos_x), Grid.cell_of(e.pos_z))] = true
		for i in range(w.items.size()):
			var it: Dictionary = w.items[i]
			var cx: int = it.cell_x
			var cz: int = it.cell_z
			ok = ok and int(it.id) == i and g.get_cell(cx, cz) == Grid.FLOOR \
				and not enemy_cells.has(Grid.index_of(cx, cz))
			if it.type == "key":
				keys.append(it)
			if g.get_room_id(cx, cz) == 0:
				room0.append(it.type)
		ok = ok and keys.size() == 1 and room0 == ["potion_hp"]
		if keys.size() == 1:
			var k: Dictionary = keys[0]
			var rid: int = g.get_room_id(k.cell_x, k.cell_z)
			var dist: PackedInt32Array = ItemsSim.bfs_unlocked(g, Grid.cell_of(g.spawn_x), Grid.cell_of(g.spawn_z))
			ok = ok and rid != 0 and rid != g.exit_room and dist[Grid.index_of(k.cell_x, k.cell_z)] >= 0
		if not ok:
			bad.append(s)
	r.check("M6-A1", bad.is_empty(), "sementes 1..100; falhas: %s" % str(bad))


static func _quaff(q: int) -> IntInput:
	var i: IntInput = IntInput.new()
	i.quaff = q
	return i


static func _a2(r: Report) -> void:
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	w.player.hp = 90
	w.player.inventory.potion_hp = 1
	w.step(_quaff(1))
	var hp1: Array = [w.player.hp, w.player.inventory.potion_hp]
	w.step(_quaff(1))
	var hp2: Array = [w.player.hp, w.player.inventory.potion_hp]
	var v: WorldSim = WorldSim.new()
	v.setup_test("room")
	v.player.stamina = 70
	v.player.inventory.potion_sp = 1
	v.step(_quaff(2))
	var sp1: Array = [v.player.stamina, v.player.inventory.potion_sp]
	v.step(_quaff(2))
	var sp2: Array = [v.player.stamina, v.player.inventory.potion_sp]
	_note_error(r, w)
	_note_error(r, v)
	r.check("M6-A2", hp1 == [100, 0] and hp2 == [100, 0] and sp1 == [100, 0] and sp2 == [100, 0],
		"vida: 1º=%s 2º=%s; vigor: 1º=%s 2º=%s" % [str(hp1), str(hp2), str(sp1), str(sp2)])


static func _use() -> IntInput:
	return IntInput.new(0, 0, 0, true)


static func _a3(r: Report) -> void:
	var w: WorldSim = WorldSim.new()
	w.setup_test("arena")
	w.player.pos_x = Grid.cell_center(19)
	w.player.pos_z = Grid.cell_center(6)
	w.step(_use())
	var no_key: String = w.terminal
	w.player.inventory.key = 1
	w.step(_use())
	var esc_ok: bool = w.terminal == "ESCAPED" and w.terminal_tick == w.tick and w.tick == 2
	var d: WorldSim = WorldSim.new()
	d.setup_test("arena")
	d.player.pos_x = Grid.cell_center(14)
	d.player.pos_z = Grid.cell_center(6)
	d.step(_use())
	var locked: bool = d.grid.get_cell(15, 6) == Grid.DOOR_LOCKED
	d.player.inventory.key = 1
	d.step(_use())
	var opened: bool = d.grid.get_cell(15, 6) == Grid.DOOR_OPEN
	_note_error(r, w)
	_note_error(r, d)
	r.check("M6-A3", no_key == "NONE" and esc_ok and locked and opened,
		"EXIT sem chave=%s; com chave=%s no tick %d; porta sem chave trancada=%s; com chave aberta=%s" % [
			no_key, w.terminal, w.terminal_tick, locked, opened])


static func _a4(r: Report) -> void:
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	w.inject_hit(200, 8397, 15360)
	w.step(IntInput.new())
	var dead_ok: bool = w.terminal == "DEAD" and w.terminal_tick == 1
	var frozen: Dictionary = w.canonical_state()
	frozen.erase("tick")
	var const_ok: bool = true
	var trace: Array = GateM3.a7_trace(GateM3.A7_SEED_FROM)
	for k in range(100):
		w.step(trace[k].inp)
		var s: Dictionary = w.canonical_state()
		s.erase("tick")
		if JSON.stringify(s, "", true) != JSON.stringify(frozen, "", true):
			const_ok = false
	_note_error(r, w)
	r.check("M6-A4", dead_ok and const_ok, "terminal=%s no tick %d; estado sem tick constante em 100 ticks=%s" % [
		w.terminal, w.terminal_tick, const_ok])


static func _a5(r: Report) -> void:
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	w.pending_xp = 100
	w.step(IntInput.new())
	var p: RefCounted = w.player
	var s1: Array = [p.level, p.hp_max, p.hp, p.stamina_max, w.sword_damage()]
	w.pending_xp = 150
	w.step(IntInput.new())
	var s2: Array = [p.xp, p.level, p.hp_max, p.stamina_max, w.sword_damage()]
	var v: WorldSim = WorldSim.new()
	v.setup_test("room")
	v.pending_xp = 300
	v.step(IntInput.new())
	var s3: Array = [v.player.level, v.player.hp_max, v.player.hp, v.player.stamina_max, v.sword_damage()]
	_note_error(r, w)
	_note_error(r, v)
	r.check("M6-A5", s1 == [2, 120, 120, 110, 30] and s2 == [250, 3, 140, 120, 35] and s3 == [3, 140, 140, 120, 35],
		"1º [nível, hp_max, hp, vigor_max, dano]=%s; 2º [xp, nível, hp_max, vigor_max, dano]=%s; 300 de uma vez=%s" % [
			str(s1), str(s2), str(s3)])


## Roda o piloto até o terminal ou `max_ticks`; devolve {world, inputs, violation}.
static func pilot_run(setup: String, seed_value: int, max_ticks: int, check_invariants: bool) -> Dictionary:
	var w: WorldSim = WorldSim.new()
	if setup == "arena":
		w.setup_test("arena")
	else:
		w.setup_seed(seed_value)
	var pilot: Pilot = Pilot.new(seed_value)
	var inputs: Array = []
	var violation: String = ""
	while w.terminal == "NONE" and w.tick < max_ticks:
		var inp: IntInput = pilot.next_input(w)
		inputs.append(inp)
		w.step(inp)
		if check_invariants and violation == "":
			violation = GateM4.invariant_violation(w)
	return {"world": w, "inputs": inputs, "violation": violation}


static func _x1(r: Report) -> void:
	var res: Dictionary = pilot_run("arena", 1, ARENA_MAX_TICKS, true)
	var w: WorldSim = res.world
	_note_error(r, w)
	r.check("M6-X1", w.terminal == "ESCAPED" and w.terminal_tick <= ARENA_MAX_TICKS and res.violation == "",
		"arena: %s no tick %d (limite %d); violação: '%s'" % [w.terminal, w.terminal_tick, ARENA_MAX_TICKS, res.violation])


static func _x2(r: Report) -> void:
	var w: WorldSim = WorldSim.new()
	w.setup_seed(1)
	var pilot: Pilot = Pilot.new(1)
	var inputs: Array = []
	for _k in range(3000):
		var inp: IntInput = pilot.next_input(w)
		inputs.append(inp)
		w.step(inp)
	var wrote: bool = TraceIO.write_trace(X2_TRACE, inputs)
	var trace: Array = TraceIO.read_trace(X2_TRACE)
	var rep: WorldSim = WorldSim.new()
	rep.setup_seed(1)
	for inp: IntInput in trace:
		rep.step(inp)
	_note_error(r, w)
	_note_error(r, rep)
	r.check("M6-X2", wrote and trace.size() == 3000 and w.chain == rep.chain and w.chain != "",
		"linhas=%d C_K piloto=%s reprodução=%s" % [trace.size(), w.chain, rep.chain])


static func _x3(r: Report) -> void:
	var w: WorldSim = WorldSim.new()
	w.setup_test("arena")
	w.player.pos_x = Grid.cell_center(8)
	w.player.pos_z = Grid.cell_center(3)
	w.step(IntInput.new())
	var gold_ok: bool = w.player.gold == 25 and w.items[1].taken
	w.player.pos_x = Grid.cell_center(11)
	w.player.pos_z = Grid.cell_center(3)
	w.step(IntInput.new())
	var key_ok: bool = int(w.player.inventory.key) == 1 and w.items[2].taken
	_note_error(r, w)
	r.check("M6-X3", gold_ok and key_ok, "ouro=%d item1 coletado=%s; chave=%d" % [
		w.player.gold, w.items[1].taken, w.player.inventory.key])


## M6-A6: fim a fim, piloto nas sementes 1..50 até 18000 ticks; invariantes por tick.
static func run_e2e(r: Report) -> void:
	var dist: Dictionary = {}
	var bad: Array = []
	var escaped: int = 0
	for s in range(1, E2E_SEEDS + 1):
		var res: Dictionary = pilot_run("seed", s, WorldSim.K_MAX, true)
		var w: WorldSim = res.world
		dist[w.terminal] = int(dist.get(w.terminal, 0)) + 1
		if w.terminal == "ESCAPED":
			escaped += 1
		if w.hash_error:
			r.runtime_error = true
			bad.append("%d: hash_error" % s)
		if res.violation != "":
			bad.append("%d: %s" % [s, res.violation])
	r.check("M6-A6", escaped >= E2E_MIN_ESCAPED and bad.is_empty(),
		"ESCAPED %d/%d (mínimo %d); terminais=%s; falhas: %s" % [escaped, E2E_SEEDS, E2E_MIN_ESCAPED, str(dist), str(bad)])


## M6-V1 e M6-V2: precisam da árvore (chamadas em _initialize de run_gates.gd).
static func run_vis(r: Report, root: Window) -> void:
	_v1(r, root)
	_v2(r, root)


static func _v1(r: Report, root: Window) -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set("start_override", "arena")
	main.set("driven_externally", true)
	root.add_child(main)
	var end: CanvasLayer = main.get_node("EndScreen")
	var iv: Node = main.get_node("ItemView")
	var sprites: int = 0
	for c: Node in iv.get_children():
		if c is Sprite3D:
			sprites += 1
	var hidden_before: bool = not end.visible
	var w: WorldSim = main.get("world")
	var pilot: Pilot = Pilot.new(1)
	var inputs: Array = []
	var key_hidden: bool = false
	while w.terminal == "NONE" and w.tick < ARENA_MAX_TICKS:
		var inp: IntInput = pilot.next_input(w)
		inputs.append(inp)
		main.call("tick_once", inp)
		if w.items[2].taken:
			var ks: Sprite3D = iv.get_node_or_null("Item_2")
			key_hidden = ks != null and not ks.visible
	var shown_after: bool = end.visible
	var core: WorldSim = WorldSim.new()
	core.setup_test("arena")
	for inp: IntInput in inputs:
		core.step(inp)
	var chain_ok: bool = core.chain == w.chain and core.chain != ""
	if w.hash_error or core.hash_error:
		r.runtime_error = true
	var term: String = w.terminal
	root.remove_child(main)
	main.free()
	r.check("M6-V1", hidden_before and shown_after and term == "ESCAPED" and sprites == 4 and key_hidden and chain_ok,
		"EndScreen antes oculto=%s depois visível=%s (%s); ItemView %d Sprite3D; chave oculta=%s; C_K cena=núcleo %s" % [
			hidden_before, shown_after, term, sprites, key_hidden, chain_ok])


static func _v2(r: Report, root: Window) -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set("start_override", "seed:1")
	main.set("driven_externally", true)
	root.add_child(main)
	var bar: Node = main.get_node("Hud/Bar")
	var hp_text: String = (bar.get_node("HpLabel") as Label).text
	var sp_text: String = (bar.get_node("StaminaLabel") as Label).text
	var hp_w: float = (bar.get_node("HpBar") as Control).size.x
	var sp_w: float = (bar.get_node("StaminaBar") as Control).size.x
	var shield: Sprite2D = main.get_node("WeaponView/Shield")
	var shield_bottom: float = shield.position.y + 16.0 * shield.scale.y
	root.remove_child(main)
	main.free()
	var hud: GDScript = load(HUD_SCRIPT)
	var labels: Array = []
	for a: int in [0, 1024, 2048, 3072, 512]:
		labels.append(hud.call("heading_label", a))
	var ok: bool = hp_text == "Vida 100/100" and sp_text == "Vigor 100/100" and is_equal_approx(hp_w, 12.0) \
		and is_equal_approx(sp_w, 12.0) and shield_bottom <= 312.0 and labels == ["E", "N", "W", "S", "NE"]
	r.check("M6-V2", ok, "'%s' '%s'; larguras %d/%d; base do escudo y=%d; bússola 0/1024/2048/3072/512=%s" % [
		hp_text, sp_text, int(hp_w), int(sp_w), int(shield_bottom), str(labels)])
