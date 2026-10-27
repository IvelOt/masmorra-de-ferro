class_name Grid
extends RefCounted
## Grade 64x64 de células e colisão AABB (caixa semiaberta) x grade.

const FixedMath = preload("res://sim/fixed_math.gd")
const StateHash = preload("res://sim/state_hash.gd")

const SIZE: int = 64
const CELL: int = 2048

const SOLID: int = 0
const FLOOR: int = 1
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5

var cells: PackedByteArray = PackedByteArray()


func _init() -> void:
	cells.resize(SIZE * SIZE)
	cells.fill(SOLID)


static func in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < SIZE and z >= 0 and z < SIZE


func get_cell(x: int, z: int) -> int:
	if not in_bounds(x, z):
		return SOLID
	return cells[z * SIZE + x]


func set_cell(x: int, z: int, c: int) -> void:
	cells[z * SIZE + x] = c


static func is_blocking(c: int) -> bool:
	return c == SOLID or c == DOOR_CLOSED or c == DOOR_LOCKED


static func is_passable(c: int) -> bool:
	return c == FLOOR or c == DOOR_OPEN or c == EXIT


func blocks_at(x: int, z: int) -> bool:
	if not in_bounds(x, z):
		return true
	return is_blocking(cells[z * SIZE + x])


func sha256() -> String:
	return StateHash.sha256_hex_bytes(cells)


## Verdadeiro se a caixa [p - h, p + h) em X e Z intersecta alguma célula bloqueante.
func box_hits_solid(px: int, pz: int, h: int) -> bool:
	var cx0: int = FixedMath.div_floor(px - h, CELL)
	var cx1: int = FixedMath.div_floor(px + h - 1, CELL)
	var cz0: int = FixedMath.div_floor(pz - h, CELL)
	var cz1: int = FixedMath.div_floor(pz + h - 1, CELL)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			if blocks_at(cx, cz):
				return true
	return false


## Resolve a colisão de um eixo depois do deslocamento. `a` é a coordenada do eixo
## resolvido, `b` a do outro eixo. Devolve [a, vel].
func collide_axis(a: int, b: int, vel: int, h: int, axis_x: bool) -> PackedInt64Array:
	var a0: int = FixedMath.div_floor(a - h, CELL)
	var a1: int = FixedMath.div_floor(a + h - 1, CELL)
	var b0: int = FixedMath.div_floor(b - h, CELL)
	var b1: int = FixedMath.div_floor(b + h - 1, CELL)
	var found: bool = false
	var min_a: int = a1
	var max_a: int = a0
	for cb in range(b0, b1 + 1):
		for ca in range(a0, a1 + 1):
			var hit: bool = blocks_at(ca, cb) if axis_x else blocks_at(cb, ca)
			if hit:
				found = true
				min_a = mini(min_a, ca)
				max_a = maxi(max_a, ca)
	if not found:
		return PackedInt64Array([a, vel])
	if vel > 0:
		a = min_a * CELL - h
	elif vel < 0:
		a = (max_a + 1) * CELL + h
	return PackedInt64Array([a, 0])
