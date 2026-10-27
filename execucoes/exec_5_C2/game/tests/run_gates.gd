extends SceneTree
## Suíte completa: gates M1–M5 (preservação), M6 (rodada 5) + testes de contrato
## (lint, R1–R4, piloto, tipos, cena, assets, vitrine).
## Comando canônico (importa o projeto antes, funciona em checkout limpo): tools/run_gates.sh
##   godot --headless --path game -s res://tests/run_gates.gd
## Saída 0 se tudo PASS, 2 se alguma asserção falha.

const MAIN_SCENE: String = "res://view/main.tscn"
const DOOR_TRACE: String = "res://tests/traces/m2_door.jsonl"
const CORRIDOR_TRACE: String = "res://tests/traces/m5_corridor.jsonl"
const DEMO_TRACE: String = "res://tests/traces/demo_iter2.jsonl"
const DEMO4_TRACE: String = "res://tests/traces/demo_iter4.jsonl"
const DEMO4_ENEMIES: Array = [["skeleton", 8, 7], ["rat", 19, 4]]
const ENEMY_NODE: String = "Enemies/enemy_0"
const RUNNER: String = "res://scripts/headless_runner.gd"
const TMP_DIR: String = "user://gates_tmp"
const ASSETS_R1: Array = [
	"wall.dungeon.stone01", "wall.dungeon.stone02", "floor.dungeon.01", "ceiling.dungeon.01",
	"door.closed", "door.locked", "door.open", "exit.portal", "torch.0", "torch.1", "torch.2", "torch.3",
	"weapon.sword", "weapon.shield", "ui.portrait", "enemy.dummy",
	"enemy.rat", "enemy.skeleton", "enemy.guardian",
	"item.potion_hp", "item.potion_sp", "item.key", "item.gold",
]
const ITEM_ASSETS: Array = ["item.potion_hp", "item.potion_sp", "item.key", "item.gold"]
const HUD_LABELS: Array = ["HpText", "SpText", "PotText", "KeyText", "Compass", "LvlText", "Message", "StatText"]
const HUD_INITIAL: Array = [
	["HUD/Frame/PotText", "PV 0  PF 0"], ["HUD/Frame/KeyText", "Chave: não"],
	["HUD/Frame/LvlText", "Nível 1"], ["HUD/Frame/StatText", "Ouro 0 · XP 0/100"],
]
const ENEMY_ASSETS: Array = ["enemy.dummy", "enemy.rat", "enemy.skeleton", "enemy.guardian"]


var _done: bool = false


## Executa no primeiro quadro (em _initialize os nós adicionados ainda não recebem _ready).
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_run_all()
	return false


func _run_all() -> void:
	var results: Array = []
	results.append_array(M1Gates.run())
	results.append_array(M2Gates.run())
	results.append_array(M3Gates.run())
	results.append_array(M4Gates.run(self))
	results.append_array(M5Gates.run(self))
	results.append_array(M6Gates.run(self))
	results.append_array(contract_tests())
	quit(2 if GateUtil.print_results(results) > 0 else 0)


## Trilha que anda, gira e tenta abrir portas (usada em R3 com masmorras geradas).
static func walker_inputs(n: int) -> Array:
	return GateUtil.walker_inputs(n)


## Trilha de combate (anda, gira, golpeia e bloqueia) para R3 quando demo_iter2.jsonl não existe.
static func combat_inputs(n: int) -> Array:
	var rng := RngPcg32.create(21, 5)
	var out: Array = []
	for _k in range(n):
		var i := IntInput.make(rng.bounded(3) - 1, rng.bounded(3) - 1, rng.bounded(65) - 32)
		i.attack = rng.bounded(5) == 0
		i.block = rng.bounded(4) == 0
		out.append(i)
	return out


## Mesma lógica de headless_runner.simulate(), executada nesta árvore.
func _simulate(p_seed: int, ticks: int, inputs: Array, test_room: bool, with_view: bool,
		fixture: String = "", dummy: bool = false, enemies: Array = [], pilot: Pilot = null) -> Dictionary:
	var world := WorldSim.create(p_seed, test_room, fixture)
	if dummy:
		world.add_dummy(DungeonGen.cell_center_u(8), DungeonGen.cell_center_u(4))
	for en: Array in enemies:
		world.add_enemy(en[0], DungeonGen.cell_center_u(en[1]), DungeonGen.cell_center_u(en[2]))
	var main: Node = null
	if with_view:
		main = (load(MAIN_SCENE) as PackedScene).instantiate()
		main.attach_world(world)
		root.add_child(main)
	var opened: int = 0
	for k in range(ticks):
		var inp: IntInput = null
		if pilot != null:
			inp = pilot.next_input(world)
		else:
			inp = inputs[k] if k < inputs.size() else IntInput.new()
		if main != null:
			main.advance(inp)
		else:
			world.step(inp)
	for dr: Dictionary in world.get_doors():
		if dr["state"] == Grid.DOOR_OPEN:
			opened += 1
	if main != null:
		root.remove_child(main)
		main.free()
	return {"chain": world.chain, "type_error": world.type_error, "opened": opened, "terminal": world.terminal}


