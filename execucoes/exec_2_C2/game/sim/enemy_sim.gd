extends RefCounted
## Inimigos (M4, GDD §4.4; plano da rodada 3 §4): tabela de tipos, linha de visão por DDA inteiro,
## campo de fluxo BFS a partir do jogador, movimento com colisão por eixo e máquina de estados.
## Só inteiros; o passo 6 de world_sim.step() chama step_all().

const FM = preload("res://sim/fixed_math.gd")
const Grid = preload("res://sim/grid.gd")
const PlayerSim = preload("res://sim/player_sim.gd")

## Condição de projeto: reach > half + PLAYER_HALF para os tipos com IA
## (rato 1024 > 640, esqueleto 1229 > 768, guardião 1434 > 896): um inimigo encostado no
## jogador está sempre no alcance.
const TYPES: Dictionary = {
	"dummy": {"hp": 100, "speed": 0, "dmg": 0, "reach": 0, "windup": 0, "cooldown": 0, "xp": 0, "half": 384},
	"guardian": {"hp": 150, "speed": 51, "dmg": 25, "reach": 1434, "windup": 30, "cooldown": 60, "xp": 100, "half": 512},
	"rat": {"hp": 20, "speed": 100, "dmg": 5, "reach": 1024, "windup": 8, "cooldown": 30, "xp": 10, "half": 256},
	"skeleton": {"hp": 50, "speed": 68, "dmg": 12, "reach": 1229, "windup": 18, "cooldown": 45, "xp": 25, "half": 384},
}

## Raio de percepção: 6 células (distância euclidiana em células, ao quadrado).
const SIGHT_CELLS_SQ: int = 36
const LOS_MAX_STEPS: int = 256
const CELL: int = 2048

const IDLE: String = "IDLE"
const CHASE: String = "CHASE"
const WINDUP: String = "WINDUP"
const STRIKE: String = "STRIKE"
const COOLDOWN: String = "COOLDOWN"
const DEAD: String = "DEAD"

## Vizinhança 4 na ordem N, L, S, O (= DungeonGen.DIRS).
const DIRS: Array = [[0, -1], [1, 0], [0, 1], [-1, 0]]


## Linha de visão do centro (x0, z0) ao centro (x1, z1), DDA inteiro estilo Amanatides–Woo.
## A célula inicial não é testada; sólido, porta fechada e porta trancada bloqueiam.
static func los(grid: Grid, x0: int, z0: int, x1: int, z1: int) -> bool:
	var cx: int = Grid.cell_of(x0)
	var cz: int = Grid.cell_of(z0)
	var tx: int = Grid.cell_of(x1)
	var tz: int = Grid.cell_of(z1)
	var dx: int = x1 - x0
	var dz: int = z1 - z0
	var sx: int = FM.sign_i(dx)
	var sz: int = FM.sign_i(dz)
	var adx: int = FM.abs_i(dx)
	var adz: int = FM.abs_i(dz)
	# distância até a primeira fronteira em cada eixo
	var nx: int = (cx + 1) * CELL - x0 if sx > 0 else x0 - cx * CELL
	var nz: int = (cz + 1) * CELL - z0 if sz > 0 else z0 - cz * CELL
	for _i in range(LOS_MAX_STEPS):
		if cx == tx and cz == tz:
			return true
		var step_x: bool = false
		var step_z: bool = false
		if sx == 0:
			step_z = true
		elif sz == 0:
			step_x = true
		else:
			# nx/adx contra nz/adz sem divisão
			var a: int = nx * adz
			var b: int = nz * adx
			if a < b:
				step_x = true
			elif a > b:
				step_z = true
			else:
				# canto exato: qualquer uma das duas células laterais bloqueia
				if grid.is_blocking_at(cx + sx, cz) or grid.is_blocking_at(cx, cz + sz):
					return false
				step_x = true
				step_z = true
		if step_x:
			cx += sx
			nx += CELL
		if step_z:
			cz += sz
			nz += CELL
		if grid.is_blocking_at(cx, cz):
			return false
	return false


## Campo de fluxo: BFS 4-vizinhança (N, L, S, O) a partir de (pcx, pcz); passável = não bloqueante.
## -1 = inalcançável. Função pura da grade e da célula do jogador (fora do hash).
static func flow_field(grid: Grid, pcx: int, pcz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.GRID_W * Grid.GRID_H)
	dist.fill(-1)
	if not Grid.in_bounds(pcx, pcz):
		return dist
	var cells: PackedByteArray = grid.cells
	var queue: PackedInt32Array = PackedInt32Array()
	queue.resize(Grid.GRID_W * Grid.GRID_H)
	var start: int = Grid.index_of(pcx, pcz)
	dist[start] = 0
	queue[0] = start
	var head: int = 0
	var tail: int = 1
	while head < tail:
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % Grid.GRID_W
		var cz: int = FM.div_trunc(cur, Grid.GRID_W)
		var d: int = dist[cur] + 1
		for dv: Array in DIRS:
			var nx: int = cx + int(dv[0])
			var nz: int = cz + int(dv[1])
			if not Grid.in_bounds(nx, nz):
				continue
			var ni: int = Grid.index_of(nx, nz)
			if dist[ni] >= 0 or Grid.is_blocking(cells[ni]):
				continue
			dist[ni] = d
			queue[tail] = ni
			tail += 1
	return dist


## Semiaberto: encostar não colide.
static func overlaps(x: int, z: int, h: int, ox: int, oz: int, oh: int) -> bool:
	return FM.abs_i(x - ox) < h + oh and FM.abs_i(z - oz) < h + oh


