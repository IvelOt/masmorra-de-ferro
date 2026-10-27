class_name DungeonGen
extends RefCounted
## M2: gerador de masmorra por semente (plano da iteração 1 §3.2) e a sala de
## teste fixa de M1 (§2.4). Só inteiros; RNG próprio no fluxo STREAM_DUNGEON.

const STREAM_DUNGEON: int = 1
const STREAM_AI: int = 2
const STREAM_PILOT: int = 3

const ROOM_ATTEMPTS: int = 200
const ROOM_MARGIN: int = 2
const LOOP_MAX_DIST: int = 24
const LOOP_CHANCE: int = 15
const EXIT_MIN_DIST: int = 20
const MAX_REGEN: int = 50

const DIRS: Array = [[0, 1], [1, 0], [0, -1], [-1, 0]]

## Estado do RNG da masmorra após a última geração (entra no estado canônico).
var rng_state: int = 0
## Última tentativa rejeitada (devolvida só se as regerações se esgotarem).
var _last_fallback: Grid = null


## Sala de teste de M1: piso em cx∈[2,29], cz∈[2,13], pilar 2×2 em [20,21]×[10,11].
static func test_room() -> Grid:
	var g: Grid = Grid.new()
	for cz: int in range(2, 14):
		for cx: int in range(2, 30):
			g.set_cell(cx, cz, Grid.FLOOR)
	for cz: int in range(10, 12):
		for cx: int in range(20, 22):
			g.set_cell(cx, cz, Grid.SOLID)
	g.rooms = [{"id": 0, "x": 2, "z": 2, "w": 28, "h": 12}]
	g.start_room = 0
	g.exit_room = 0
	g.spawn_x = 4 * Grid.CELL + Grid.CELL / 2
	g.spawn_z = 7 * Grid.CELL + Grid.CELL / 2
	g.spawn_angle = 0
	return g


static func room_center(r: Dictionary) -> Array:
	return [int(r["x"]) + FixedMath.div_floor(int(r["w"]), 2),
		int(r["z"]) + FixedMath.div_floor(int(r["h"]), 2)]


static func manhattan(a: Array, b: Array) -> int:
	return FixedMath.abs_i(int(a[0]) - int(b[0])) + FixedMath.abs_i(int(a[1]) - int(b[1]))


static func in_room(r: Dictionary, cx: int, cz: int) -> bool:
	return cx >= int(r["x"]) and cx < int(r["x"]) + int(r["w"]) \
		and cz >= int(r["z"]) and cz < int(r["z"]) + int(r["h"])


func generate(p_seed: int) -> Grid:
	var rng: RngPcg32 = RngPcg32.new(p_seed, STREAM_DUNGEON)
	var g: Grid = null
	for _attempt: int in range(MAX_REGEN):
		g = _generate_once(rng)
		if g != null:
			rng_state = rng.state
			return g
	push_error("DungeonGen: semente %d esgotou %d regerações" % [p_seed, MAX_REGEN])
	rng_state = rng.state
	return _last_fallback


func _place_rooms(rng: RngPcg32) -> Array:
	var rooms: Array = []
	while true:
		rooms = []
		var n: int = rng.range_i(6, 9)
		for _t: int in range(ROOM_ATTEMPTS):
			if rooms.size() >= n:
				break
			var w: int = rng.range_i(4, 9)
			var h: int = rng.range_i(4, 9)
			var x: int = rng.range_i(1, Grid.W - 1 - w - 1)
			var z: int = rng.range_i(1, Grid.H - 1 - h - 1)
			var ok: bool = true
			for o: Dictionary in rooms:
				if x - ROOM_MARGIN < int(o["x"]) + int(o["w"]) and int(o["x"]) < x + w + ROOM_MARGIN \
						and z - ROOM_MARGIN < int(o["z"]) + int(o["h"]) and int(o["z"]) < z + h + ROOM_MARGIN:
					ok = false
					break
			if ok:
				rooms.append({"id": rooms.size(), "x": x, "z": z, "w": w, "h": h})
		if rooms.size() >= 6:
			break
	return rooms


