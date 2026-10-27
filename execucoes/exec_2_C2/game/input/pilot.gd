extends RefCounted
## Piloto em malha fechada (plano da rodada 3 §6): só LÊ o WorldSim e devolve um IntInput por tick.
## Só inteiros (o linter aplica as regras do núcleo a este arquivo). RNG próprio
## Pcg32(seed, STREAM_PILOT); nunca toca o RNG da masmorra. Usado pelo runner (--mode=pilot), pelo
## modo de atração de main.gd e pelos gates M6-A6, X1, X2 e V1.

const FM = preload("res://sim/fixed_math.gd")
const Grid = preload("res://sim/grid.gd")
const Trig = preload("res://sim/trig_table.gd")
const Pcg32 = preload("res://sim/rng_pcg32.gd")
const IntInput = preload("res://sim/int_input.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const Combat = preload("res://sim/combat.gd")

const TURN_MAX: int = 48
## ≈ 4096 / 2π: radianos (tangente pequena) -> BAM.
const RAD_TO_BAM: int = 652
## [ajustável] distância BFS (células) ao EXIT, com a chave, abaixo da qual o piloto ignora inimigos.
const ESCAPE_DIST: int = 0
## [ajustável] alcance (u, Chebyshev) para escolher um alvo de combate.
const COMBAT_RANGE: int = 8192
## [ajustável] folga sobre o alcance do inimigo para erguer o escudo durante o WINDUP dele.
const BLOCK_MARGIN: int = 512
const QUAFF_HP_BELOW: int = 30
const QUAFF_SP_BELOW: int = 20
## [ajustável] desatolamento: ticks parado com move = 1 antes de 20 ticks de strafe.
const STUCK_TICKS: int = 30
const UNSTICK_TICKS: int = 20
const DIRS: Array = [[0, -1], [1, 0], [0, 1], [-1, 0]]

var rng: Pcg32 = null
var _dist: PackedInt32Array = PackedInt32Array()
var _nav_key: String = ""
var _last_attack: bool = false
var _last_quaff: bool = false
var _use_toggle: bool = false
var _still_ticks: int = 0
var _unstick_left: int = 0
var _unstick_dir: int = 1
var _last_x: int = 0
var _last_z: int = 0


func _init(seed_value: int = 1) -> void:
	rng = Pcg32.new(seed_value, Pcg32.STREAM_PILOT)


func next_input(world: RefCounted) -> IntInput:
	var inp: IntInput = IntInput.new()
	var p: RefCounted = world.player
	var g: Grid = world.grid
	var has_key: bool = int(p.inventory.key) > 0
	var pcx: int = Grid.cell_of(p.pos_x)
	var pcz: int = Grid.cell_of(p.pos_z)
	# 1. objetivo
	var goal: Array = _exit_cell(g) if has_key else _key_cell(world)
	if goal.is_empty():
		goal = _exit_cell(g)
	# 2. navegação
	_refresh_nav(g, goal, has_key)
	var here: int = _dist[Grid.index_of(pcx, pcz)]
	var tx: int = p.pos_x
	var tz: int = p.pos_z
	var next_c: Array = []
	if here > 0:
		for dv: Array in DIRS:
			var nx: int = pcx + int(dv[0])
			var nz: int = pcz + int(dv[1])
			if Grid.in_bounds(nx, nz) and _dist[Grid.index_of(nx, nz)] == here - 1:
				next_c = [nx, nz]
				tx = Grid.cell_center(nx)
				tz = Grid.cell_center(nz)
				break
	elif here == 0:
		tx = Grid.cell_center(pcx)
		tz = Grid.cell_center(pcz)
	var steer: Array = _steer(p, tx - p.pos_x, tz - p.pos_z)
	inp.turn = steer[0]
	inp.move = 1 if steer[1] else 0
	if here == 0 and not has_key:
		inp.move = 0
	# 4. portas
	if not next_c.is_empty():
		var t: int = g.get_cell(next_c[0], next_c[1])
		if t == Grid.DOOR_CLOSED or (t == Grid.DOOR_LOCKED and has_key):
			if FM.max_i(FM.abs_i(int(next_c[0]) - pcx), FM.abs_i(int(next_c[1]) - pcz)) <= 1 \
					and steer[2] > 0 and FM.abs_i(steer[3]) <= steer[2]:
				_use_toggle = not _use_toggle
				inp.use = _use_toggle
	# 5. fuga
	var near_exit: bool = has_key and here >= 0 and here <= ESCAPE_DIST
	if has_key and g.get_cell(pcx, pcz) == Grid.EXIT:
		_use_toggle = not _use_toggle
		inp.use = _use_toggle
	# 6. combate
	if not near_exit:
		var target: Dictionary = _combat_target(world)
		if not target.is_empty():
			_fight(world, inp, target)
	# 7. poções (um tick; nunca em dois ticks seguidos)
	if _last_quaff:
		_last_quaff = false
	elif p.hp < QUAFF_HP_BELOW and int(p.inventory.potion_hp) > 0:
		inp.quaff = 1
		_last_quaff = true
	elif p.stamina < QUAFF_SP_BELOW and int(p.inventory.potion_sp) > 0:
		inp.quaff = 2
		_last_quaff = true
	# 8. exploração e desatolamento
	if rng.next_bounded(16) == 0:
		inp.strafe = 1 if rng.next_bounded(2) == 0 else -1
	if _unstick_left > 0:
		_unstick_left -= 1
		inp.strafe = _unstick_dir
	elif inp.move == 1 and p.pos_x == _last_x and p.pos_z == _last_z:
		_still_ticks += 1
		if _still_ticks >= STUCK_TICKS:
			_still_ticks = 0
			_unstick_left = UNSTICK_TICKS
			_unstick_dir = 1 if rng.next_bounded(2) == 0 else -1
	else:
		_still_ticks = 0
	_last_x = p.pos_x
	_last_z = p.pos_z
	return inp


## [turn, avança?, dot, cross] para encarar o vetor (dx, dz), sem trigonometria inversa.
func _steer(p: RefCounted, dx: int, dz: int) -> Array:
	var fx: int = Trig.cos_q16(p.angle)
	var fz: int = Trig.sin_q16(p.angle)
	var cross: int = (fx * dz - fz * dx) >> 16
	var dot: int = (fx * dx + fz * dz) >> 16
	var turn: int = 0
	if dot <= 0:
		turn = -TURN_MAX if cross < 0 else TURN_MAX
	else:
		turn = FM.clamp_i(FM.div_trunc(cross * RAD_TO_BAM, FM.max_i(dot, 1)), -TURN_MAX, TURN_MAX)
	var fwd: bool = dot > 0 and 2 * FM.abs_i(cross) < dot
	return [turn, fwd, dot, cross]


func _exit_cell(g: Grid) -> Array:
	if g.exit_room < 0:
		return []
	var r: Dictionary = g.rooms[g.exit_room]
	return [int(r.cx), int(r.cz)]


func _key_cell(world: RefCounted) -> Array:
	for it: Dictionary in world.items:
		if it.type == "key" and not it.taken:
			return [int(it.cell_x), int(it.cell_z)]
	return []


## BFS a partir do objetivo; passável = não SOLID; DOOR_LOCKED só com a chave.
func _refresh_nav(g: Grid, goal: Array, has_key: bool) -> void:
	var key: String = "%d,%d,%s,%s" % [goal[0], goal[1], has_key, g.sha256()]
	if key == _nav_key:
		return
	_nav_key = key
	_dist = PackedInt32Array()
	_dist.resize(Grid.GRID_W * Grid.GRID_H)
	_dist.fill(-1)
	var cells: PackedByteArray = g.cells
	var queue: PackedInt32Array = PackedInt32Array()
	queue.resize(Grid.GRID_W * Grid.GRID_H)
	var start: int = Grid.index_of(goal[0], goal[1])
	_dist[start] = 0
	queue[0] = start
	var head: int = 0
	var tail: int = 1
	while head < tail:
		var cur: int = queue[head]
		head += 1
		var cx: int = cur % Grid.GRID_W
		var cz: int = FM.div_trunc(cur, Grid.GRID_W)
		for dv: Array in DIRS:
			var nx: int = cx + int(dv[0])
			var nz: int = cz + int(dv[1])
			if not Grid.in_bounds(nx, nz):
				continue
			var ni: int = Grid.index_of(nx, nz)
			var t: int = cells[ni]
			if _dist[ni] >= 0 or t == Grid.SOLID or (t == Grid.DOOR_LOCKED and not has_key):
				continue
			_dist[ni] = _dist[cur] + 1
			queue[tail] = ni
			tail += 1


## Inimigo vivo e acordado mais próximo (Chebyshev) com linha de visão e a ≤ COMBAT_RANGE.
func _combat_target(world: RefCounted) -> Dictionary:
	var p: RefCounted = world.player
	var best: Dictionary = {}
	var best_d: int = COMBAT_RANGE + 1
	for e: Dictionary in world.enemies:
		if e.state == "DEAD" or not e.awake or e.type == "dummy":
			continue
		var d: int = FM.max_i(FM.abs_i(int(e.pos_x) - p.pos_x), FM.abs_i(int(e.pos_z) - p.pos_z))
		if d < best_d and EnemySim.los(world.grid, p.pos_x, p.pos_z, e.pos_x, e.pos_z):
			best = e
			best_d = d
	return best


func _fight(world: RefCounted, inp: IntInput, e: Dictionary) -> void:
	var p: RefCounted = world.player
	var steer: Array = _steer(p, int(e.pos_x) - p.pos_x, int(e.pos_z) - p.pos_z)
	inp.turn = steer[0]
	var dot: int = steer[2]
	var cross: int = steer[3]
	var d: int = FM.max_i(FM.abs_i(int(e.pos_x) - p.pos_x), FM.abs_i(int(e.pos_z) - p.pos_z))
	var reach: int = EnemySim.TYPES[e.type].reach
	inp.move = 0
	if e.state == "WINDUP" and d <= reach + BLOCK_MARGIN:
		inp.block = true
		_last_attack = false
		return
	if p.swing_state == "IDLE" and p.stamina >= Combat.SWING_COST and dot <= Combat.SWORD_REACH + int(e.half) \
			and dot > 0 and 2 * FM.abs_i(cross) < dot:
		if not _last_attack:
			inp.attack = true
			_last_attack = true
			return
	_last_attack = false
	if dot > Combat.SWORD_REACH and 2 * FM.abs_i(cross) < dot:
		inp.move = 1
