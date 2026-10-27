class_name DungeonGen
extends RefCounted
## M2: gerador de masmorra por semente (só inteiros) e sala de teste fixa de M1.

const MAX_ATTEMPTS: int = 200
const MAX_RESTARTS: int = 64
const NEIGHBOR_DIST: int = 24
const LOOP_PERCENT: int = 15
const MIN_EXIT_DIST: int = 20


class Dungeon:
	extends RefCounted
	var grid: Grid = Grid.new()
	var rooms: Array = []        # {id, x, z, w, h} em células
	var start_room: int = 0
	var exit_room: int = -1
	var exit_cell: Dictionary = {"cx": -1, "cz": -1}
	var doors: Array = []        # {id, cx, cz} em ordem de cz*64+cx
	var player_start: Dictionary = {"pos_x": 0, "pos_z": 0, "angle": 0}
	var rng: RngPcg32 = null
	var valid: bool = true


static func room_center(r: Dictionary) -> Array:
	return [r["x"] + r["w"] / 2, r["z"] + r["h"] / 2]


static func cell_center_u(c: int) -> int:
	return c * Grid.CELL + Grid.CELL / 2


static func _collect_doors(d: Dungeon) -> void:
	d.doors = []
	for cz in range(Grid.H):
		for cx in range(Grid.W):
			var c: int = d.grid.get_cell(cx, cz)
			if c == Grid.DOOR_CLOSED or c == Grid.DOOR_OPEN or c == Grid.DOOR_LOCKED:
				d.doors.append({"id": d.doors.size(), "cx": cx, "cz": cz})


## Sala fixa de M1 (sem RNG): câmaras A e B separadas por parede x=15 com porta (15,7).
static func test_room(p_seed: int = 0) -> Dungeon:
	var d := Dungeon.new()
	for z in range(1, 15):
		for x in range(1, 15):
			d.grid.set_cell(x, z, Grid.FLOOR)
		for x in range(16, 23):
			d.grid.set_cell(x, z, Grid.FLOOR)
	d.grid.set_cell(15, 7, Grid.DOOR_CLOSED)
	d.rooms = [
		{"id": 0, "x": 1, "z": 1, "w": 14, "h": 14},
		{"id": 1, "x": 16, "z": 1, "w": 7, "h": 14},
	]
	d.start_room = 0
	_collect_doors(d)
	d.player_start = {"pos_x": cell_center_u(2), "pos_z": cell_center_u(7), "angle": 0}
	d.rng = RngPcg32.create(p_seed, RngPcg32.STREAM_DUNGEON)
	return d


## Fixture fixa de M5 (sem RNG): três salas 6x6 ligadas por dois corredores com portas nas pontas.
static func automap_fixture(p_seed: int = 0) -> Dungeon:
	var d := Dungeon.new()
	d.rooms = [
		{"id": 0, "x": 2, "z": 2, "w": 6, "h": 6},
		{"id": 1, "x": 16, "z": 2, "w": 6, "h": 6},
		{"id": 2, "x": 2, "z": 14, "w": 6, "h": 6},
	]
	for r: Dictionary in d.rooms:
		for z in range(r["z"], r["z"] + r["h"]):
			for x in range(r["x"], r["x"] + r["w"]):
				d.grid.set_cell(x, z, Grid.FLOOR)
	for x in range(8, 16):
		d.grid.set_cell(x, 5, Grid.FLOOR)
	for z in range(8, 14):
		d.grid.set_cell(5, z, Grid.FLOOR)
	d.grid.set_cell(8, 5, Grid.DOOR_CLOSED)
	d.grid.set_cell(15, 5, Grid.DOOR_CLOSED)
	d.grid.set_cell(5, 8, Grid.DOOR_CLOSED)
	d.grid.set_cell(5, 13, Grid.DOOR_CLOSED)
	d.start_room = 0
	d.exit_room = -1
	d.exit_cell = {"cx": -1, "cz": -1}
	_collect_doors(d)
	d.player_start = {"pos_x": cell_center_u(5), "pos_z": cell_center_u(5), "angle": 0}
	d.rng = RngPcg32.create(p_seed, RngPcg32.STREAM_DUNGEON)
	return d


static func _in_room(rooms: Array, cx: int, cz: int) -> int:
	for r: Dictionary in rooms:
		if cx >= r["x"] and cx < r["x"] + r["w"] and cz >= r["z"] and cz < r["z"] + r["h"]:
			return r["id"]
	return -1


static func _manhattan(a: Array, b: Array) -> int:
	return FixedMath.abs_i(a[0] - b[0]) + FixedMath.abs_i(a[1] - b[1])


