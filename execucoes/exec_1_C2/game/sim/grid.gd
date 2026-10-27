class_name Grid
extends RefCounted
## Grade 64x64 de células; index = cz*64 + cx. Colisão AABB x grade com
## intervalos semiabertos [a, b).

const SIZE: int = 64
const CELL: int = 2048
const CELL_SHIFT: int = 11

const SOLID: int = 0
const FLOOR: int = 1
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5

var cells: PackedByteArray
var _sha_cache: String = ""


func _init() -> void:
	cells = PackedByteArray()
	cells.resize(SIZE * SIZE)
	cells.fill(SOLID)


static func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < SIZE and cz < SIZE


func get_cell(cx: int, cz: int) -> int:
	if not in_bounds(cx, cz):
		return SOLID
	return cells[cz * SIZE + cx]


func set_cell(cx: int, cz: int, t: int) -> void:
	if not in_bounds(cx, cz):
		return
	cells[cz * SIZE + cx] = t
	_sha_cache = ""


func fill_rect(x0: int, z0: int, x1: int, z1: int, t: int) -> void:
	for cz in range(z0, z1 + 1):
		for cx in range(x0, x1 + 1):
			set_cell(cx, cz, t)


static func is_blocking_type(t: int) -> bool:
	return t == SOLID or t == DOOR_CLOSED or t == DOOR_LOCKED


static func is_door_type(t: int) -> bool:
	return t == DOOR_CLOSED or t == DOOR_OPEN or t == DOOR_LOCKED


func is_blocking(cx: int, cz: int) -> bool:
	return is_blocking_type(get_cell(cx, cz))


## A caixa [x0, x1) x [z0, z1) intersecta alguma célula bloqueante?
func box_hits_blocking(x0: int, x1: int, z0: int, z1: int) -> bool:
	for cz in range(z0 >> CELL_SHIFT, ((z1 - 1) >> CELL_SHIFT) + 1):
		for cx in range(x0 >> CELL_SHIFT, ((x1 - 1) >> CELL_SHIFT) + 1):
			if is_blocking(cx, cz):
				return true
	return false


func duplicate_grid() -> Grid:
	var g: Grid = Grid.new()
	g.cells = cells.duplicate()
	return g


## SHA-256 dos 4096 bytes da grade, em hexadecimal minúsculo.
func sha256() -> String:
	if _sha_cache == "":
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(cells)
		_sha_cache = ctx.finish().hex_encode()
	return _sha_cache


## Grade como string de 4096 dígitos (cabeçalho do relatório).
func to_digit_string() -> String:
	var parts: PackedStringArray = PackedStringArray()
	parts.resize(SIZE * SIZE)
	for i in range(SIZE * SIZE):
		parts[i] = str(cells[i])
	return "".join(parts)
