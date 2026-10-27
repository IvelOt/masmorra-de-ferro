class_name GateM5
extends RefCounted
## M5-A1..A6: automapa (plano da iteração 5 §5.1).

const A2_TRACE: String = "m5_a2_corridor_seed1.jsonl"
const SEEDS: int = 20
const A3_TICKS: int = 1200
const A4_SEED: int = 1337
const A4_TAB_EVERY: int = 37
const A6_TICKS: int = 30
const CORRIDOR_MAX_TICKS: int = 1500
const CORRIDOR_SETTLE: int = 30
## Distância ao centro da última célula para parar (u).
const CORRIDOR_STOP_U: int = 512
const OVERLAY_SCENE: String = "res://view/automap_overlay.tscn"
const MAIN_SCENE: String = "res://view/main.tscn"


static func run(r: GateReport, tree: SceneTree) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r, tree)
	_a5(r, tree)
	await _a6(r, tree)


## Retângulo da sala inicial expandido em 1 e recortado a [0, 63].
static func _start_rect(g: Grid) -> Array:
	var room: Dictionary = g.rooms[g.start_room]
	return [maxi(int(room["x"]) - 1, 0), maxi(int(room["z"]) - 1, 0),
		mini(int(room["x"]) + int(room["w"]), Grid.W - 1), mini(int(room["z"]) + int(room["h"]), Grid.H - 1)]


static func _a1(r: GateReport) -> void:
	var fails: Array = []
	for s: int in range(1, SEEDS + 1):
		var sim: WorldSim = WorldSim.new(s)
		sim.step(IntInput.new())
		var rect: Array = _start_rect(sim.grid)
		var room: Dictionary = sim.grid.rooms[sim.grid.start_room]
		var ok: bool = sim.automap.count() == (int(room["w"]) + 2) * (int(room["h"]) + 2)
		for cz: int in range(Grid.H):
			for cx: int in range(Grid.W):
				var inside: bool = cx >= int(rect[0]) and cx <= int(rect[2]) and cz >= int(rect[1]) and cz <= int(rect[3])
				if sim.automap.is_visited(cx, cz) != inside:
					ok = false
		if not ok:
			fails.append(s)
	r.check("M5-A1", fails.is_empty(), "sementes 1..%d: visited = sala inicial + contorno, contagem (w+2)(h+2); falhas=%s" % [SEEDS, str(fails)])


## Caminho BFS da porta de m2_a6 até a sala vizinha, sem entrar na sala inicial;
## para na célula anterior ao contorno (anel de paredes/portas) da outra sala.
static func corridor_path(g: Grid, door: Array) -> Array:
	var start: Dictionary = g.rooms[g.start_room]
	var parent: Dictionary = {}
	var sx: int = int(door[0])
	var sz: int = int(door[1])
	parent[sz * Grid.W + sx] = -1
	var queue: Array = [sz * Grid.W + sx]
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx & 63
		var cz: int = idx >> 6
		for d: Array in DungeonGen.DIRS:
			var nx: int = cx + int(d[0])
			var nz: int = cz + int(d[1])
			var nidx: int = nz * Grid.W + nx
			if not Grid.in_bounds(nx, nz) or parent.has(nidx) or g.get_cell(nx, nz) == Grid.SOLID \
					or DungeonGen.in_room(start, nx, nz):
				continue
			parent[nidx] = idx
			if _near_other_room(g, nx, nz):
				var path: Array = []
				var k: int = idx
				while k >= 0:
					path.push_front([k & 63, k >> 6])
					k = int(parent[k])
				return path
			queue.append(nidx)
	return []


## Célula no retângulo expandido (sala + contorno) de uma sala que não é a inicial.
static func _near_other_room(g: Grid, cx: int, cz: int) -> bool:
	for room: Dictionary in g.rooms:
		if int(room["id"]) == g.start_room:
			continue
		if cx >= int(room["x"]) - 1 and cx <= int(room["x"]) + int(room["w"]) \
				and cz >= int(room["z"]) - 1 and cz <= int(room["z"]) + int(room["h"]):
			return true
	return false


