class_name AutomapSim
extends RefCounted
## M5: bitmap de células visitadas 64×64 (índice cz*64 + cx), 0 ou 1. Só marca;
## nunca zera (monotonia, M5-A3). O SHA-256 é cacheado por `rev`.

var visited: PackedByteArray = PackedByteArray()
## Sobe quando algum byte passa de 0 para 1.
var rev: int = 0
var _sha_rev: int = -1
var _sha: String = ""
# Última célula marcada: remarcar a mesma célula não muda nada (só desempenho).
var _last_cx: int = -1
var _last_cz: int = -1


func _init() -> void:
	visited.resize(Grid.W * Grid.H)
	visited.fill(0)


func is_visited(cx: int, cz: int) -> bool:
	if not Grid.in_bounds(cx, cz):
		return false
	return visited[cz * Grid.W + cx] == 1


func count() -> int:
	var n: int = 0
	for i: int in range(visited.size()):
		n += visited[i]
	return n


## Passo 9: sala (primeira em ordem de id que contém a célula) mais contorno;
## fora de sala (corredor ou porta), a célula e as vizinhas-8.
func mark(g: Grid, px: int, pz: int) -> void:
	var pcx: int = FixedMath.div_floor(px, Grid.CELL)
	var pcz: int = FixedMath.div_floor(pz, Grid.CELL)
	if pcx == _last_cx and pcz == _last_cz:
		return
	_last_cx = pcx
	_last_cz = pcz
	for r: Dictionary in g.rooms:
		if DungeonGen.in_room(r, pcx, pcz):
			_mark_rect(int(r["x"]) - 1, int(r["z"]) - 1, int(r["x"]) + int(r["w"]), int(r["z"]) + int(r["h"]))
			return
	_mark_rect(pcx - 1, pcz - 1, pcx + 1, pcz + 1)


## Retângulo inclusivo [x0, x1] × [z0, z1], recortado a [0, 63].
func _mark_rect(x0: int, z0: int, x1: int, z1: int) -> void:
	for cz: int in range(maxi(z0, 0), mini(z1, Grid.H - 1) + 1):
		for cx: int in range(maxi(x0, 0), mini(x1, Grid.W - 1) + 1):
			var i: int = cz * Grid.W + cx
			if visited[i] == 0:
				visited[i] = 1
				rev += 1


func sha256() -> String:
	if _sha_rev != rev:
		_sha = StateHash.sha256_bytes(visited)
		_sha_rev = rev
	return _sha
