class_name PilotSim
extends RefCounted
## M6-A6: piloto em malha fechada do runner (plano da iteração 4 §3.9). Só lê o
## WorldSim e devolve um IntInput por tick; RNG próprio no fluxo STREAM_PILOT.
## O estado interno fica aqui, fora de s_k: a trilha gravada reproduz a partida (R4).

const ENGAGE_U: int = 3072
const BLOCK_MARGIN: int = 512
const SAFE_CELLS: int = 3
const LOW_HP: int = 30
const LOW_SP: int = 15
const TURN_FAST: int = 48
const TURN_FINE: int = 16
const STUCK_TICKS: int = 45
const UNSTICK_TICKS: int = 20
## Exploração: 2 valores em 32 (p = 1/16) dão strafe aleatório no tick.
const EXPLORE_SPAN: int = 31

var rng: RngPcg32 = null
## Objetivo fixo [cx, cz] no lugar de chave/saída (trilha de demonstração).
var goal_override: Array = []
var _last_attack: bool = false
var _last_use: bool = false
var _field: PackedInt32Array = PackedInt32Array()
var _field_key: String = ""
var _cell_x: int = -1
var _cell_z: int = -1
var _still: int = 0
var _unstick_left: int = 0
var _unstick_strafe: int = 0
var _last_move: int = 0


func _init(p_seed: int = 1) -> void:
	rng = RngPcg32.new(p_seed, DungeonGen.STREAM_PILOT)


static func cell_of(v: int) -> int:
	return FixedMath.div_floor(v, Grid.CELL)


static func center(c: int) -> int:
	return c * Grid.CELL + Grid.CELL / 2


## Mira inteira: devolve [turn, alinhado].
static func aim(p: PlayerSim, tx: int, tz: int) -> Array:
	var dx: int = tx - p.pos_x
	var dz: int = tz - p.pos_z
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var dot: int = (dx * fx + dz * fz) >> 16
	var cross: int = (fx * dz - fz * dx) >> 16
	var ac: int = FixedMath.abs_i(cross)
	if dot > 0 and ac * 4 <= dot:
		return [0, true]
	var turn: int = TURN_FAST
	if cross < 0:
		turn = -TURN_FAST
	if dot > 0 and ac * 2 <= dot:
		turn = TURN_FINE if cross > 0 else -TURN_FINE
	return [turn, false]


## Alvo de combate: vivo, acordado, não boneco, com linha de visão e a <= 3 m
## (Chebyshev); menor distância, desempate pelo menor id. Com a chave, o Guardião
## é ignorado (fugir passando por ele é válido).
static func combat_target(sim: WorldSim) -> EnemySim.Enemy:
	var best: EnemySim.Enemy = null
	var best_d: int = -1
	for e: EnemySim.Enemy in sim.enemies:
		if e.state == EnemySim.DEAD or not e.awake or e.type == EnemySim.DUMMY:
			continue
		if e.type == EnemySim.GUARDIAN and sim.player.has_key:
			continue
		var d: int = EnemySim.cheb_u(e, sim.player)
		if d > ENGAGE_U or (best != null and d >= best_d):
			continue
		if not EnemySim.los(sim.grid, e.pos_x, e.pos_z, sim.player.pos_x, sim.player.pos_z):
			continue
		best = e
		best_d = d
	return best


static func _enemy_near(sim: WorldSim, cells: int) -> bool:
	var pcx: int = cell_of(sim.player.pos_x)
	var pcz: int = cell_of(sim.player.pos_z)
	for e: EnemySim.Enemy in sim.enemies:
		if e.state == EnemySim.DEAD or not e.awake or e.type == EnemySim.DUMMY:
			continue
		if maxi(FixedMath.abs_i(cell_of(e.pos_x) - pcx), FixedMath.abs_i(cell_of(e.pos_z) - pcz)) <= cells:
			return true
	return false


## Objetivo de navegação: override, senão a chave (se ainda não a tem), senão EXIT.
func goal(sim: WorldSim) -> Array:
	if not goal_override.is_empty():
		return goal_override
	if not sim.player.has_key:
		for it: ItemsSim.Item in sim.items:
			if it.type == ItemsSim.KEY and not it.taken:
				return [it.cell_x, it.cell_z]
	for cz: int in range(Grid.H):
		for cx: int in range(Grid.W):
			if sim.grid.get_cell(cx, cz) == Grid.EXIT:
				return [cx, cz]
	return []


## Campo BFS a partir do objetivo: SOLID bloqueia, DOOR_CLOSED passa e
## DOOR_LOCKED só passa com a chave.
static func goal_field(g: Grid, gx: int, gz: int, has_key: bool) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.W * Grid.H)
	dist.fill(-1)
	if not Grid.in_bounds(gx, gz):
		return dist
	var queue: PackedInt32Array = PackedInt32Array()
	queue.append(gz * Grid.W + gx)
	dist[gz * Grid.W + gx] = 0
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
			if dist[nidx] >= 0 or t == Grid.SOLID or (t == Grid.DOOR_LOCKED and not has_key):
				continue
			dist[nidx] = dist[idx] + 1
			queue.append(nidx)
	return dist


