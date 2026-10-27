class_name AutomapSim
extends RefCounted
## M5: bitmap de células visitadas (GDD §4.5, plano R4 §3.1). Faz parte do estado hasheado.

const Grid = preload("res://sim/grid.gd")
const StateHash = preload("res://sim/state_hash.gd")

## Índice z * 64 + x; 1 = visto. Nunca volta a 0.
var visited: PackedByteArray = PackedByteArray()


func _init() -> void:
	visited.resize(Grid.SIZE * Grid.SIZE)
	visited.fill(0)


## Marca a sala que contém (px, pz) com piso e contorno (com cantos); fora de sala,
## a célula e suas 8 vizinhas. Tudo cortado aos limites da grade.
func mark(px: int, pz: int, rooms: Array) -> void:
	for r: Dictionary in rooms:
		var rx: int = r["x"]
		var rz: int = r["z"]
		var rw: int = r["w"]
		var rh: int = r["h"]
		if px >= rx and px < rx + rw and pz >= rz and pz < rz + rh:
			_mark_rect(rx - 1, rz - 1, rx + rw, rz + rh)
			return
	_mark_rect(px - 1, pz - 1, px + 1, pz + 1)


func _mark_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	for z in range(maxi(z0, 0), mini(z1, Grid.SIZE - 1) + 1):
		for x in range(maxi(x0, 0), mini(x1, Grid.SIZE - 1) + 1):
			visited[z * Grid.SIZE + x] = 1


func is_visited(x: int, z: int) -> bool:
	if not Grid.in_bounds(x, z):
		return false
	return visited[z * Grid.SIZE + x] == 1


func count() -> int:
	var n: int = 0
	for v: int in visited:
		n += v
	return n


func sha256() -> String:
	return StateHash.sha256_hex_bytes(visited)
