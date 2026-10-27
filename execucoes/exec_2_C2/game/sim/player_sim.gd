extends RefCounted
## Estado e passo do jogador (M1): giro, empuxo, momento, colisão por eixo (GDD §4.1).
## M3: campos de combate (vida, vigor, golpe, bloqueio, atordoamento); a lógica fica em combat.gd.
## M4: colisão com entidades vivas (bloqueadores). M6: nível, XP, ouro e inventário.

const FM = preload("res://sim/fixed_math.gd")
const Trig = preload("res://sim/trig_table.gd")
const Grid = preload("res://sim/grid.gd")

const UNITS_PER_M: int = 1024
const CELL: int = 2048
const ANGLE_FULL: int = 4096
const ANGLE_MASK: int = 4095
const PLAYER_HALF: int = 384
const THRUST_FORWARD: int = 14
const THRUST_STRAFE: int = 12
const FRICTION_NUM: int = 58
const FRICTION_DEN: int = 64
const TURN_KEY: int = 48
const TURN_MIN: int = -128
const TURN_MAX: int = 128
const HP_MAX: int = 100
const STAMINA_MAX: int = 100

var pos_x: int = 0
var pos_z: int = 0
var vel_x: int = 0
var vel_z: int = 0
var angle: int = 0
var hp: int = HP_MAX
var hp_max: int = HP_MAX
var stamina: int = STAMINA_MAX
var stamina_max: int = STAMINA_MAX
## "IDLE" | "WINDUP" | "ACTIVE" | "RECOVERY"
var swing_state: String = "IDLE"
## Ticks já passados na fase atual (1 no primeiro tick da fase; 0 em IDLE).
var swing_ticks: int = 0
## Ids de entidades já acertadas neste golpe, em ordem crescente.
var swing_hits: Array = []
## Bloqueio efetivo deste tick (não é o input cru).
var blocking: bool = false
var stun_ticks: int = 0
var regen_ticks: int = 0
var level: int = 1
var xp: int = 0
var gold: int = 0
## Só int: {"potion_hp", "potion_sp", "key"}.
var inventory: Dictionary = {"potion_hp": 0, "potion_sp": 0, "key": 0}


func place(px: int, pz: int, a: int) -> void:
	pos_x = px
	pos_z = pz
	vel_x = 0
	vel_z = 0
	angle = a & ANGLE_MASK
	hp = HP_MAX
	hp_max = HP_MAX
	stamina = STAMINA_MAX
	stamina_max = STAMINA_MAX
	swing_state = "IDLE"
	swing_ticks = 0
	swing_hits = []
	blocking = false
	stun_ticks = 0
	regen_ticks = 0
	level = 1
	xp = 0
	gold = 0
	inventory = {"potion_hp": 0, "potion_sp": 0, "key": 0}


## `p_blocking` (bloqueio efetivo) reduz o empuxo pela metade; com false o caminho é o da rodada 1.
## `blockers` = [[x, z, half], …] das entidades vivas: por eixo, depois da grade, se a caixa passa a
## sobrepor um bloqueador que não sobrepunha antes, o eixo volta e a velocidade dele zera.
## Com `blockers = []` o caminho é bit a bit o das rodadas 1 e 2.
func step(inp: RefCounted, grid: Grid, p_blocking: bool = false, blockers: Array = []) -> void:
	# 1. giro
	angle = (angle + inp.turn) & ANGLE_MASK
	# 2. empuxo (soma antes do >> 16; diagonal não normalizada, intencional)
	var fx: int = Trig.cos_q16(angle)
	var fz: int = Trig.sin_q16(angle)
	var rx: int = Trig.cos_q16(angle - 1024)
	var rz: int = Trig.sin_q16(angle - 1024)
	var tx: int = (inp.move * THRUST_FORWARD * fx + inp.strafe * THRUST_STRAFE * rx) >> 16
	var tz: int = (inp.move * THRUST_FORWARD * fz + inp.strafe * THRUST_STRAFE * rz) >> 16
	if p_blocking:
		tx = FM.div_trunc(tx, 2)
		tz = FM.div_trunc(tz, 2)
	# 3. momento
	vel_x = FM.div_trunc(vel_x * FRICTION_NUM, FRICTION_DEN) + tx
	vel_z = FM.div_trunc(vel_z * FRICTION_NUM, FRICTION_DEN) + tz
	# 4. colisão eixo X
	var ox: int = pos_x
	pos_x += vel_x
	_resolve_x(grid)
	if not blockers.is_empty() and _hits_blockers(pos_x, pos_z, blockers) and not _hits_blockers(ox, pos_z, blockers):
		pos_x = ox
		vel_x = 0
	# 5. colisão eixo Z
	var oz: int = pos_z
	pos_z += vel_z
	_resolve_z(grid)
	if not blockers.is_empty() and _hits_blockers(pos_x, pos_z, blockers) and not _hits_blockers(pos_x, oz, blockers):
		pos_z = oz
		vel_z = 0


