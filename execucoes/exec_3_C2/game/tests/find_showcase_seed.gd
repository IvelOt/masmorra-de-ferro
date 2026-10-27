extends SceneTree
## C10 (plano R5 §4.1): busca a semente de vitrine do modo atração.
## godot --headless --path game -s res://tests/find_showcase_seed.gd
## Só usa o núcleo e o piloto; o ângulo relativo é calculado em float aqui (fora do núcleo).
## C15 (plano R6 §5.1): a semente também precisa de item em quadro (MIN_ITEM_TICKS, com
## fallback para MIN_ITEM_TICKS_FALLBACK).

const IntInput = preload("res://sim/int_input.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const Grid = preload("res://sim/grid.gd")
const PilotEscape = preload("res://scripts/pilot_escape.gd")

const IDLE_TICKS: int = 30
const LAST_TICK: int = 420
const WINDOW_FROM: int = 60
const MAX_DIST: float = 8192.0
const MAX_REL_BAM: int = 341
const MIN_TICKS: int = 90
const MAX_FIRST: int = 300
const SEARCH_MAX: int = 2000
const MIN_ITEM_TICKS: int = 30
const MIN_ITEM_TICKS_FALLBACK: int = 15


## Ids dos inimigos "em quadro" (§4.1 item 2) no estado atual do mundo.
static func enemies_in_frame(w: WorldSim) -> Array:
	var out: Array = []
	var p: Variant = w.player
	for e: EnemySim in w.enemies:
		if e.state == "DEAD":
			continue
		var dx: float = float(e.pos_x - p.pos_x)
		var dz: float = float(e.pos_z - p.pos_z)
		if dx * dx + dz * dz > MAX_DIST * MAX_DIST:
			continue
		var bearing: int = roundi(atan2(dz, dx) * 4096.0 / TAU)
		if absi(wrapi(bearing - int(p.angle), -2048, 2048)) > MAX_REL_BAM:
			continue
		if not EnemySim.line_of_sight(w.grid, e.pos_x, e.pos_z, p.pos_x, p.pos_z):
			continue
		out.append(e.id)
	return out


## Ids dos itens "em quadro" (plano R6 §5.1) no estado atual do mundo.
static func items_in_frame(w: WorldSim) -> Array:
	var out: Array = []
	var p: Variant = w.player
	for it: Dictionary in w.items:
		if it["taken"]:
			continue
		var ix: int = int(it["cell_x"]) * Grid.CELL + Grid.CELL / 2
		var iz: int = int(it["cell_z"]) * Grid.CELL + Grid.CELL / 2
		var dx: float = float(ix - p.pos_x)
		var dz: float = float(iz - p.pos_z)
		if dx * dx + dz * dz > MAX_DIST * MAX_DIST:
			continue
		var bearing: int = roundi(atan2(dz, dx) * 4096.0 / TAU)
		if absi(wrapi(bearing - int(p.angle), -2048, 2048)) > MAX_REL_BAM:
			continue
		if not EnemySim.line_of_sight(w.grid, ix, iz, p.pos_x, p.pos_z):
			continue
		out.append(int(it["id"]))
	return out


## [contagem com inimigo, primeiro tick com inimigo, contagem com item] para a
## semente s, como no modo atração.
static func evaluate(s: int) -> Array:
	var w := WorldSim.new(s, "dungeon")
	var pe := PilotEscape.new(s)
	var count: int = 0
	var first: int = -1
	var items: int = 0
	for t in range(1, LAST_TICK + 1):
		if t <= IDLE_TICKS:
			w.step(IntInput.new())
		else:
			w.step(pe.next_input(w))
		if t < WINDOW_FROM:
			continue
		if not enemies_in_frame(w).is_empty():
			count += 1
			if first < 0:
				first = t
		if not items_in_frame(w).is_empty():
			items += 1
	return [count, first, items]


static func accepted(r: Array, min_items: int = MIN_ITEM_TICKS) -> bool:
	return int(r[0]) >= MIN_TICKS and int(r[1]) >= 0 and int(r[1]) <= MAX_FIRST and int(r[2]) >= min_items


func _init() -> void:
	for min_items: int in [MIN_ITEM_TICKS, MIN_ITEM_TICKS_FALLBACK]:
		for s in range(1, SEARCH_MAX + 1):
			var r: Array = evaluate(s)
			if accepted(r, min_items):
				print("semente de vitrine: %d (%d ticks com inimigo em quadro, primeiro em t=%d; %d ticks com item, limiar %d)"
					% [s, r[0], r[1], r[2], min_items])
				quit(0)
				return
	print("nenhuma semente de 1 a %d passou" % SEARCH_MAX)
	quit(1)
