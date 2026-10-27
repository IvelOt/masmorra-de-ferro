class_name Grid
extends RefCounted
## Grade 64×64 de células (índice cz*64 + cx) e colisão AABB × grade.

const W: int = 64
const H: int = 64
const CELL: int = 2048

const SOLID: int = 0
const FLOOR: int = 1
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5

var cells: PackedByteArray = PackedByteArray()
## Salas em células: {id, x, z, w, h}.
var rooms: Array = []
var start_room: int = 0
var exit_room: int = 0
## Pose de spawn do jogador (unidades de simulação).
var spawn_x: int = 0
var spawn_z: int = 0
var spawn_angle: int = 0
# Caches derivados de `cells` (só desempenho): invalidados por set_cell().
var _rev: int = 0
var _doors_rev: int = -1
var _doors_cache: Array = []
var _sha_rev: int = -1
var _sha_cache: String = ""


func _init() -> void:
	cells.resize(W * H)
	cells.fill(SOLID)


static func in_bounds(cx: int, cz: int) -> bool:
	return cx >= 0 and cx < W and cz >= 0 and cz < H


func get_cell(cx: int, cz: int) -> int:
	if not in_bounds(cx, cz):
		return SOLID
	return cells[cz * W + cx]


func set_cell(cx: int, cz: int, t: int) -> void:
	if in_bounds(cx, cz):
		cells[cz * W + cx] = t
		_rev += 1


static func is_blocking_type(t: int) -> bool:
	return t == SOLID or t == DOOR_CLOSED or t == DOOR_LOCKED


static func is_door_type(t: int) -> bool:
	return t == DOOR_CLOSED or t == DOOR_OPEN or t == DOOR_LOCKED


## Fora da grade conta como sólido.
func is_blocking(cx: int, cz: int) -> bool:
	return is_blocking_type(get_cell(cx, cz))


## Caixa semiaberta [x0, x1) × [z0, z1) em unidades; true se cobre célula bloqueante.
func box_hits_solid(x0: int, z0: int, x1: int, z1: int) -> bool:
	var cx0: int = FixedMath.div_floor(x0, CELL)
	var cx1: int = FixedMath.div_floor(x1 - 1, CELL)
	var cz0: int = FixedMath.div_floor(z0, CELL)
	var cz1: int = FixedMath.div_floor(z1 - 1, CELL)
	for cz: int in range(cz0, cz1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			if is_blocking(cx, cz):
				return true
	return false


## Primeira célula bloqueante coberta pela caixa no eixo X: devolve o cx mais
## próximo na direção do movimento (dir > 0: menor cx; dir < 0: maior cx).
func blocking_cx(x0: int, z0: int, x1: int, z1: int, dir: int) -> int:
	var cx0: int = FixedMath.div_floor(x0, CELL)
	var cx1: int = FixedMath.div_floor(x1 - 1, CELL)
	var cz0: int = FixedMath.div_floor(z0, CELL)
	var cz1: int = FixedMath.div_floor(z1 - 1, CELL)
	var best: int = -1
	var found: bool = false
	for cz: int in range(cz0, cz1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			if is_blocking(cx, cz):
				if not found or (dir > 0 and cx < best) or (dir < 0 and cx > best):
					best = cx
					found = true
	return best


func blocking_cz(x0: int, z0: int, x1: int, z1: int, dir: int) -> int:
	var cx0: int = FixedMath.div_floor(x0, CELL)
	var cx1: int = FixedMath.div_floor(x1 - 1, CELL)
	var cz0: int = FixedMath.div_floor(z0, CELL)
	var cz1: int = FixedMath.div_floor(z1 - 1, CELL)
	var best: int = -1
	var found: bool = false
	for cz: int in range(cz0, cz1 + 1):
		for cx: int in range(cx0, cx1 + 1):
			if is_blocking(cx, cz):
				if not found or (dir > 0 and cz < best) or (dir < 0 and cz > best):
					best = cz
					found = true
	return best


## SHA-256 dos 4096 bytes da grade, hex minúsculo.
func grid_sha256() -> String:
	if _sha_rev == _rev:
		return _sha_cache
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(cells)
	_sha_cache = ctx.finish().hex_encode()
	_sha_rev = _rev
	return _sha_cache


## Portas em ordem de varredura (cz crescente, depois cx): {id, cell_x, cell_z, state}.
func doors() -> Array:
	if _doors_rev != _rev:
		_doors_cache = _scan_doors()
		_doors_rev = _rev
	return _doors_cache.duplicate(true)


func _scan_doors() -> Array:
	var out: Array = []
	var next_id: int = 0
	for cz: int in range(H):
		for cx: int in range(W):
			var t: int = cells[cz * W + cx]
			if is_door_type(t):
				out.append({"id": next_id, "cell_x": cx, "cell_z": cz, "state": t})
				next_id += 1
	return out


## 64 strings de 64 dígitos (linha = cz).
func rows() -> Array:
	var out: Array = []
	for cz: int in range(H):
		var s: String = ""
		for cx: int in range(W):
			s += str(cells[cz * W + cx])
		out.append(s)
	return out


func duplicate_grid() -> Grid:
	var g: Grid = Grid.new()
	g.cells = cells.duplicate()
	g.rooms = rooms.duplicate(true)
	g.start_room = start_room
	g.exit_room = exit_room
	g.spawn_x = spawn_x
	g.spawn_z = spawn_z
	g.spawn_angle = spawn_angle
	return g