## Sobreposição semiaberta (encostar não colide) com algum bloqueador.
static func _hits_blockers(x: int, z: int, blockers: Array) -> bool:
	for b: Array in blockers:
		if FM.abs_i(x - int(b[0])) < PLAYER_HALF + int(b[2]) and FM.abs_i(z - int(b[1])) < PLAYER_HALF + int(b[2]):
			return true
	return false


func box_hits(grid: Grid) -> bool:
	return grid.box_hits_solid(pos_x - PLAYER_HALF, pos_z - PLAYER_HALF, pos_x + PLAYER_HALF, pos_z + PLAYER_HALF)


func _resolve_x(grid: Grid) -> void:
	if vel_x == 0 or not box_hits(grid):
		return
	var cx0: int = Grid.cell_of(pos_x - PLAYER_HALF)
	var cx1: int = Grid.cell_of(pos_x + PLAYER_HALF - 1)
	var cz0: int = Grid.cell_of(pos_z - PLAYER_HALF)
	var cz1: int = Grid.cell_of(pos_z + PLAYER_HALF - 1)
	var hit: int = -1
	var found: bool = false
	for cx in range(cx0, cx1 + 1):
		for cz in range(cz0, cz1 + 1):
			if grid.is_blocking_at(cx, cz):
				if not found or (vel_x > 0 and cx < hit) or (vel_x < 0 and cx > hit):
					hit = cx
					found = true
	if vel_x > 0:
		pos_x = hit * CELL - PLAYER_HALF
	else:
		pos_x = (hit + 1) * CELL + PLAYER_HALF
	vel_x = 0


func _resolve_z(grid: Grid) -> void:
	if vel_z == 0 or not box_hits(grid):
		return
	var cx0: int = Grid.cell_of(pos_x - PLAYER_HALF)
	var cx1: int = Grid.cell_of(pos_x + PLAYER_HALF - 1)
	var cz0: int = Grid.cell_of(pos_z - PLAYER_HALF)
	var cz1: int = Grid.cell_of(pos_z + PLAYER_HALF - 1)
	var hit: int = -1
	var found: bool = false
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			if grid.is_blocking_at(cx, cz):
				if not found or (vel_z > 0 and cz < hit) or (vel_z < 0 and cz > hit):
					hit = cz
					found = true
	if vel_z > 0:
		pos_z = hit * CELL - PLAYER_HALF
	else:
		pos_z = (hit + 1) * CELL + PLAYER_HALF
	vel_z = 0


func to_dict() -> Dictionary:
	return {
		"pos_x": pos_x,
		"pos_z": pos_z,
		"vel_x": vel_x,
		"vel_z": vel_z,
		"angle": angle,
		"hp": hp,
		"hp_max": hp_max,
		"stamina": stamina,
		"stamina_max": stamina_max,
		"swing_state": swing_state,
		"swing_ticks": swing_ticks,
		"swing_hits": swing_hits.duplicate(),
		"blocking": blocking,
		"stun_ticks": stun_ticks,
		"regen_ticks": regen_ticks,
		"level": level,
		"xp": xp,
		"gold": gold,
		"inventory": inventory.duplicate(),
	}
