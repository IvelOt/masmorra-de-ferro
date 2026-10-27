class_name Pilot
extends RefCounted
## M6 (GDD §5.6): piloto em malha fechada. Só LÊ o mundo (campos e getters), nunca chama step()
## e nunca consome rng_dungeon/rng_ai; o sorteio usa o fluxo próprio STREAM_PILOT.
## Prioridades por tick: terminal > poção > fuga > combate > navegação; destravamento por cima.

## Vizinhança N, L, S, O (a mesma de DungeonGen.bfs).
const DXS: Array = [0, 1, 0, -1]
const DZS: Array = [-1, 0, 1, 0]
const TURN_MAX: int = 48
const ATAN_K: int = 652                 # atan(x) ~ x rad; 4096 / 2pi ~ 652
const ENGAGE_U: int = 4096
const BLOCK_MARGIN: int = 384
const CHASE_MIN_U: int = 1400
const FLEE_CELLS: int = 8
const HP_QUAFF: int = 30
const STUCK_TICKS: int = 45
const STUCK_U: int = 64
const UNSTICK_TICKS: int = 20
const UNSTICK_BACK: int = 10

var rng: RngPcg32
var flow: PackedInt32Array = PackedInt32Array()
var flow_target: int = -1
var flow_key: bool = false
var doors_sig: String = ""
var _quaffed_last: bool = false
var _move_streak: int = 0
var _anchor_x: int = 0
var _anchor_z: int = 0
var _unstick: int = 0
var _unstick_strafe: int = 0


static func create(p_seed: int) -> Pilot:
	var p := Pilot.new()
	p.rng = RngPcg32.create(p_seed, RngPcg32.STREAM_PILOT)
	return p


## Direção inteira até (tx, tz) em u: along/lat no referencial do jogador, giro e "de frente" (±40°).
## lat > 0 => o alvo está no sentido de ângulo crescente (turn > 0).
static func aim(p: PlayerSim, tx: int, tz: int) -> Dictionary:
	var dx: int = tx - p.pos_x
	var dz: int = tz - p.pos_z
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var along: int = (dx * fx + dz * fz) >> 16
	var lat: int = (dz * fx - dx * fz) >> 16
	var turn: int = 0
	if along <= 0:
		turn = TURN_MAX if lat >= 0 else -TURN_MAX
	else:
		turn = FixedMath.clamp_i(FixedMath.div_trunc(lat * ATAN_K, along), -TURN_MAX, TURN_MAX)
	var facing: bool = along > 0 and FixedMath.abs_i(lat) * Combat.TAN40_DEN <= along * Combat.TAN40_NUM
	return {"along": along, "lat": lat, "turn": turn, "facing": facing}


func next_input(world: WorldSim) -> IntInput:
	var out := IntInput.new()
	if world.terminal != "NONE":
		_quaffed_last = false
		return out
	var p: PlayerSim = world.player
	var target: EntitySim = _combat_target(world)
	# 2. poção (o restante do input segue as regras abaixo)
	if not _quaffed_last:
		if p.hp < HP_QUAFF and p.potion_hp > 0:
			out.quaff = 1
		elif p.stamina < Combat.SWING_COST and p.potion_sp > 0 and target != null:
			out.quaff = 2
	_quaffed_last = out.quaff != 0
	_ensure_flow(world)
	var dist: int = _flow_at(p.cell_x(), p.cell_z())
	if p.key and dist >= 0 and dist <= FLEE_CELLS:
		_flee(world, out)
	elif target != null:
		_fight(world, target, out)
	else:
		_navigate(world, out)
	_apply_unstick(p, out)
	out.clamp_self()
	return out


