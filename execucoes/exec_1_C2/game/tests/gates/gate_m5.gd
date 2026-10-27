extends RefCounted
## Acceptance Gate de M5 (plano da rodada 3, §9.2): M5-A1 a M5-A5.
## M5-A4 e M5-A5 instanciam cenas: chamar a partir de _process.

const GateM1 = preload("res://tests/gates/gate_m1.gd")
const MAIN_SCENE: String = "res://view/main.tscn"
const OVERLAY_SCENE: String = "res://view/automap_overlay.tscn"


static func run(results: Array[Dictionary]) -> void:
	_a1(results)
	_a2(results)
	_a3(results)
	_a4(results)
	_a5(results)


## Conjunto de índices marcados.
static func _marked(w: WorldSim) -> Array[int]:
	var out: Array[int] = []
	for i in range(Grid.SIZE * Grid.SIZE):
		if w.automap.visited[i] == 1:
			out.append(i)
	return out


static func _rect_set(x0: int, z0: int, x1: int, z1: int) -> Array[int]:
	var out: Array[int] = []
	for z in range(maxi(z0, 0), mini(z1, Grid.SIZE - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, Grid.SIZE - 1) + 1):
			out.append(z * Grid.SIZE + x)
	out.sort()
	return out


static func _a1(results: Array[Dictionary]) -> void:
	var bad: String = ""
	var t: WorldSim = WorldSim.create(1, "test")
	t.step(IntInput.new())
	var got: Array[int] = _marked(t)
	if got != _rect_set(0, 0, 15, 15):
		bad = "test: %d células marcadas (esperado 256 de [0,15]x[0,15])" % got.size()
	for s in range(1, 101):
		if bad != "":
			break
		var w: WorldSim = WorldSim.create(s, "dungeon")
		w.step(IntInput.new())
		var r: Dictionary = w.dungeon.rooms[0]
		var exp: Array[int] = _rect_set(int(r.x) - 1, int(r.z) - 1, int(r.x) + int(r.w), int(r.z) + int(r.h))
		var m: Array[int] = _marked(w)
		if m != exp or m.size() != (int(r.w) + 2) * (int(r.h) + 2):
			bad = "semente %d: %d marcadas, esperado %d" % [s, m.size(), (int(r.w) + 2) * (int(r.h) + 2)]
	GateM1.check(results, "M5-A1", bad == "", "test = [0,15]^2; masmorra = sala 0 com contorno", bad)


static func _center_of(r: Dictionary) -> Array[int]:
	return [int(r.x) + (int(r.w) >> 1), int(r.z) + (int(r.h) >> 1)]


## Caminho BFS (lista de índices) do centro da sala 0 ao centro da sala mais próxima.
static func _path_to_nearest(w: WorldSim) -> Array[int]:
	var c0: Array[int] = _center_of(w.dungeon.rooms[0])
	var dist: PackedInt32Array = DungeonGen.bfs(w.grid, c0[0], c0[1])
	var best: int = -1
	var best_d: int = -1
	for r: Dictionary in w.dungeon.rooms:
		if int(r.id) == 0:
			continue
		var c: Array[int] = _center_of(r)
		var dv: int = dist[c[1] * Grid.SIZE + c[0]]
		if dv >= 0 and (best_d < 0 or dv < best_d):
			best_d = dv
			best = int(r.id)
	var cd: Array[int] = _center_of(w.dungeon.rooms[best])
	var path: Array[int] = [cd[1] * Grid.SIZE + cd[0]]
	var cur: int = path[0]
	while dist[cur] > 0:
		var cx: int = cur % Grid.SIZE
		var cz: int = cur / Grid.SIZE
		for k in range(4):
			var ni: int = (cz + EnemySim.NDZ[k]) * Grid.SIZE + cx + EnemySim.NDX[k]
			if Grid.in_bounds(cx + EnemySim.NDX[k], cz + EnemySim.NDZ[k]) and dist[ni] == dist[cur] - 1:
				cur = ni
				break
		path.push_front(cur)
	return path


static func _near_corridor(i: int, corridor: Array[int]) -> bool:
	for c in corridor:
		if maxi(absi(c % Grid.SIZE - i % Grid.SIZE), absi(c / Grid.SIZE - i / Grid.SIZE)) <= 1:
			return true
	return false