## Distância Chebyshev ≤ reach e linha de visão.
static func in_reach(world: RefCounted, e: Dictionary) -> bool:
	var p: RefCounted = world.player
	var ex: int = e.pos_x
	var ez: int = e.pos_z
	var reach: int = TYPES[e.type].reach
	if FM.max_i(FM.abs_i(p.pos_x - ex), FM.abs_i(p.pos_z - ez)) > reach:
		return false
	return los(world.grid, ex, ez, p.pos_x, p.pos_z)


## Recalcula o campo de fluxo só quando (célula do jogador, sha256 da grade) muda.
static func refresh_flow(world: RefCounted) -> void:
	var pcx: int = Grid.cell_of(world.player.pos_x)
	var pcz: int = Grid.cell_of(world.player.pos_z)
	var key: String = "%d,%d,%s" % [pcx, pcz, world.grid.sha256()]
	if key != world.flow_key:
		world.flow = flow_field(world.grid, pcx, pcz)
		world.flow_key = key


## Passo 6: inimigos em ordem crescente de id (pula DEAD e dummy).
static func step_all(world: RefCounted) -> void:
	for e: Dictionary in world.enemies:
		if e.type == "dummy" or e.state == DEAD:
			continue
		var t: Dictionary = TYPES[e.type]
		if e.state == IDLE:
			if _perceive(world, e):
				e.awake = true
				e.state = CHASE
				e.state_ticks = 0
				_chase(world, e)
		elif e.state == CHASE:
			_chase(world, e)
		elif e.state == WINDUP:
			e.state_ticks = int(e.state_ticks) + 1
			if int(e.state_ticks) > int(t.windup):
				e.state = STRIKE
				e.state_ticks = 1
				# resolvido no passo 7 do mesmo tick
				if in_reach(world, e):
					world.inject_hit(int(t.dmg), int(e.pos_x), int(e.pos_z))
		elif e.state == STRIKE:
			e.state = COOLDOWN
			e.state_ticks = 1
		elif e.state == COOLDOWN:
			e.state_ticks = int(e.state_ticks) + 1
			if int(e.state_ticks) > int(t.cooldown):
				e.state = CHASE
				e.state_ticks = 0
				_chase(world, e)


static func _perceive(world: RefCounted, e: Dictionary) -> bool:
	var p: RefCounted = world.player
	var dcx: int = Grid.cell_of(p.pos_x) - Grid.cell_of(int(e.pos_x))
	var dcz: int = Grid.cell_of(p.pos_z) - Grid.cell_of(int(e.pos_z))
	if dcx * dcx + dcz * dcz > SIGHT_CELLS_SQ:
		return false
	return los(world.grid, e.pos_x, e.pos_z, p.pos_x, p.pos_z)


static func _chase(world: RefCounted, e: Dictionary) -> void:
	if in_reach(world, e):
		e.state = WINDUP
		e.state_ticks = 1
		return
	_move(world, e)


## Movimento (plano §4.5). Diagonal não normalizada (cada eixo limitado a ±speed), coerente com
## o estilo DOOM do jogador. Um eixo bloqueado é cancelado (sem empurrão, sem prender à face),
## salvo se a entidade já estava bloqueada antes (entidades postas sobrepostas pelos testes).
static func _move(world: RefCounted, e: Dictionary) -> void:
	refresh_flow(world)
	var p: RefCounted = world.player
	var ex: int = e.pos_x
	var ez: int = e.pos_z
	var ecx: int = Grid.cell_of(ex)
	var ecz: int = Grid.cell_of(ez)
	if not Grid.in_bounds(ecx, ecz):
		return
	var flow: PackedInt32Array = world.flow
	var d: int = flow[Grid.index_of(ecx, ecz)]
	if d < 0:
		return
	var tx: int = p.pos_x
	var tz: int = p.pos_z
	if d > 1:
		for dv: Array in DIRS:
			var nx: int = ecx + int(dv[0])
			var nz: int = ecz + int(dv[1])
			if Grid.in_bounds(nx, nz) and flow[Grid.index_of(nx, nz)] == d - 1:
				tx = Grid.cell_center(nx)
				tz = Grid.cell_center(nz)
				break
	var speed: int = TYPES[e.type].speed
	var h: int = e.half
	var mx: int = FM.clamp_i(tx - ex, -speed, speed)
	var mz: int = FM.clamp_i(tz - ez, -speed, speed)
	if mx != 0:
		var nx2: int = ex + mx
		if not (_blocked(world, e, nx2, ez, h) and not _blocked(world, e, ex, ez, h)):
			ex = nx2
	if mz != 0:
		var nz2: int = ez + mz
		if not (_blocked(world, e, ex, nz2, h) and not _blocked(world, e, ex, ez, h)):
			ez = nz2
	e.pos_x = ex
	e.pos_z = ez


static func _blocked(world: RefCounted, self_e: Dictionary, x: int, z: int, h: int) -> bool:
	if world.grid.box_hits_solid(x - h, z - h, x + h, z + h):
		return true
	for o: Dictionary in world.enemies:
		if o.id == self_e.id or o.state == DEAD:
			continue
		if overlaps(x, z, h, o.pos_x, o.pos_z, o.half):
			return true
	var p: RefCounted = world.player
	return overlaps(x, z, h, p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF)


## Bloqueadores do jogador: [[x, z, half], …] das entidades vivas, em ordem de id.
static func blockers(world: RefCounted) -> Array:
	var out: Array = []
	for e: Dictionary in world.enemies:
		if e.state != DEAD:
			out.append([int(e.pos_x), int(e.pos_z), int(e.half)])
	return out