## Alvo de combate: vivo, acordado, Chebyshev (u) <= 4096 e com linha de visão; empate -> menor id.
func _combat_target(world: WorldSim) -> EntitySim:
	var p: PlayerSim = world.player
	var best: EntitySim = null
	var best_d: int = ENGAGE_U + 1
	for i in range(world.enemies.size()):
		var e: EntitySim = world.enemies[i]
		if e.state == "DEAD" or not e.awake or e.type == "dummy":
			continue
		var d: int = _cheb_u(e, p)
		if d < best_d and EnemySim.los(world.dungeon.grid, p.pos_x, p.pos_z, e.pos_x, e.pos_z):
			best = e
			best_d = d
	return best


static func _cheb_u(e: EntitySim, p: PlayerSim) -> int:
	return FixedMath.max_i(FixedMath.abs_i(e.pos_x - p.pos_x), FixedMath.abs_i(e.pos_z - p.pos_z))


## Bloqueio se o inimigo prepara o golpe no alcance; senão golpe de frente; senão aproximação.
func _fight(world: WorldSim, e: EntitySim, out: IntInput) -> void:
	var p: PlayerSim = world.player
	var a: Dictionary = aim(p, e.pos_x, e.pos_z)
	var t: Dictionary = EnemySim.TYPES[e.type]
	var cheb: int = _cheb_u(e, p)
	out.turn = a["turn"]
	if e.state == "WINDUP" and cheb <= int(t["reach"]) + BLOCK_MARGIN \
			and p.swing_state != "WINDUP" and p.swing_state != "ACTIVE":
		out.block = true
		out.move = 0
	elif p.swing_state == "IDLE" and p.stamina >= Combat.SWING_COST and a["facing"] \
			and int(a["along"]) <= Combat.SWORD_REACH + int(EntitySim.HALF[e.type]):
		out.attack = true
	else:
		out.move = 1 if cheb > CHASE_MIN_U else 0


## Fuga: com a chave e perto do EXIT, não engaja o Guardião; só bloqueia o golpe dele no alcance.
func _flee(world: WorldSim, out: IntInput) -> void:
	var p: PlayerSim = world.player
	for i in range(world.enemies.size()):
		var e: EntitySim = world.enemies[i]
		if e.type != "guardian" or e.state != "WINDUP":
			continue
		if _cheb_u(e, p) <= int(EnemySim.TYPES["guardian"]["reach"]) + BLOCK_MARGIN \
				and p.swing_state != "WINDUP" and p.swing_state != "ACTIVE":
			out.turn = aim(p, e.pos_x, e.pos_z)["turn"]
			out.block = true
			out.move = 0
			return
	_navigate(world, out)


## Segue o campo de fluxo até o alvo; abre portas no caminho; `use` sobre o EXIT com a chave.
func _navigate(world: WorldSim, out: IntInput) -> void:
	var p: PlayerSim = world.player
	var grid: Grid = world.dungeon.grid
	var pcx: int = p.cell_x()
	var pcz: int = p.cell_z()
	var ec: Dictionary = world.dungeon.exit_cell
	if p.key and pcx == ec["cx"] and pcz == ec["cz"]:
		out.use = true
	var nxt: Array = _next_cell(pcx, pcz)
	var tx: int = DungeonGen.cell_center_u(pcx)
	var tz: int = DungeonGen.cell_center_u(pcz)
	if not nxt.is_empty():
		tx = DungeonGen.cell_center_u(nxt[0])
		tz = DungeonGen.cell_center_u(nxt[1])
	var a: Dictionary = aim(p, tx, tz)
	out.turn = a["turn"]
	var code: int = grid.get_cell(nxt[0], nxt[1]) if not nxt.is_empty() else Grid.FLOOR
	if code == Grid.DOOR_CLOSED or (code == Grid.DOOR_LOCKED and p.key):
		if a["facing"]:
			out.use = true
			out.move = 0
			return
	var along: int = a["along"]
	if a["facing"] or (along > 0 and FixedMath.abs_i(a["lat"]) <= along):
		out.move = 1
	if rng.bounded(16) == 0:
		out.strafe = rng.bounded(2) * 2 - 1


