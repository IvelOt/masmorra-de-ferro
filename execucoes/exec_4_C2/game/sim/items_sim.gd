class_name ItemsSim
extends RefCounted
## M6: tabela de itens, posicionamento determinístico (continua o RNG da
## masmorra), coleta automática e poções (plano da iteração 4 §3.2–§3.5).

const POTION_HP: int = 0
const POTION_SP: int = 1
const KEY: int = 2
const GOLD: int = 3

const NAMES: Array = ["Poção de Vida", "Poção de Vigor", "Chave da Saída", "Ouro"]
const TEX_IDS: Array = ["item.potion_hp", "item.potion_sp", "item.key", "item.gold"]
const GOLD_VALUE: int = 25
const POTION_HP_GAIN: int = 40
const POTION_SP_GAIN: int = 50
const POTION_CHANCE: int = 50
const GOLD_CHANCE: int = 60
const FREE_TRIES: int = 16


class Item:
	extends RefCounted
	var id: int = 0
	var type: int = 0
	var cell_x: int = 0
	var cell_z: int = 0
	var taken: bool = false

	func to_dict() -> Dictionary:
		return {"id": id, "type": type, "cell_x": cell_x, "cell_z": cell_z, "taken": taken}


static func make(id: int, t: int, cx: int, cz: int) -> Item:
	var it: Item = Item.new()
	it.id = id
	it.type = t
	it.cell_x = cx
	it.cell_z = cz
	return it


## BFS vizinhança-4 em que SOLID e DOOR_LOCKED bloqueiam; -1 = inalcançável.
static func bfs_lock(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	var t0: int = g.get_cell(sx, sz)
	if t0 == Grid.SOLID or t0 == Grid.DOOR_LOCKED:
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
		for d: Array in DungeonGen.DIRS:
			var nx: int = cx + int(d[0])
			var nz: int = cz + int(d[1])
			if not Grid.in_bounds(nx, nz):
				continue
			var nidx: int = nz * Grid.W + nx
			var t: int = g.cells[nidx]
			if dist[nidx] >= 0 or t == Grid.SOLID or t == Grid.DOOR_LOCKED:
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


static func _has_item(items: Array, cx: int, cz: int) -> bool:
	for it: Item in items:
		if it.cell_x == cx and it.cell_z == cz:
			return true
	return false


static func _cell_ok(g: Grid, r: Dictionary, items: Array, cx: int, cz: int) -> bool:
	if g.get_cell(cx, cz) != Grid.FLOOR or _has_item(items, cx, cz):
		return false
	var c: Array = DungeonGen.room_center(r)
	if cx == int(c[0]) and cz == int(c[1]):
		return false
	if int(r["id"]) == g.exit_room and cx == int(c[0]) and cz == int(c[1]) + 1:
		return false
	return true


## Até 16 sorteios (todos consomem o RNG); depois varredura linha a linha (sem RNG).
static func free_cell(g: Grid, r: Dictionary, rng: RngPcg32, items: Array) -> Array:
	var x: int = int(r["x"])
	var z: int = int(r["z"])
	var w: int = int(r["w"])
	var h: int = int(r["h"])
	for _t: int in range(FREE_TRIES):
		var cx: int = x + rng.range_i(0, w - 1)
		var cz: int = z + rng.range_i(0, h - 1)
		if _cell_ok(g, r, items, cx, cz):
			return [cx, cz]
	for cz: int in range(z, z + h):
		for cx: int in range(x, x + w):
			if _cell_ok(g, r, items, cx, cz):
				return [cx, cz]
	return []


## Posiciona os itens de uma masmorra gerada (ordem exata de §3.3).
static func place(g: Grid, rng: RngPcg32) -> Array:
	var items: Array = []
	var sc: Array = DungeonGen.room_center(g.rooms[g.start_room])
	var scx: int = int(sc[0])
	var scz: int = int(sc[1])
	items.append(make(0, POTION_HP, scx + 1, scz))
	# Chave: só salas alcançáveis sem passar pela porta trancada entram no sorteio.
	var reach: PackedInt32Array = bfs_lock(g, scx, scz)
	var cand: Array = []
	for r: Dictionary in g.rooms:
		var rid: int = int(r["id"])
		if rid == g.start_room or rid == g.exit_room:
			continue
		var c: Array = DungeonGen.room_center(r)
		if reach[int(c[1]) * Grid.W + int(c[0])] >= 0:
			cand.append(r)
	if cand.is_empty():
		push_warning("ItemsSim: nenhuma sala candidata para a chave")
		items.append(make(1, KEY, scx - 1, scz))
	else:
		var kr: Dictionary = cand[rng.range_i(0, cand.size() - 1)]
		var kc: Array = free_cell(g, kr, rng, items)
		items.append(make(1, KEY, int(kc[0]), int(kc[1])))
	for r: Dictionary in g.rooms:
		if int(r["id"]) == g.start_room:
			continue
		if rng.range_i(0, 99) < POTION_CHANCE:
			var pt: int = rng.range_i(0, 1)
			var pc: Array = free_cell(g, r, rng, items)
			if not pc.is_empty():
				items.append(make(items.size(), pt, int(pc[0]), int(pc[1])))
		if rng.range_i(0, 99) < GOLD_CHANCE:
			var gc: Array = free_cell(g, r, rng, items)
			if not gc.is_empty():
				items.append(make(items.size(), GOLD, int(gc[0]), int(gc[1])))
	return items


## Coleta automática na célula do jogador, em ordem de id. Devolve os tipos coletados.
static func collect(p: PlayerSim, items: Array) -> Array:
	var pcx: int = FixedMath.div_floor(p.pos_x, Grid.CELL)
	var pcz: int = FixedMath.div_floor(p.pos_z, Grid.CELL)
	var got: Array = []
	for it: Item in items:
		if it.taken or it.cell_x != pcx or it.cell_z != pcz:
			continue
		it.taken = true
		got.append(it.type)
		if it.type == POTION_HP:
			p.potion_hp += 1
		elif it.type == POTION_SP:
			p.potion_sp += 1
		elif it.type == KEY:
			p.has_key = true
		else:
			p.gold += GOLD_VALUE
	return got


## Passo 4: beber. Com a barra cheia ou sem poção, não tem efeito (§3.5).
static func quaff(p: PlayerSim, which: int) -> void:
	if which == 1 and p.potion_hp > 0 and p.hp < p.hp_max:
		p.potion_hp -= 1
		p.hp = mini(p.hp + POTION_HP_GAIN, p.hp_max)
	elif which == 2 and p.potion_sp > 0 and p.stamina < p.stamina_max:
		p.potion_sp -= 1
		p.stamina = mini(p.stamina + POTION_SP_GAIN, p.stamina_max)
