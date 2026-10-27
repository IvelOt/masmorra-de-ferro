class_name EnemySim
extends RefCounted
## Inimigo (M4): tabela de tipos, percepção (DDA inteiro), campo de fluxo,
## máquina de estados, movimento por eixo e posicionamento na masmorra.

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

# índice = type
const HP: Array[int] = [100, 20, 50, 150]
const SPEED: Array[int] = [0, 100, 68, 51]
const DAMAGE: Array[int] = [0, 5, 12, 25]
const REACH: Array[int] = [0, 1024, 1229, 1434]
const WINDUP_TICKS: Array[int] = [0, 8, 18, 30]
const COOLDOWN_TICKS: Array[int] = [0, 30, 45, 60]
const XP: Array[int] = [0, 10, 25, 100]
const HALF: Array[int] = [384, 320, 384, 448]

const SIGHT_CELLS: int = 6
const LOS_MAX_STEPS: int = 256

# vizinhança-4 na ordem fixa N, L, S, O (N = -Z)
const NDX: Array[int] = [0, 1, 0, -1]
const NDZ: Array[int] = [-1, 0, 1, 0]

var id: int = 0
var type: int = DUMMY
var pos_x: int = 0
var pos_z: int = 0
var hp: int = 0
var state: int = IDLE
var state_ticks: int = 0
var awake: bool = false


static func make(id_in: int, type_in: int, x: int, z: int) -> EnemySim:
	var e: EnemySim = EnemySim.new()
	e.id = id_in
	e.type = type_in
	e.pos_x = x
	e.pos_z = z
	e.hp = HP[type_in]
	return e


func half() -> int:
	return HALF[type]


func alive() -> bool:
	return state != DEAD


func cell_x() -> int:
	return pos_x >> Grid.CELL_SHIFT


func cell_z() -> int:
	return pos_z >> Grid.CELL_SHIFT


## Aplica dano do golpe do jogador (§4.3 do plano).
func take_hit(dmg: int) -> void:
	hp -= dmg
	if type != DUMMY:
		awake = true
		if state == IDLE:
			state = CHASE
	if hp <= 0:
		hp = 0
		state = DEAD
		state_ticks = 0


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "pos_x": pos_x, "pos_z": pos_z, "hp": hp,
		"state": state, "state_ticks": state_ticks, "awake": awake,
	}


## Caixas [c-h, c+h) se intersectam nos dois eixos?
static func boxes_overlap(ax: int, az: int, ah: int, bx: int, bz: int, bh: int) -> bool:
	return ax - ah < bx + bh and bx - bh < ax + ah and az - ah < bz + bh and bz - bh < az + ah


static func is_opaque(g: Grid, cx: int, cz: int) -> bool:
	return g.is_blocking(cx, cz)


static func _sign(v: int) -> int:
	if v > 0:
		return 1
	if v < 0:
		return -1
	return 0


## Linha de visão por DDA inteiro (Amanatides-Woo), centro a centro.
static func line_of_sight(g: Grid, x0: int, z0: int, x1: int, z1: int) -> bool:
	var cx: int = x0 >> Grid.CELL_SHIFT
	var cz: int = z0 >> Grid.CELL_SHIFT
	var tx: int = x1 >> Grid.CELL_SHIFT
	var tz: int = z1 >> Grid.CELL_SHIFT
	var dx: int = x1 - x0
	var dz: int = z1 - z0
	var sx: int = _sign(dx)
	var sz: int = _sign(dz)
	var adx: int = FixedMath.abs_i(dx)
	var adz: int = FixedMath.abs_i(dz)
	var bx: int = (((cx + 1) << Grid.CELL_SHIFT) - x0) if sx > 0 else (x0 - (cx << Grid.CELL_SHIFT))
	var bz: int = (((cz + 1) << Grid.CELL_SHIFT) - z0) if sz > 0 else (z0 - (cz << Grid.CELL_SHIFT))
	var steps: int = 0
	while cx != tx or cz != tz:
		steps += 1
		if steps > LOS_MAX_STEPS:
			return false
		if adx == 0:
			cz += sz
			bz += Grid.CELL
		elif adz == 0:
			cx += sx
			bx += Grid.CELL
		else:
			var lhs: int = bx * adz
			var rhs: int = bz * adx
			if lhs < rhs:
				cx += sx
				bx += Grid.CELL
			elif lhs > rhs:
				cz += sz
				bz += Grid.CELL
			else:
				if is_opaque(g, cx + sx, cz) or is_opaque(g, cx, cz + sz):
					return false
				cx += sx
				cz += sz
				bx += Grid.CELL
				bz += Grid.CELL
		if (cx != tx or cz != tz) and is_opaque(g, cx, cz):
			return false
	return true


static func passable_for_enemy(t: int) -> bool:
	return t == Grid.FLOOR or t == Grid.DOOR_OPEN or t == Grid.EXIT


