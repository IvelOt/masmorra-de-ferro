class_name EnemySim
extends RefCounted
## M4: inimigo (entidade), tabela de tipos, percepção por DDA, campo de fluxo e IA
## (GDD §4.3, plano R3 §4.1–§4.6). Tudo inteiro.

const FixedMath = preload("res://sim/fixed_math.gd")
const Grid = preload("res://sim/grid.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
## Referência a si mesmo sem depender do cache global de class_name.
const EnemySimScript = preload("res://sim/enemy_sim.gd")

## Tabela constante por tipo (plano R3 §2). `xp` só é usado em M6.
const TYPES: Dictionary = {
	"dummy": {"hp": 100, "speed": 0, "damage": 0, "range": 0, "windup": 0, "cooldown": 0, "xp": 0, "half": 320, "height": 1434},
	"rat": {"hp": 20, "speed": 100, "damage": 5, "range": 1024, "windup": 8, "cooldown": 30, "xp": 10, "half": 256, "height": 614},
	"skeleton": {"hp": 50, "speed": 68, "damage": 12, "range": 1229, "windup": 18, "cooldown": 45, "xp": 25, "half": 320, "height": 1638},
	"guardian": {"hp": 150, "speed": 51, "damage": 25, "range": 1434, "windup": 30, "cooldown": 60, "xp": 100, "half": 448, "height": 2048},
}
## Percepção: raio de 6 células (distância euclidiana ao quadrado).
const SIGHT_CELLS_SQ: int = 36
const DDA_MAX_STEPS: int = 256
## Vizinhança-4 na ordem N, L, S, O em (x, z) da simulação.
const FLOW_DIRS: Array = [[0, 1], [1, 0], [0, -1], [-1, 0]]

var id: int = 0
var type: String = "dummy"
var pos_x: int = 0
var pos_z: int = 0
var hp: int = 0
var state: String = "IDLE"
var state_ticks: int = 0
var awake: bool = false


func _init(id_in: int = 0, type_in: String = "dummy", x: int = 0, z: int = 0) -> void:
	id = id_in
	type = type_in
	pos_x = x
	pos_z = z
	hp = TYPES[type_in]["hp"]


static func create(id_in: int, type_in: String, x: int, z: int) -> EnemySimScript:
	return EnemySimScript.new(id_in, type_in, x, z)


func stat(key: String) -> int:
	return TYPES[type][key]


func half() -> int:
	return TYPES[type]["half"]


func height() -> int:
	return TYPES[type]["height"]


func is_alive() -> bool:
	return state != "DEAD"


func cell_x() -> int:
	return FixedMath.div_floor(pos_x, Grid.CELL)


func cell_z() -> int:
	return FixedMath.div_floor(pos_z, Grid.CELL)


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "pos_x": pos_x, "pos_z": pos_z, "hp": hp,
		"state": state, "state_ticks": state_ticks, "awake": awake,
	}


## Distância de Chebyshev (u) entre o inimigo e um ponto.
func cheb(px: int, pz: int) -> int:
	return maxi(FixedMath.abs_i(pos_x - px), FixedMath.abs_i(pos_z - pz))


# ------------------------------------------------------------------ percepção

## Raio de 6 células e linha de visão (plano R3 §4.4).
static func perceives(grid: Grid, e: EnemySimScript, px: int, pz: int) -> bool:
	var dcx: int = FixedMath.div_floor(px, Grid.CELL) - e.cell_x()
	var dcz: int = FixedMath.div_floor(pz, Grid.CELL) - e.cell_z()
	if dcx * dcx + dcz * dcz > SIGHT_CELLS_SQ:
		return false
	return line_of_sight(grid, e.pos_x, e.pos_z, px, pz)


## DDA inteiro (Amanatides–Woo) do ponto a ao ponto b; as células das pontas não bloqueiam.
static func line_of_sight(grid: Grid, ax: int, az: int, bx: int, bz: int) -> bool:
	var cx: int = FixedMath.div_floor(ax, Grid.CELL)
	var cz: int = FixedMath.div_floor(az, Grid.CELL)
	var tx: int = FixedMath.div_floor(bx, Grid.CELL)
	var tz: int = FixedMath.div_floor(bz, Grid.CELL)
	var dx: int = bx - ax
	var dz: int = bz - az
	var sx: int = signi(dx)
	var sz: int = signi(dz)
	var adx: int = FixedMath.abs_i(dx)
	var adz: int = FixedMath.abs_i(dz)
	var nbx: int = (cx + (1 if sx > 0 else 0)) * Grid.CELL
	var nbz: int = (cz + (1 if sz > 0 else 0)) * Grid.CELL
	var steps: int = 0
	while cx != tx or cz != tz:
		steps += 1
		if steps > DDA_MAX_STEPS:
			return false
		var adv_x: bool
		var adv_z: bool
		if adx == 0:
			adv_x = false
			adv_z = true
		elif adz == 0:
			adv_x = true
			adv_z = false
		else:
			var tx_num: int = FixedMath.abs_i(nbx - ax) * adz
			var tz_num: int = FixedMath.abs_i(nbz - az) * adx
			adv_x = tx_num <= tz_num
			adv_z = tz_num <= tx_num
			if adv_x and adv_z:
				# canto exato: as duas células laterais precisam estar livres
				if _blocks_los(grid, cx + sx, cz, tx, tz) or _blocks_los(grid, cx, cz + sz, tx, tz):
					return false
		if adv_x:
			cx += sx
			nbx += sx * Grid.CELL
		if adv_z:
			cz += sz
			nbz += sz * Grid.CELL
		if _blocks_los(grid, cx, cz, tx, tz):
			return false
	return true


