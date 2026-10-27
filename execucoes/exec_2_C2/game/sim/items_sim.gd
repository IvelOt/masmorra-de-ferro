extends RefCounted
## Itens, progressão e condição terminal (M6, GDD §4.6; plano da rodada 3 §5): posicionamento
## (populate) de inimigos e itens, coleta automática, poções, XP/nível e terminais.
## Só inteiros; world_sim.step() chama as funções abaixo nos passos 3, 4, 8 e 10.

const FM = preload("res://sim/fixed_math.gd")
const Grid = preload("res://sim/grid.gd")
const Combat = preload("res://sim/combat.gd")

const RAT_PERCENT: int = 60
const POTION_HP_HEAL: int = 40
const POTION_SP_GAIN: int = 50
## XP mínimo dos níveis 1, 2 e 3 (nível máximo 3).
const LEVEL_XP: Array = [0, 100, 250]
const LEVEL_MAX: int = 3
const LEVEL_HP_BONUS: int = 20
const LEVEL_SP_BONUS: int = 10
const LEVEL_DMG_BONUS: int = 5
const GOLD_MIN: int = 10
const GOLD_SPAN: int = 21
const GOLD_EXIT: int = 50

## Vizinhança 4 na ordem N, L, S, O (= DungeonGen.DIRS).
const DIRS: Array = [[0, -1], [1, 0], [0, 1], [-1, 0]]


static func sword_damage(level: int) -> int:
	return Combat.SWORD_DAMAGE + LEVEL_DMG_BONUS * (level - 1)


## Chamado por setup_seed() depois de generate(), continuando o MESMO rng (STREAM_DUNGEON).
## A ordem dos sorteios é normativa (plano §4.8 e §5.2).
static func populate(world: RefCounted, rng: RefCounted) -> void:
	var g: Grid = world.grid
	var n: int = g.rooms.size()
	var exit_room: int = g.exit_room
	# inimigos: um por sala >= 1; guardião ao lado do EXIT na Sala da Saída
	var guard_cx: int = -1
	var guard_cz: int = -1
	for rid in range(1, n):
		var r: Dictionary = g.rooms[rid]
		if rid == exit_room:
			guard_cx = int(r.cx) - 1
			guard_cz = int(r.cz)
			world.spawn_enemy("guardian", Grid.cell_center(guard_cx), Grid.cell_center(guard_cz))
		else:
			var t: int = rng.next_bounded(100)
			var kind: String = "rat" if t < RAT_PERCENT else "skeleton"
			world.spawn_enemy(kind, Grid.cell_center(int(r.cx)), Grid.cell_center(int(r.cz)))
	# itens
	var used: Dictionary = {}
	# 1. poção de vida na sala 0
	_place(world, rng, 0, guard_cx, guard_cz, used, "potion_hp", 0)
	# 2. chave numa sala alcançável sem passar por porta trancada (filtrar antes de sortear)
	var k: Array = key_rooms(g)
	if not k.is_empty():
		var rid_k: int = k[rng.next_bounded(k.size())]
		_place(world, rng, rid_k, guard_cx, guard_cz, used, "key", 0)
	# 3. poção (50%) e ouro nas demais salas
	for rid in range(1, n):
		if rid == exit_room:
			continue
		if rng.next_bounded(2) == 0:
			var kind2: String = "potion_hp" if rng.next_bounded(3) < 2 else "potion_sp"
			_place(world, rng, rid, guard_cx, guard_cz, used, kind2, 0)
		var amount: int = GOLD_MIN + rng.next_bounded(GOLD_SPAN)
		_place(world, rng, rid, guard_cx, guard_cz, used, "gold", amount)
	# 4. pilha fixa na Sala da Saída
	if exit_room > 0:
		_place(world, rng, exit_room, guard_cx, guard_cz, used, "gold", GOLD_EXIT)


## Salas candidatas à chave: id ≠ 0, ≠ Saída, centro alcançável do centro da sala 0 por BFS com
## DOOR_LOCKED (e SOLID) bloqueando; ordem crescente.
static func key_rooms(g: Grid) -> Array:
	var r0: Dictionary = g.rooms[0]
	var dist: PackedInt32Array = bfs_unlocked(g, r0.cx, r0.cz)
	var out: Array = []
	for r: Dictionary in g.rooms:
		var rid: int = r.id
		if rid == 0 or rid == g.exit_room:
			continue
		if dist[Grid.index_of(r.cx, r.cz)] >= 0:
			out.append(rid)
	return out


