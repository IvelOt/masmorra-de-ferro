class_name EnemySim
extends RefCounted
## M4: tabela de tipos, posicionamento, linha de visão (DDA inteiro), campo de fluxo e IA (passo 6).
## Determinística e sem sorteio: rng_ai não é consumido nesta rodada.

## Distâncias em u (1 m = 1024 u). half = meia-aresta da caixa (raio_alvo da hitbox de M3).
const TYPES: Dictionary = {
	"rat": {"hp": 20, "speed": 100, "dmg": 5, "reach": 1024, "windup": 8, "cooldown": 30, "xp": 10, "half": 256},
	"skeleton": {"hp": 50, "speed": 68, "dmg": 12, "reach": 1229, "windup": 18, "cooldown": 45, "xp": 25, "half": 384},
	"guardian": {"hp": 150, "speed": 51, "dmg": 25, "reach": 1434, "windup": 30, "cooldown": 60, "xp": 100, "half": 512},
}
const CHEB_WAKE_CELLS: int = 6
## Vizinhança N, L, S, O (a mesma de DungeonGen.bfs; "N" é z - 1 da grade).
const DXS: Array = [0, 1, 0, -1]
const DZS: Array = [-1, 0, 1, 0]


## Inimigos da masmorra gerada: um por sala (exceto a inicial); Guardião na sala da saída.
static func spawn(world: WorldSim) -> void:
	var d: DungeonGen.Dungeon = world.dungeon
	for i in range(d.rooms.size()):
		var r: Dictionary = d.rooms[i]
		if r["id"] == d.start_room:
			continue
		var c: Array = DungeonGen.room_center(r)
		var type: String = ""
		var cx: int = c[0]
		var cz: int = c[1]
		if r["id"] == d.exit_room:
			type = "guardian"
			cx = c[0] - 1     # a célula central é o EXIT; w >= 4 garante cx >= r.x + 1
		else:
			type = "rat" if world.rng_dungeon.bounded(2) == 0 else "skeleton"
		world.add_enemy(type, DungeonGen.cell_center_u(cx), DungeonGen.cell_center_u(cz))


## Linha de visão de centro a centro (Amanatides–Woo inteiro, tempos comparados por produto cruzado).
## Origem e destino não são testados; passar exatamente por um canto exige as duas vizinhas livres.
static func los(grid: Grid, x0: int, z0: int, x1: int, z1: int) -> bool:
	var cx: int = FixedMath.div_floor(x0, Grid.CELL)
	var cz: int = FixedMath.div_floor(z0, Grid.CELL)
	var tx: int = FixedMath.div_floor(x1, Grid.CELL)
	var tz: int = FixedMath.div_floor(z1, Grid.CELL)
	var dx: int = x1 - x0
	var dz: int = z1 - z0
	var sx: int = FixedMath.sign_i(dx)
	var sz: int = FixedMath.sign_i(dz)
	var adx: int = FixedMath.abs_i(dx)
	var adz: int = FixedMath.abs_i(dz)
	var bx: int = 0
	if sx > 0:
		bx = (cx + 1) * Grid.CELL - x0
	elif sx < 0:
		bx = x0 - cx * Grid.CELL
	var bz: int = 0
	if sz > 0:
		bz = (cz + 1) * Grid.CELL - z0
	elif sz < 0:
		bz = z0 - cz * Grid.CELL
	for _i in range(256):
		if cx == tx and cz == tz:
			return true
		if adz == 0 or (adx != 0 and bx * adz < bz * adx):
			cx += sx
			bx += Grid.CELL
		elif adx == 0 or bz * adx < bx * adz:
			cz += sz
			bz += Grid.CELL
		else:
			if grid.is_blocking(cx + sx, cz) or grid.is_blocking(cx, cz + sz):
				return false
			cx += sx
			cz += sz
			bx += Grid.CELL
			bz += Grid.CELL
		if (cx != tx or cz != tz) and grid.is_blocking(cx, cz):
			return false
	return false


## Recalcula o campo de fluxo (BFS-4 a partir da célula do jogador) se a célula mudou ou uma porta abriu.
static func ensure_flow(world: WorldSim) -> void:
	var pcx: int = world.player.cell_x()
	var pcz: int = world.player.cell_z()
	var pidx: int = pcz * Grid.W + pcx
	if not world.flow_dirty and world.flow_cell == pidx:
		return
	world.flow_recalcs += 1
	world.flow_cell = pidx
	world.flow_dirty = false
	var grid: Grid = world.dungeon.grid
	var dist := PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	world.flow_dist = dist
	if not grid.in_bounds(pcx, pcz) or grid.is_blocking(pcx, pcz):
		return
	var queue := PackedInt32Array()
	queue.append(pidx)
	dist[pidx] = 0
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx % Grid.W
		var cz: int = FixedMath.div_trunc(idx, Grid.W)
		for k in range(4):
			var nx: int = cx + DXS[k]
			var nz: int = cz + DZS[k]
			if grid.in_bounds(nx, nz) and not grid.is_blocking(nx, nz) and dist[nz * Grid.W + nx] < 0:
				dist[nz * Grid.W + nx] = dist[idx] + 1
				queue.append(nz * Grid.W + nx)
	world.flow_dist = dist