## Trilha de M5-A2 (semente 1, sem inimigos): pose de GateM2.a6_setup, `use` na
## porta e caminhada em malha fechada pelo caminho de corridor_path.
static func corridor_setup() -> Dictionary:
	var sim: WorldSim = WorldSim.new(1, false, false)
	var setup: Dictionary = GateM2.a6_setup(sim.grid)
	var h: Dictionary = setup["header"]
	sim.set_player_pose(int(h["pos_x"]), int(h["pos_z"]), int(h["angle"]))
	var path: Array = corridor_path(sim.grid, setup["door"])
	var out: Array = [IntInput.new(0, 0, 0, false, false, true)]
	sim.step(out[0])
	var i: int = 0
	var settle: int = 0
	while out.size() < CORRIDOR_MAX_TICKS and settle < CORRIDOR_SETTLE and not path.is_empty():
		var pcx: int = PilotSim.cell_of(sim.player.pos_x)
		var pcz: int = PilotSim.cell_of(sim.player.pos_z)
		while i < path.size() - 1 and pcx == int(path[i][0]) and pcz == int(path[i][1]):
			i += 1
		var tx: int = PilotSim.center(int(path[i][0]))
		var tz: int = PilotSim.center(int(path[i][1]))
		var inp: IntInput = IntInput.new()
		var last: bool = i == path.size() - 1
		var near: bool = maxi(absi(tx - sim.player.pos_x), absi(tz - sim.player.pos_z)) <= CORRIDOR_STOP_U
		if last and near:
			settle += 1
		else:
			var a: Array = PilotSim.aim(sim.player, tx, tz)
			inp = IntInput.new(1 if bool(a[1]) else 0, 0, int(a[0]))
		out.append(inp)
		sim.step(inp)
	return {"header": h, "inputs": out, "path": path}


static func _a2(r: GateReport) -> void:
	var setup: Dictionary = corridor_setup()
	var tr: Variant = GateTraces.load_trace(A2_TRACE)
	var trace_ok: bool = tr != null and GateTraces.same_inputs(tr["inputs"], setup["inputs"]) \
		and tr["header"] == setup["header"]
	if not trace_ok:
		r.check("M5-A2", false, "trilha %s não confere com a geração" % A2_TRACE)
		return
	var h: Dictionary = tr["header"]
	var sim: WorldSim = WorldSim.new(1, false, false)
	sim.set_player_pose(int(h["pos_x"]), int(h["pos_z"]), int(h["angle"]))
	var trodden: Dictionary = {}
	for inp: IntInput in tr["inputs"]:
		sim.step(inp)
		var cx: int = PilotSim.cell_of(sim.player.pos_x)
		var cz: int = PilotSim.cell_of(sim.player.pos_z)
		var in_any: bool = false
		for room: Dictionary in sim.grid.rooms:
			if DungeonGen.in_room(room, cx, cz):
				in_any = true
		if not in_any:
			trodden[cz * Grid.W + cx] = [cx, cz]
	var missing: Array = []
	for c: Array in trodden.values():
		for dz: int in range(-1, 2):
			for dx: int in range(-1, 2):
				var nx: int = int(c[0]) + dx
				var nz: int = int(c[1]) + dz
				if Grid.in_bounds(nx, nz) and not sim.automap.is_visited(nx, nz):
					missing.append([nx, nz])
	var leaked: Array = []
	for room: Dictionary in sim.grid.rooms:
		if int(room["id"]) == sim.grid.start_room:
			continue
		for cz: int in range(int(room["z"]), int(room["z"]) + int(room["h"])):
			for cx: int in range(int(room["x"]), int(room["x"]) + int(room["w"])):
				if sim.automap.is_visited(cx, cz):
					leaked.append([cx, cz])
	var path: Array = setup["path"]
	var end_ok: bool = not path.is_empty() and PilotSim.cell_of(sim.player.pos_x) == int(path[-1][0]) \
		and PilotSim.cell_of(sim.player.pos_z) == int(path[-1][1])
	r.check("M5-A2", trodden.size() >= 3 and end_ok and missing.is_empty() and leaked.is_empty(),
		"%d células de corredor pisadas (caminho %d, chegou ao fim=%s); vizinhas-8 sem marca=%s; células de outra sala marcadas=%s" % [
			trodden.size(), path.size(), end_ok, str(missing), str(leaked)])