## BFS a partir da célula do jogador; -1 = inalcançável.
static func flow_field(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.SIZE * Grid.SIZE)
	dist.fill(-1)
	if not Grid.in_bounds(sx, sz):
		return dist
	var queue: PackedInt32Array = PackedInt32Array([sz * Grid.SIZE + sx])
	dist[queue[0]] = 0
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cx: int = cur & (Grid.SIZE - 1)
		var cz: int = cur >> 6
		for k in range(4):
			var nx: int = cx + NDX[k]
			var nz: int = cz + NDZ[k]
			if not passable_for_enemy(g.get_cell(nx, nz)):
				continue
			var ni: int = nz * Grid.SIZE + nx
			if dist[ni] >= 0:
				continue
			dist[ni] = dist[cur] + 1
			queue.append(ni)
	return dist


func cheb_to(px: int, pz: int) -> int:
	return maxi(FixedMath.abs_i(pos_x - px), FixedMath.abs_i(pos_z - pz))


## Passo 6 para este inimigo (vivo, não DUMMY). Enfileira dano em hits.
func think(w: WorldSim, hits: Array[Dictionary]) -> void:
	var p: PlayerSim = w.player
	if not awake:
		var cd: int = maxi(FixedMath.abs_i(cell_x() - p.cell_x()), FixedMath.abs_i(cell_z() - p.cell_z()))
		if cd > SIGHT_CELLS or not line_of_sight(w.grid, pos_x, pos_z, p.pos_x, p.pos_z):
			return
		awake = true
		state = CHASE
		state_ticks = 0
	state_ticks += 1
	if state == WINDUP:
		if state_ticks >= WINDUP_TICKS[type]:
			state = STRIKE
			state_ticks = 0
			if cheb_to(p.pos_x, p.pos_z) <= REACH[type]:
				hits.append({"src_x": pos_x, "src_z": pos_z, "dmg": DAMAGE[type]})
		return
	if state == STRIKE:
		state = COOLDOWN
		state_ticks = 0
		return
	if state == COOLDOWN:
		if state_ticks < COOLDOWN_TICKS[type]:
			return
		state = CHASE
		state_ticks = 0
	if state == CHASE:
		if cheb_to(p.pos_x, p.pos_z) <= REACH[type]:
			state = WINDUP
			state_ticks = 0
			return
		_chase_move(w)
		if cheb_to(p.pos_x, p.pos_z) <= REACH[type]:
			state = WINDUP
			state_ticks = 0


func _chase_move(w: WorldSim) -> void:
	var dist: PackedInt32Array = w.flow()
	var cx: int = cell_x()
	var cz: int = cell_z()
	if not Grid.in_bounds(cx, cz):
		return
	var dc: int = dist[cz * Grid.SIZE + cx]
	var ax: int = 0
	var az: int = 0
	if dc < 0:
		return
	if dc == 0:
		ax = w.player.pos_x
		az = w.player.pos_z
	else:
		var found: bool = false
		for k in range(4):
			var nx: int = cx + NDX[k]
			var nz: int = cz + NDZ[k]
			if not Grid.in_bounds(nx, nz):
				continue
			if dist[nz * Grid.SIZE + nx] == dc - 1:
				ax = (nx << Grid.CELL_SHIFT) + 1024
				az = (nz << Grid.CELL_SHIFT) + 1024
				found = true
				break
		if not found:
			return
	var v: int = SPEED[type]
	var mx: int = FixedMath.clamp_i(ax - pos_x, -v, v)
	var mz: int = FixedMath.clamp_i(az - pos_z, -v, v)
	if mx != 0 and not w.entity_blocked(self, pos_x + mx, pos_z):
		pos_x += mx
	if mz != 0 and not w.entity_blocked(self, pos_x, pos_z + mz):
		pos_z += mz


## Posicionamento na masmorra (§5.6), continuando d.rng depois da grade pronta.
static func spawn_dungeon(d: DungeonGen) -> Array[EnemySim]:
	var out: Array[EnemySim] = []
	for r: Dictionary in d.rooms:
		var rid: int = r.id
		if rid == d.start_room:
			continue
		if rid == d.exit_room:
			var gx: int = d.exit_cell[0]
			var gz: int = d.exit_cell[1] - 1
			out.append(make(out.size(), GUARDIAN, (gx << Grid.CELL_SHIFT) + 1024, (gz << Grid.CELL_SHIFT) + 1024))
			continue
		var t: int = RAT if d.rng.next_range(100) < 55 else SKELETON
		var ccx: int = int(r.x) + (int(r.w) >> 1)
		var ccz: int = int(r.z) + (int(r.h) >> 1)
		out.append(make(out.size(), t, (ccx << Grid.CELL_SHIFT) + 1024, (ccz << Grid.CELL_SHIFT) + 1024))
	return out