func contract_tests() -> Array:
	var out: Array = []
	out.append(_lint_test())
	var tr: Dictionary = TraceIO.read(DOOR_TRACE)
	var door_in: Array = tr["inputs"]
	# R1 / R3 na sala de teste com a trilha dourada (600 ticks)
	var a: Dictionary = _simulate(1, 600, door_in, true, false)
	var b: Dictionary = _simulate(1, 600, door_in, true, false)
	var c: Dictionary = _simulate(1, 600, door_in, true, true)
	out.append(GateUtil.res("R1", a["chain"] == b["chain"] and a["chain"] == M6Gates.R1_CHAIN and not a["type_error"], a["chain"]))
	out.append(GateUtil.res("R3-test-room", a["chain"] == c["chain"], "%s vs %s" % [a["chain"], c["chain"]]))
	# R1 com IA: masmorra gerada (com inimigos), duas instâncias no mesmo processo
	var walk_ai: Array = walker_inputs(900)
	var ai1: Dictionary = _simulate(1, 900, walk_ai, false, false)
	var ai2: Dictionary = _simulate(1, 900, walk_ai, false, false)
	out.append(GateUtil.res("R1-AI", ai1["chain"] == ai2["chain"] and not ai1["type_error"], ai1["chain"]))
	# R1 / R3 no automap_fixture com a trilha de M5
	var cor_in: Array = TraceIO.read(CORRIDOR_TRACE)["inputs"]
	var m1: Dictionary = _simulate(1, 421, cor_in, false, false, "automap")
	var m2: Dictionary = _simulate(1, 421, cor_in, false, false, "automap")
	var m3: Dictionary = _simulate(1, 421, cor_in, false, true, "automap")
	out.append(GateUtil.res("R1-M5", m1["chain"] == m2["chain"] and not m1["type_error"], m1["chain"]))
	out.append(GateUtil.res("R3-automap", m1["chain"] == m3["chain"], m1["chain"].left(16)))
	# R3 na sala de teste com boneco e trilha de combate
	var demo: Dictionary = TraceIO.read(DEMO_TRACE)
	var combat: Array = demo["inputs"] if demo["error"] == "" else combat_inputs(600)
	var n_c: int = maxi(combat.size(), 600)
	var d1: Dictionary = _simulate(1, n_c, combat, true, false, "", true)
	var d2: Dictionary = _simulate(1, n_c, combat, true, true, "", true)
	out.append(GateUtil.res("R3-dummy", d1["chain"] == d2["chain"] and not d1["type_error"],
		"%s %s" % ["demo_iter2" if demo["error"] == "" else "gerada", d1["chain"].left(16)]))
	# R3 nas sementes 1..5 com geração e trilha que anda e abre portas
	var walk: Array = walker_inputs(900)
	for s in range(1, 6):
		var core: Dictionary = _simulate(s, 900, walk, false, false)
		var view: Dictionary = _simulate(s, 900, walk, false, true)
		out.append(GateUtil.res("R3-seed-%d" % s, core["chain"] == view["chain"],
			"portas abertas=%d %s" % [core["opened"], core["chain"].left(16)]))
	# R3 com IA: test_room + esqueleto e rato + demo_iter4.jsonl, com e sem view
	var d4: Dictionary = TraceIO.read(DEMO4_TRACE)
	var d4_in: Array = d4["inputs"]
	var e1: Dictionary = _simulate(1, d4_in.size(), d4_in, true, false, "", false, DEMO4_ENEMIES)
	var e2: Dictionary = _simulate(1, d4_in.size(), d4_in, true, true, "", false, DEMO4_ENEMIES)
	out.append(GateUtil.res("R3-enemies", d4["error"] == "" and e1["chain"] == e2["chain"] and not e1["type_error"],
		"%s %s" % [d4["error"] if d4["error"] != "" else "demo_iter4", e1["chain"].left(16)]))
	out.append(_demo4_test(d4))
	# Rodada 5: piloto (R1-pilot, R3-pilot) e execuções independentes do runner (R2, R4)
	var p1: Dictionary = _simulate(1, 3000, [], false, false, "", false, [], Pilot.create(1))
	var p2: Dictionary = _simulate(1, 3000, [], false, false, "", false, [], Pilot.create(1))
	out.append(GateUtil.res("R1-pilot", p1["chain"] == p2["chain"] and not p1["type_error"],
		"terminal=%s %s" % [p1["terminal"], p1["chain"].left(16)]))
	var v1: Dictionary = _simulate(2, 3000, [], false, false, "", false, [], Pilot.create(2))
	var v2: Dictionary = _simulate(2, 3000, [], false, true, "", false, [], Pilot.create(2))
	out.append(GateUtil.res("R3-pilot", v1["chain"] == v2["chain"] and not v1["type_error"],
		"terminal=%s %s" % [v1["terminal"], v1["chain"].left(16)]))
	out.append(_r2_test())
	out.append(_r4_test())
	out.append(_types_test())
	out.append(_scene_test())
	out.append(_asset_test())
	out.append(_showcase_test())
	return out