## Movimento sem progresso por 45 ticks -> 20 ticks de recuo/lateral (mira mantida).
func _apply_unstick(p: PlayerSim, out: IntInput) -> void:
	if _unstick > 0:
		var k: int = UNSTICK_TICKS - _unstick
		out.move = -1 if k < UNSTICK_BACK else 0
		out.strafe = _unstick_strafe
		out.attack = false
		out.use = false
		_unstick -= 1
		_move_streak = 0
		return
	if out.move != 1:
		_move_streak = 0
		return
	if _move_streak == 0:
		_anchor_x = p.pos_x
		_anchor_z = p.pos_z
	_move_streak += 1
	if _move_streak >= STUCK_TICKS:
		var moved: int = FixedMath.max_i(FixedMath.abs_i(p.pos_x - _anchor_x), FixedMath.abs_i(p.pos_z - _anchor_z))
		if moved < STUCK_U:
			_unstick = UNSTICK_TICKS
			_unstick_strafe = rng.bounded(2) * 2 - 1
		_move_streak = 0


## Alvo de navegação: célula da chave sem a chave; senão o EXIT.
func _target_idx(world: WorldSim) -> int:
	var ec: Dictionary = world.dungeon.exit_cell
	if not world.player.key:
		for i in range(world.items.size()):
			var it: Dictionary = world.items[i]
			if it["type"] == "key" and not it["taken"]:
				return int(it["cell_z"]) * Grid.W + int(it["cell_x"])
	return int(ec["cz"]) * Grid.W + int(ec["cx"])


func _doors_signature(world: WorldSim) -> String:
	var sig := PackedStringArray()
	var doors: Array = world.dungeon.doors
	for i in range(doors.size()):
		var dr: Dictionary = doors[i]
		sig.append(str(world.dungeon.grid.get_cell(dr["cx"], dr["cz"])))
	return "".join(sig)


## Campo de fluxo do piloto: BFS-4 (N, L, S, O) a partir do alvo; trancada só passa com a chave.
func _ensure_flow(world: WorldSim) -> void:
	var target: int = _target_idx(world)
	var key: bool = world.player.key
	var sig: String = _doors_signature(world)
	if target == flow_target and key == flow_key and sig == doors_sig and not flow.is_empty():
		return
	flow_target = target
	flow_key = key
	doors_sig = sig
	var grid: Grid = world.dungeon.grid
	flow = PackedInt32Array()
	flow.resize(Grid.W * Grid.H)
	flow.fill(-1)
	if target < 0:
		return
	var queue := PackedInt32Array()
	queue.append(target)
	flow[target] = 0
	var head: int = 0
	while head < queue.size():
		var idx: int = queue[head]
		head += 1
		var cx: int = idx % Grid.W
		var cz: int = FixedMath.div_trunc(idx, Grid.W)
		for k in range(4):
			var nx: int = cx + DXS[k]
			var nz: int = cz + DZS[k]
			if not grid.in_bounds(nx, nz) or flow[nz * Grid.W + nx] >= 0:
				continue
			var c: int = grid.get_cell(nx, nz)
			if c == Grid.SOLID or (c == Grid.DOOR_LOCKED and not key):
				continue
			flow[nz * Grid.W + nx] = flow[idx] + 1
			queue.append(nz * Grid.W + nx)


func _flow_at(cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= Grid.W or cz >= Grid.H or flow.is_empty():
		return -1
	return flow[cz * Grid.W + cx]


## Primeiro vizinho (N, L, S, O) com fluxo = fluxo atual - 1; [] no alvo ou fora do campo.
func _next_cell(cx: int, cz: int) -> Array:
	var cur: int = _flow_at(cx, cz)
	if cur <= 0:
		return []
	for k in range(4):
		var nx: int = cx + DXS[k]
		var nz: int = cz + DZS[k]
		if _flow_at(nx, nz) == cur - 1:
			return [nx, nz]
	return []
