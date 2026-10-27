class_name Pilot
extends RefCounted
## Piloto em malha fechada (M6-A6, plano §6): só lê a WorldSim e devolve o
## IntInput do tick. Usa apenas o fluxo PCG do piloto (seq = 3). Só inteiros.
##
## Limiares usados:
##   ENGAGE_RANGE = 2048 + SWING_REACH  alcance para adotar um inimigo como alvo (com linha de visão)
##   ATTACK_RANGE = SWING_REACH + HALF  alcance do golpe; ATTACK_TAN = tan 30 x 1024
##   STAND_OFF    = 1100                abaixo disso o piloto não avança sobre o alvo
##   QUAFF_HP_BELOW = 30, QUAFF_SP_BELOW = 15
##   EXPLORE = 1/16 com +-24 BAM; STUCK_TICKS = 30; UNSTUCK_TICKS = 20
## Objetivo com chave: vai direto ao EXIT; a rota com chave atravessa DOOR_LOCKED
## e o piloto abre cada porta trancada no caminho (equivale à etapa "porta
## trancada mais próxima" do plano, pois toda porta da sala da saída é trancada).

const ENGAGE_RANGE: int = 2048 + Combat.SWING_REACH
const ATTACK_TAN: int = 591
const STAND_OFF: int = 1100
const QUAFF_HP_BELOW: int = 30
const QUAFF_SP_BELOW: int = 15
const EXPLORE_TURN: int = 24
const STUCK_TICKS: int = 30
const UNSTUCK_TICKS: int = 20

var _rng: RngPcg32
var _dist: PackedInt32Array = PackedInt32Array()
var _route_goal: int = -1
var _route_cell: int = -1
var _route_key: bool = false
var _last_x: int = 0
var _last_z: int = 0
var _still: int = 0
var _unstuck: int = 0
var _unstuck_dir: int = 1


static func create(seed_value: int) -> Pilot:
	var p: Pilot = Pilot.new()
	p._rng = RngPcg32.create(seed_value, RngPcg32.STREAM_PILOT)
	return p


func next_input(w: WorldSim) -> IntInput:
	var inp: IntInput = IntInput.new()
	var p: PlayerSim = w.player
	# 7. sorteios da exploração: sempre dois por tick
	var explore: bool = _rng.next_range(16) == 0
	var explore_sign: int = _rng.next_range(2) * 2 - 1
	if w.terminal != "NONE":
		return inp
	var target: EnemySim = _pick_target(w)
	if target != null:
		_steer(inp, p, target.pos_x, target.pos_z)
		var dx: int = target.pos_x - p.pos_x
		var dz: int = target.pos_z - p.pos_z
		var cheb: int = maxi(FixedMath.abs_i(dx), FixedMath.abs_i(dz))
		var fx: int = TrigTable.cos_q16(p.angle)
		var fz: int = TrigTable.sin_q16(p.angle)
		var along: int = (dx * fx + dz * fz) >> 16
		var side: int = FixedMath.abs_i((dx * fz - dz * fx) >> 16)
		var facing: bool = along > 0 and side * 1024 <= along * ATTACK_TAN
		if cheb <= STAND_OFF:
			inp.move = 0
		if target.state == EnemySim.WINDUP and facing:
			inp.block = true
			inp.move = 0
		elif p.swing_state == Combat.S_IDLE and p.stamina >= Combat.SWING_COST \
				and cheb <= Combat.SWING_REACH + target.half() and facing:
			inp.attack = true
	else:
		_route(inp, w)
	# 6. poções
	if p.hp < QUAFF_HP_BELOW and p.potion_hp > 0:
		inp.quaff = 1
	elif p.stamina < QUAFF_SP_BELOW and p.potion_sp > 0:
		inp.quaff = 2
	if explore:
		inp.turn = FixedMath.clamp_i(inp.turn + explore_sign * EXPLORE_TURN, -128, 128)
	# 8. destravamento
	if _unstuck > 0:
		_unstuck -= 1
		inp.move = -1
		inp.strafe = _unstuck_dir
	elif inp.move == 1 and p.pos_x == _last_x and p.pos_z == _last_z:
		_still += 1
		if _still >= STUCK_TICKS:
			_still = 0
			_unstuck = UNSTUCK_TICKS
			_unstuck_dir = 1 if (w.tick & 1) == 0 else -1
	else:
		_still = 0
	_last_x = p.pos_x
	_last_z = p.pos_z
	return inp


## Inimigo vivo e acordado mais próximo (Chebyshev, desempate por id), com
## linha de visão, a até ENGAGE_RANGE.
func _pick_target(w: WorldSim) -> EnemySim:
	var p: PlayerSim = w.player
	var best: EnemySim = null
	var best_d: int = 0
	for e in w.enemies:
		if not e.alive() or not e.awake:
			continue
		var d: int = e.cheb_to(p.pos_x, p.pos_z)
		if d > ENGAGE_RANGE:
			continue
		if best != null and d >= best_d:
			continue
		if not EnemySim.line_of_sight(w.grid, p.pos_x, p.pos_z, e.pos_x, e.pos_z):
			continue
		best = e
		best_d = d
	return best


