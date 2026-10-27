extends RefCounted
## Automapa (M5, GDD §4.5): bitmap `visited` 64×64 (índice cz·64 + cx), valores 0/1, monotônico.
## O estado "mapa aberto" não existe no núcleo: é só da apresentação.

const Grid = preload("res://sim/grid.gd")
const FM = preload("res://sim/fixed_math.gd")

var visited: PackedByteArray = PackedByteArray()

var _sha_cache: String = ""


func _init() -> void:
	reset()


func reset() -> void:
	visited.resize(Grid.GRID_W * Grid.GRID_H)
	visited.fill(0)
	_sha_cache = ""


## Passo 9. Célula de sala: marca a sala expandida de 1 célula (contorno);
## qualquer outra célula (corredor, porta): marca a célula e as 8 vizinhas. Limitado a [0, 63].
func mark(grid: Grid, pcx: int, pcz: int) -> void:
	var rid: int = grid.get_room_id(pcx, pcz)
	if rid >= 0:
		var r: Dictionary = grid.rooms[rid]
		_mark_rect(int(r.x) - 1, int(r.z) - 1, int(r.x) + int(r.w), int(r.z) + int(r.h))
	else:
		_mark_rect(pcx - 1, pcz - 1, pcx + 1, pcz + 1)


## Retângulo inclusivo [x0, x1] × [z0, z1].
func _mark_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	var ax: int = FM.max_i(x0, 0)
	var az: int = FM.max_i(z0, 0)
	var bx: int = FM.min_i(x1, Grid.GRID_W - 1)
	var bz: int = FM.min_i(z1, Grid.GRID_H - 1)
	for cz in range(az, bz + 1):
		for cx in range(ax, bx + 1):
			var i: int = Grid.index_of(cx, cz)
			if visited[i] == 0:
				visited[i] = 1
				_sha_cache = ""


func is_visited(cx: int, cz: int) -> bool:
	return Grid.in_bounds(cx, cz) and visited[Grid.index_of(cx, cz)] != 0


func count() -> int:
	var n: int = 0
	for v: int in visited:
		n += v
	return n


func sha256() -> String:
	if _sha_cache == "":
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(visited)
		_sha_cache = ctx.finish().hex_encode()
	return _sha_cache