## Executa o runner num processo novo; devolve o relatório JSON (ou {} em erro).
func _run_runner(args: Array, tag: String) -> Dictionary:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(TMP_DIR))
	var report: String = ProjectSettings.globalize_path("%s/%s.json" % [TMP_DIR, tag])
	var argv: Array = ["--headless", "--path", ProjectSettings.globalize_path("res://"), "-s", RUNNER, "--"]
	argv.append_array(args)
	argv.append("--output=%s" % report)
	var lines: Array = []
	var code: int = OS.execute(OS.get_executable_path(), argv, lines, true)
	if code != 0:
		return {}
	var f := FileAccess.open(report, FileAccess.READ)
	if f == null:
		return {}
	var v: Variant = JSON.parse_string(f.get_as_text())
	return v if typeof(v) == TYPE_DICTIONARY else {}


## R2: duas execuções independentes do runner (piloto, semente 1, 3000 ticks) -> chain_final iguais.
func _r2_test() -> Dictionary:
	var args: Array = ["--seed=1", "--mode=pilot", "--ticks=3000"]
	var a: Dictionary = _run_runner(args, "r2_a")
	var b: Dictionary = _run_runner(args, "r2_b")
	var ok: bool = not a.is_empty() and not b.is_empty() and a["chain_final"] == b["chain_final"]
	return GateUtil.res("R2", ok, "terminal=%s terminal_tick=%s %s" % [
		a.get("terminal", "?"), str(int(a.get("terminal_tick", -1))), String(a.get("chain_final", "erro")).left(16)])


## R4: piloto gravado (--record) e reproduzido (--mode=replay) nas sementes 1..3 -> chain_final iguais.
func _r4_test() -> Dictionary:
	var ok: bool = true
	var parts: Array = []
	for s in range(1, 4):
		var trace: String = ProjectSettings.globalize_path("%s/r4_s%d.jsonl" % [TMP_DIR, s])
		var rec: Dictionary = _run_runner(["--seed=%d" % s, "--mode=pilot", "--ticks=6000", "--record=%s" % trace], "r4_rec_%d" % s)
		var rep: Dictionary = _run_runner(["--seed=%d" % s, "--mode=replay", "--ticks=6000", "--trace=%s" % trace], "r4_rep_%d" % s)
		var same: bool = not rec.is_empty() and not rep.is_empty() and rec["chain_final"] == rep["chain_final"]
		ok = ok and same
		parts.append("s%d=%s(%s)" % [s, "ok" if same else "DIFERE", rec.get("terminal", "?")])
	return GateUtil.res("R4", ok, " ".join(parts))


func _lint_test() -> Dictionary:
	var script: String = ProjectSettings.globalize_path("res://").path_join("../tools/lint_sim.py").simplify_path()
	var lines: Array = []
	var code: int = OS.execute("python3", [script], lines, true)
	var txt: String = "".join(lines).strip_edges()
	return GateUtil.res("LINT", code == 0, txt.get_slice("\n", txt.get_slice_count("\n") - 1))


