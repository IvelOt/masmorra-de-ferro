class_name PlayerSim
extends RefCounted
## M1: estado inteiro e passo do jogador (giro -> empuxo/momento -> colisão X, depois Z).

const PLAYER_HALF: int = 384
const THRUST_FORWARD: int = 14
const THRUST_STRAFE: int = 12
const FRICTION_NUM: int = 58
const FRICTION_DEN: int = 64
const TURN_KEY: int = 48
const HP_MAX: int = 100
const STAMINA_MAX: int = 100

var pos_x: int = 0
var pos_z: int = 0
var vel_x: int = 0
var vel_z: int = 0
var angle: int = 0

# Campos de M3/M6 com valores padrão (entram no hash desde já).
var hp: int = HP_MAX
var hp_max: int = HP_MAX
var stamina: int = STAMINA_MAX
var stamina_max: int = STAMINA_MAX
var swing_state: String = "IDLE"
var swing_ticks: int = 0
var swing_hits: Array = []
var blocking: bool = false
var stun_ticks: int = 0
var level: int = 1
var xp: int = 0
var gold: int = 0
var potion_hp: int = 0
var potion_sp: int = 0
var key: bool = false

# Transitório, não hasheado: atordoado neste tick (vale só dentro do tick; M3).
var stunned_now: bool = false


func box_hits(grid: Grid) -> bool:
	return grid.box_hits_solid(pos_x - PLAYER_HALF, pos_z - PLAYER_HALF, pos_x + PLAYER_HALF, pos_z + PLAYER_HALF)


func cell_x() -> int:
	return FixedMath.div_floor(pos_x, Grid.CELL)


func cell_z() -> int:
	return FixedMath.div_floor(pos_z, Grid.CELL)


## M3, início do passo 2 (antes do giro): atordoamento e bloqueio. swing_state é o do tick anterior.
func pre_step(input: IntInput) -> void:
	stunned_now = stun_ticks > 0
	if stunned_now:
		stun_ticks -= 1
	blocking = input.block and not stunned_now and swing_state != "WINDUP" and swing_state != "ACTIVE"


func step(input: IntInput, grid: Grid) -> void:
	angle = (angle + input.turn) & 4095
	var fx: int = TrigTable.cos_q16(angle)
	var fz: int = TrigTable.sin_q16(angle)
	var rx: int = TrigTable.cos_q16(angle - 1024)
	var rz: int = TrigTable.sin_q16(angle - 1024)
	var thrust_x: int = (input.move * THRUST_FORWARD * fx + input.strafe * THRUST_STRAFE * rx) >> 16
	var thrust_z: int = (input.move * THRUST_FORWARD * fz + input.strafe * THRUST_STRAFE * rz) >> 16
	if blocking:
		thrust_x = FixedMath.div_trunc(thrust_x, 2)
		thrust_z = FixedMath.div_trunc(thrust_z, 2)
	vel_x = FixedMath.div_trunc(vel_x * FRICTION_NUM, FRICTION_DEN) + thrust_x
	vel_z = FixedMath.div_trunc(vel_z * FRICTION_NUM, FRICTION_DEN) + thrust_z
	# Eixo X
	pos_x += vel_x
	if vel_x != 0 and box_hits(grid):
		var hit: Array = _blocking_cols(grid)
		if vel_x > 0:
			pos_x = Grid.CELL * hit[0] - PLAYER_HALF
		else:
			pos_x = Grid.CELL * (hit[1] + 1) + PLAYER_HALF
		vel_x = 0
	# Eixo Z
	pos_z += vel_z
	if vel_z != 0 and box_hits(grid):
		var hitz: Array = _blocking_rows(grid)
		if vel_z > 0:
			pos_z = Grid.CELL * hitz[0] - PLAYER_HALF
		else:
			pos_z = Grid.CELL * (hitz[1] + 1) + PLAYER_HALF
		vel_z = 0


func _cover() -> Array:
	return [
		FixedMath.div_floor(pos_x - PLAYER_HALF, Grid.CELL),
		FixedMath.div_floor(pos_x + PLAYER_HALF - 1, Grid.CELL),
		FixedMath.div_floor(pos_z - PLAYER_HALF, Grid.CELL),
		FixedMath.div_floor(pos_z + PLAYER_HALF - 1, Grid.CELL),
	]


## [menor cx, maior cx] entre as células bloqueantes cobertas pela caixa.
func _blocking_cols(grid: Grid) -> Array:
	var c: Array = _cover()
	var lo: int = 1 << 30
	var hi: int = -(1 << 30)
	for cz in range(c[2], c[3] + 1):
		for cx in range(c[0], c[1] + 1):
			if grid.is_blocking(cx, cz):
				lo = FixedMath.min_i(lo, cx)
				hi = FixedMath.max_i(hi, cx)
	return [lo, hi]


func _blocking_rows(grid: Grid) -> Array:
	var c: Array = _cover()
	var lo: int = 1 << 30
	var hi: int = -(1 << 30)
	for cz in range(c[2], c[3] + 1):
		for cx in range(c[0], c[1] + 1):
			if grid.is_blocking(cx, cz):
				lo = FixedMath.min_i(lo, cz)
				hi = FixedMath.max_i(hi, cz)
	return [lo, hi]


func to_canon() -> Dictionary:
	return {
		"pos_x": pos_x, "pos_z": pos_z, "vel_x": vel_x, "vel_z": vel_z, "angle": angle,
		"hp": hp, "hp_max": hp_max, "stamina": stamina, "stamina_max": stamina_max,
		"swing_state": swing_state, "swing_ticks": swing_ticks, "swing_hits": swing_hits.duplicate(),
		"blocking": blocking, "stun_ticks": stun_ticks,
		"level": level, "xp": xp, "gold": gold,
		"inventory": {"potion_hp": potion_hp, "potion_sp": potion_sp, "key": key},
	}
