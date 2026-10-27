class_name ItemsSim
extends RefCounted
## Itens e progressão (M6): constantes, posicionamento na masmorra (continua
## d.rng depois dos inimigos), coleta, poções, XP e nível. Só inteiros.

const POTION_HP: int = 0
const POTION_SP: int = 1
const KEY: int = 2
const GOLD: int = 3

const POTION_HP_HEAL: int = 40
const POTION_SP_RESTORE: int = 50
const GOLD_VALUE: int = 25

const LEVEL_XP: Array[int] = [0, 100, 250]   # XP mínimo dos níveis 1, 2, 3
const LEVEL_MAX: int = 3
const LEVEL_HP: int = 20
const LEVEL_SP: int = 10
const LEVEL_DMG: int = 5

const K_MAX: int = 18000


static func make(id: int, type: int, cx: int, cz: int) -> Dictionary:
	return {"id": id, "type": type, "cell_x": cx, "cell_z": cz, "taken": false}


## Posicionamento na masmorra (plano §4.2). info["key_fallback"] diz se a
## chave caiu no caminho de reserva.
static func place_dungeon(d: DungeonGen, enemies: Array[EnemySim], info: Dictionary = {}) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	info["key_fallback"] = false
	var s_cx: int = d.start_pos[0] >> Grid.CELL_SHIFT
	var s_cz: int = d.start_pos[1] >> Grid.CELL_SHIFT
	items.append(make(0, POTION_HP, s_cx + 1, s_cz))
	# chave
	var blocked: Grid = d.grid.duplicate_grid()
	for i in range(Grid.SIZE * Grid.SIZE):
		if blocked.cells[i] == Grid.DOOR_LOCKED:
			blocked.cells[i] = Grid.SOLID
	var reach: PackedInt32Array = DungeonGen.bfs(blocked, s_cx, s_cz)
	var cands: Array[int] = []
	for r: Dictionary in d.rooms:
		if int(r.id) != d.start_room and int(r.id) != d.exit_room:
			cands.append(int(r.id))
	var chosen: int = -1
	if cands.size() > 0:
		var k: int = d.rng.next_range(cands.size())
		for j in range(cands.size()):
			var rid: int = cands[(k + j) % cands.size()]
			var r: Dictionary = d.rooms[rid]
			var ccx: int = int(r.x) + (int(r.w) >> 1)
			var ccz: int = int(r.z) + (int(r.h) >> 1)
			if reach[ccz * Grid.SIZE + ccx] >= 0 and not free_cells(d, enemies, items, rid).is_empty():
				chosen = rid
				break
	if chosen >= 0:
		var free: Array[int] = free_cells(d, enemies, items, chosen)
		var c: int = free[d.rng.next_range(free.size())]
		items.append(make(1, KEY, c & (Grid.SIZE - 1), c >> 6))
	else:
		info["key_fallback"] = true
		var best: int = -1
		for i in range(Grid.SIZE * Grid.SIZE):
			var cx: int = i & (Grid.SIZE - 1)
			var cz: int = i >> 6
			if reach[i] < 0 or d.grid.cells[i] != Grid.FLOOR:
				continue
			var rid: int = _room_at(d, cx, cz)
			if rid == d.start_room or rid == d.exit_room or _occupied(d, enemies, items, cx, cz):
				continue
			if best < 0 or reach[i] > reach[best]:
				best = i
		if best >= 0:
			items.append(make(1, KEY, best & (Grid.SIZE - 1), best >> 6))
	# itens comuns: uma tiragem por sala, exceto a inicial
	for r: Dictionary in d.rooms:
		var rid: int = int(r.id)
		if rid == d.start_room:
			continue
		var t: int = d.rng.next_range(100)
		var type: int = -1
		if t < 35:
			type = POTION_HP
		elif t < 55:
			type = POTION_SP
		elif t < 85:
			type = GOLD
		if type < 0:
			continue
		var free: Array[int] = free_cells(d, enemies, items, rid)
		if free.is_empty():
			continue
		var c: int = free[d.rng.next_range(free.size())]
		items.append(make(items.size(), type, c & (Grid.SIZE - 1), c >> 6))
	return items


## Células livres da sala em ordem de linha (cz, depois cx), como índices.
static func free_cells(d: DungeonGen, enemies: Array[EnemySim], items: Array[Dictionary], rid: int) -> Array[int]:
	var out: Array[int] = []
	var r: Dictionary = d.rooms[rid]
	for cz in range(int(r.z), int(r.z) + int(r.h)):
		for cx in range(int(r.x), int(r.x) + int(r.w)):
			if d.grid.get_cell(cx, cz) != Grid.FLOOR or _occupied(d, enemies, items, cx, cz):
				continue
			out.append(cz * Grid.SIZE + cx)
	return out


static func _occupied(d: DungeonGen, enemies: Array[EnemySim], items: Array[Dictionary], cx: int, cz: int) -> bool:
	if d.exit_cell.size() == 2 and d.exit_cell[0] == cx and d.exit_cell[1] == cz:
		return true
	for e in enemies:
		if e.cell_x() == cx and e.cell_z() == cz:
			return true
	for it: Dictionary in items:
		if int(it.cell_x) == cx and int(it.cell_z) == cz:
			return true
	return false


static func _room_at(d: DungeonGen, cx: int, cz: int) -> int:
	for r: Dictionary in d.rooms:
		if cx >= int(r.x) and cx < int(r.x) + int(r.w) and cz >= int(r.z) and cz < int(r.z) + int(r.h):
			return int(r.id)
	return -1


## Passo 3a: coleta automática na célula do jogador, em ordem de id.
static func collect(p: PlayerSim, items: Array[Dictionary]) -> void:
	var cx: int = p.cell_x()
	var cz: int = p.cell_z()
	for it: Dictionary in items:
		if it.taken or int(it.cell_x) != cx or int(it.cell_z) != cz:
			continue
		it.taken = true
		match int(it.type):
			POTION_HP:
				p.potion_hp += 1
			POTION_SP:
				p.potion_sp += 1
			KEY:
				p.has_key = true
			GOLD:
				p.gold += GOLD_VALUE


## Passo 4.
static func quaff(p: PlayerSim, q: int) -> void:
	if q == 1 and p.potion_hp > 0:
		p.potion_hp -= 1
		p.hp = mini(p.hp + POTION_HP_HEAL, p.hp_max)
	elif q == 2 and p.potion_sp > 0:
		p.potion_sp -= 1
		p.stamina = mini(p.stamina + POTION_SP_RESTORE, p.stamina_max)


## Passo 8, depois da regeneração.
static func gain_xp(p: PlayerSim, gain: int) -> void:
	p.xp += gain
	while p.level < LEVEL_MAX and p.xp >= LEVEL_XP[p.level]:
		p.level += 1
		p.hp_max += LEVEL_HP
		p.stamina_max += LEVEL_SP
		p.hp = p.hp_max
