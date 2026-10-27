class_name AutomapSim
extends RefCounted
## M5: bitmap 64x64 de células visitadas (0/1, índice z*64+x). Monotônico: só escreve 1.

var visited: PackedByteArray


func _init() -> void:
	visited = PackedByteArray()
	visited.resize(Grid.W * Grid.H)
	visited.fill(0)


## Passo 9: sala (em ordem de id) -> sala + contorno; senão célula atual + vizinhas-8.
func mark(pcx: int, pcz: int, dungeon: DungeonGen.Dungeon) -> void:
	for i in range(dungeon.rooms.size()):
		var r: Dictionary = dungeon.rooms[i]
		if pcx >= r["x"] and pcx < r["x"] + r["w"] and pcz >= r["z"] and pcz < r["z"] + r["h"]:
			_mark_rect(r["x"] - 1, r["z"] - 1, r["x"] + r["w"], r["z"] + r["h"])
			return
	_mark_rect(pcx - 1, pcz - 1, pcx + 1, pcz + 1)


## Marca o retângulo inclusivo [x0, x1] x [z0, z1], recortado a 0..63.
func _mark_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	for cz in range(FixedMath.max_i(z0, 0), FixedMath.min_i(z1, Grid.H - 1) + 1):
		for cx in range(FixedMath.max_i(x0, 0), FixedMath.min_i(x1, Grid.W - 1) + 1):
			visited[cz * Grid.W + cx] = 1


func is_visited(cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= Grid.W or cz >= Grid.H:
		return false
	return visited[cz * Grid.W + cx] == 1


func count() -> int:
	var n: int = 0
	for i in range(visited.size()):
		n += visited[i]
	return n


func sha256() -> String:
	return Grid.sha256_bytes(visited)


func duplicate_bytes() -> PackedByteArray:
	return visited.duplicate()
