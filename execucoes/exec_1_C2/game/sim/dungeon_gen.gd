class_name DungeonGen
extends RefCounted
## Sala de teste fixa (M1) e gerador de masmorra por semente (M2).
## Só usa o fluxo PCG da masmorra (seq = 1).

const MAX_ROOM_TRIES: int = 200
const MAX_LAYOUT_TRIES: int = 50
const LOOP_MAX_DIST: int = 24
const LOOP_CHANCE: int = 15
const MIN_EXIT_DIST: int = 20

var grid: Grid
var rooms: Array[Dictionary] = []     # {id, x, z, w, h}
var start_room: int = 0
var exit_room: int = -1
var exit_cell: Array[int] = []        # [cx, cz]
var doors: Array[Dictionary] = []     # {id, cx, cz}, ordenadas por id
var start_pos: Array[int] = []        # [pos_x, pos_z]
var layout_tries: int = 0
var rng: RngPcg32 = null              # fluxo 1 após a grade pronta (posicionamento de M4)
var ok: bool = false

var _edges: Array[Array] = []         # [a, b] na ordem de escavação
var _edge_paths: Array[Array] = []    # células [cx, cz] escavadas por aresta
var _corridor: Dictionary = {}        # index -> true (células escavadas)


## Sala de teste permanente de M1 (plano §4.4).
static func test_room() -> DungeonGen:
	var d: DungeonGen = DungeonGen.new()
	d.grid = Grid.new()
	d.grid.fill_rect(1, 1, 14, 14, Grid.FLOOR)
	d.grid.fill_rect(10, 10, 11, 11, Grid.SOLID)
	d.grid.set_cell(15, 4, Grid.DOOR_CLOSED)
	d.grid.set_cell(15, 11, Grid.DOOR_OPEN)
	d.grid.fill_rect(16, 1, 21, 14, Grid.FLOOR)
	d.rooms = [{"id": 0, "x": 1, "z": 1, "w": 14, "h": 14}, {"id": 1, "x": 16, "z": 1, "w": 6, "h": 14}]
	d.start_pos = [2 * Grid.CELL + 1024, 7 * Grid.CELL + 1024]
	d._collect_doors()
	d.ok = true
	return d


static func generate(seed_value: int) -> DungeonGen:
	var d: DungeonGen = DungeonGen.new()
	var rng: RngPcg32 = RngPcg32.create(seed_value, RngPcg32.STREAM_DUNGEON)
	for attempt in range(MAX_LAYOUT_TRIES):
		d.layout_tries = attempt + 1
		if d._try_layout(rng):
			d.ok = true
			break
	if not d.ok:
		push_error("DungeonGen: semente %d esgotou %d tentativas" % [seed_value, MAX_LAYOUT_TRIES])
	d.rng = rng
	d._collect_doors()
	return d