## Primeiro vizinho (N, L, S, O) um passo mais perto do jogador; [] se inalcançável ou já na célula dele.
static func flow_next(world: WorldSim, ecx: int, ecz: int) -> Array:
	if not world.dungeon.grid.in_bounds(ecx, ecz):
		return []
	var cur: int = world.flow_dist[ecz * Grid.W + ecx]
	if cur <= 0:
		return []
	for k in range(4):
		var nx: int = ecx + DXS[k]
		var nz: int = ecz + DZS[k]
		if not world.dungeon.grid.in_bounds(nx, nz):
			continue
		var nd: int = world.flow_dist[nz * Grid.W + nx]
		if nd >= 0 and nd == cur - 1:
			return [nx, nz]
	return []


static func cheb_cells(e: EntitySim, p: PlayerSim) -> int:
	var ecx: int = FixedMath.div_floor(e.pos_x, Grid.CELL)
	var ecz: int = FixedMath.div_floor(e.pos_z, Grid.CELL)
	return FixedMath.max_i(FixedMath.abs_i(ecx - p.cell_x()), FixedMath.abs_i(ecz - p.cell_z()))


static func in_reach(e: EntitySim, p: PlayerSim) -> bool:
	var t: Dictionary = TYPES[e.type]
	var d: int = FixedMath.max_i(FixedMath.abs_i(e.pos_x - p.pos_x), FixedMath.abs_i(e.pos_z - p.pos_z))
	return d <= int(t["reach"])


## Passo 6: máquina de estados de cada inimigo, em ordem crescente de id. O boneco é ignorado.
static func step_all(world: WorldSim) -> void:
	ensure_flow(world)
	var p: PlayerSim = world.player
	for i in range(world.enemies.size()):
		var e: EntitySim = world.enemies[i]
		if e.type == "dummy" or e.state == "DEAD":
			continue
		var t: Dictionary = TYPES[e.type]
		if e.state == "IDLE":
			if cheb_cells(e, p) <= CHEB_WAKE_CELLS and los(world.dungeon.grid, e.pos_x, e.pos_z, p.pos_x, p.pos_z):
				e.awake = true
				e.state = "CHASE"
				e.state_ticks = 0
			continue                       # não age no tick em que acorda
		if e.state == "WINDUP":
			e.state_ticks += 1
			if e.state_ticks > int(t["windup"]):
				e.state = "STRIKE"
				e.state_ticks = 1
				_strike(world, e)
			continue
		if e.state == "STRIKE":
			e.state = "COOLDOWN"
			e.state_ticks = 1
			continue
		if e.state == "COOLDOWN":
			e.state_ticks += 1
			if e.state_ticks <= int(t["cooldown"]):
				continue
			e.state = "CHASE"
			e.state_ticks = 0              # segue para a lógica de CHASE no mesmo tick
		# CHASE
		if in_reach(e, p):
			e.state = "WINDUP"
			e.state_ticks = 1
		else:
			_move(world, e)
			e.state_ticks += 1


## Golpe no fim da preparação: só entra no canal se o jogador ainda estiver no alcance.
static func _strike(world: WorldSim, e: EntitySim) -> void:
	if in_reach(e, world.player):
		world.pending_hits.append({"src_x": e.pos_x, "src_z": e.pos_z, "dmg": int(TYPES[e.type]["dmg"])})


## Passo inteiro (sem momento) para o centro da próxima célula do fluxo; eixo X primeiro, depois Z.
static func _move(world: WorldSim, e: EntitySim) -> void:
	var p: PlayerSim = world.player
	var speed: int = TYPES[e.type]["speed"]
	var ecx: int = FixedMath.div_floor(e.pos_x, Grid.CELL)
	var ecz: int = FixedMath.div_floor(e.pos_z, Grid.CELL)
	var tx: int = 0
	var tz: int = 0
	if ecx == p.cell_x() and ecz == p.cell_z():
		tx = p.pos_x
		tz = p.pos_z
	else:
		var nxt: Array = flow_next(world, ecx, ecz)
		if nxt.is_empty():
			return
		tx = DungeonGen.cell_center_u(nxt[0])
		tz = DungeonGen.cell_center_u(nxt[1])
	var mx: int = FixedMath.clamp_i(tx - e.pos_x, -speed, speed)
	var mz: int = FixedMath.clamp_i(tz - e.pos_z, -speed, speed)
	if mx != 0 and not box_blocked(world, e, e.pos_x + mx, e.pos_z):
		e.pos_x += mx
	if mz != 0 and not box_blocked(world, e, e.pos_x, e.pos_z + mz):
		e.pos_z += mz


## Caixa semiaberta de `e` em (x, z) contra sólidos/portas fechadas, outras entidades vivas e o jogador.
static func box_blocked(world: WorldSim, e: EntitySim, x: int, z: int) -> bool:
	var h: int = EntitySim.HALF[e.type]
	if world.dungeon.grid.box_hits_solid(x - h, z - h, x + h, z + h):
		return true
	for i in range(world.enemies.size()):
		var o: EntitySim = world.enemies[i]
		if o.id == e.id or o.state == "DEAD":
			continue
		var s: int = h + int(EntitySim.HALF[o.type])
		if FixedMath.abs_i(x - o.pos_x) < s and FixedMath.abs_i(z - o.pos_z) < s:
			return true
	var sp: int = h + PlayerSim.PLAYER_HALF
	return FixedMath.abs_i(x - world.player.pos_x) < sp and FixedMath.abs_i(z - world.player.pos_z) < sp
