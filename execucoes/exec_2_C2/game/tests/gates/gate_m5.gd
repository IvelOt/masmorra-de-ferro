extends RefCounted
## Gate M5 (automapa): M5-A1..A3 e X1 no núcleo; M5-A4 e A5 (cena em headless) em run_vis().

const Grid = preload("res://sim/grid.gd")
const DungeonGen = preload("res://sim/dungeon_gen.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const TraceIO = preload("res://input/trace_io.gd")
const AutomapSim = preload("res://sim/automap_sim.gd")
const GateM3 = preload("res://tests/gates/gate_m3.gd")
const Report = preload("res://tests/gates/gate_report.gd")

const CORRIDOR_TRACE: String = "res://tests/traces/m5_a2_corridor.jsonl"
const DEMO_TRACE: String = "res://tests/traces/demo_iter2.jsonl"
const MAIN_SCENE: String = "res://view/main.tscn"
const OVERLAY_SCENE: String = "res://view/automap_overlay.tscn"
const A4_TICKS: int = 180
const A4_TAB_TICKS: Array = [10, 50, 51, 120]


static func _note_error(r: Report, w: WorldSim) -> void:
	if w.hash_error:
		r.runtime_error = true


## Conjunto exato de células marcadas == retângulo inclusivo [x0, x1] × [z0, z1].
static func _visited_is_rect(w: WorldSim, x0: int, z0: int, x1: int, z1: int) -> bool:
	for cz in range(Grid.GRID_H):
		for cx in range(Grid.GRID_W):
			var inside: bool = cx >= x0 and cx <= x1 and cz >= z0 and cz <= z1
			if w.automap.is_visited(cx, cz) != inside:
				return false
	return true


static func run(r: Report) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_x1(r)


static func _a1(r: Report) -> void:
	var bad: Array = []
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	w.step(IntInput.new())
	var room_ok: bool = w.automap.count() == 308 and _visited_is_rect(w, 1, 1, 22, 14)
	var w2: WorldSim = WorldSim.new()
	w2.setup_test("door")
	w2.step(IntInput.new())
	var door_ok: bool = w2.automap.count() == 49 and _visited_is_rect(w2, 1, 1, 7, 7)
	for s in range(1, 101):
		var ws: WorldSim = WorldSim.new()
		ws.setup_seed(s)
		var zero_before: bool = ws.automap.count() == 0
		ws.step(IntInput.new())
		var r0: Dictionary = ws.grid.rooms[0]
		var x0: int = maxi(int(r0.x) - 1, 0)
		var z0: int = maxi(int(r0.z) - 1, 0)
		var x1: int = mini(int(r0.x) + int(r0.w), 63)
		var z1: int = mini(int(r0.z) + int(r0.h), 63)
		if not zero_before or not _visited_is_rect(ws, x0, z0, x1, z1):
			bad.append(s)
		_note_error(r, ws)
	r.check("M5-A1", room_ok and door_ok and bad.is_empty(),
		"test_room=%d células (%s); test_door_room=%d (%s); sementes com falha: %s" % [
			w.automap.count(), room_ok, w2.automap.count(), door_ok, str(bad)])


static func _a2(r: Report) -> void:
	var trace: Array = TraceIO.read_trace(CORRIDOR_TRACE)
	var w: WorldSim = WorldSim.new()
	w.setup_test("door")
	for inp: IntInput in trace:
		w.step(inp)
	_note_error(r, w)
	var set_ok: bool = true
	for cz in range(Grid.GRID_H):
		for cx in range(Grid.GRID_W):
			var want: bool = (cx >= 1 and cx <= 7 and cz >= 1 and cz <= 7) \
				or (cx >= 6 and cx <= 10 and cz >= 3 and cz <= 5)
			if w.automap.is_visited(cx, cz) != want:
				set_ok = false
	var am: AutomapSim = w.automap
	var cells_ok: bool = am.is_visited(7, 4) and am.is_visited(8, 4) and am.is_visited(9, 4) \
		and not am.is_visited(10, 2) and not am.is_visited(10, 6)
	var far_ok: bool = true
	for cz in range(Grid.GRID_H):
		for cx in range(11, Grid.GRID_W):
			if am.is_visited(cx, cz):
				far_ok = false
	var pos_ok: bool = w.player.pos_x == 19029 and Grid.cell_of(w.player.pos_x) == 9 and w.player.vel_x == 0
	r.check("M5-A2", trace.size() == 153 and am.count() == 58 and set_ok and cells_ok and far_ok and pos_ok,
		"linhas=%d células=%d conjunto=%s corredor=%s cx>=11 vazio=%s pos_x=%d célula=%d vel_x=%d" % [
			trace.size(), am.count(), set_ok, cells_ok, far_ok, w.player.pos_x, Grid.cell_of(w.player.pos_x),
			w.player.vel_x])


static func _a3(r: Report) -> void:
	var bad: Array = []
	for s in range(1, 11):
		var w: WorldSim = WorldSim.new()
		w.setup_seed(s)
		var prev: PackedByteArray = w.automap.visited.duplicate()
		var prev_n: int = 0
		for e: Dictionary in GateM3.a7_trace(GateM3.A7_SEED_FROM):
			GateM3.a7_step(w, e)
			var cur: PackedByteArray = w.automap.visited
			var n: int = w.automap.count()
			var mono: bool = n >= prev_n
			if mono:
				for i in range(cur.size()):
					if prev[i] == 1 and cur[i] == 0:
						mono = false
						break
			if not mono:
				bad.append("%d@%d" % [s, w.tick])
				break
			prev = cur.duplicate()
			prev_n = n
		_note_error(r, w)
	r.check("M5-A3", bad.is_empty(), "sementes 1..10, 600 ticks; falhas: %s" % str(bad))


static func _x1(r: Report) -> void:
	# porta aberta à mão; um mundo anda 1 célula para o corredor, o outro não
	var still: Array = []
	for walk: bool in [true, false, false]:
		var w: WorldSim = WorldSim.new()
		w.setup_test("door")
		w.grid.set_cell(8, 4, Grid.DOOR_OPEN)
		for _t in range(60):
			w.step(IntInput.new(1 if walk else 0, 0, 0))
		still.append([w.automap.sha256(), Grid.cell_of(w.player.pos_x)])
	var moved_diff: bool = still[0][0] != still[1][0] and int(still[0][1]) >= 7
	var same: bool = still[1][0] == still[2][0]
	r.check("M5-X1", moved_diff and same, "andou até a célula %d: sha distinto=%s; parados: sha igual=%s" % [
		still[0][1], moved_diff, same])


## M5-A4 e M5-A5: precisam da árvore (chamadas em _initialize de run_gates.gd).
static func run_vis(r: Report, root: Window) -> void:
	_a4(r, root)
	_a5(r, root)


static func _tab(root: Window, pressed: bool) -> void:
	var ev: InputEventKey = InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = pressed
	root.push_input(ev)


static func _a4(r: Report, root: Window) -> void:
	var trace: Array = TraceIO.read_trace(DEMO_TRACE)
	var n: int = mini(A4_TICKS, trace.size())
	var core: WorldSim = WorldSim.new()
	core.setup_seed(1)
	for k in range(n):
		core.step(trace[k])
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set("start_override", "seed:1")
	main.set("driven_externally", true)
	root.add_child(main)
	var overlay: Control = main.get_node("Automap/Overlay")
	var toggles: int = 0
	for k in range(n):
		if A4_TAB_TICKS.has(k + 1):
			var before: bool = overlay.visible
			_tab(root, true)
			_tab(root, false)
			if overlay.visible != before:
				toggles += 1
		main.call("tick_once", trace[k])
	var scene_world: WorldSim = main.get("world")
	var ok: bool = n == A4_TICKS and core.chain == scene_world.chain and core.chain != "" and toggles == 4 \
		and core.tick == scene_world.tick
	if scene_world.hash_error or core.hash_error:
		r.runtime_error = true
	root.remove_child(main)
	main.free()
	r.check("M5-A4", ok, "ticks=%d Tab alternou %d/4; C_K núcleo=%s cena=%s" % [
		n, toggles, core.chain, scene_world.chain])


static func _a5(r: Report, root: Window) -> void:
	var layer: Node = (load(OVERLAY_SCENE) as PackedScene).instantiate()
	root.add_child(layer)
	var overlay: Control = layer.get_node("Overlay")
	var v0: bool = overlay.visible
	_tab(root, true)
	_tab(root, false)
	var v1: bool = overlay.visible
	_tab(root, true)
	_tab(root, false)
	var v2: bool = overlay.visible
	var a: float = overlay.modulate.a
	var lay: int = (layer as CanvasLayer).layer if layer is CanvasLayer else -1
	root.remove_child(layer)
	layer.free()
	r.check("M5-A5", not v0 and v1 and not v2 and a > 0.0 and a < 1.0 and is_equal_approx(a, 0.6) and lay == 3,
		"visível: início=%s Tab=%s Tab=%s; modulate.a=%.2f; layer=%d" % [v0, v1, v2, a, lay])
