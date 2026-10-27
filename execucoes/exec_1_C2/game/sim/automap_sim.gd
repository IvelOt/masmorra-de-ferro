class_name AutomapSim
extends RefCounted
## Automapa no núcleo (M5): bitmap de células visitadas e mapa de salas por
## célula. Nunca desmarca; marcar a mesma célula de novo não muda nada.

var visited: PackedByteArray
var room_of: PackedInt32Array
var _rooms: Array[Dictionary] = []
var _sha_cache: String = ""


static func create(d: DungeonGen) -> AutomapSim:
	var a: AutomapSim = AutomapSim.new()
	a.visited = PackedByteArray()
	a.visited.resize(Grid.SIZE * Grid.SIZE)
	a.visited.fill(0)
	a.room_of = PackedInt32Array()
	a.room_of.resize(Grid.SIZE * Grid.SIZE)
	a.room_of.fill(-1)
	a._rooms = d.rooms
	for r: Dictionary in d.rooms:
		for cz in range(int(r.z), int(r.z) + int(r.h)):
			for cx in range(int(r.x), int(r.x) + int(r.w)):
				if Grid.in_bounds(cx, cz):
					a.room_of[cz * Grid.SIZE + cx] = int(r.id)
	return a


## Passo 9: sala inteira com contorno, ou a célula e as 8 vizinhas fora de sala.
func mark(cx: int, cz: int) -> void:
	if not Grid.in_bounds(cx, cz):
		return
	var r: int = room_of[cz * Grid.SIZE + cx]
	if r >= 0:
		var room: Dictionary = _rooms[r]
		_mark_rect(int(room.x) - 1, int(room.z) - 1, int(room.x) + int(room.w), int(room.z) + int(room.h))
	else:
		_mark_rect(cx - 1, cz - 1, cx + 1, cz + 1)


func _mark_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, Grid.SIZE - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, Grid.SIZE - 1) + 1):
			if visited[z * Grid.SIZE + x] == 0:
				visited[z * Grid.SIZE + x] = 1
				_sha_cache = ""


func is_visited(cx: int, cz: int) -> bool:
	return Grid.in_bounds(cx, cz) and visited[cz * Grid.SIZE + cx] == 1


func count() -> int:
	var n: int = 0
	for i in range(Grid.SIZE * Grid.SIZE):
		n += visited[i]
	return n


## SHA-256 dos 4096 bytes de visited, em hexadecimal minúsculo.
func sha256() -> String:
	if _sha_cache == "":
		var ctx: HashingContext = HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(visited)
		_sha_cache = ctx.finish().hex_encode()
	return _sha_cache