## Prim a partir da sala 0; desempate: distância, id novo, id da árvore.
func _mst(centers: Array) -> Array:
	var n: int = centers.size()
	var in_tree: Array = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var edges: Array = []
	for _k: int in range(n - 1):
		var best_d: int = -1
		var best_new: int = -1
		var best_old: int = -1
		for v: int in range(n):
			if in_tree[v]:
				continue
			for u: int in range(n):
				if not in_tree[u]:
					continue
				var d: int = manhattan(centers[u], centers[v])
				if best_d < 0 or d < best_d or (d == best_d and v < best_new) \
						or (d == best_d and v == best_new and u < best_old):
					best_d = d
					best_new = v
					best_old = u
		in_tree[best_new] = true
		edges.append([best_old, best_new])
	return edges


func _carve_l(g: Grid, corridor: PackedByteArray, a: Array, b: Array, bit: int) -> void:
	var ax: int = int(a[0])
	var az: int = int(a[1])
	var bx: int = int(b[0])
	var bz: int = int(b[1])
	if bit == 0:
		_carve_h(g, corridor, ax, bx, az)
		_carve_v(g, corridor, az, bz, bx)
	else:
		_carve_v(g, corridor, az, bz, ax)
		_carve_h(g, corridor, ax, bx, bz)


func _carve_cell(g: Grid, corridor: PackedByteArray, cx: int, cz: int) -> void:
	if g.get_cell(cx, cz) == Grid.SOLID and Grid.in_bounds(cx, cz):
		g.set_cell(cx, cz, Grid.FLOOR)
		corridor[cz * Grid.W + cx] = 1


func _carve_h(g: Grid, corridor: PackedByteArray, x0: int, x1: int, z: int) -> void:
	var step: int = 1 if x1 >= x0 else -1
	var x: int = x0
	while true:
		_carve_cell(g, corridor, x, z)
		if x == x1:
			break
		x += step


func _carve_v(g: Grid, corridor: PackedByteArray, z0: int, z1: int, x: int) -> void:
	var step: int = 1 if z1 >= z0 else -1
	var z: int = z0
	while true:
		_carve_cell(g, corridor, x, z)
		if z == z1:
			break
		z += step