## BFS 4-vizinhança; passável = não SOLID e não DOOR_LOCKED.
static func bfs_unlocked(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.GRID_W * Grid.GRID_H)
	dist.fill(-1)
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
			var t: int = g.get_cell(nx, nz)
			if t == Grid.SOLID or t == Grid.DOOR_LOCKED:
				continue
			var ni: int = Grid.index_of(nx, nz)
			if dist[ni] >= 0:
				continue
			dist[ni] = dist[cur] + 1
			queue.append(ni)
	return dist


## Células livres da sala rid em ordem (cz, cx): FLOOR, da própria sala, fora do centro, da célula
## do guardião e do EXIT, sem item.
static func free_cells(g: Grid, rid: int, guard_cx: int, guard_cz: int, used: Dictionary) -> Array:
	var r: Dictionary = g.rooms[rid]
	var out: Array = []
	for cz in range(int(r.z), int(r.z) + int(r.h)):
		for cx in range(int(r.x), int(r.x) + int(r.w)):
			if g.get_cell(cx, cz) != Grid.FLOOR or g.get_room_id(cx, cz) != rid:
				continue
			if cx == int(r.cx) and cz == int(r.cz):
				continue
			if cx == guard_cx and cz == guard_cz:
				continue
			if used.has(Grid.index_of(cx, cz)):
				continue
			out.append([cx, cz])
	return out


static func _place(world: RefCounted, rng: RefCounted, rid: int, guard_cx: int, guard_cz: int,
		used: Dictionary, kind: String, amount: int) -> void:
	var cells: Array = free_cells(world.grid, rid, guard_cx, guard_cz, used)
	if cells.is_empty():
		return
	var c: Array = cells[rng.next_bounded(cells.size())]
	used[Grid.index_of(c[0], c[1])] = true
	world.add_item(kind, c[0], c[1], amount)


## Passo 3b: coleta automática dos itens na célula do jogador, em ordem de id.
static func collect(world: RefCounted) -> void:
	var p: RefCounted = world.player
	var pcx: int = Grid.cell_of(p.pos_x)
	var pcz: int = Grid.cell_of(p.pos_z)
	for it: Dictionary in world.items:
		if it.taken or int(it.cell_x) != pcx or int(it.cell_z) != pcz:
			continue
		it.taken = true
		if it.type == "gold":
			p.gold += int(it.amount)
		else:
			p.inventory[it.type] = int(p.inventory[it.type]) + 1


## Passo 3c: `use` sobre o EXIT com a chave pede a fuga (resolvida no passo 10).
static func try_escape(world: RefCounted) -> void:
	var p: RefCounted = world.player
	if int(p.inventory.key) > 0 and world.grid.get_cell(Grid.cell_of(p.pos_x), Grid.cell_of(p.pos_z)) == Grid.EXIT:
		world.escape_pending = true


## Passo 4: quaff 1 = poção de vida, 2 = poção de vigor; inventário vazio não muda nada.
static func quaff(world: RefCounted, q: int) -> void:
	var p: RefCounted = world.player
	if q == 1 and int(p.inventory.potion_hp) > 0:
		p.inventory.potion_hp = int(p.inventory.potion_hp) - 1
		p.hp = FM.min_i(p.hp + POTION_HP_HEAL, p.hp_max)
	elif q == 2 and int(p.inventory.potion_sp) > 0:
		p.inventory.potion_sp = int(p.inventory.potion_sp) - 1
		p.stamina = FM.min_i(p.stamina + POTION_SP_GAIN, p.stamina_max)


## Passo 8 (depois do vigor): XP pendente e subida de nível (vários níveis no mesmo tick acumulam).
static func xp_step(world: RefCounted) -> void:
	var p: RefCounted = world.player
	p.xp += world.pending_xp
	world.pending_xp = 0
	while p.level < LEVEL_MAX and p.xp >= int(LEVEL_XP[p.level]):
		p.level += 1
		p.hp_max += LEVEL_HP_BONUS
		p.stamina_max += LEVEL_SP_BONUS
		p.hp = p.hp_max


## Passo 10: terminais em ordem de prioridade (DEAD, ESCAPED, TIMEOUT).
static func terminal_step(world: RefCounted, k_max: int) -> void:
	if world.player.hp <= 0:
		world.terminal = "DEAD"
	elif world.escape_pending:
		world.terminal = "ESCAPED"
	elif world.tick >= k_max:
		world.terminal = "TIMEOUT"
	if world.terminal != "NONE":
		world.terminal_tick = world.tick
	world.escape_pending = false
