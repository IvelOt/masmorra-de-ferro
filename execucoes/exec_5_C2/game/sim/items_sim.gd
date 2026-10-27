class_name ItemsSim
extends RefCounted
## M6: tabela de itens, posicionamento (só rng_dungeon), coleta (passo 3), XP/nível (passo 8).

const POTION_HP_HEAL: int = 40
const POTION_SP_GAIN: int = 50
const GOLD_PER_PILE: int = 10
const LEVEL_XP: Array = [0, 0, 100, 250]     # índice = nível
const LEVEL_MAX: int = 3
const LEVEL_HP_BONUS: int = 20
const LEVEL_SP_BONUS: int = 10
const K_MAX: int = 18000
const TYPES: Array = ["potion_hp", "potion_sp", "key", "gold"]
## Vizinhança N, L, S, O (a mesma de DungeonGen.bfs).
const DXS: Array = [0, 1, 0, -1]
const DZS: Array = [-1, 0, 1, 0]


static func make(id: int, type: String, cx: int, cz: int) -> Dictionary:
	return {"id": id, "type": type, "cell_x": cx, "cell_z": cz, "taken": false}


## BFS-4 (N, L, S, O) a partir de (sx, sz): SOLID e DOOR_LOCKED bloqueiam; portas fechadas/abertas passam.
static func bfs_no_locked(grid: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	if not grid.in_bounds(sx, sz):
		return dist
	var queue := PackedInt32Array()
	queue.append(sz * Grid.W + sx)
	dist[sz * Grid.W + sx] = 0
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx % Grid.W
		var cz: int = FixedMath.div_trunc(idx, Grid.W)
		for k in range(4):
			var nx: int = cx + DXS[k]
			var nz: int = cz + DZS[k]
			if not grid.in_bounds(nx, nz):
				continue
			var c: int = grid.get_cell(nx, nz)
			if c == Grid.SOLID or c == Grid.DOOR_LOCKED or dist[nz * Grid.W + nx] >= 0:
				continue
			dist[nz * Grid.W + nx] = dist[idx] + 1
			queue.append(nz * Grid.W + nx)
	return dist


## Célula livre para item: FLOOR, fora da célula inicial, sem inimigo e sem outro item.
static func cell_free(world: WorldSim, cx: int, cz: int) -> bool:
	if world.dungeon.grid.get_cell(cx, cz) != Grid.FLOOR:
		return false
	if cx == world.player.cell_x() and cz == world.player.cell_z():
		return false
	for i in range(world.enemies.size()):
		var e: EntitySim = world.enemies[i]
		if FixedMath.div_floor(e.pos_x, Grid.CELL) == cx and FixedMath.div_floor(e.pos_z, Grid.CELL) == cz:
			return false
	for i in range(world.items.size()):
		var it: Dictionary = world.items[i]
		if it["cell_x"] == cx and it["cell_z"] == cz:
			return false
	return true


## Células livres dentro do retângulo da sala, em ordem de cz*64 + cx.
static func free_cells(world: WorldSim, r: Dictionary) -> Array:
	var out: Array = []
	for cz in range(r["z"], r["z"] + r["h"]):
		for cx in range(r["x"], r["x"] + r["w"]):
			if cell_free(world, cx, cz):
				out.append([cx, cz])
	return out


## Sorteia uma célula da lista. Lista vazia => [] SEM consumir RNG (o item correspondente é pulado).
static func _draw(world: WorldSim, cells: Array) -> Array:
	if cells.is_empty():
		return []
	return cells[world.rng_dungeon.bounded(cells.size())]


static func _add(world: WorldSim, type: String, cell: Array) -> void:
	if cell.is_empty():
		return
	world.items.append(make(world.items.size(), type, cell[0], cell[1]))


## Posicionamento da masmorra gerada (plano 5 §3.3). Chamado logo depois de EnemySim.spawn.
static func spawn(world: WorldSim) -> void:
	var d: DungeonGen.Dungeon = world.dungeon
	# 1. poção inicial na sala inicial
	_add(world, "potion_hp", _draw(world, free_cells(world, d.rooms[d.start_room])))
	# 2. chave: sala alcançável sem atravessar portas trancadas (filtrar e depois sortear)
	var reach: PackedInt32Array = bfs_no_locked(d.grid, world.player.cell_x(), world.player.cell_z())
	var cand: Array = []
	var cand_cells: Array = []
	for i in range(d.rooms.size()):
		var r: Dictionary = d.rooms[i]
		if r["id"] == d.start_room or r["id"] == d.exit_room:
			continue
		var cells: Array = []
		var all: Array = free_cells(world, r)
		for j in range(all.size()):
			var c: Array = all[j]
			if reach[c[1] * Grid.W + c[0]] >= 0:
				cells.append(c)
		if not cells.is_empty():
			cand.append(r["id"])
			cand_cells.append(cells)
	if cand.is_empty():
		push_error("ItemsSim.spawn: nenhuma sala candidata para a chave (semente %d)" % world.seed_value)
	else:
		_add(world, "key", _draw(world, cand_cells[world.rng_dungeon.bounded(cand.size())]))
	# 3. poção opcional + ouro por sala (exceto a inicial; inclui a sala da saída)
	for i in range(d.rooms.size()):
		var r: Dictionary = d.rooms[i]
		if r["id"] == d.start_room:
			continue
		var t: int = world.rng_dungeon.bounded(3)
		if t < 2:
			_add(world, "potion_hp" if t == 0 else "potion_sp", _draw(world, free_cells(world, r)))
		_add(world, "gold", _draw(world, free_cells(world, r)))


## Passo 3 (coleta automática, todo tick): itens não coletados na célula do jogador, em ordem de id.
static func collect(world: WorldSim) -> void:
	var p: PlayerSim = world.player
	var pcx: int = p.cell_x()
	var pcz: int = p.cell_z()
	for i in range(world.items.size()):
		var it: Dictionary = world.items[i]
		if it["taken"] or it["cell_x"] != pcx or it["cell_z"] != pcz:
			continue
		it["taken"] = true
		match String(it["type"]):
			"potion_hp":
				p.potion_hp += 1
			"potion_sp":
				p.potion_sp += 1
			"key":
				p.key = true
			"gold":
				p.gold += GOLD_PER_PILE
		world.events.append("pickup:%d" % it["id"])


## Passo 8: XP dos abates do jogador neste tick e subida de nível (pode subir mais de um).
static func apply_xp(world: WorldSim) -> void:
	var p: PlayerSim = world.player
	for i in range(world.killed_now.size()):
		var e: EntitySim = world.enemies[world.killed_now[i]]
		if e.type != "dummy":
			p.xp += int(EnemySim.TYPES[e.type]["xp"])
	while p.level < LEVEL_MAX and p.xp >= int(LEVEL_XP[p.level + 1]):
		p.level += 1
		p.hp_max += LEVEL_HP_BONUS
		p.stamina_max += LEVEL_SP_BONUS
		p.hp = p.hp_max
		world.events.append("level:%d" % p.level)
