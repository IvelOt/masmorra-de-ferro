class_name DungeonGen
extends RefCounted
## M2: gerador de masmorra por semente e salas de teste (plano §4.2, §3.4, §4.4).

const FixedMath = preload("res://sim/fixed_math.gd")
const Grid = preload("res://sim/grid.gd")
const PCG32 = preload("res://sim/rng_pcg32.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const ItemsSim = preload("res://sim/items_sim.gd")

const MAX_ATTEMPTS: int = 64
const MAX_ROOM_DRAWS: int = 200
const MIN_ROOMS: int = 6
const MIN_EXIT_DIST: int = 20
const LOOP_MAX_DIST: int = 24
const LOOP_PERCENT: int = 15
## Piso a piso >= 4 células (contornos a >= 2 células).
const MIN_FLOOR_GAP: int = 4
## M6: sorteios de célula de item antes do fallback por varredura.
const ITEM_CELL_DRAWS: int = 32


static func _spawn_of(cx: int, cz: int) -> Dictionary:
	return {"spawn_x": cx * Grid.CELL + Grid.CELL / 2, "spawn_z": cz * Grid.CELL + Grid.CELL / 2}


## Sala de teste de M1: 14x14 de piso com pilar 2x2.
static func test_room() -> Dictionary:
	var g := Grid.new()
	for z in range(1, 15):
		for x in range(1, 15):
			g.set_cell(x, z, Grid.FLOOR)
	for z in range(10, 12):
		for x in range(10, 12):
			g.set_cell(x, z, Grid.SOLID)
	var d: Dictionary = {
		"grid": g, "rooms": [], "start_room": 0, "exit_room": -1, "doors": [], "attempts": 0,
	}
	d.merge(_spawn_of(2, 4))
	return d


## test_room() + coluna sólida em x = 8 com porta fechada em (8, 4).
static func test_room_door() -> Dictionary:
	var d: Dictionary = test_room()
	var g: Grid = d["grid"]
	for z in range(1, 15):
		g.set_cell(8, z, Grid.SOLID)
	g.set_cell(8, 4, Grid.DOOR_CLOSED)
	d["doors"] = [{"id": 0, "cell_x": 8, "cell_z": 4}]
	return d


## Gera a masmorra. Consome `rng` (fluxo STREAM_DUNGEON) e devolve {} se as
## MAX_ATTEMPTS tentativas falharem.
static func generate(seed_value: int, rng: PCG32 = null) -> Dictionary:
	if rng == null:
		rng = PCG32.new(seed_value, PCG32.STREAM_DUNGEON)
	for attempt in range(1, MAX_ATTEMPTS + 1):
		var res: Dictionary = _try_generate(rng)
		if not res.is_empty():
			res["attempts"] = attempt
			return res
	push_error("DungeonGen: semente %d falhou em %d tentativas" % [seed_value, MAX_ATTEMPTS])
	return {}


static func manhattan(a: Dictionary, b: Dictionary) -> int:
	return FixedMath.abs_i(a["cx"] - b["cx"]) + FixedMath.abs_i(a["cz"] - b["cz"])


## Verdadeiro se os pisos ficam a menos de MIN_FLOOR_GAP células nos dois eixos.
static func rooms_too_close(x: int, z: int, w: int, h: int, r: Dictionary) -> bool:
	var rx: int = r["x"]
	var rz: int = r["z"]
	var rw: int = r["w"]
	var rh: int = r["h"]
	var sep_x: bool = x - (rx + rw - 1) >= MIN_FLOOR_GAP or rx - (x + w - 1) >= MIN_FLOOR_GAP
	var sep_z: bool = z - (rz + rh - 1) >= MIN_FLOOR_GAP or rz - (z + h - 1) >= MIN_FLOOR_GAP
	return not (sep_x or sep_z)


## Células do contorno sem os cantos: [[x, z, eixo_perpendicular_e_z], ...].
static func outline_cells(r: Dictionary) -> Array:
	var out: Array = []
	var x: int = r["x"]
	var z: int = r["z"]
	var w: int = r["w"]
	var h: int = r["h"]
	for cx in range(x, x + w):
		out.append([cx, z - 1, true])
		out.append([cx, z + h, true])
	for cz in range(z, z + h):
		out.append([x - 1, cz, false])
		out.append([x + w, cz, false])
	return out


## Porta válida: passável (não sólido) nos dois lados de um eixo, SOLID nos dois do outro.
static func door_ok(g: Grid, x: int, z: int) -> bool:
	var zn: bool = g.get_cell(x, z - 1) != Grid.SOLID and g.get_cell(x, z + 1) != Grid.SOLID
	var xs: bool = g.get_cell(x - 1, z) == Grid.SOLID and g.get_cell(x + 1, z) == Grid.SOLID
	var xn: bool = g.get_cell(x - 1, z) != Grid.SOLID and g.get_cell(x + 1, z) != Grid.SOLID
	var zs: bool = g.get_cell(x, z - 1) == Grid.SOLID and g.get_cell(x, z + 1) == Grid.SOLID
	return (zn and xs) or (xn and zs)


## BFS vizinhança-4 com todas as portas abertas; -1 = inalcançável.
static func bfs(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Grid.SIZE * Grid.SIZE)
	dist.fill(-1)
	if g.get_cell(sx, sz) == Grid.SOLID:
		return dist
	var queue := PackedInt32Array([sz * Grid.SIZE + sx])
	dist[sz * Grid.SIZE + sx] = 0
	var head: int = 0
	var dirs: Array = [[1, 0], [0, 1], [-1, 0], [0, -1]]
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx % Grid.SIZE
		@warning_ignore("integer_division")
		var cz: int = idx / Grid.SIZE
		for d: Array in dirs:
			var nx: int = cx + d[0]
			var nz: int = cz + d[1]
			if not Grid.in_bounds(nx, nz) or g.get_cell(nx, nz) == Grid.SOLID:
				continue
			var nidx: int = nz * Grid.SIZE + nx
			if dist[nidx] >= 0:
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


static func _carve_h(g: Grid, x0: int, x1: int, z: int) -> void:
	for x in range(mini(x0, x1), maxi(x0, x1) + 1):
		if g.get_cell(x, z) == Grid.SOLID:
			g.set_cell(x, z, Grid.FLOOR)


static func _carve_v(g: Grid, z0: int, z1: int, x: int) -> void:
	for z in range(mini(z0, z1), maxi(z0, z1) + 1):
		if g.get_cell(x, z) == Grid.SOLID:
			g.set_cell(x, z, Grid.FLOOR)


static func _try_generate(rng: PCG32) -> Dictionary:
	# 1. Salas
	var target: int = MIN_ROOMS + rng.bounded(4)
	var rooms: Array = []
	var draws: int = 0
	while rooms.size() < target and draws < MAX_ROOM_DRAWS:
		draws += 1
		var w: int = 4 + rng.bounded(6)
		var h: int = 4 + rng.bounded(6)
		var x: int = 2 + rng.bounded(60 - w)
		var z: int = 2 + rng.bounded(60 - h)
		var ok: bool = true
		for r: Dictionary in rooms:
			if rooms_too_close(x, z, w, h, r):
				ok = false
				break
		if ok:
			# 2. Centros
			rooms.append({
				"id": rooms.size(), "x": x, "z": z, "w": w, "h": h,
				"cx": x + FixedMath.div_floor(w, 2), "cz": z + FixedMath.div_floor(h, 2),
			})
	if rooms.size() < MIN_ROOMS:
		return {}
	var n: int = rooms.size()
	var g := Grid.new()
	for r: Dictionary in rooms:
		for zz in range(r["z"], r["z"] + r["h"]):
			for xx in range(r["x"], r["x"] + r["w"]):
				g.set_cell(xx, zz, Grid.FLOOR)

	# 3. Prim, chave (manhattan, v, u)
	var in_tree: Array = []
	in_tree.resize(n)
	in_tree.fill(false)
	in_tree[0] = true
	var edges: Array = []
	var in_mst: Dictionary = {}
	for _k in range(n - 1):
		var best: Array = []
		for u in range(n):
			if not in_tree[u]:
				continue
			for v in range(n):
				if in_tree[v]:
					continue
				var key: Array = [manhattan(rooms[u], rooms[v]), v, u]
				if best.is_empty() or _lex_less(key, best):
					best = key
		var bu: int = best[2]
		var bv: int = best[1]
		in_tree[bv] = true
		edges.append([bu, bv])
		in_mst[mini(bu, bv) * 16 + maxi(bu, bv)] = true

	# 4. Laços
	for i in range(n):
		for j in range(i + 1, n):
			if in_mst.has(i * 16 + j):
				continue
			if manhattan(rooms[i], rooms[j]) > LOOP_MAX_DIST:
				continue
			if rng.bounded(100) < LOOP_PERCENT:
				edges.append([i, j])

	# 5. Corredores em L
	for e: Array in edges:
		var a: Dictionary = rooms[e[0]]
		var b: Dictionary = rooms[e[1]]
		var bit: int = rng.next_u32() & 1
		if bit == 0:
			_carve_h(g, a["cx"], b["cx"], a["cz"])
			_carve_v(g, a["cz"], b["cz"], b["cx"])
		else:
			_carve_v(g, a["cz"], b["cz"], a["cx"])
			_carve_h(g, a["cx"], b["cx"], b["cz"])

	# 6. Portas
	for r: Dictionary in rooms:
		for oc: Array in outline_cells(r):
			var ox: int = oc[0]
			var oz: int = oc[1]
			if g.get_cell(ox, oz) != Grid.FLOOR:
				continue
			var perp_ok: bool
			var along_solid: bool
			if oc[2]:
				perp_ok = g.get_cell(ox, oz - 1) != Grid.SOLID and g.get_cell(ox, oz + 1) != Grid.SOLID
				along_solid = g.get_cell(ox - 1, oz) == Grid.SOLID and g.get_cell(ox + 1, oz) == Grid.SOLID
			else:
				perp_ok = g.get_cell(ox - 1, oz) != Grid.SOLID and g.get_cell(ox + 1, oz) != Grid.SOLID
				along_solid = g.get_cell(ox, oz - 1) == Grid.SOLID and g.get_cell(ox, oz + 1) == Grid.SOLID
			if perp_ok and along_solid:
				g.set_cell(ox, oz, Grid.DOOR_CLOSED)

	# 7. Saída e validações
	var r0: Dictionary = rooms[0]
	var dist: PackedInt32Array = bfs(g, r0["cx"], r0["cz"])
	var exit_room: int = -1
	var best_d: int = -1
	for i in range(1, n):
		var d: int = dist[rooms[i]["cz"] * Grid.SIZE + rooms[i]["cx"]]
		if d > best_d:
			best_d = d
			exit_room = i
	if exit_room < 0 or best_d < MIN_EXIT_DIST:
		return {}
	var er: Dictionary = rooms[exit_room]
	for oc: Array in outline_cells(er):
		var c: int = g.get_cell(oc[0], oc[1])
		if c == Grid.FLOOR:
			return {}
		if c == Grid.DOOR_CLOSED:
			g.set_cell(oc[0], oc[1], Grid.DOOR_LOCKED)
	g.set_cell(er["cx"], er["cz"], Grid.EXIT)
	var doors: Array = []
	for z in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var c: int = g.get_cell(x, z)
			if c == Grid.FLOOR and dist[z * Grid.SIZE + x] < 0:
				return {}
			if c == Grid.DOOR_CLOSED or c == Grid.DOOR_LOCKED:
				if not door_ok(g, x, z):
					return {}
				doors.append({"id": doors.size(), "cell_x": x, "cell_z": z})

	# 8. Retorno
	var res: Dictionary = {
		"grid": g, "rooms": rooms, "start_room": 0, "exit_room": exit_room,
		"doors": doors, "attempts": 0,
	}
	res.merge(_spawn_of(r0["cx"], r0["cz"]))
	return res


## M4: um inimigo por sala exceto a 0 (plano R3 §4.2). Continua o fluxo `rng`
## depois de generate(); não altera a grade.
static func place_enemies(layout: Dictionary, rng: PCG32) -> Array:
	var out: Array = []
	var rooms: Array = layout.get("rooms", [])
	var exit_room: int = layout.get("exit_room", -1)
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		var type: String
		var cx: int = r["cx"]
		var cz: int = r["cz"]
		if i == exit_room:
			type = "guardian"
			cz -= 1
		else:
			type = ["rat", "skeleton"][rng.bounded(2)]
		out.append(EnemySim.create(out.size(), type, cx * Grid.CELL + Grid.CELL / 2, cz * Grid.CELL + Grid.CELL / 2))
	return out


## BFS vizinhança-4 em que SOLID e DOOR_LOCKED bloqueiam (portas fechadas comuns
## contam como passáveis); -1 = inalcançável.
static func bfs_no_locked(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Grid.SIZE * Grid.SIZE)
	dist.fill(-1)
	if not Grid.in_bounds(sx, sz) or _locked_or_solid(g.get_cell(sx, sz)):
		return dist
	var queue := PackedInt32Array([sz * Grid.SIZE + sx])
	dist[sz * Grid.SIZE + sx] = 0
	var head: int = 0
	var dirs: Array = [[1, 0], [0, 1], [-1, 0], [0, -1]]
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx % Grid.SIZE
		@warning_ignore("integer_division")
		var cz: int = idx / Grid.SIZE
		for d: Array in dirs:
			var nx: int = cx + d[0]
			var nz: int = cz + d[1]
			if not Grid.in_bounds(nx, nz) or _locked_or_solid(g.get_cell(nx, nz)):
				continue
			var nidx: int = nz * Grid.SIZE + nx
			if dist[nidx] >= 0:
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


static func _locked_or_solid(c: int) -> bool:
	return c == Grid.SOLID or c == Grid.DOOR_LOCKED


## Célula livre para item na sala r: FLOOR, no piso de r, fora de (cx, cz) e de
## (cx, cz - 1), sem outro item.
static func _cell_free(g: Grid, r: Dictionary, x: int, z: int, items: Array) -> bool:
	if g.get_cell(x, z) != Grid.FLOOR:
		return false
	if x < r["x"] or x >= r["x"] + r["w"] or z < r["z"] or z >= r["z"] + r["h"]:
		return false
	if x == r["cx"] and (z == r["cz"] or z == r["cz"] - 1):
		return false
	for it: Dictionary in items:
		if it["cell_x"] == x and it["cell_z"] == z:
			return false
	return true


## Até ITEM_CELL_DRAWS sorteios; senão varredura z crescente, depois x (sem RNG).
## Devolve [x, z] ou [] se a sala não tem célula livre.
static func _free_cell(g: Grid, r: Dictionary, rng: PCG32, items: Array) -> Array:
	for _k in range(ITEM_CELL_DRAWS):
		var x: int = r["x"] + rng.bounded(r["w"])
		var z: int = r["z"] + rng.bounded(r["h"])
		if _cell_free(g, r, x, z, items):
			return [x, z]
	for z in range(r["z"], r["z"] + r["h"]):
		for x in range(r["x"], r["x"] + r["w"]):
			if _cell_free(g, r, x, z, items):
				return [x, z]
	return []


static func _add_item(items: Array, type: String, cell: Array, amount: int = 1) -> void:
	if cell.is_empty():
		return
	items.append(ItemsSim.make(items.size(), type, cell[0], cell[1], amount))


## M6 (plano R4 §4.2): continua o fluxo `rng` depois de place_enemies(); não altera a
## grade nem os inimigos. Ordem fixa: poção de vida na sala 0, chave, e (poção, ouro)
## por sala 1..n-1. Grava layout["key_fallback"] se nenhuma sala servir para a chave.
static func place_items(layout: Dictionary, _enemies: Array, rng: PCG32) -> Array:
	var items: Array = []
	var rooms: Array = layout.get("rooms", [])
	if rooms.is_empty():
		return items
	var g: Grid = layout["grid"]
	var exit_room: int = layout.get("exit_room", -1)
	var r0: Dictionary = rooms[0]
	_add_item(items, "potion_hp", _free_cell(g, r0, rng, items))
	var dist: PackedInt32Array = bfs_no_locked(g, r0["cx"], r0["cz"])
	var cands: Array = []
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		if i != exit_room and dist[int(r["cz"]) * Grid.SIZE + int(r["cx"])] >= 0:
			cands.append(i)
	if cands.is_empty():
		layout["key_fallback"] = true
		_add_item(items, "key", _free_cell(g, r0, rng, items))
	else:
		var kr: Dictionary = rooms[cands[rng.bounded(cands.size())]]
		_add_item(items, "key", _free_cell(g, kr, rng, items))
	for i in range(1, rooms.size()):
		var r: Dictionary = rooms[i]
		var ptype: String = ["potion_hp", "potion_sp"][rng.bounded(2)]
		_add_item(items, ptype, _free_cell(g, r, rng, items))
		var amount: int = ItemsSim.GOLD_MIN + rng.bounded(ItemsSim.GOLD_SPAN)
		_add_item(items, "gold", _free_cell(g, r, rng, items), amount)
	return items


static func _lex_less(a: Array, b: Array) -> bool:
	for i in range(a.size()):
		if a[i] != b[i]:
			return a[i] < b[i]
	return false
