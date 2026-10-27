class_name Grid
extends RefCounted
## Grade 64x64 de células (índice z * 64 + x) e colisão AABB inteira x grade.

const W: int = 64
const H: int = 64
const CELL: int = 2048

const SOLID: int = 0
const FLOOR: int = 1
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5

var cells: PackedByteArray


func _init() -> void:
	cells = PackedByteArray()
	cells.resize(W * H)
	cells.fill(SOLID)


func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < W and cz < H


func get_cell(cx: int, cz: int) -> int:
	if not in_bounds(cx, cz):
		return SOLID
	return cells[cz * W + cx]


func set_cell(cx: int, cz: int, code: int) -> void:
	if in_bounds(cx, cz):
		cells[cz * W + cx] = code


static func code_blocks(code: int) -> bool:
	return code == SOLID or code == DOOR_CLOSED or code == DOOR_LOCKED


func is_blocking(cx: int, cz: int) -> bool:
	return code_blocks(get_cell(cx, cz))


func is_passable(cx: int, cz: int) -> bool:
	return get_cell(cx, cz) != SOLID


func duplicate_grid() -> Grid:
	var g := Grid.new()
	g.cells = cells.duplicate()
	return g


func sha256() -> String:
	return sha256_bytes(cells)


static func sha256_bytes(b: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(b)
	return ctx.finish().hex_encode()


func to_codes() -> Array:
	var out: Array = []
	for i in range(W * H):
		out.append(int(cells[i]))
	return out


## Caixa semiaberta [min_x, max_x_excl) x [min_z, max_z_excl).
func box_hits_solid(min_x: int, min_z: int, max_x_excl: int, max_z_excl: int) -> bool:
	var c0x: int = FixedMath.div_floor(min_x, CELL)
	var c1x: int = FixedMath.div_floor(max_x_excl - 1, CELL)
	var c0z: int = FixedMath.div_floor(min_z, CELL)
	var c1z: int = FixedMath.div_floor(max_z_excl - 1, CELL)
	for cz in range(c0z, c1z + 1):
		for cx in range(c0x, c1x + 1):
			if is_blocking(cx, cz):
				return true
	return false
