class_name WorldSim
extends RefCounted
## Orquestra step() na ordem fixa do GDD §2.2 (plano R4 §6: passos 1 a 11).

const FixedMath = preload("res://sim/fixed_math.gd")
const TrigTable = preload("res://sim/trig_table.gd")
const PCG32 = preload("res://sim/rng_pcg32.gd")
const IntInput = preload("res://sim/int_input.gd")
const Grid = preload("res://sim/grid.gd")
const DungeonGen = preload("res://sim/dungeon_gen.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const Combat = preload("res://sim/combat.gd")
const StateHash = preload("res://sim/state_hash.gd")
const AutomapSim = preload("res://sim/automap_sim.gd")
const ItemsSim = preload("res://sim/items_sim.gd")

## cos 45° em Q16: limite para a porta estar "de frente".
const FACING_MIN_Q16: int = 46341
const USE_DIRS: Array = [[1, 0], [0, 1], [-1, 0], [0, -1]]
## 5 min a 60 ticks/s.
const K_MAX: int = 18000

var seed_value: int = 0
var map_name: String = "dungeon"
var tick: int = 0
var terminal: String = "NONE"
## -1 enquanto terminal == "NONE".
var terminal_tick: int = -1
## Alterável só por debug_set_k_max.
var k_max: int = K_MAX
var grid: Grid
var player: PlayerSim
var doors: Array = []
var rooms: Array = []
var exit_room: int = -1
var rng_dungeon: PCG32
## Reservado para a IA (hasheado, ainda não consumido).
var rng_ai: PCG32
## Inimigos em ordem crescente de id (id = índice).
var enemies: Array = []
## Golpes recebidos neste tick: {src_x, src_z, damage}; esvaziado no passo 7.
var pending_hits: Array = []
## Itens em ordem crescente de id (id = índice).
var items: Array = []
var automap: AutomapSim
var key_fallback: bool = false
## XP dos abates deste tick (não hasheado; zerado no passo 8).
var pending_xp: int = 0
## `use` no EXIT com a chave neste tick (não hasheado; zerado no passo 10).
var _escape_requested: bool = false
var _debug_hits: Array = []
var _flow: PackedInt32Array = PackedInt32Array()
var _flow_cell: int = -1
var _flow_sha: String = ""
var generation_failed: bool = false
var type_error: bool = false
var grid_sha256: String = ""
var last_hash: String = ""
var chain: String = ""


func _init(seed_in: int, map: String = "dungeon") -> void:
	seed_value = seed_in
	map_name = map
	rng_dungeon = PCG32.new(seed_in, PCG32.STREAM_DUNGEON)
	rng_ai = PCG32.new(seed_in, PCG32.STREAM_AI)
	automap = AutomapSim.new()
	var layout: Dictionary
	match map:
		"test":
			layout = DungeonGen.test_room()
		"test_door":
			layout = DungeonGen.test_room_door()
		_:
			layout = DungeonGen.generate(seed_in, rng_dungeon)
	if layout.is_empty():
		generation_failed = true
		grid = Grid.new()
		player = PlayerSim.new(0, 0, 0)
	else:
		grid = layout["grid"]
		doors = layout["doors"]
		rooms = layout["rooms"]
		exit_room = layout["exit_room"]
		player = PlayerSim.new(layout["spawn_x"], layout["spawn_z"], 0)
		if map != "test" and map != "test_door":
			enemies = DungeonGen.place_enemies(layout, rng_dungeon)
			items = DungeonGen.place_items(layout, enemies, rng_dungeon)
			key_fallback = layout.get("key_fallback", false)
	grid_sha256 = grid.sha256()
	chain = StateHash.chain_0(seed_value, StateHash.SCHEMA_VERSION)


func step(raw: IntInput) -> void:
	var inp: IntInput = raw.clamped()
	# 1. tick; estado terminal congela tudo menos o contador
	tick += 1
	if terminal == "NONE":
		_step_live(inp)
	# 11. serialização canônica, H_k e C_k
	var s: Dictionary = canonical_state()
	if not StateHash.is_canonical(s):
		type_error = true
		push_error("WorldSim: tipo não canônico no estado do tick %d" % tick)
		return
	last_hash = StateHash.sha256_hex_text(StateHash.canon_json(s))
	chain = StateHash.chain_next(chain, last_hash)


## Passos 2 a 10.
func _step_live(inp: IntInput) -> void:
	# 2. jogador
	player.step(inp, grid, enemies)
	# 3. interação: coleta automática, depois use (EXIT com chave ou portas)
	ItemsSim.collect(items, player)
	if inp.use:
		if grid.get_cell(player.cell_x(), player.cell_z()) == Grid.EXIT and player.has_key:
			_escape_requested = true
		else:
			_use_doors()
	# 4. poções
	ItemsSim.quaff(player, inp.quaff)
	# 5. combate do jogador
	Combat.player_step(self, inp)
	# 6. inimigos por id
	for e: EnemySim in enemies:
		e.ai_step(self)
	# 7. dano recebido (golpes inimigos, depois os do gancho de teste)
	pending_hits.append_array(_debug_hits)
	_debug_hits = []
	Combat.resolve_hits(self)
	# 8. regeneração, depois XP e níveis
	Combat.regen(self)
	ItemsSim.apply_xp(player, pending_xp)
	pending_xp = 0
	# 9. automapa
	automap.mark(player.cell_x(), player.cell_z(), rooms)
	# 10. terminais: DEAD > ESCAPED > TIMEOUT
	if player.hp <= 0:
		terminal = "DEAD"
	elif _escape_requested:
		terminal = "ESCAPED"
	elif tick >= k_max:
		terminal = "TIMEOUT"
	if terminal != "NONE":
		terminal_tick = tick
	_escape_requested = false


## A chave não é consumida: continua necessária no EXIT.
func _has_key() -> bool:
	return player.has_key


func _use_doors() -> void:
	var pcx: int = player.cell_x()
	var pcz: int = player.cell_z()
	var fx: int = TrigTable.cos_q16(player.angle)
	var fz: int = TrigTable.sin_q16(player.angle)
	for d: Array in USE_DIRS:
		var dx: int = d[0]
		var dz: int = d[1]
		if fx * dx + fz * dz < FACING_MIN_Q16:
			continue
		var c: int = grid.get_cell(pcx + dx, pcz + dz)
		if c == Grid.DOOR_CLOSED or (c == Grid.DOOR_LOCKED and _has_key()):
			grid.set_cell(pcx + dx, pcz + dz, Grid.DOOR_OPEN)
			grid_sha256 = grid.sha256()
			return


func canonical_state() -> Dictionary:
	var door_list: Array = []
	for d: Dictionary in doors:
		door_list.append({
			"id": d["id"], "cell_x": d["cell_x"], "cell_z": d["cell_z"],
			"state": grid.get_cell(d["cell_x"], d["cell_z"]),
		})
	return {
		"schema_version": StateHash.SCHEMA_VERSION,
		"tick": tick,
		"terminal": terminal,
		"terminal_tick": terminal_tick,
		"player": player.to_dict(),
		"dungeon": {"grid_sha256": grid_sha256, "doors": door_list},
		"enemies": get_enemies(),
		"items": get_items(),
		"automap": {"visited_sha256": automap.sha256()},
		"rng": {"dungeon_state": rng_dungeon.state_hex(), "ai_state": rng_ai.state_hex()},
	}


## Campo de fluxo até o jogador; recalculado só se a célula do jogador ou a grade mudam.
func get_flow() -> PackedInt32Array:
	var cell: int = player.cell_z() * Grid.SIZE + player.cell_x()
	if cell != _flow_cell or grid_sha256 != _flow_sha:
		_flow = EnemySim.build_flow(grid, player.cell_x(), player.cell_z())
		_flow_cell = cell
		_flow_sha = grid_sha256
	return _flow


func enemy_intersects_solid() -> bool:
	for e: EnemySim in enemies:
		if e.is_alive() and grid.box_hits_solid(e.pos_x, e.pos_z, e.half()):
			return true
	return false


## Sobreposição estrita entre caixas vivas (inimigo x inimigo e inimigo x jogador).
func live_boxes_overlap() -> bool:
	for i in range(enemies.size()):
		var a: EnemySim = enemies[i]
		if not a.is_alive():
			continue
		var rp: int = a.half() + PlayerSim.PLAYER_HALF
		if FixedMath.abs_i(a.pos_x - player.pos_x) < rp and FixedMath.abs_i(a.pos_z - player.pos_z) < rp:
			return true
		for j in range(i + 1, enemies.size()):
			var b: EnemySim = enemies[j]
			if not b.is_alive():
				continue
			var r: int = a.half() + b.half()
			if FixedMath.abs_i(a.pos_x - b.pos_x) < r and FixedMath.abs_i(a.pos_z - b.pos_z) < r:
				return true
	return false


# --- ganchos de teste (só tests/; lint_sim.py proíbe .debug_*( em view/, input/, scripts/) ---

func debug_spawn_enemy(type: String, x: int, z: int) -> int:
	var e: EnemySim = EnemySim.create(enemies.size(), type, x, z)
	enemies.append(e)
	return e.id


func debug_set_player(x: int, z: int, a: int) -> void:
	player.pos_x = x
	player.pos_z = z
	player.angle = a & 4095


func debug_set_stamina(v: int) -> void:
	player.stamina = v


func debug_queue_hit(src_x: int, src_z: int, damage: int) -> void:
	_debug_hits.append({"src_x": src_x, "src_z": src_z, "damage": damage})


func debug_open_all_doors() -> void:
	for z in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			if grid.get_cell(x, z) == Grid.DOOR_CLOSED:
				grid.set_cell(x, z, Grid.DOOR_OPEN)
	grid_sha256 = grid.sha256()


func debug_keep_only_enemy(id: int) -> void:
	for e: EnemySim in enemies:
		if e.id != id:
			e.state = "DEAD"
			e.state_ticks = 0


func debug_force_awake(id: int) -> void:
	var e: EnemySim = enemies[id]
	e.awake = true
	e.state = "CHASE"
	e.state_ticks = 0


func debug_set_cell(x: int, z: int, c: int) -> void:
	grid.set_cell(x, z, c)
	grid_sha256 = grid.sha256()


func debug_add_item(type: String, cx: int, cz: int, amount: int = 1) -> int:
	items.append(ItemsSim.make(items.size(), type, cx, cz, amount))
	return items.size() - 1


func debug_give(kind: String, n: int) -> void:
	match kind:
		"potion_hp":
			player.potion_hp += n
		"potion_sp":
			player.potion_sp += n
		"key":
			player.has_key = n > 0


func debug_set_hp(v: int) -> void:
	player.hp = v


func debug_add_xp(v: int) -> void:
	pending_xp += v


func debug_set_k_max(v: int) -> void:
	k_max = v


func player_intersects_solid() -> bool:
	return grid.box_hits_solid(player.pos_x, player.pos_z, PlayerSim.PLAYER_HALF)


# --- getters somente leitura para a apresentação ---

func get_player() -> Dictionary:
	return player.to_dict()


func get_grid() -> PackedByteArray:
	return grid.cells.duplicate()


func get_grid_sha256() -> String:
	return grid_sha256


func get_doors() -> Array:
	return canonical_state()["dungeon"]["doors"]


## Cópias somente leitura dos inimigos, em ordem de id.
func get_enemies() -> Array:
	var out: Array = []
	for e: EnemySim in enemies:
		out.append(e.to_dict())
	return out


func get_tick() -> int:
	return tick


## Cópia profunda dos itens, em ordem de id.
func get_items() -> Array:
	return items.duplicate(true)


func get_visited() -> PackedByteArray:
	return automap.visited.duplicate()


func get_rooms() -> Array:
	return rooms.duplicate(true)


func get_terminal() -> String:
	return terminal


func get_terminal_tick() -> int:
	return terminal_tick
