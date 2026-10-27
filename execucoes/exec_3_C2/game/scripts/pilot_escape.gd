class_name PilotEscape
extends RefCounted
## M6: piloto de fuga em malha fechada (plano R4 §4.9). Só lê o mundo e só usa
## inteiros; consome apenas o próprio fluxo PCG32 (STREAM_PILOT).

const TrigTable = preload("res://sim/trig_table.gd")
const FixedMath = preload("res://sim/fixed_math.gd")
const PCG32 = preload("res://sim/rng_pcg32.gd")
const IntInput = preload("res://sim/int_input.gd")
const Grid = preload("res://sim/grid.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const Combat = preload("res://sim/combat.gd")

const TURN_STEP: int = 64
const COMBAT_RANGE: int = 3072
const BLOCK_MARGIN: int = 512
const QUAFF_HP_BELOW: int = 30
const STUCK_TICKS: int = 120
const UNSTICK_TICKS: int = 30

var _rng: PCG32
var _dist: PackedInt32Array = PackedInt32Array()
var _dist_key: String = ""
var _exit_cell: Array = []
var _exit_sha: String = ""
var _last_cell: int = -1
var _same_cell_ticks: int = 0
var _unstick_left: int = 0
var _last_quaff_tick: int = -2


func _init(seed_value: int) -> void:
	_rng = PCG32.new(seed_value, PCG32.STREAM_PILOT)


func next_input(world: Variant) -> IntInput:
	var inp := IntInput.new()
	var p: Variant = world.player
	var even: bool = (world.tick & 1) == 0
	var pcx: int = p.cell_x()
	var pcz: int = p.cell_z()
	var cell: int = pcz * Grid.SIZE + pcx
	if world.terminal != "NONE":
		return inp
	# 7. destravamento
	if cell == _last_cell:
		_same_cell_ticks += 1
	else:
		_last_cell = cell
		_same_cell_ticks = 0
	if _unstick_left == 0 and _same_cell_ticks >= STUCK_TICKS:
		_unstick_left = UNSTICK_TICKS
		_same_cell_ticks = 0
	if _unstick_left > 0:
		_unstick_left -= 1
		inp.move = 1
		inp.turn = TURN_STEP * (_rng.bounded(3) - 1)
		inp.strafe = _rng.bounded(3) - 1
		return inp
	# 6. poção (só nesse tick, nunca em dois ticks seguidos)
	if p.hp < QUAFF_HP_BELOW and p.potion_hp > 0 and world.tick != _last_quaff_tick + 1:
		inp.quaff = 1
		_last_quaff_tick = world.tick
	# 1. alvo
	var target: Array = _target_cell(world)
	if target.is_empty():
		return inp
	if pcx == target[0] and pcz == target[1] and p.has_key:
		inp.use = even
		return inp
	# 2. caminho
	var next: Array = _next_cell(world, target, pcx, pcz)
	var tx: int = next[0] * Grid.CELL + Grid.CELL / 2
	var tz: int = next[1] * Grid.CELL + Grid.CELL / 2
	# 5. combate: mira no inimigo vivo e acordado mais próximo
	var foe: Variant = _nearest_foe(world)
	if foe != null:
		tx = foe.pos_x
		tz = foe.pos_z
	# 3. direção sem atan2
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var dx: int = tx - p.pos_x
	var dz: int = tz - p.pos_z
	var along: int = (dx * fx + dz * fz) >> 16
	var side: int = (fx * dz - fz * dx) >> 16
	var aside: int = FixedMath.abs_i(side)
	if along > 0 and aside * 8 <= along:
		inp.turn = 0
	elif side > 0:
		inp.turn = TURN_STEP
	else:
		inp.turn = -TURN_STEP
	inp.move = 1 if along > 0 and aside * 2 <= along else 0
	if foe != null:
		if foe.state == "WINDUP" and foe.cheb(p.pos_x, p.pos_z) <= foe.stat("range") + BLOCK_MARGIN:
			inp.block = true
		elif Combat.hit(p, foe) and p.stamina >= Combat.SWING_COST:
			inp.attack = true
		return inp
	# 4. portas
	var nc: int = world.grid.get_cell(next[0], next[1])
	if (nc == Grid.DOOR_CLOSED or (nc == Grid.DOOR_LOCKED and p.has_key)) and along > 0 and aside <= along:
		inp.move = 0
		inp.use = even
	return inp


## Sem chave: célula do item `key`; com chave: célula EXIT.
func _target_cell(world: Variant) -> Array:
	if not world.player.has_key:
		for it: Dictionary in world.items:
			if it["type"] == "key" and not it["taken"]:
				return [it["cell_x"], it["cell_z"]]
		return []
	if _exit_sha != world.grid_sha256:
		_exit_sha = world.grid_sha256
		_exit_cell = []
		for z in range(Grid.SIZE):
			for x in range(Grid.SIZE):
				if world.grid.get_cell(x, z) == Grid.EXIT:
					_exit_cell = [x, z]
	return _exit_cell


## BFS a partir do alvo (recalculada quando a célula do jogador, a grade ou o alvo
## mudam); devolve a vizinha de menor distância (empate: N, L, S, O) ou o próprio alvo.
func _next_cell(world: Variant, target: Array, pcx: int, pcz: int) -> Array:
	var key: String = "%d,%d,%d,%d,%s,%s" % [pcx, pcz, target[0], target[1], world.grid_sha256, world.player.has_key]
	if key != _dist_key:
		_dist_key = key
		_dist = _bfs(world.grid, target[0], target[1], world.player.has_key)
	if pcx == target[0] and pcz == target[1]:
		return target
	var best: int = -1
	var out: Array = target
	for d: Array in EnemySim.FLOW_DIRS:
		var nx: int = pcx + d[0]
		var nz: int = pcz + d[1]
		if not Grid.in_bounds(nx, nz):
			continue
		var v: int = _dist[nz * Grid.SIZE + nx]
		if v >= 0 and (best < 0 or v < best):
			best = v
			out = [nx, nz]
	return out


static func _bfs(g: Grid, sx: int, sz: int, has_key: bool) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(Grid.SIZE * Grid.SIZE)
	dist.fill(-1)
	var queue := PackedInt32Array([sz * Grid.SIZE + sx])
	dist[sz * Grid.SIZE + sx] = 0
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var x: int = idx % Grid.SIZE
		@warning_ignore("integer_division")
		var z: int = idx / Grid.SIZE
		for d: Array in EnemySim.FLOW_DIRS:
			var nx: int = x + d[0]
			var nz: int = z + d[1]
			if not Grid.in_bounds(nx, nz):
				continue
			var c: int = g.get_cell(nx, nz)
			if c == Grid.SOLID or (c == Grid.DOOR_LOCKED and not has_key):
				continue
			var nidx: int = nz * Grid.SIZE + nx
			if dist[nidx] >= 0:
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


## Inimigo vivo e acordado mais próximo (Chebyshev, empate por id) a <= COMBAT_RANGE.
func _nearest_foe(world: Variant) -> Variant:
	var p: Variant = world.player
	var best: Variant = null
	var best_d: int = 0
	for e: Variant in world.enemies:
		if not e.is_alive() or not e.awake:
			continue
		var d: int = e.cheb(p.pos_x, p.pos_z)
		if d <= COMBAT_RANGE and (best == null or d < best_d):
			best = e
			best_d = d
	return best
