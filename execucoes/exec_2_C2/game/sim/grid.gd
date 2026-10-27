extends RefCounted
## Grade 64×64 de células (GDD §4.2) e colisão AABB × grade com intervalos semiabertos.

const FM = preload("res://sim/fixed_math.gd")

const SOLID: int = 0
const FLOOR: int = 1
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5

const CELL: int = 2048
const GRID_W: int = 64
const GRID_H: int = 64

## Tipo de cada célula, índice cz * GRID_W + cx.
var cells: PackedByteArray = PackedByteArray()
## Id da sala de cada célula (-1 = não é sala).
var room_id: PackedInt32Array = PackedInt32Array()
## Salas aceitas: [{id, x, z, w, h, cx, cz}] em ordem de id.
var rooms: Array = []
var exit_room: int = -1
var spawn_x: int = 0
var spawn_z: int = 0
var spawn_angle: int = 0

var _sha_cache: String = ""


func _init() -> void:
	cells.resize(GRID_W * GRID_H)
	cells.fill(SOLID)
	room_id.resize(GRID_W * GRID_H)
	room_id.fill(-1)


static func index_of(cx: int, cz: int) -> int:
	return cz * GRID_W + cx


static func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < GRID_W and cz < GRID_H


static func is_blocking(t: int) -> bool:
	return t == SOLID or t == DOOR_CLOSED or t == DOOR_LOCKED


static func is_door(t: int) -> bool:
	return t == DOOR_CLOSED or t == DOOR_OPEN or t == DOOR_LOCKED


static func cell_of(u: int) -> int:
	return FM.div_floor(u, CELL)


## Centro da célula em unidades de simulação.
static func cell_center(c: int) -> int:
	return c * CELL + FM.div_trunc(CELL, 2)


func get_cell(cx: int, cz: int) -> int:
	if not in_bounds(cx, cz):
		return SOLID
	return cells[index_of(cx, cz)]


func set_cell(cx: int, cz: int, t: int) -> void:
	if not in_bounds(cx, cz):
		push_error("set_cell fora dos limites")
		return
	cells[index_of(cx, cz)] = t
	_sha_cache = ""


func get_room_id(cx: int, cz: int) -> int:
	if not in_bounds(cx, cz):
		return -1
	return room_id[index_of(cx, cz)]


func set_room_id(cx: int, cz: int, rid: int) -> void:
	room_id[index_of(cx, cz)] = rid


func is_blocking_at(cx: int, cz: int) -> bool:
	return is_blocking(get_cell(cx, cz))


## Caixa semiaberta [min, max) em cada eixo.
func box_hits_solid(min_x: int, min_z: int, max_x: int, max_z: int) -> bool:
	var cx0: int = cell_of(min_x)
	var cx1: int = cell_of(max_x - 1)
	var cz0: int = cell_of(min_z)
	var cz1: int = cell_of(max_z - 1)
	for cz in range(cz0, cz1 + 1):
		for cx in range(cx0, cx1 + 1):
			if is_blocking_at(cx, cz):
				return true
	return false


func sha256() -> String:
	if _sha_cache == "":
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(cells)
		_sha_cache = ctx.finish().hex_encode()
	return _sha_cache


## Portas em ordem crescente de índice de célula; id = índice de célula.
func doors() -> Array:
	var out: Array = []
	for i in range(GRID_W * GRID_H):
		var t: int = cells[i]
		if is_door(t):
			out.append({"id": i, "cx": i % GRID_W, "cz": FM.div_trunc(i, GRID_W), "type": t})
	return out
