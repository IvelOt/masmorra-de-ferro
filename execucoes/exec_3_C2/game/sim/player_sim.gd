class_name PlayerSim
extends RefCounted
## M1: giro, empuxo, momento e colisão do jogador (GDD §4.1).
## M3: vida, vigor, golpe, bloqueio e atordoamento (estado; regras em combat.gd).
## M6: nível, XP, ouro e inventário (estado; regras em items_sim.gd).

const FixedMath = preload("res://sim/fixed_math.gd")
const TrigTable = preload("res://sim/trig_table.gd")
const Grid = preload("res://sim/grid.gd")
const IntInput = preload("res://sim/int_input.gd")

const PLAYER_HALF: int = 384
const THRUST_FORWARD: int = 14
const THRUST_STRAFE: int = 12
const FRICTION_NUM: int = 58
const FRICTION_DEN: int = 64
const TURN_KEY: int = 48
const UNITS_PER_M: int = 1024

var pos_x: int = 0
var pos_z: int = 0
var vel_x: int = 0
var vel_z: int = 0
var angle: int = 0
var hp: int = 100
var hp_max: int = 100
var stamina: int = 100
var stamina_max: int = 100
var swing_state: String = "IDLE"
var swing_ticks: int = 0
## Ids de inimigo já atingidos neste golpe, sempre em ordem crescente.
var swing_hits: Array = []
var blocking: bool = false
var stun_ticks: int = 0
var level: int = 1
var xp: int = 0
var gold: int = 0
var potion_hp: int = 0
var potion_sp: int = 0
var has_key: bool = false


func _init(px: int = 0, pz: int = 0, a: int = 0) -> void:
	pos_x = px
	pos_z = pz
	angle = a & 4095


## `enemies`: lista de EnemySim; os vivos bloqueiam o jogador (plano R3 §3.2).
func step(inp: IntInput, grid: Grid, enemies: Array = []) -> void:
	angle = (angle + inp.turn) & 4095
	var fx: int = TrigTable.cos_q16(angle)
	var fz: int = TrigTable.sin_q16(angle)
	var rx: int = TrigTable.cos_q16(angle - 1024)
	var rz: int = TrigTable.sin_q16(angle - 1024)
	var tx: int = (inp.move * THRUST_FORWARD * fx + inp.strafe * THRUST_STRAFE * rx) >> 16
	var tz: int = (inp.move * THRUST_FORWARD * fz + inp.strafe * THRUST_STRAFE * rz) >> 16
	# bloqueio do tick anterior (o passo 5 vem depois): empuxo pela metade
	if blocking:
		tx = FixedMath.div_trunc(tx, 2)
		tz = FixedMath.div_trunc(tz, 2)
	vel_x = FixedMath.div_trunc(vel_x * FRICTION_NUM, FRICTION_DEN) + tx
	vel_z = FixedMath.div_trunc(vel_z * FRICTION_NUM, FRICTION_DEN) + tz
	var prev_x: int = pos_x
	pos_x += vel_x
	var rx_res: PackedInt64Array = grid.collide_axis(pos_x, pos_z, vel_x, PLAYER_HALF, true)
	pos_x = rx_res[0]
	vel_x = rx_res[1]
	if overlaps_enemy(enemies):
		pos_x = prev_x
		vel_x = 0
	var prev_z: int = pos_z
	pos_z += vel_z
	var rz_res: PackedInt64Array = grid.collide_axis(pos_z, pos_x, vel_z, PLAYER_HALF, false)
	pos_z = rz_res[0]
	vel_z = rz_res[1]
	if overlaps_enemy(enemies):
		pos_z = prev_z
		vel_z = 0


## Sobreposição estrita da caixa do jogador com a de algum inimigo vivo.
func overlaps_enemy(enemies: Array) -> bool:
	for e: Variant in enemies:
		if e.state == "DEAD":
			continue
		var reach: int = PLAYER_HALF + e.half()
		if FixedMath.abs_i(e.pos_x - pos_x) < reach and FixedMath.abs_i(e.pos_z - pos_z) < reach:
			return true
	return false


func cell_x() -> int:
	return FixedMath.div_floor(pos_x, Grid.CELL)


func cell_z() -> int:
	return FixedMath.div_floor(pos_z, Grid.CELL)


func to_dict() -> Dictionary:
	return {
		"pos_x": pos_x, "pos_z": pos_z, "vel_x": vel_x, "vel_z": vel_z, "angle": angle,
		"hp": hp, "hp_max": hp_max, "stamina": stamina, "stamina_max": stamina_max,
		"swing_state": swing_state, "swing_ticks": swing_ticks, "swing_hits": swing_hits.duplicate(),
		"blocking": blocking, "stun_ticks": stun_ticks,
		"level": level, "xp": xp, "gold": gold,
		"inventory": {"potion_hp": potion_hp, "potion_sp": potion_sp, "key": has_key},
	}