func _try_layout(rng: RngPcg32) -> bool:
	grid = Grid.new()
	rooms = []
	exit_room = -1
	exit_cell = []
	_edges = []
	_edge_paths = []
	_corridor = {}
	# 1. salas
	var n: int = 6 + rng.next_range(4)
	var tries: int = 0
	while rooms.size() < n and tries < MAX_ROOM_TRIES:
		tries += 1
		var w: int = 4 + rng.next_range(6)
		var h: int = 4 + rng.next_range(6)
		var x: int = 2 + rng.next_range(64 - w - 4)
		var z: int = 2 + rng.next_range(64 - h - 4)
		var clash: bool = false
		for r: Dictionary in rooms:
			if x - 2 < r.x + r.w and r.x < x + w + 2 and z - 2 < r.z + r.h and r.z < z + h + 2:
				clash = true
				break
		if not clash:
			rooms.append({"id": rooms.size(), "x": x, "z": z, "w": w, "h": h})
	for r: Dictionary in rooms:
		grid.fill_rect(r.x, r.z, r.x + r.w - 1, r.z + r.h - 1, Grid.FLOOR)
	if rooms.size() < 6:
		return false
	# 2. MST de Prim
	var count: int = rooms.size()
	var in_tree: Array[bool] = []
	in_tree.resize(count)
	in_tree.fill(false)
	in_tree[0] = true
	var tree_pairs: Dictionary = {}
	for _k in range(count - 1):
		var best_d: int = -1
		var best_src: int = -1
		var best_dst: int = -1
		for dst in range(count):
			if in_tree[dst]:
				continue
			for src in range(count):
				if not in_tree[src]:
					continue
				var dd: int = _room_dist(src, dst)
				if best_d < 0 or dd < best_d or (dd == best_d and (dst < best_dst or (dst == best_dst and src < best_src))):
					best_d = dd
					best_src = src
					best_dst = dst
		in_tree[best_dst] = true
		_edges.append([best_src, best_dst])
		tree_pairs[mini(best_src, best_dst) * 64 + maxi(best_src, best_dst)] = true
	# 3. laços
	for i in range(count):
		for j in range(i + 1, count):
			if tree_pairs.has(i * 64 + j):
				continue
			if _room_dist(i, j) <= LOOP_MAX_DIST and rng.next_range(100) < LOOP_CHANCE:
				_edges.append([i, j])
	# 4. corredores em L
	for e: Array in _edges:
		var a: Array[int] = _center(e[0])
		var b: Array[int] = _center(e[1])
		var path: Array = []
		if rng.next_range(2) == 0:
			_carve_h(a[0], b[0], a[1], path)
			_carve_v(a[1], b[1], b[0], path)
		else:
			_carve_v(a[1], b[1], a[0], path)
			_carve_h(a[0], b[0], b[1], path)
		_edge_paths.append(path)
	# 5. portas
	var door_cells: Array[int] = []
	for cz in range(Grid.SIZE):
		for cx in range(Grid.SIZE):
			if not _corridor.has(cz * Grid.SIZE + cx) or _room_at(cx, cz) >= 0:
				continue
			if _adjacent_room(cx, cz) < 0:
				continue
			if _door_shape_ok(cx, cz):
				door_cells.append(cz * Grid.SIZE + cx)
	for idx in door_cells:
		grid.cells[idx] = Grid.DOOR_CLOSED
	# 6. sala da saída
	var c0: Array[int] = _center(0)
	var dist: PackedInt32Array = bfs(grid, c0[0], c0[1])
	var best: int = -1
	var best_dist: int = -1
	for r: Dictionary in rooms:
		var c: Array[int] = _center(r.id)
		var dv: int = dist[c[1] * Grid.SIZE + c[0]]
		if dv > best_dist:
			best_dist = dv
			best = r.id
	exit_room = best
	var ec: Array[int] = _center(exit_room)
	exit_cell = [ec[0], ec[1]]
	for idx in door_cells:
		if _adjacent_to_room(idx % Grid.SIZE, idx / Grid.SIZE, exit_room):
			grid.cells[idx] = Grid.DOOR_LOCKED
	grid.set_cell(ec[0], ec[1], Grid.EXIT)
	start_room = 0
	start_pos = [c0[0] * Grid.CELL + 1024, c0[1] * Grid.CELL + 1024]
	# 7. validação
	if exit_room == 0 or best_dist < MIN_EXIT_DIST:
		return false
	var reach: PackedInt32Array = bfs(grid, c0[0], c0[1])
	for i in range(Grid.SIZE * Grid.SIZE):
		if grid.cells[i] != Grid.SOLID and reach[i] < 0:
			return false
	for k in range(_edges.size()):
		var e: Array = _edges[k]
		if e[0] == exit_room or e[1] == exit_room:
			continue
		for cell: Array in _edge_paths[k]:
			if _in_room(cell[0], cell[1], exit_room):
				return false
	return true