## BFS-4 (ordem N, L, S, O) tratando toda célula não-SOLID como atravessável.
static func bfs(grid: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	if not grid.is_passable(sx, sz):
		return dist
	var queue := PackedInt32Array()
	queue.append(sz * Grid.W + sx)
	dist[sz * Grid.W + sx] = 0
	var head: int = 0
	var dxs: Array = [0, 1, 0, -1]
	var dzs: Array = [-1, 0, 1, 0]
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx % Grid.W
		var cz: int = idx / Grid.W
		for k in range(4):
			var nx: int = cx + dxs[k]
			var nz: int = cz + dzs[k]
			if grid.is_passable(nx, nz) and dist[nz * Grid.W + nx] < 0:
				dist[nz * Grid.W + nx] = dist[idx] + 1
				queue.append(nz * Grid.W + nx)
	return dist


## Padrão M2-A4: atravessável nos dois lados opostos, SOLID nos outros dois.
static func door_pattern_ok(grid: Grid, cx: int, cz: int) -> bool:
	var n: bool = grid.is_passable(cx, cz - 1)
	var s: bool = grid.is_passable(cx, cz + 1)
	var e: bool = grid.is_passable(cx + 1, cz)
	var w: bool = grid.is_passable(cx - 1, cz)
	return (n and s and not e and not w) or (e and w and not n and not s)


static func generate(p_seed: int) -> Dungeon:
	var rng := RngPcg32.create(p_seed, RngPcg32.STREAM_DUNGEON)
	for _restart in range(MAX_RESTARTS + 1):
		var d: Dungeon = _attempt(rng)
		if d != null and validate(d):
			d.rng = rng
			return d
	push_error("DungeonGen: reinícios esgotados para a semente %d" % p_seed)
	var bad := Dungeon.new()
	bad.valid = false
	bad.rng = rng
	return bad


static func _attempt(rng: RngPcg32) -> Dungeon:
	var d := Dungeon.new()
	# 1-3. salas por tentativa e rejeição
	var n_target: int = 6 + rng.bounded(4)
	var rooms: Array = []
	var attempts: int = 0
	while attempts < MAX_ATTEMPTS and rooms.size() < n_target:
		attempts += 1
		var w: int = 4 + rng.bounded(6)
		var h: int = 4 + rng.bounded(6)
		var x: int = 1 + rng.bounded(Grid.W - w - 2)
		var z: int = 1 + rng.bounded(Grid.H - h - 2)
		var ok: bool = true
		for r: Dictionary in rooms:
			if x - 2 < r["x"] + r["w"] and r["x"] < x + w + 2 and z - 2 < r["z"] + r["h"] and r["z"] < z + h + 2:
				ok = false
				break
		if ok:
			rooms.append({"id": rooms.size(), "x": x, "z": z, "w": w, "h": h})
	if rooms.size() < 6:
		return null
	d.rooms = rooms
	for r: Dictionary in rooms:
		for zz in range(r["z"], r["z"] + r["h"]):
			for xx in range(r["x"], r["x"] + r["w"]):
				d.grid.set_cell(xx, zz, Grid.FLOOR)
	var centers: Array = []
	for r: Dictionary in rooms:
		centers.append(room_center(r))
	var n: int = rooms.size()
	# 5. Prim (Manhattan; empate: menor destino, depois menor origem)
	var in_tree: Array = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var edges: Array = []
	var tree_set: Dictionary = {}
	for _step in range(n - 1):
		var best_d: int = -1
		var best_u: int = -1
		var best_v: int = -1
		for v in range(n):
			if in_tree[v]:
				continue
			for u in range(n):
				if not in_tree[u]:
					continue
				var dd: int = _manhattan(centers[u], centers[v])
				if best_d < 0 or dd < best_d:
					best_d = dd
					best_u = u
					best_v = v
		in_tree[best_v] = true
		edges.append([best_u, best_v])
		tree_set[FixedMath.min_i(best_u, best_v) * 16 + FixedMath.max_i(best_u, best_v)] = true
	# 6. laços
	for i in range(n):
		for j in range(i + 1, n):
			if tree_set.has(i * 16 + j):
				continue
			if _manhattan(centers[i], centers[j]) <= NEIGHBOR_DIST:
				if rng.bounded(100) < LOOP_PERCENT:
					edges.append([i, j])
	# 7. corredores em L
	var corridor := PackedByteArray()
	corridor.resize(Grid.W * Grid.H)
	corridor.fill(0)
	for e: Array in edges:
		var a: Array = centers[e[0]]
		var b: Array = centers[e[1]]
		var vertical_first: bool = rng.bounded(2) == 1
		var path: Array = []
		if vertical_first:
			_line(path, a[0], a[1], a[0], b[1])
			_line(path, a[0], b[1], b[0], b[1])
		else:
			_line(path, a[0], a[1], b[0], a[1])
			_line(path, b[0], a[1], b[0], b[1])
		for c: Array in path:
			if d.grid.get_cell(c[0], c[1]) == Grid.SOLID:
				d.grid.set_cell(c[0], c[1], Grid.FLOOR)
			if _in_room(rooms, c[0], c[1]) < 0:
				corridor[c[1] * Grid.W + c[0]] = 1
	# 8. portas
	for cz in range(Grid.H):
		for cx in range(Grid.W):
			if corridor[cz * Grid.W + cx] == 0:
				continue
			var adj: bool = _in_room(rooms, cx, cz - 1) >= 0 or _in_room(rooms, cx + 1, cz) >= 0 \
				or _in_room(rooms, cx, cz + 1) >= 0 or _in_room(rooms, cx - 1, cz) >= 0
			if adj and door_pattern_ok(d.grid, cx, cz):
				d.grid.set_cell(cx, cz, Grid.DOOR_CLOSED)
	# 9. sala da saída
	var c0: Array = centers[0]
	var dist: PackedInt32Array = bfs(d.grid, c0[0], c0[1])
	var exit_id: int = 0
	var exit_d: int = -1
	for r: Dictionary in rooms:
		var c: Array = centers[r["id"]]
		var dd: int = dist[c[1] * Grid.W + c[0]]
		if dd > exit_d:
			exit_d = dd
			exit_id = r["id"]
	d.exit_room = exit_id
	var er: Dictionary = rooms[exit_id]
	for cz in range(er["z"] - 1, er["z"] + er["h"] + 1):
		for cx in range(er["x"] - 1, er["x"] + er["w"] + 1):
			if d.grid.get_cell(cx, cz) == Grid.DOOR_CLOSED and _adjacent_to_room(er, cx, cz):
				d.grid.set_cell(cx, cz, Grid.DOOR_LOCKED)
	var ec: Array = centers[exit_id]
	d.grid.set_cell(ec[0], ec[1], Grid.EXIT)
	d.exit_cell = {"cx": ec[0], "cz": ec[1]}
	_collect_doors(d)
	# 11. início do jogador
	d.start_room = 0
	d.player_start = {"pos_x": cell_center_u(c0[0]), "pos_z": cell_center_u(c0[1]), "angle": 0}
	return d


static func _adjacent_to_room(r: Dictionary, cx: int, cz: int) -> bool:
	var rs: Array = [r]
	return _in_room(rs, cx, cz - 1) >= 0 or _in_room(rs, cx + 1, cz) >= 0 \
		or _in_room(rs, cx, cz + 1) >= 0 or _in_room(rs, cx - 1, cz) >= 0


static func _line(path: Array, x0: int, z0: int, x1: int, z1: int) -> void:
	var sx: int = FixedMath.sign_i(x1 - x0)
	var sz: int = FixedMath.sign_i(z1 - z0)
	var x: int = x0
	var z: int = z0
	path.append([x, z])
	while x != x1 or z != z1:
		x += sx if x != x1 else 0
		z += sz if z != z1 else 0
		path.append([x, z])


## Validação interna (A1-A4 e entradas da sala da saída). Pública para os gates.
static func validate(d: Dungeon) -> bool:
	return validation_errors(d).is_empty()


static func validation_errors(d: Dungeon) -> Array:
	var errs: Array = []
	var rooms: Array = d.rooms
	if rooms.size() < 6 or rooms.size() > 9:
		errs.append("A1: %d salas" % rooms.size())
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			var a: Dictionary = rooms[i]
			var b: Dictionary = rooms[j]
			if a["x"] - 2 < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] + 2 \
					and a["z"] - 2 < b["z"] + b["h"] and b["z"] < a["z"] + a["h"] + 2:
				errs.append("A1: salas %d e %d sobrepostas/sem margem" % [i, j])
	if rooms.is_empty():
		return errs
	var c0: Array = room_center(rooms[0])
	var dist: PackedInt32Array = bfs(d.grid, c0[0], c0[1])
	for cz in range(Grid.H):
		for cx in range(Grid.W):
			if d.grid.is_passable(cx, cz) and dist[cz * Grid.W + cx] < 0:
				errs.append("A2: célula (%d,%d) inalcançável" % [cx, cz])
				break
	if d.exit_room <= 0:
		errs.append("A3: exit_room == %d" % d.exit_room)
	else:
		var ce: Array = room_center(rooms[d.exit_room])
		var de: int = dist[ce[1] * Grid.W + ce[0]]
		if de < MIN_EXIT_DIST:
			errs.append("A3: distância %d < %d" % [de, MIN_EXIT_DIST])
		# toda entrada da sala da saída é uma porta trancada válida
		var er: Dictionary = rooms[d.exit_room]
		for cz in range(er["z"] - 1, er["z"] + er["h"] + 1):
			for cx in range(er["x"] - 1, er["x"] + er["w"] + 1):
				if _in_room([er], cx, cz) >= 0 or not _adjacent_to_room(er, cx, cz):
					continue
				if d.grid.is_passable(cx, cz) and d.grid.get_cell(cx, cz) != Grid.DOOR_LOCKED:
					errs.append("saída: entrada (%d,%d) sem porta trancada" % [cx, cz])
	for dr: Dictionary in d.doors:
		if not door_pattern_ok(d.grid, dr["cx"], dr["cz"]):
			errs.append("A4: porta (%d,%d) inválida" % [dr["cx"], dr["cz"]])
	return errs
