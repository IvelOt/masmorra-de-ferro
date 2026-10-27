extends RefCounted
## Gerador de masmorra (M2) e salas de teste fixas (M1/M2). Só inteiros, PCG32 próprio.

const FM = preload("res://sim/fixed_math.gd")
const Grid = preload("res://sim/grid.gd")
const Pcg32 = preload("res://sim/rng_pcg32.gd")

const ROOMS_MIN: int = 6
const ROOMS_MAX: int = 9
const ROOM_SIZE_MIN: int = 4
const ROOM_SIZE_MAX: int = 9
const ROOM_TRIES: int = 200
const ROOM_MARGIN: int = 2
const LOOP_CHANCE_NUM: int = 15
const LOOP_CHANCE_DEN: int = 100
const GEN_TRIES: int = 50
const MIN_EXIT_DIST: int = 20

## Vizinhança 4 na ordem N, L, S, O.
const DIRS: Array = [[0, -1], [1, 0], [0, 1], [-1, 0]]

var rng: Pcg32 = null
var attempts_used: int = 0
var exit_distance: int = 0


## Sala de teste de M1: FLOOR em cx ∈ [2, 21], cz ∈ [2, 13]; spawn no centro de (3, 7).
static func test_room() -> Grid:
	var g: Grid = Grid.new()
	_fill_rect(g, 2, 2, 20, 12, Grid.FLOOR, 0)
	g.rooms = [{"id": 0, "x": 2, "z": 2, "w": 20, "h": 12, "cx": 3, "cz": 7}]
	g.spawn_x = Grid.cell_center(3)
	g.spawn_z = Grid.cell_center(7)
	g.spawn_angle = 0
	return g


## Duas salas ligadas por corredor cz = 4 com DOOR_CLOSED em (8, 4); spawn no centro de (4, 4).
static func test_door_room() -> Grid:
	var g: Grid = Grid.new()
	_fill_rect(g, 2, 2, 5, 5, Grid.FLOOR, 0)
	_fill_rect(g, 10, 2, 5, 5, Grid.FLOOR, 1)
	for cx in range(7, 10):
		g.set_cell(cx, 4, Grid.FLOOR)
	g.set_cell(8, 4, Grid.DOOR_CLOSED)
	g.rooms = [
		{"id": 0, "x": 2, "z": 2, "w": 5, "h": 5, "cx": 4, "cz": 4},
		{"id": 1, "x": 10, "z": 2, "w": 5, "h": 5, "cx": 12, "cz": 4},
	]
	g.spawn_x = Grid.cell_center(4)
	g.spawn_z = Grid.cell_center(4)
	g.spawn_angle = 0
	return g


## Arena de demonstração (plano da rodada 3 §4.9): sala 0 em x ∈ [2, 13], z ∈ [2, 11]; corredor
## (14, 6)–(16, 6) com DOOR_LOCKED em (15, 6); Sala da Saída x ∈ [17, 21], z ∈ [4, 8] com EXIT em
## (19, 6); spawn no centro de (3, 6), olhando para L.
static func test_arena() -> Grid:
	var g: Grid = Grid.new()
	_fill_rect(g, 2, 2, 12, 10, Grid.FLOOR, 0)
	_fill_rect(g, 17, 4, 5, 5, Grid.FLOOR, 1)
	g.set_cell(14, 6, Grid.FLOOR)
	g.set_cell(16, 6, Grid.FLOOR)
	g.set_cell(15, 6, Grid.DOOR_LOCKED)
	g.set_cell(19, 6, Grid.EXIT)
	g.rooms = [
		{"id": 0, "x": 2, "z": 2, "w": 12, "h": 10, "cx": 8, "cz": 7},
		{"id": 1, "x": 17, "z": 4, "w": 5, "h": 5, "cx": 19, "cz": 6},
	]
	g.exit_room = 1
	g.spawn_x = Grid.cell_center(3)
	g.spawn_z = Grid.cell_center(6)
	g.spawn_angle = 0
	return g


static func _fill_rect(g: Grid, x: int, z: int, w: int, h: int, t: int, rid: int) -> void:
	for cz in range(z, z + h):
		for cx in range(x, x + w):
			g.set_cell(cx, cz, t)
			g.set_room_id(cx, cz, rid)


static func manhattan(a: Dictionary, b: Dictionary) -> int:
	return FM.abs_i(int(a.cx) - int(b.cx)) + FM.abs_i(int(a.cz) - int(b.cz))