## DEMO-4 (plano 4 §6.1): a trilha de demonstração mostra bloqueio, abate, porta e rato acordado.
func _demo4_test(tr: Dictionary) -> Dictionary:
	if tr["error"] != "":
		return GateUtil.res("DEMO-4", false, tr["error"])
	var w := WorldSim.create(1, true)
	for en: Array in DEMO4_ENEMIES:
		w.add_enemy(en[0], DungeonGen.cell_center_u(en[1]), DungeonGen.cell_center_u(en[2]))
	var sk: EntitySim = w.enemies[0]
	var rat: EntitySim = w.enemies[1]
	var blocked: Array = []
	for i: IntInput in tr["inputs"]:
		var hp0: int = w.player.hp
		w.step(i)
		var lost: int = hp0 - w.player.hp
		if sk.state == "STRIKE" and lost > 0 and lost < 12:
			blocked.append("t%d -%d" % [w.tick, lost])
	var ok: bool = sk.state == "DEAD" and not blocked.is_empty() and w.get_cell(15, 7) == Grid.DOOR_OPEN \
		and rat.awake and w.player.hp > 0
	return GateUtil.res("DEMO-4", ok, "%d ticks; esqueleto=%s bloqueio=%s porta=%d rato awake=%s state=%s hp=%d" % [
		w.tick, sk.state, ",".join(blocked), w.get_cell(15, 7), rat.awake, rat.state, w.player.hp])


## enemies[] e automap.visited_sha256 reais passam na guarda de tipos (sem float).
func _types_test() -> Dictionary:
	var w := WorldSim.create(1, true)
	w.add_dummy(6349, 15360)
	for t in range(1, 31):
		var i := IntInput.make(0, 0, 0)
		i.attack = t == 1
		w.step(i)
	var s: Dictionary = StateHash.canon(w)
	var enemies: Array = s["enemies"]
	var sha: String = s["automap"]["visited_sha256"]
	var ok: bool = StateHash.assert_types(s) and not w.type_error and enemies.size() == 1 \
		and (enemies[0] as Dictionary).size() == 8 and enemies[0]["hp"] == 75 and sha.length() == 64
	return GateUtil.res("TYPES", ok, "enemies=%s visited_sha256=%s" % [JSON.stringify(enemies), sha.left(16)])


func _scene_test() -> Dictionary:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.attach_world(WorldSim.create(1, true))
	root.add_child(main)
	var player: Node = main.get_node_or_null("Player")
	var ok: bool = player is CharacterBody3D
	var detail: String = "player=%s" % (player.get_class() if player else "null")
	var cam: Camera3D = player.get_node_or_null("Camera3D") if player else null
	ok = ok and cam != null and is_equal_approx(cam.position.y, 1.5)
	if cam:
		detail += " cam_y=%.2f" % cam.position.y
	# yaw em angle=0 aponta a câmera para +X do Godot (+X da simulação)
	main.advance(IntInput.new())
	var fwd: Vector3 = -cam.global_transform.basis.z if cam else Vector3.ZERO
	ok = ok and fwd.x > 0.99
	detail += " fwd=(%.2f,%.2f,%.2f)" % [fwd.x, fwd.y, fwd.z]
	ok = ok and main.get_node_or_null("DungeonView/Doors/door_0") != null
	# camadas da rodada 2
	for n: String in ["WeaponView", "HUD", "AutomapOverlay"]:
		if main.get_node_or_null(n) == null:
			ok = false
			detail += " sem %s" % n
	# rótulos numéricos da HUD antes do primeiro tick (plano 4 §4.2)
	for pair: Array in [["HUD/Frame/HpText", "Vida 100/100"], ["HUD/Frame/SpText", "Vigor 100/100"]]:
		var lb: Label = main.get_node_or_null(pair[0]) as Label
		ok = ok and lb != null and lb.text == pair[1]
		detail += " %s=%s" % [String(pair[0]).get_file(), ("\"%s\"" % lb.text) if lb else "null"]
	var wv: Node = main.get_node_or_null("WeaponView")
	for n: String in ["Sword", "Shield"]:
		var tr: TextureRect = wv.get_node_or_null(n) if wv else null
		var good: bool = tr != null and tr.texture != null and tr.texture.get_size() == Vector2(32, 32) \
			and tr.size == Vector2(128, 128) and tr.scale == Vector2.ONE
		ok = ok and good
		detail += " %s=%s" % [n, "128x128" if good else "ERRO"]
	root.remove_child(main)
	main.free()
	# boneco como Sprite3D billboard
	var md: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	var wd := WorldSim.create(1, true)
	wd.add_dummy(DungeonGen.cell_center_u(8), DungeonGen.cell_center_u(4))
	md.attach_world(wd)
	root.add_child(md)
	var en: Sprite3D = md.get_node_or_null(ENEMY_NODE) as Sprite3D
	var e_ok: bool = en != null and en.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y \
		and is_equal_approx(en.pixel_size, 0.05)
	ok = ok and e_ok
	detail += " %s=%s" % [ENEMY_NODE, "Sprite3D billboard 0.05" if e_ok else "ERRO"]
	root.remove_child(md)
	md.free()
	var m6: Array = _scene_m6()
	return GateUtil.res("SCENE", ok and m6[0], detail + m6[1])


