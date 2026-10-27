class_name EnemySim
extends RefCounted
## M4: tabela de tipos, entidade, IA (percepção por DDA, campo de fluxo, ataque)
## e colisão entre entidades (plano da iteração 2 §3). Só inteiros.

const DUMMY: int = 0
const RAT: int = 1
const SKELETON: int = 2
const GUARDIAN: int = 3

const IDLE: int = 0
const CHASE: int = 1
const WINDUP: int = 2
const STRIKE: int = 3
const COOLDOWN: int = 4
const DEAD: int = 5

## Tabela constante indexada por `type` (DUMMY, RAT, SKELETON, GUARDIAN).
const NAMES: Array = ["Boneco", "Rato", "Esqueleto", "Guardião"]
const HP: Array = [100, 20, 50, 150]
const SPEED: Array = [0, 100, 68, 51]
const DAMAGE: Array = [0, 5, 12, 25]
const REACH: Array = [0, 1024, 1229, 1434]
const WINDUP_TICKS: Array = [0, 8, 18, 30]
const COOLDOWN_TICKS: Array = [0, 30, 45, 60]
## XP só registrada (concedida em M6).
const XP: Array = [0, 10, 25, 100]
const HALF: Array = [320, 256, 320, 448]
const HEIGHT_U: Array = [1638, 512, 1792, 2355]

const WAKE_CELLS: int = 6
const LOS_MAX_STEPS: int = 256


class Enemy:
	extends RefCounted
	var id: int = 0
	var type: int = 0
	var pos_x: int = 0
	var pos_z: int = 0
	var hp: int = 0
	var state: int = 0
	var state_ticks: int = 0
	var awake: bool = false

	func to_dict() -> Dictionary:
		return {"id": id, "type": type, "pos_x": pos_x, "pos_z": pos_z, "hp": hp,
			"state": state, "state_ticks": state_ticks, "awake": awake}


static func half_of(t: int) -> int:
	return int(HALF[t])


static func height_of(t: int) -> int:
	return int(HEIGHT_U[t])


static func make(id: int, t: int, x: int, z: int) -> Enemy:
	var e: Enemy = Enemy.new()
	e.id = id
	e.type = t
	e.pos_x = x
	e.pos_z = z
	e.hp = int(HP[t])
	return e


## Um inimigo por sala exceto a inicial; Guardião na Sala da Saída, uma célula
## ao norte da célula EXIT. Continua o RNG da masmorra (`rng`) depois da grade pronta.
static func spawn_for_dungeon(g: Grid, rng: RngPcg32) -> Array:
	var out: Array = []
	for r: Dictionary in g.rooms:
		var rid: int = int(r["id"])
		if rid == g.start_room:
			continue
		var c: Array = DungeonGen.room_center(r)
		var cx: int = int(c[0])
		var cz: int = int(c[1])
		var t: int = GUARDIAN
		if rid == g.exit_room:
			cz += 1
		else:
			t = RAT + rng.range_i(0, 1)
		out.append(make(out.size(), t, cx * Grid.CELL + Grid.CELL / 2, cz * Grid.CELL + Grid.CELL / 2))
	return out


static func cell_of(v: int) -> int:
	return FixedMath.div_floor(v, Grid.CELL)