## Distâncias BFS (vizinhança-4) sobre células não SOLID; -1 = inalcançável.
static func bfs(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	if g.get_cell(sx, sz) == Grid.SOLID:
		return dist
	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(sz * Grid.W + sx)
	dist[sz * Grid.W + sx] = 0
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx & 63
		var cz: int = idx >> 6
		for d: Array in DIRS:
			var nx: int = cx + int(d[0])
			var nz: int = cz + int(d[1])
			if not Grid.in_bounds(nx, nz):
				continue
			var nidx: int = nz * Grid.W + nx
			if dist[nidx] >= 0 or g.cells[nidx] == Grid.SOLID:
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


## Porta válida: não-SOLID nos dois vizinhos de um eixo, SOLID nos dois do outro.
static func door_shape_ok(g: Grid, cx: int, cz: int) -> bool:
	var e: bool = g.get_cell(cx + 1, cz) != Grid.SOLID
	var w: bool = g.get_cell(cx - 1, cz) != Grid.SOLID
	var n: bool = g.get_cell(cx, cz + 1) != Grid.SOLID
	var s: bool = g.get_cell(cx, cz - 1) != Grid.SOLID
	return (e and w and not n and not s) or (n and s and not e and not w)


## Uma tentativa completa; null se violar M2-A3 ou faltar porta numa sala.
func _generate_once(rng: RngPcg32) -> Grid:
	var g: Grid = Grid.new()
	var rooms: Array = _place_rooms(rng)
	g.rooms = rooms
	for r: Dictionary in rooms:
		for cz: int in range(int(r["z"]), int(r["z"]) + int(r["h"])):
			for cx: int in range(int(r["x"]), int(r["x"]) + int(r["w"])):
				g.set_cell(cx, cz, Grid.FLOOR)
	var centers: Array = []
	for r: Dictionary in rooms:
		centers.append(room_center(r))
	var edges: Array = _mst(centers)
	var linked: Dictionary = {}
	for e: Array in edges:
		linked[mini(int(e[0]), int(e[1])) * 16 + maxi(int(e[0]), int(e[1]))] = true
	for i: int in range(rooms.size()):
		for j: int in range(i + 1, rooms.size()):
			if linked.has(i * 16 + j):
				continue
			if manhattan(centers[i], centers[j]) <= LOOP_MAX_DIST:
				if rng.range_i(0, 99) < LOOP_CHANCE:
					edges.append([i, j])
	var corridor: PackedByteArray = PackedByteArray()
	corridor.resize(Grid.W * Grid.H)
	corridor.fill(0)
	for e: Array in edges:
		var bit: int = rng.next_u32() & 1
		_carve_l(g, corridor, centers[int(e[0])], centers[int(e[1])], bit)
	# Portas: corredor vizinho-4 de célula de sala (logo fora do retângulo).
	var candidates: Array = []
	for cz: int in range(Grid.H):
		for cx: int in range(Grid.W):
			if corridor[cz * Grid.W + cx] == 0:
				continue
			var touches: bool = false
			for r: Dictionary in rooms:
				for d: Array in DIRS:
					if in_room(r, cx + int(d[0]), cz + int(d[1])):
						touches = true
			if touches:
				g.set_cell(cx, cz, Grid.DOOR_CLOSED)
				candidates.append([cx, cz])
	# Validação M2-A4 (só depende de SOLID vs não-SOLID, logo independe da ordem).
	for c: Array in candidates:
		if not door_shape_ok(g, int(c[0]), int(c[1])):
			g.set_cell(int(c[0]), int(c[1]), Grid.FLOOR)
	# >= 1 porta por sala (toda sala tem corredor, pela MST).
	for r: Dictionary in rooms:
		if _room_doors(g, r).is_empty():
			_last_fallback = g
			return null
	# Sala da Saída: maior distância BFS do centro da sala 0; desempate menor id.
	var c0: Array = centers[0]
	var dist: PackedInt32Array = bfs(g, int(c0[0]), int(c0[1]))
	var best: int = 0
	var best_d: int = -1
	for i: int in range(rooms.size()):
		var c: Array = centers[i]
		var d: int = dist[int(c[1]) * Grid.W + int(c[0])]
		if d > best_d:
			best_d = d
			best = i
	if best == 0 or best_d < EXIT_MIN_DIST:
		_last_fallback = g
		return null
	g.start_room = 0
	g.exit_room = best
	for dc: Array in _room_doors(g, rooms[best]):
		g.set_cell(int(dc[0]), int(dc[1]), Grid.DOOR_LOCKED)
	var ce: Array = centers[best]
	g.set_cell(int(ce[0]), int(ce[1]), Grid.EXIT)
	g.spawn_x = int(c0[0]) * Grid.CELL + Grid.CELL / 2
	g.spawn_z = int(c0[1]) * Grid.CELL + Grid.CELL / 2
	g.spawn_angle = 0
	return g


## Células de porta vizinhas-4 do retângulo da sala.
static func _room_doors(g: Grid, r: Dictionary) -> Array:
	var out: Array = []
	var x0: int = int(r["x"]) - 1
	var x1: int = int(r["x"]) + int(r["w"])
	var z0: int = int(r["z"]) - 1
	var z1: int = int(r["z"]) + int(r["h"])
	for cz: int in range(z0, z1 + 1):
		for cx: int in range(x0, x1 + 1):
			var corner: bool = (cx == x0 or cx == x1) and (cz == z0 or cz == z1)
			if corner or in_room(r, cx, cz):
				continue
			if Grid.is_door_type(g.get_cell(cx, cz)):
				out.append([cx, cz])
	return out