func generate(seed_value: int) -> Grid:
	rng = Pcg32.new(seed_value, Pcg32.STREAM_DUNGEON)
	var g: Grid = null
	for attempt in range(GEN_TRIES):
		g = Grid.new()
		if _try_generate(g):
			attempts_used = attempt + 1
			return g
	attempts_used = GEN_TRIES
	push_error("dungeon_gen: %d tentativas falharam para a semente %d" % [GEN_TRIES, seed_value])
	return g


func _try_generate(g: Grid) -> bool:
	# 1. salas
	var n: int = rng.range_incl(ROOMS_MIN, ROOMS_MAX)
	var rooms: Array = []
	for _t in range(ROOM_TRIES):
		if rooms.size() >= n:
			break
		var w: int = rng.range_incl(ROOM_SIZE_MIN, ROOM_SIZE_MAX)
		var h: int = rng.range_incl(ROOM_SIZE_MIN, ROOM_SIZE_MAX)
		var x: int = rng.range_incl(2, 62 - w)
		var z: int = rng.range_incl(2, 62 - h)
		var ok: bool = true
		for r: Dictionary in rooms:
			var ox: int = r.x
			var oz: int = r.z
			if x - ROOM_MARGIN < ox + int(r.w) and ox < x + w + ROOM_MARGIN \
					and z - ROOM_MARGIN < oz + int(r.h) and oz < z + h + ROOM_MARGIN:
				ok = false
				break
		if ok:
			var rid: int = rooms.size()
			rooms.append({
				"id": rid, "x": x, "z": z, "w": w, "h": h,
				"cx": x + FM.div_trunc(w, 2), "cz": z + FM.div_trunc(h, 2),
			})
			_fill_rect(g, x, z, w, h, Grid.FLOOR, rid)
	g.rooms = rooms
	var count: int = rooms.size()
	if count < ROOMS_MIN:
		return false
	# 2. árvore geradora mínima de Prim
	var in_tree: Array = []
	in_tree.resize(count)
	in_tree.fill(false)
	in_tree[0] = true
	var edges: Array = []
	for _k in range(count - 1):
		var bd: int = -1
		var bu: int = -1
		var bv: int = -1
		for u in range(count):
			if not in_tree[u]:
				continue
			for v in range(count):
				if in_tree[v]:
					continue
				var d: int = manhattan(rooms[u], rooms[v])
				if bd < 0 or d < bd or (d == bd and (v < bv or (v == bv and u < bu))):
					bd = d
					bu = u
					bv = v
		edges.append([bu, bv])
		in_tree[bv] = true
	# 3. laços: pares fora da árvore entre os 2 vizinhos mais próximos
	var nearest: Array = []
	for i in range(count):
		var best1: int = -1
		var best2: int = -1
		for j in range(count):
			if j == i:
				continue
			if best1 < 0 or _closer(rooms, i, j, best1):
				best2 = best1
				best1 = j
			elif best2 < 0 or _closer(rooms, i, j, best2):
				best2 = j
		nearest.append([best1, best2])
	var loops: Array = []
	for i in range(count):
		for j in range(i + 1, count):
			if _has_edge(edges, i, j):
				continue
			if not (nearest[i] as Array).has(j):
				continue
			if rng.chance(LOOP_CHANCE_NUM, LOOP_CHANCE_DEN):
				loops.append([i, j])
	# 4. corredores em L
	for e: Array in edges + loops:
		var a: Dictionary = rooms[e[0]]
		var b: Dictionary = rooms[e[1]]
		var bit: int = rng.next_bounded(2)
		if bit == 0:
			_carve_h(g, a.cx, b.cx, a.cz)
			_carve_v(g, a.cz, b.cz, b.cx)
		else:
			_carve_v(g, a.cz, b.cz, a.cx)
			_carve_h(g, a.cx, b.cx, b.cz)
	# 5. portas onde o corredor entra numa sala
	for cz in range(Grid.GRID_H):
		for cx in range(Grid.GRID_W):
			if g.get_cell(cx, cz) != Grid.FLOOR or g.get_room_id(cx, cz) >= 0:
				continue
			if not _touches_room(g, cx, cz, -1):
				continue
			if door_pattern_ok(g, cx, cz):
				g.set_cell(cx, cz, Grid.DOOR_CLOSED)
	# 6. sala da saída por BFS
	var r0: Dictionary = rooms[0]
	var dist: PackedInt32Array = bfs(g, r0.cx, r0.cz)
	var exit_id: int = -1
	var exit_d: int = -1
	for r: Dictionary in rooms:
		var d: int = dist[Grid.index_of(r.cx, r.cz)]
		if d > exit_d:
			exit_d = d
			exit_id = r.id
	# 7. validação
	if exit_id <= 0 or exit_d < MIN_EXIT_DIST:
		return false
	var er: Dictionary = rooms[exit_id]
	var exit_doors: Array = []
	for cz in range(int(er.z), int(er.z) + int(er.h)):
		for cx in range(int(er.x), int(er.x) + int(er.w)):
			for dv: Array in DIRS:
				var nx: int = cx + int(dv[0])
				var nz: int = cz + int(dv[1])
				var t: int = g.get_cell(nx, nz)
				if t == Grid.SOLID or g.get_room_id(nx, nz) == exit_id:
					continue
				if not Grid.is_door(t):
					return false
				exit_doors.append([nx, nz])
	for i in range(Grid.GRID_W * Grid.GRID_H):
		if g.cells[i] != Grid.SOLID and dist[i] < 0:
			return false
	for p: Array in exit_doors:
		g.set_cell(p[0], p[1], Grid.DOOR_LOCKED)
	g.set_cell(er.cx, er.cz, Grid.EXIT)
	g.exit_room = exit_id
	exit_distance = exit_d
	# 8. spawn
	g.spawn_x = Grid.cell_center(r0.cx)
	g.spawn_z = Grid.cell_center(r0.cz)
	g.spawn_angle = 0
	return true