## Objetivo atual como índice de célula: chave, depois EXIT.
func _goal(w: WorldSim) -> int:
	if not w.player.has_key:
		for it: Dictionary in w.items:
			if int(it.type) == ItemsSim.KEY and not it.taken:
				return int(it.cell_z) * Grid.SIZE + int(it.cell_x)
	var ec: Array[int] = w.dungeon.exit_cell
	if ec.size() == 2:
		return ec[1] * Grid.SIZE + ec[0]
	return -1


static func _passable(t: int, key: bool) -> bool:
	return t == Grid.FLOOR or t == Grid.DOOR_OPEN or t == Grid.DOOR_CLOSED or t == Grid.EXIT \
		or (key and t == Grid.DOOR_LOCKED)


func _bfs(g: Grid, goal: int, key: bool) -> PackedInt32Array:
	var dist: PackedInt32Array = PackedInt32Array()
	dist.resize(Grid.SIZE * Grid.SIZE)
	dist.fill(-1)
	var queue: PackedInt32Array = PackedInt32Array([goal])
	dist[goal] = 0
	var head: int = 0
	while head < queue.size():
		var cur: int = queue[head]
		head += 1
		var cx: int = cur & (Grid.SIZE - 1)
		var cz: int = cur >> 6
		for k in range(4):
			var nx: int = cx + EnemySim.NDX[k]
			var nz: int = cz + EnemySim.NDZ[k]
			if not _passable(g.get_cell(nx, nz), key):
				continue
			var ni: int = nz * Grid.SIZE + nx
			if dist[ni] >= 0:
				continue
			dist[ni] = dist[cur] + 1
			queue.append(ni)
	return dist


func _route(inp: IntInput, w: WorldSim) -> void:
	var p: PlayerSim = w.player
	var goal: int = _goal(w)
	if goal < 0:
		return
	var cx: int = p.cell_x()
	var cz: int = p.cell_z()
	var cell: int = cz * Grid.SIZE + cx
	# portas mudam a grade: a rota também é refeita a cada porta aberta
	if goal != _route_goal or cell != _route_cell or p.has_key != _route_key or _dist.is_empty():
		_dist = _bfs(w.grid, goal, p.has_key)
		_route_goal = goal
		_route_cell = cell
		_route_key = p.has_key
	var gx: int = goal & (Grid.SIZE - 1)
	var gz: int = goal >> 6
	var tx: int = (gx << Grid.CELL_SHIFT) + 1024
	var tz: int = (gz << Grid.CELL_SHIFT) + 1024
	var next_x: int = gx
	var next_z: int = gz
	var dc: int = _dist[cell] if Grid.in_bounds(cx, cz) else -1
	if dc > 0:
		for k in range(4):
			var nx: int = cx + EnemySim.NDX[k]
			var nz: int = cz + EnemySim.NDZ[k]
			if Grid.in_bounds(nx, nz) and _dist[nz * Grid.SIZE + nx] == dc - 1:
				next_x = nx
				next_z = nz
				tx = (nx << Grid.CELL_SHIFT) + 1024
				tz = (nz << Grid.CELL_SHIFT) + 1024
				break
	_steer(inp, p, tx, tz)
	# 4. portas e saída
	var nt: int = w.grid.get_cell(next_x, next_z)
	if dc > 0 and (nt == Grid.DOOR_CLOSED or (nt == Grid.DOOR_LOCKED and p.has_key)):
		var dir: int = 0
		for k in range(4):
			if cx + [1, 0, -1, 0][k] == next_x and cz + [0, 1, 0, -1][k] == next_z:
				dir = k
		var rel: int = ((p.angle - dir * 1024 + 2048) & 4095) - 2048
		if FixedMath.abs_i(rel) <= 512:
			inp.use = true
	if dc == 0 and w.grid.get_cell(cx, cz) == Grid.EXIT and p.has_key:
		inp.use = true


## Item 3 do plano: giro proporcional ao produto vetorial; anda só alinhado.
func _steer(inp: IntInput, p: PlayerSim, tx: int, tz: int) -> void:
	var dx: int = tx - p.pos_x
	var dz: int = tz - p.pos_z
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var cross: int = (fx * dz - fz * dx) >> 16
	var dot: int = (fx * dx + fz * dz) >> 16
	var n: int = maxi(maxi(FixedMath.abs_i(dx), FixedMath.abs_i(dz)), 1)
	inp.turn = FixedMath.clamp_i(FixedMath.div_trunc(cross * 128, n), -128, 128)
	if dot <= 0:
		# alvo atrás: gira no máximo para o lado do produto vetorial
		inp.turn = 128 if cross >= 0 else -128
	inp.move = 1 if dot > 0 and 2 * FixedMath.abs_i(cross) <= dot else 0