## SCENE (rodada 5): itens billboard, tela final, rótulos novos e geometria/fonte da HUD.
func _scene_m6() -> Array:
	var ok: bool = true
	var detail: String = ""
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	var w := WorldSim.create(1, false)
	main.attach_world(w)
	root.add_child(main)
	var items_root: Node = main.get_node_or_null("Items")
	var n_items: int = items_root.get_child_count() if items_root else -1
	var it_ok: bool = n_items == w.items.size()
	for it: Dictionary in w.get_items():
		var sp: Sprite3D = main.get_node_or_null("Items/item_%d" % it["id"]) as Sprite3D
		var px: float = 0.015625 if it["type"] == "key" else 0.0125
		it_ok = it_ok and sp != null and sp.billboard == BaseMaterial3D.BILLBOARD_FIXED_Y \
			and is_equal_approx(sp.pixel_size, px) and sp.visible
	ok = ok and it_ok
	detail += " Items=%d/%d%s" % [n_items, w.items.size(), "" if it_ok else " ERRO"]
	for pair: Array in HUD_INITIAL:
		var lb: Label = main.get_node_or_null(pair[0]) as Label
		ok = ok and lb != null and lb.text == pair[1]
		detail += " %s=%s" % [String(pair[0]).get_file(), ("\"%s\"" % lb.text) if lb else "null"]
	var rects: Array = []
	var geo_ok: bool = true
	for n: String in HUD_LABELS:
		var lb: Label = main.get_node_or_null("HUD/Frame/" + n) as Label
		if lb == null:
			geo_ok = false
			continue
		var r := Rect2(lb.position, lb.size)
		geo_ok = geo_ok and lb.get_theme_font_size("font_size") == 12 and Rect2(0, 0, 640, 48).encloses(r)
		for o: Rect2 in rects:
			geo_ok = geo_ok and not o.intersects(r)
		rects.append(r)
	ok = ok and geo_ok
	detail += " HUD fonte12/retângulos=%s" % ("ok" if geo_ok else "ERRO")
	var es: CanvasLayer = main.get_node_or_null("EndScreen") as CanvasLayer
	var es_ok: bool = es != null and es.layer == 4 and not es.visible
	if es != null:
		w.terminal = "ESCAPED"
		main._present([], null)
		var title: Label = es.get_node_or_null("Panel/Title") as Label
		es_ok = es_ok and es.visible and title != null and title.text == "VOCÊ ESCAPOU!"
	ok = ok and es_ok
	detail += " EndScreen=%s" % ("layer4 oculto->\"VOCÊ ESCAPOU!\"" if es_ok else "ERRO")
	root.remove_child(main)
	main.free()
	return [ok, detail]


## VITRINE: main.tscn em modo vitrine (piloto) por 600 _physics_process simulados.
func _showcase_test() -> Dictionary:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.force_showcase = true
	root.add_child(main)
	var w: WorldSim = main.world
	var start: Array = [w.player.cell_x(), w.player.cell_z()]
	for _k in range(600):
		main._physics_process(1.0 / 60.0)
	var now: Array = [w.player.cell_x(), w.player.cell_z()]
	var ok: bool = w.seed_value == 1 and w.tick == 600 and now != start and not w.type_error \
		and ["NONE", "ESCAPED", "DEAD", "TIMEOUT"].has(w.terminal)
	var detail: String = "tick=%d célula %s->%s terminal=%s itens coletados=%d" % [
		w.tick, str(start), str(now), w.terminal, w.get_items().filter(func(it: Dictionary) -> bool: return it["taken"]).size()]
	root.remove_child(main)
	main.free()
	return GateUtil.res("VITRINE", ok, detail)


func _asset_test() -> Dictionary:
	var missing: Array = []
	for id: String in ASSETS_R1:
		if not AssetResolver.exists(id):
			missing.append(id)
		elif (ENEMY_ASSETS.has(id) or ITEM_ASSETS.has(id)) and AssetResolver.texture(id).get_size() != Vector2(32, 32):
			missing.append(id + "(!32x32)")
	return GateUtil.res("ASSETS", missing.is_empty(), "faltando: %s" % ",".join(missing) if missing else "%d identificadores" % ASSETS_R1.size())