## BFS vizinhança-4 sobre células não sólidas (portas e EXIT passáveis).
## Devolve a distância por índice, -1 se inalcançável.
static func bfs(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.SIZE * Grid.SIZE)
	dist.fill(-1)
	if g.get_cell(sx, sz) == Grid.SOLID:
		return dist
	var queue: PackedInt32Array = PackedInt32Array([sz * Grid.SIZE + sx])
	dist[queue[0]] = 0
	var head: int = 0
	var dxs: Array[int] = [1, 0, -1, 0]
	var dzs: Array[int] = [0, 1, 0, -1]
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % Grid.SIZE
		var cz: int = cur / Grid.SIZE
		for k in range(4):
			var nx: int = cx + dxs[k]
			var nz: int = cz + dzs[k]
			if g.get_cell(nx, nz) == Grid.SOLID:
				continue
			var ni: int = nz * Grid.SIZE + nx
			if dist[ni] >= 0:
				continue
			dist[ni] = dist[cur] + 1
			queue.append(ni)
	return dist


func _center(id: int) -> Array[int]:
	var r: Dictionary = rooms[id]
	return [r.x + (r.w >> 1), r.z + (r.h >> 1)]


func _room_dist(a: int, b: int) -> int:
	var ca: Array[int] = _center(a)
	var cb: Array[int] = _center(b)
	return FixedMath.abs_i(ca[0] - cb[0]) + FixedMath.abs_i(ca[1] - cb[1])


func _carve(cx: int, cz: int, path: Array) -> void:
	path.append([cx, cz])
	if grid.get_cell(cx, cz) == Grid.SOLID:
		grid.set_cell(cx, cz, Grid.FLOOR)
		_corridor[cz * Grid.SIZE + cx] = true


func _carve_h(x0: int, x1: int, z: int, path: Array) -> void:
	var s: int = 1 if x1 >= x0 else -1
	var x: int = x0
	while true:
		_carve(x, z, path)
		if x == x1:
			break
		x += s


func _carve_v(z0: int, z1: int, x: int, path: Array) -> void:
	var s: int = 1 if z1 >= z0 else -1
	var z: int = z0
	while true:
		_carve(x, z, path)
		if z == z1:
			break
		z += s


func _in_room(cx: int, cz: int, id: int) -> bool:
	var r: Dictionary = rooms[id]
	return cx >= r.x and cx < r.x + r.w and cz >= r.z and cz < r.z + r.h


func _room_at(cx: int, cz: int) -> int:
	for r: Dictionary in rooms:
		if _in_room(cx, cz, r.id):
			return r.id
	return -1


func _adjacent_to_room(cx: int, cz: int, id: int) -> bool:
	return _in_room(cx + 1, cz, id) or _in_room(cx - 1, cz, id) \
		or _in_room(cx, cz + 1, id) or _in_room(cx, cz - 1, id)


func _adjacent_room(cx: int, cz: int) -> int:
	for r: Dictionary in rooms:
		if _adjacent_to_room(cx, cz, r.id):
			return r.id
	return -1


## Passável (não sólido) em dois lados opostos e sólido nos outros dois.
func _door_shape_ok(cx: int, cz: int) -> bool:
	return door_shape_ok(grid, cx, cz)


static func door_shape_ok(g: Grid, cx: int, cz: int) -> bool:
	var e: bool = g.get_cell(cx + 1, cz) != Grid.SOLID
	var w: bool = g.get_cell(cx - 1, cz) != Grid.SOLID
	var s: bool = g.get_cell(cx, cz + 1) != Grid.SOLID
	var n: bool = g.get_cell(cx, cz - 1) != Grid.SOLID
	return (e and w and not s and not n) or (s and n and not e and not w)


func _collect_doors() -> void:
	doors = []
	for cz in range(Grid.SIZE):
		for cx in range(Grid.SIZE):
			if Grid.is_door_type(grid.get_cell(cx, cz)):
				doors.append({"id": doors.size(), "cx": cx, "cz": cz})
