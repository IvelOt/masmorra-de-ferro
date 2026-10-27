class_name PlayerSim
extends RefCounted
## M1: controlador estilo DOOM em inteiros (giro, empuxo, momento, colisão por eixo).
## M3: campos de combate; o bloqueio corta o empuxo pela metade (Combat faz o resto).
## M6: máximos, nível, XP, ouro e inventário como campos (HP_MAX/STAMINA_MAX são
## os valores iniciais).

const UNIT_PER_M: int = 1024
const CELL: int = 2048
const PLAYER_HALF: int = 384
const THRUST_FORWARD: int = 14
const THRUST_STRAFE: int = 12
const FRICTION_NUM: int = 58
const FRICTION_DEN: int = 64
const TURN_KEY: int = 48
const ANGLE_MASK: int = 4095
const HP_MAX: int = 100
const STAMINA_MAX: int = 100
const LEVEL_MAX: int = 3
## XP para atingir o nível i (índice = nível).
const LEVEL_XP: Array = [0, 0, 100, 250]
const LEVEL_HP_BONUS: int = 20
const LEVEL_SP_BONUS: int = 10

var pos_x: int = 0
var pos_z: int = 0
var vel_x: int = 0
var vel_z: int = 0
var angle: int = 0
var hp: int = HP_MAX
var stamina: int = STAMINA_MAX
# M3 (estado canônico): golpe, bloqueio e atordoamento.
var swing_state: int = 0
var swing_ticks: int = 0
var swing_hits: Array = []
var blocking: bool = false
var stun_ticks: int = 0
# M6 (estado canônico): progressão e inventário.
var hp_max: int = HP_MAX
var stamina_max: int = STAMINA_MAX
var level: int = 1
var xp: int = 0
var gold: int = 0
var potion_hp: int = 0
var potion_sp: int = 0
var has_key: bool = false
## Derivado no início do passo 2 e usado nos passos 5 e 8 do mesmo tick (fora do estado).
var stunned: bool = false


func set_pose(x: int, z: int, a: int) -> void:
	pos_x = x
	pos_z = z
	angle = a & ANGLE_MASK
	vel_x = 0
	vel_z = 0


## Passo 8 (M6): XP dos abates e laço de subida de nível (vida restaurada; vigor não).
func gain_xp(amount: int) -> void:
	xp += amount
	while level < LEVEL_MAX and xp >= int(LEVEL_XP[level + 1]):
		level += 1
		hp_max += LEVEL_HP_BONUS
		stamina_max += LEVEL_SP_BONUS
		hp = hp_max


func box_hits(grid: Grid) -> bool:
	return grid.box_hits_solid(pos_x - PLAYER_HALF, pos_z - PLAYER_HALF,
		pos_x + PLAYER_HALF, pos_z + PLAYER_HALF)


func step(inp: IntInput, grid: Grid) -> void:
	# Bloqueio (M3): usa o swing_state do tick anterior.
	stunned = stun_ticks > 0
	blocking = inp.block and not stunned and swing_state != Combat.WINDUP and swing_state != Combat.ACTIVE
	angle = (angle + inp.turn) & ANGLE_MASK
	var fx: int = TrigTable.cos_q16(angle)
	var fz: int = TrigTable.sin_q16(angle)
	var rx: int = TrigTable.cos_q16(angle - 1024)
	var rz: int = TrigTable.sin_q16(angle - 1024)
	var tx: int = (inp.move * THRUST_FORWARD * fx + inp.strafe * THRUST_STRAFE * rx) >> 16
	var tz: int = (inp.move * THRUST_FORWARD * fz + inp.strafe * THRUST_STRAFE * rz) >> 16
	if blocking:
		tx = FixedMath.div_trunc(tx, 2)
		tz = FixedMath.div_trunc(tz, 2)
	vel_x = FixedMath.div_trunc(vel_x * FRICTION_NUM, FRICTION_DEN) + tx
	vel_z = FixedMath.div_trunc(vel_z * FRICTION_NUM, FRICTION_DEN) + tz
	# Eixo X
	pos_x += vel_x
	if vel_x != 0 and box_hits(grid):
		var cx: int = grid.blocking_cx(pos_x - PLAYER_HALF, pos_z - PLAYER_HALF,
			pos_x + PLAYER_HALF, pos_z + PLAYER_HALF, vel_x)
		if vel_x > 0:
			pos_x = cx * CELL - PLAYER_HALF
		else:
			pos_x = (cx + 1) * CELL + PLAYER_HALF
		vel_x = 0
	# Eixo Z (com X já resolvido)
	pos_z += vel_z
	if vel_z != 0 and box_hits(grid):
		var cz: int = grid.blocking_cz(pos_x - PLAYER_HALF, pos_z - PLAYER_HALF,
			pos_x + PLAYER_HALF, pos_z + PLAYER_HALF, vel_z)
		if vel_z > 0:
			pos_z = cz * CELL - PLAYER_HALF
		else:
			pos_z = (cz + 1) * CELL + PLAYER_HALF
		vel_z = 0
