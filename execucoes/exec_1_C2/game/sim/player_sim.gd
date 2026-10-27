class_name PlayerSim
extends RefCounted
## Estado e passo do jogador (M1 + M3 + M6): giro, empuxo, momento, colisão por
## eixo contra a grade e contra inimigos vivos; campos de combate e progressão.

const PLAYER_HALF: int = 384
const THRUST_FORWARD: int = 14
const THRUST_STRAFE: int = 12
const FRICTION_NUM: int = 58
const FRICTION_DEN: int = 64
const TURN_KEY: int = 48

var pos_x: int = 0
var pos_z: int = 0
var vel_x: int = 0
var vel_z: int = 0
var angle: int = 0
var hp: int = Combat.HP_MAX
var hp_max: int = Combat.HP_MAX
var stamina: int = Combat.STAMINA_MAX
var stamina_max: int = Combat.STAMINA_MAX
var swing_state: int = Combat.S_IDLE
var swing_ticks: int = 0
var swing_hits: Array[int] = []
var blocking: bool = false
var stun_ticks: int = 0
var level: int = 1
var xp: int = 0
var gold: int = 0
var potion_hp: int = 0
var potion_sp: int = 0
var has_key: bool = false


func step(grid: Grid, inp: IntInput, enemies: Array[EnemySim] = []) -> void:
	blocking = Combat.compute_blocking(self, inp)
	angle = (angle + inp.turn) & 4095
	var fx: int = TrigTable.cos_q16(angle)
	var fz: int = TrigTable.sin_q16(angle)
	var ra: int = (angle - 1024) & 4095
	var rx: int = TrigTable.cos_q16(ra)
	var rz: int = TrigTable.sin_q16(ra)
	var tx: int = (inp.move * THRUST_FORWARD * fx + inp.strafe * THRUST_STRAFE * rx) >> 16
	var tz: int = (inp.move * THRUST_FORWARD * fz + inp.strafe * THRUST_STRAFE * rz) >> 16
	if blocking:
		tx = FixedMath.div_trunc(tx, 2)
		tz = FixedMath.div_trunc(tz, 2)
	vel_x = FixedMath.div_trunc(vel_x * FRICTION_NUM, FRICTION_DEN) + tx
	vel_z = FixedMath.div_trunc(vel_z * FRICTION_NUM, FRICTION_DEN) + tz
	var dir_x: int = vel_x
	_move_x(grid)
	_clamp_enemies_x(enemies, dir_x)
	var dir_z: int = vel_z
	_move_z(grid)
	_clamp_enemies_z(enemies, dir_z)


func _move_x(grid: Grid) -> void:
	pos_x += vel_x
	if not box_hits(grid):
		return
	if vel_x > 0:
		pos_x = (((pos_x + PLAYER_HALF - 1) >> Grid.CELL_SHIFT) << Grid.CELL_SHIFT) - PLAYER_HALF
	elif vel_x < 0:
		pos_x = ((((pos_x - PLAYER_HALF) >> Grid.CELL_SHIFT) + 1) << Grid.CELL_SHIFT) + PLAYER_HALF
	vel_x = 0


func _move_z(grid: Grid) -> void:
	pos_z += vel_z
	if not box_hits(grid):
		return
	if vel_z > 0:
		pos_z = (((pos_z + PLAYER_HALF - 1) >> Grid.CELL_SHIFT) << Grid.CELL_SHIFT) - PLAYER_HALF
	elif vel_z < 0:
		pos_z = ((((pos_z - PLAYER_HALF) >> Grid.CELL_SHIFT) + 1) << Grid.CELL_SHIFT) + PLAYER_HALF
	vel_z = 0


## Prende à face do inimigo vivo mais próximo na direção do movimento (empate: menor id).
func _clamp_enemies_x(enemies: Array[EnemySim], dir: int) -> void:
	if dir == 0:
		return
	var found: bool = false
	var best: int = 0
	for e in enemies:
		if not e.alive() or not EnemySim.boxes_overlap(pos_x, pos_z, PLAYER_HALF, e.pos_x, e.pos_z, e.half()):
			continue
		var face: int = e.pos_x - e.half() - PLAYER_HALF if dir > 0 else e.pos_x + e.half() + PLAYER_HALF
		if not found or (dir > 0 and face < best) or (dir < 0 and face > best):
			best = face
			found = true
	if found:
		pos_x = best
		vel_x = 0


func _clamp_enemies_z(enemies: Array[EnemySim], dir: int) -> void:
	if dir == 0:
		return
	var found: bool = false
	var best: int = 0
	for e in enemies:
		if not e.alive() or not EnemySim.boxes_overlap(pos_x, pos_z, PLAYER_HALF, e.pos_x, e.pos_z, e.half()):
			continue
		var face: int = e.pos_z - e.half() - PLAYER_HALF if dir > 0 else e.pos_z + e.half() + PLAYER_HALF
		if not found or (dir > 0 and face < best) or (dir < 0 and face > best):
			best = face
			found = true
	if found:
		pos_z = best
		vel_z = 0


func box_hits(grid: Grid) -> bool:
	return grid.box_hits_blocking(pos_x - PLAYER_HALF, pos_x + PLAYER_HALF,
		pos_z - PLAYER_HALF, pos_z + PLAYER_HALF)


func cell_x() -> int:
	return pos_x >> Grid.CELL_SHIFT


func cell_z() -> int:
	return pos_z >> Grid.CELL_SHIFT


func to_dict() -> Dictionary:
	return {"pos_x": pos_x, "pos_z": pos_z, "vel_x": vel_x, "vel_z": vel_z, "angle": angle}


## Estado completo do jogador para s_k v3.
func to_state_dict() -> Dictionary:
	var d: Dictionary = to_dict()
	d["hp"] = hp
	d["hp_max"] = hp_max
	d["stamina"] = stamina
	d["stamina_max"] = stamina_max
	d["swing_state"] = swing_state
	d["swing_ticks"] = swing_ticks
	d["swing_hits"] = swing_hits.duplicate()
	d["blocking"] = blocking
	d["stun_ticks"] = stun_ticks
	d["level"] = level
	d["xp"] = xp
	d["gold"] = gold
	d["inventory"] = {"potion_hp": potion_hp, "potion_sp": potion_sp, "key": has_key}
	return d