static func _a2(results: Array[Dictionary]) -> void:
	var bad: String = ""
	for s in range(1, 6):
		var w: WorldSim = WorldSim.create(s, "dungeon")
		for d: Dictionary in w.dungeon.doors:
			w.grid.set_cell(d.cx, d.cz, Grid.DOOR_OPEN)
		for e in w.enemies:
			e.state = EnemySim.DEAD
		var path: Array[int] = _path_to_nearest(w)
		var dest: int = w.automap.room_of[path[path.size() - 1]]
		var on_path_rooms: Array[int] = []
		for i in path:
			var r: int = w.automap.room_of[i]
			if r >= 0 and not on_path_rooms.has(r):
				on_path_rooms.append(r)
		var corridor_seen: Array[int] = []
		var entered: bool = false
		for i in path:
			w.player.pos_x = (i % Grid.SIZE) * Grid.CELL + 1024
			w.player.pos_z = (i / Grid.SIZE) * Grid.CELL + 1024
			w.step(IntInput.new())
			if w.automap.room_of[i] < 0:
				corridor_seen.append(i)
			if w.automap.room_of[i] == dest:
				entered = true
			if entered:
				continue
			# (ii) antes de entrar, só células a Chebyshev <= 1 de corredor já visitado
			var r: Dictionary = w.dungeon.rooms[dest]
			for cz in range(int(r.z), int(r.z) + int(r.h)):
				for cx in range(int(r.x), int(r.x) + int(r.w)):
					var ci: int = cz * Grid.SIZE + cx
					if w.automap.visited[ci] == 1 and not _near_corridor(ci, corridor_seen):
						bad = "semente %d tick %d: sala %d marcada antes da entrada em (%d, %d)" % [s, w.tick, dest, cx, cz]
			if bad != "":
				break
		if bad != "":
			break
		# (i) corredores do caminho marcados
		for c in corridor_seen:
			if w.automap.visited[c] != 1:
				bad = "semente %d: corredor %d não marcado" % [s, c]
		# (iii) salas fora do caminho
		for r: Dictionary in w.dungeon.rooms:
			if on_path_rooms.has(int(r.id)):
				continue
			for cz in range(int(r.z), int(r.z) + int(r.h)):
				for cx in range(int(r.x), int(r.x) + int(r.w)):
					var ci: int = cz * Grid.SIZE + cx
					if w.automap.visited[ci] == 1 and not _near_corridor(ci, corridor_seen):
						bad = "semente %d: sala %d fora do caminho marcada em (%d, %d)" % [s, r.id, cx, cz]
		if bad != "":
			break
	GateM1.check(results, "M5-A2", bad == "", "marcação por sala/corredor ao longo do caminho BFS", bad)


static func _random_input(rng: RngPcg32) -> IntInput:
	var inp: IntInput = IntInput.new()
	inp.move = rng.next_range(3) - 1
	inp.strafe = rng.next_range(3) - 1
	inp.turn = rng.next_range(257) - 128
	return inp


static func _monotonic(w: WorldSim, ticks: int) -> String:
	var rng: RngPcg32 = RngPcg32.create(1, RngPcg32.STREAM_PILOT)
	var prev: PackedByteArray = w.automap.visited.duplicate()
	var prev_n: int = w.automap.count()
	for k in range(ticks):
		w.step(_random_input(rng))
		var cur: PackedByteArray = w.automap.visited
		for i in range(cur.size()):
			if prev[i] == 1 and cur[i] == 0:
				return "tick %d: célula %d desmarcada" % [w.tick, i]
		var n: int = w.automap.count()
		if n < prev_n:
			return "tick %d: contagem caiu %d -> %d" % [w.tick, prev_n, n]
		prev = cur.duplicate()
		prev_n = n
	return ""


static func _a3(results: Array[Dictionary]) -> void:
	var bad: String = _monotonic(WorldSim.create(1, "test"), 600)
	if bad != "":
		bad = "test: " + bad
	for s in range(1, 6):
		if bad != "":
			break
		var v: String = _monotonic(WorldSim.create(s, "dungeon"), 600)
		if v != "":
			bad = "semente %d: %s" % [s, v]
	GateM1.check(results, "M5-A3", bad == "", "visited monotônico em 600 ticks aleatórios", bad)


static func _a4(results: Array[Dictionary]) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var a: WorldSim = WorldSim.create(7, "dungeon")
	var b: WorldSim = WorldSim.create(7, "dungeon")
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("attach_sim", b)
	tree.root.add_child(main)
	var overlay: CanvasLayer = main.get_node("Automap")
	var rng_a: RngPcg32 = RngPcg32.create(1, RngPcg32.STREAM_PILOT)
	var rng_b: RngPcg32 = RngPcg32.create(1, RngPcg32.STREAM_PILOT)
	var opens: int = 0
	var closes: int = 0
	for k in range(600):
		a.step(_random_input(rng_a))
		b.step(_random_input(rng_b))
		main.call("refresh_from_sim")
		if b.tick % 37 == 0:
			main.call("toggle_automap")
			if overlay.visible:
				opens += 1
			else:
				closes += 1
	tree.root.remove_child(main)
	main.free()
	var ok: bool = a.chain() == b.chain() and opens >= 8 and closes >= 8
	GateM1.check(results, "M5-A4", ok, "cadeias iguais e mapa aberto/fechado >= 8 vezes",
		"iguais=%s aberturas=%d fechamentos=%d" % [a.chain() == b.chain(), opens, closes])


static func _a5(results: Array[Dictionary]) -> void:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	var ov: CanvasLayer = (load(OVERLAY_SCENE) as PackedScene).instantiate()
	tree.root.add_child(ov)
	var states: Array[bool] = [ov.visible]
	for k in range(2):
		var ev: InputEventKey = InputEventKey.new()
		ev.keycode = KEY_TAB
		ev.physical_keycode = KEY_TAB
		ev.pressed = true
		ov.call("_unhandled_input", ev)
		states.append(ov.visible)
	var alpha: float = (ov.get_node("Map") as Control).modulate.a
	ov.call("_draw_map")
	tree.root.remove_child(ov)
	ov.free()
	var ok: bool = states == [false, true, false] and alpha > 0.0 and alpha < 1.0
	GateM1.check(results, "M5-A5", ok, "visible false->true->false, 0 < alpha < 1",
		"visible %s, alpha %.2f" % [str(states), alpha])