## j está mais perto de i do que k (Manhattan, desempate por menor id).
static func _closer(rooms: Array, i: int, j: int, k: int) -> bool:
	var dj: int = manhattan(rooms[i], rooms[j])
	var dk: int = manhattan(rooms[i], rooms[k])
	return dj < dk or (dj == dk and j < k)


static func _has_edge(edges: Array, i: int, j: int) -> bool:
	for e: Array in edges:
		if (e[0] == i and e[1] == j) or (e[0] == j and e[1] == i):
			return true
	return false


static func _carve(g: Grid, cx: int, cz: int) -> void:
	if g.get_cell(cx, cz) == Grid.SOLID:
		g.set_cell(cx, cz, Grid.FLOOR)
		g.set_room_id(cx, cz, -1)


static func _carve_h(g: Grid, x0: int, x1: int, cz: int) -> void:
	var s: int = FM.sign_i(x1 - x0)
	var x: int = x0
	_carve(g, x, cz)
	while x != x1:
		x += s
		_carve(g, x, cz)


static func _carve_v(g: Grid, z0: int, z1: int, cx: int) -> void:
	var s: int = FM.sign_i(z1 - z0)
	var z: int = z0
	_carve(g, cx, z)
	while z != z1:
		z += s
		_carve(g, cx, z)


## Célula 4-adjacente a uma sala (qualquer sala se rid < 0).
static func _touches_room(g: Grid, cx: int, cz: int, rid: int) -> bool:
	for dv: Array in DIRS:
		var r: int = g.get_room_id(cx + int(dv[0]), cz + int(dv[1]))
		if r >= 0 and (rid < 0 or r == rid):
			return true
	return false


## Padrão de porta: passável nos dois lados opostos e SOLID nos outros dois.
static func door_pattern_ok(g: Grid, cx: int, cz: int) -> bool:
	var n_open: bool = g.get_cell(cx, cz - 1) != Grid.SOLID
	var s_open: bool = g.get_cell(cx, cz + 1) != Grid.SOLID
	var e_open: bool = g.get_cell(cx + 1, cz) != Grid.SOLID
	var w_open: bool = g.get_cell(cx - 1, cz) != Grid.SOLID
	return (n_open and s_open and not e_open and not w_open) \
		or (e_open and w_open and not n_open and not s_open)


## BFS em vizinhança 4 (N, L, S, O) sobre células não SOLID; -1 = inalcançável.
static func bfs(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.GRID_W * Grid.GRID_H)
	dist.fill(-1)
	if g.get_cell(sx, sz) == Grid.SOLID:
		return dist
	var queue: PackedInt32Array = PackedInt32Array()
	var start: int = Grid.index_of(sx, sz)
	dist[start] = 0
	queue.append(start)
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % Grid.GRID_W
		var cz: int = FM.div_trunc(cur, Grid.GRID_W)
		for dv: Array in DIRS:
			var nx: int = cx + int(dv[0])
			var nz: int = cz + int(dv[1])
			if g.get_cell(nx, nz) == Grid.SOLID:
				continue
			var ni: int = Grid.index_of(nx, nz)
			if dist[ni] >= 0:
				continue
			dist[ni] = dist[cur] + 1
			queue.append(ni)
	return dist