static func sign_i(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0


## Linha de visão por DDA inteiro (Amanatides–Woo) entre centros, em u.
## Empate (quina exata): as duas células intermediárias contam (conservador).
static func los(g: Grid, ax: int, az: int, bx: int, bz: int) -> bool:
	var cx: int = cell_of(ax)
	var cz: int = cell_of(az)
	var tcx: int = cell_of(bx)
	var tcz: int = cell_of(bz)
	var sx: int = sign_i(bx - ax)
	var sz: int = sign_i(bz - az)
	var adx: int = FixedMath.abs_i(bx - ax)
	var adz: int = FixedMath.abs_i(bz - az)
	for _i: int in range(LOS_MAX_STEPS):
		if cx == tcx and cz == tcz:
			return true
		var step_x: bool = false
		var step_z: bool = false
		if sx == 0:
			step_z = true
		elif sz == 0:
			step_x = true
		else:
			var bnd_x: int = (cx + 1) * Grid.CELL if sx > 0 else cx * Grid.CELL
			var bnd_z: int = (cz + 1) * Grid.CELL if sz > 0 else cz * Grid.CELL
			var t_x: int = FixedMath.abs_i(bnd_x - ax) * adz
			var t_z: int = FixedMath.abs_i(bnd_z - az) * adx
			step_x = t_x <= t_z
			step_z = t_z <= t_x
		if step_x and step_z:
			if g.is_blocking(cx + sx, cz) or g.is_blocking(cx, cz + sz):
				return false
			cx += sx
			cz += sz
		elif step_x:
			cx += sx
		else:
			cz += sz
		if cx == tcx and cz == tcz:
			return true
		if g.is_blocking(cx, cz):
			return false
	return false


## BFS N, L, S, O a partir da célula do jogador; passável = não bloqueante. -1 = inalcançável.
static func flow_field(g: Grid, pcx: int, pcz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	if not Grid.in_bounds(pcx, pcz) or g.is_blocking(pcx, pcz):
		return dist
	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(pcz * Grid.W + pcx)
	dist[pcz * Grid.W + pcx] = 0
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
			if dist[nidx] >= 0 or g.is_blocking(nx, nz):
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


static func cheb_u(e: Enemy, p: PlayerSim) -> int:
	return maxi(FixedMath.abs_i(e.pos_x - p.pos_x), FixedMath.abs_i(e.pos_z - p.pos_z))


## Caixa do inimigo em (x, z) colide com a grade ou com outra entidade viva (inimigos e jogador)?
static func blocked_at(g: Grid, enemies: Array, p: PlayerSim, e: Enemy, x: int, z: int) -> bool:
	var h: int = half_of(e.type)
	if g.box_hits_solid(x - h, z - h, x + h, z + h):
		return true
	if Combat.boxes_overlap(x, z, h, p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF):
		return true
	for o: Enemy in enemies:
		if o.id == e.id or o.state == DEAD:
			continue
		if Combat.boxes_overlap(x, z, h, o.pos_x, o.pos_z, half_of(o.type)):
			return true
	return false


## Passo 6: todos os inimigos em ordem crescente de id. `pending` recebe os golpes.
## `flow` é o campo de fluxo já atualizado para a célula do jogador.
static func step_all(g: Grid, enemies: Array, p: PlayerSim, flow: PackedInt32Array, pending: Array) -> void:
	var pcx: int = cell_of(p.pos_x)
	var pcz: int = cell_of(p.pos_z)
	for e: Enemy in enemies:
		if e.state == DEAD or e.type == DUMMY:
			continue
		# 6.1 percepção
		if not e.awake:
			var cheb: int = maxi(FixedMath.abs_i(cell_of(e.pos_x) - pcx), FixedMath.abs_i(cell_of(e.pos_z) - pcz))
			if cheb <= WAKE_CELLS and los(g, e.pos_x, e.pos_z, p.pos_x, p.pos_z):
				e.awake = true
				e.state = CHASE
				e.state_ticks = 0
			else:
				continue
		# 6.2 máquina de estados
		if e.state != IDLE:
			e.state_ticks += 1
		if e.state == CHASE:
			if cheb_u(e, p) <= int(REACH[e.type]):
				e.state = WINDUP
				e.state_ticks = 0
			else:
				_move(g, enemies, p, e, flow, pcx, pcz)
		elif e.state == WINDUP:
			if e.state_ticks >= int(WINDUP_TICKS[e.type]):
				e.state = STRIKE
				e.state_ticks = 0
				if cheb_u(e, p) <= int(REACH[e.type]):
					pending.append({"origin_x": e.pos_x, "origin_z": e.pos_z, "dmg": int(DAMAGE[e.type])})
		elif e.state == STRIKE:
			e.state = COOLDOWN
			e.state_ticks = 0
		elif e.state == COOLDOWN:
			if e.state_ticks >= int(COOLDOWN_TICKS[e.type]):
				e.state = CHASE
				e.state_ticks = 0


## Passo inteiro por eixo (X e depois Z) rumo ao centro da próxima célula do fluxo.
## O jogador não é bloqueado por inimigos (contrato da rodada): se ele já se
## sobrepõe a este inimigo, o inimigo não se move em eixo algum até separar.
static func _move(g: Grid, enemies: Array, p: PlayerSim, e: Enemy, flow: PackedInt32Array,
		pcx: int, pcz: int) -> void:
	if Combat.boxes_overlap(e.pos_x, e.pos_z, half_of(e.type), p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF):
		return
	var ecx: int = cell_of(e.pos_x)
	var ecz: int = cell_of(e.pos_z)
	var tx: int = p.pos_x
	var tz: int = p.pos_z
	if ecx != pcx or ecz != pcz:
		if not Grid.in_bounds(ecx, ecz):
			return
		var here: int = flow[ecz * Grid.W + ecx]
		if here < 0:
			return
		var found: bool = false
		for d: Array in DungeonGen.DIRS:
			var nx: int = ecx + int(d[0])
			var nz: int = ecz + int(d[1])
			if Grid.in_bounds(nx, nz) and flow[nz * Grid.W + nx] == here - 1:
				tx = nx * Grid.CELL + Grid.CELL / 2
				tz = nz * Grid.CELL + Grid.CELL / 2
				found = true
				break
		if not found:
			return
	var spd: int = int(SPEED[e.type])
	var mx: int = FixedMath.clamp_i(tx - e.pos_x, -spd, spd)
	var mz: int = FixedMath.clamp_i(tz - e.pos_z, -spd, spd)
	if mx != 0 and not blocked_at(g, enemies, p, e, e.pos_x + mx, e.pos_z):
		e.pos_x += mx
	if mz != 0 and not blocked_at(g, enemies, p, e, e.pos_x, e.pos_z + mz):
		e.pos_z += mz