static func _blocks_los(grid: Grid, x: int, z: int, tx: int, tz: int) -> bool:
	if x == tx and z == tz:
		return false
	return grid.blocks_at(x, z)


# ------------------------------------------------------------------ campo de fluxo

## BFS vizinhança-4 (N, L, S, O) a partir da célula do jogador; -1 = inalcançável.
static func build_flow(grid: Grid, pcx: int, pcz: int) -> PackedInt32Array:
	var flow := PackedInt32Array()
	flow.resize(Grid.SIZE * Grid.SIZE)
	flow.fill(-1)
	if not Grid.in_bounds(pcx, pcz):
		return flow
	var queue := PackedInt32Array([pcz * Grid.SIZE + pcx])
	flow[pcz * Grid.SIZE + pcx] = 0
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var x: int = idx % Grid.SIZE
		@warning_ignore("integer_division")
		var z: int = idx / Grid.SIZE
		for d: Array in FLOW_DIRS:
			var nx: int = x + d[0]
			var nz: int = z + d[1]
			if not Grid.in_bounds(nx, nz) or not Grid.is_passable(grid.get_cell(nx, nz)):
				continue
			var nidx: int = nz * Grid.SIZE + nx
			if flow[nidx] >= 0:
				continue
			flow[nidx] = flow[idx] + 1
			queue.append(nidx)
	return flow


# ------------------------------------------------------------------ IA (passo 6)

## Um tick de IA deste inimigo. `world` fornece grid, player, enemies, flow e pending_hits.
func ai_step(world: Variant) -> void:
	if state == "DEAD" or type == "dummy":
		return
	var p: Variant = world.player
	match state:
		"IDLE":
			if perceives(world.grid, self, p.pos_x, p.pos_z):
				awake = true
				state = "CHASE"
				state_ticks = 0
		"CHASE":
			if cheb(p.pos_x, p.pos_z) <= stat("range"):
				state = "WINDUP"
				state_ticks = stat("windup")
			else:
				_move(world)
		"WINDUP":
			state_ticks -= 1
			if state_ticks == 0:
				state = "STRIKE"
				if cheb(p.pos_x, p.pos_z) <= stat("range"):
					world.pending_hits.append({"src_x": pos_x, "src_z": pos_z, "damage": stat("damage")})
		"STRIKE":
			state = "COOLDOWN"
			state_ticks = stat("cooldown")
		"COOLDOWN":
			state_ticks -= 1
			if state_ticks == 0:
				state = "CHASE"


func _move(world: Variant) -> void:
	var p: Variant = world.player
	var target_x: int
	var target_z: int
	var ecx: int = cell_x()
	var ecz: int = cell_z()
	if ecx == p.cell_x() and ecz == p.cell_z():
		target_x = p.pos_x
		target_z = p.pos_z
	else:
		var flow: PackedInt32Array = world.get_flow()
		var best: int = -1
		var best_x: int = 0
		var best_z: int = 0
		for d: Array in FLOW_DIRS:
			var nx: int = ecx + d[0]
			var nz: int = ecz + d[1]
			if not Grid.in_bounds(nx, nz):
				continue
			var f: int = flow[nz * Grid.SIZE + nx]
			if f >= 0 and (best < 0 or f < best):
				best = f
				best_x = nx
				best_z = nz
		if best < 0:
			return
		target_x = best_x * Grid.CELL + Grid.CELL / 2
		target_z = best_z * Grid.CELL + Grid.CELL / 2
	var speed: int = stat("speed")
	var mx: int = FixedMath.clamp_i(target_x - pos_x, -speed, speed)
	var mz: int = FixedMath.clamp_i(target_z - pos_z, -speed, speed)
	var h: int = half()
	var prev_x: int = pos_x
	pos_x += mx
	pos_x = world.grid.collide_axis(pos_x, pos_z, mx, h, true)[0]
	if _overlaps_any(world):
		pos_x = prev_x
	var prev_z: int = pos_z
	pos_z += mz
	pos_z = world.grid.collide_axis(pos_z, pos_x, mz, h, false)[0]
	if _overlaps_any(world):
		pos_z = prev_z


## Sobreposição estrita com o jogador ou com outro inimigo vivo.
func _overlaps_any(world: Variant) -> bool:
	var p: Variant = world.player
	var rp: int = half() + PlayerSim.PLAYER_HALF
	if FixedMath.abs_i(pos_x - p.pos_x) < rp and FixedMath.abs_i(pos_z - p.pos_z) < rp:
		return true
	for o: Variant in world.enemies:
		if o.id == id or o.state == "DEAD":
			continue
		var r: int = half() + o.half()
		if FixedMath.abs_i(pos_x - o.pos_x) < r and FixedMath.abs_i(pos_z - o.pos_z) < r:
			return true
	return false