func _field_for(sim: WorldSim, gl: Array) -> PackedInt32Array:
	var key: String = "%d,%d,%d,%s" % [int(gl[0]), int(gl[1]), sim.grid_version, sim.player.has_key]
	if key != _field_key:
		_field = goal_field(sim.grid, int(gl[0]), int(gl[1]), sim.player.has_key)
		_field_key = key
	return _field


## Próxima célula [cx, cz] do caminho até o objetivo; [] se já está nele ou sem caminho.
func next_cell(sim: WorldSim) -> Array:
	var gl: Array = goal(sim)
	if gl.is_empty():
		return []
	var f: PackedInt32Array = _field_for(sim, gl)
	var pcx: int = cell_of(sim.player.pos_x)
	var pcz: int = cell_of(sim.player.pos_z)
	if not Grid.in_bounds(pcx, pcz):
		return []
	var here: int = f[pcz * Grid.W + pcx]
	if here <= 0:
		return []
	for d: Array in DungeonGen.DIRS:
		var nx: int = pcx + int(d[0])
		var nz: int = pcz + int(d[1])
		if Grid.in_bounds(nx, nz) and f[nz * Grid.W + nx] == here - 1:
			return [nx, nz]
	return []


func _pulse_use() -> bool:
	return not _last_use


func next_input(sim: WorldSim) -> IntInput:
	var p: PlayerSim = sim.player
	# Exatamente um sorteio por tick (exploração).
	var explore: int = rng.range_i(0, EXPLORE_SPAN)
	var move: int = 0
	var strafe: int = 0
	var turn: int = 0
	var attack: bool = false
	var block: bool = false
	var use: bool = false
	var quaff: int = 0
	# 1. Poções
	if p.hp < LOW_HP and p.potion_hp > 0:
		quaff = 1
	elif p.stamina < LOW_SP and p.potion_sp > 0 and not _enemy_near(sim, SAFE_CELLS):
		quaff = 2
	var on_exit: bool = sim.on_exit_cell() and p.has_key and goal_override.is_empty()
	var target: EnemySim.Enemy = combat_target(sim)
	if on_exit:
		use = _pulse_use()
	elif target != null:
		# 2. Combate
		var a: Array = aim(p, target.pos_x, target.pos_z)
		turn = int(a[0])
		var aligned: bool = bool(a[1])
		var d: int = EnemySim.cheb_u(target, p)
		if target.state == EnemySim.WINDUP and d <= int(EnemySim.REACH[target.type]) + BLOCK_MARGIN:
			block = true
		elif d <= Combat.SWORD_REACH + EnemySim.half_of(target.type) and aligned and p.stamina >= Combat.SWING_COST:
			attack = not _last_attack
		elif p.stamina < Combat.SWING_COST:
			move = -1
			block = true
		elif aligned and d > Combat.SWORD_REACH + EnemySim.half_of(target.type):
			# Só avança alinhado: andar girando faz o jogador orbitar o alvo.
			move = 1
	else:
		# 3. Navegação
		var nc: Array = next_cell(sim)
		if not nc.is_empty():
			var nx: int = int(nc[0])
			var nz: int = int(nc[1])
			var t: int = sim.grid.get_cell(nx, nz)
			var a2: Array = aim(p, center(nx), center(nz))
			turn = int(a2[0])
			if t == Grid.DOOR_CLOSED or (t == Grid.DOOR_LOCKED and p.has_key):
				use = _pulse_use()
			elif bool(a2[1]) or FixedMath.abs_i(turn) == TURN_FINE:
				# Navegação: avança já na zona de ajuste fino (<= ~26°), girando junto.
				move = 1
	# 5. Destravamento e exploração
	var pcx: int = cell_of(p.pos_x)
	var pcz: int = cell_of(p.pos_z)
	if pcx != _cell_x or pcz != _cell_z:
		_cell_x = pcx
		_cell_z = pcz
		_still = 0
	elif _last_move != 0:
		_still += 1
	if _unstick_left == 0 and _still >= STUCK_TICKS:
		_unstick_left = UNSTICK_TICKS
		_unstick_strafe = -1 if rng.range_i(0, 1) == 0 else 1
		_still = 0
	if _unstick_left > 0:
		_unstick_left -= 1
		move = -1
		strafe = _unstick_strafe
		attack = false
		use = false
	elif explore < 2:
		strafe = explore * 2 - 1
	_last_attack = attack
	_last_use = use
	_last_move = move
	return IntInput.new(move, strafe, turn, attack, block, use, quaff)