static func _a3(r: GateReport) -> void:
	var fails: Array = []
	for s: int in range(1, SEEDS + 1):
		var sim: WorldSim = WorldSim.new(s)
		var prev: PackedByteArray = sim.automap.visited.duplicate()
		var prev_n: int = sim.automap.count()
		for inp: IntInput in GateTraces.random_inputs(s, A3_TICKS, true):
			sim.step(inp)
			var cur: PackedByteArray = sim.automap.visited
			if cur == prev:
				continue
			var n: int = 0
			var bad: bool = false
			for i: int in range(cur.size()):
				n += cur[i]
				if prev[i] == 1 and cur[i] != 1:
					bad = true
			if bad or n < prev_n:
				fails.append([s, sim.tick])
				break
			prev = cur.duplicate()
			prev_n = n
	r.check("M5-A3", fails.is_empty(), "sementes 1..%d, %d ticks aleatórios: nenhuma célula volta a 0 e a contagem não decresce; falhas=%s" % [
		SEEDS, A3_TICKS, str(fails)])


static func tab_event(pressed: bool, echo: bool = false) -> InputEventKey:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = pressed
	ev.echo = echo
	return ev


## Cena dirigida pela trilha; com `tab`, Tab (pressionado e solto) a cada 37 ticks.
## Devolve [C_K, alternâncias de Map.visible].
static func _scene_chain(tree: SceneTree, inputs: Array, tab: bool) -> Array:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("configure", A4_SEED, false, true)
	tree.root.add_child(main)
	var overlay: AutomapOverlay = main.get_node("Automap") as AutomapOverlay
	var map: Control = overlay.get_node("Map") as Control
	var flips: int = 0
	var was: bool = map.visible
	for k: int in range(inputs.size()):
		if tab and k % A4_TAB_EVERY == 0:
			overlay._unhandled_input(tab_event(true))
			overlay._unhandled_input(tab_event(false))
		main.call("advance", inputs[k])
		if map.visible != was:
			flips += 1
			was = map.visible
	var chain: String = (main.get("sim") as WorldSim).chain
	tree.root.remove_child(main)
	main.free()
	return [chain, flips]


static func _a4(r: GateReport, tree: SceneTree) -> void:
	var inputs: Array = GateTraces.load_inputs(GateRepro.TRACE)
	var sim: WorldSim = WorldSim.new(A4_SEED)
	for inp: IntInput in inputs:
		sim.step(inp)
	var b: Array = _scene_chain(tree, inputs, true)
	var c: Array = _scene_chain(tree, inputs, false)
	r.check("M5-A4", inputs.size() == 600 and sim.chain == String(b[0]) and sim.chain == String(c[0]) and int(b[1]) >= 10,
		"C_K núcleo=%s, cena com Tab=%s, cena sem Tab=%s; Map.visible alternou %d vezes" % [
			sim.chain, b[0], c[0], int(b[1])])


static func _a5(r: GateReport, tree: SceneTree) -> void:
	var overlay: AutomapOverlay = (load(OVERLAY_SCENE) as PackedScene).instantiate() as AutomapOverlay
	tree.root.add_child(overlay)
	var map: Control = overlay.get_node("Map") as Control
	var seq: Array = [map.visible]
	overlay._unhandled_input(tab_event(true))
	seq.append(map.visible)
	overlay._unhandled_input(tab_event(false))
	seq.append(map.visible)
	overlay._unhandled_input(tab_event(true))
	seq.append(map.visible)
	overlay._unhandled_input(tab_event(false))
	overlay._unhandled_input(tab_event(true, true))
	seq.append(map.visible)
	var alpha: float = map.modulate.a
	var ok: bool = seq == [false, true, true, false, false] and alpha > 0.0 and alpha < 1.0 \
		and overlay.layer == 3 and map.size == Vector2(640, 312)
	r.check("M5-A5", ok, "visível início/Tab/solto/Tab/eco=%s alpha=%.2f layer=%d Map.size=%s" % [
		str(seq), alpha, overlay.layer, map.size])
	tree.root.remove_child(overlay)
	overlay.free()


static func _a6(r: GateReport, tree: SceneTree) -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("configure", 1, false, true)
	tree.root.add_child(main)
	var overlay: AutomapOverlay = main.get_node("Automap") as AutomapOverlay
	overlay.set_open(true)
	for _k: int in range(A6_TICKS):
		main.call("advance", IntInput.new())
		await tree.process_frame
	var draws: int = overlay.draw_count
	tree.root.remove_child(main)
	main.free()
	var src: String = FileAccess.get_file_as_string("res://view/automap_overlay.gd")
	var bad: Array = []
	for pat: String in ["mark(", "step(", "set_cell("]:
		if src.contains(pat):
			bad.append(pat)
	r.check("M5-A6", draws > 0 and bad.is_empty(), "overlay desenhou %d vezes em %d ticks com o mapa aberto; chamadas proibidas=%s" % [
		draws, A6_TICKS, str(bad)])
