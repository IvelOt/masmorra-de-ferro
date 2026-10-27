class_name WorldSim
extends RefCounted
## Orquestra step() em ordem fixa (GDD §2.2, passos 1 a 11).

var grid: Grid
var player: PlayerSim
var dungeon: DungeonGen
var tick: int = 0
var seed_value: int = 0
var room: String = "dungeon"
var terminal: String = "NONE"
var type_error: bool = false
var enemies: Array[EnemySim] = []          # a view lê; não escreve
var pending_hits: Array[Dictionary] = []   # {src_x, src_z, dmg}; esvaziada no passo 7
var items: Array[Dictionary] = []          # {id, type, cell_x, cell_z, taken}; a view lê
var automap: AutomapSim                    # a view lê automap.visited
var terminal_tick: int = -1
var key_fallback: bool = false             # diagnóstico de M6-A1; fora do hash

const K_MAX: int = ItemsSim.K_MAX

var _ai_state: String = ""
var _xp_gain: int = 0
var _escape_request: bool = false

var _flow: PackedInt32Array = PackedInt32Array()
var _flow_cell: int = -1

var _last_hash: String = ""
var _chain: String = ""


static func create(seed_value_in: int, room_in: String = "dungeon") -> WorldSim:
	var w: WorldSim = WorldSim.new()
	w.seed_value = seed_value_in
	w.room = room_in
	if room_in == "dungeon":
		w.dungeon = DungeonGen.generate(seed_value_in)
	else:
		w.dungeon = DungeonGen.test_room()
	if room_in == "vault":
		w.dungeon.grid.set_cell(15, 4, Grid.DOOR_LOCKED)
		w.dungeon.grid.set_cell(19, 7, Grid.EXIT)
		w.dungeon.exit_room = 1
		w.dungeon.exit_cell = [19, 7]
		w.dungeon._collect_doors()
	w.grid = w.dungeon.grid
	w.player = PlayerSim.new()
	w.player.pos_x = w.dungeon.start_pos[0]
	w.player.pos_z = w.dungeon.start_pos[1]
	if room_in == "combat":
		w.add_enemy(EnemySim.DUMMY, 6349, 15360)
	elif room_in == "arena":
		w.add_enemy(EnemySim.RAT, 12 * Grid.CELL + 1024, 4 * Grid.CELL + 1024)
		w.add_enemy(EnemySim.SKELETON, 18 * Grid.CELL + 1024, 7 * Grid.CELL + 1024)
	elif room_in == "vault":
		w.add_item(ItemsSim.KEY, 4, 7)
		w.add_item(ItemsSim.POTION_HP, 6, 7)
		w.add_item(ItemsSim.POTION_SP, 6, 9)
		w.add_item(ItemsSim.GOLD, 8, 7)
	elif room_in == "dungeon" and w.dungeon.ok:
		w.enemies = EnemySim.spawn_dungeon(w.dungeon)
		var info: Dictionary = {}
		w.items = ItemsSim.place_dungeon(w.dungeon, w.enemies, info)
		w.key_fallback = info.key_fallback
	w.automap = AutomapSim.create(w.dungeon)
	w._ai_state = RngPcg32.create(seed_value_in, RngPcg32.STREAM_AI).state_hex()
	w._chain = StateHash.chain_seed(seed_value_in)
	return w


## Só antes do 1º step(); devolve o id (= tamanho atual da lista).
func add_enemy(type_in: int, x: int, z: int) -> int:
	var id: int = enemies.size()
	enemies.append(EnemySim.make(id, type_in, x, z))
	return id


## Só antes do 1º step(); devolve o id (= tamanho atual da lista).
func add_item(type_in: int, cell_x: int, cell_z: int) -> int:
	var id: int = items.size()
	items.append(ItemsSim.make(id, type_in, cell_x, cell_z))
	return id


## Enfileira um golpe resolvido no passo 7 do próximo step().
func inject_hit(src_x: int, src_z: int, dmg: int) -> void:
	pending_hits.append({"src_x": src_x, "src_z": src_z, "dmg": dmg})


func step(inp_raw: IntInput) -> void:
	var inp: IntInput = inp_raw.clamped()
	# 1. tick; com terminal, o estado fica congelado e só o hash é emitido
	tick += 1
	if terminal == "NONE":
		_step_live(inp)
	else:
		pending_hits = []
	# 11. hash
	var h: String = StateHash.hash_state(snapshot())
	if h == "":
		type_error = true
	_last_hash = h
	_chain = StateHash.chain_next(_chain, h)


func _step_live(inp: IntInput) -> void:
	# 2. jogador (bloqueio, giro, empuxo, colisão contra grade e inimigos)
	player.step(grid, inp, enemies)
	# 3. interação: (a) coleta, (b) porta à frente, (c) saída
	ItemsSim.collect(player, items)
	if inp.use:
		_use_door()
		if grid.get_cell(player.cell_x(), player.cell_z()) == Grid.EXIT and player.has_key:
			_escape_request = true
	# 4. poções
	ItemsSim.quaff(player, inp.quaff)
	# 5. combate do jogador
	_xp_gain = Combat.player_step(player, inp, enemies)
	# 6. inimigos em ordem crescente de id
	for e in enemies:
		if e.alive() and e.type != EnemySim.DUMMY:
			e.think(self, pending_hits)
	# 7. dano recebido
	Combat.resolve_hits(player, pending_hits)
	pending_hits = []
	# 8. regeneração de vigor, depois XP e nível
	Combat.regen(player, tick)
	ItemsSim.gain_xp(player, _xp_gain)
	_xp_gain = 0
	# 9. automapa
	automap.mark(player.cell_x(), player.cell_z())
	# 10. terminais, por prioridade
	if player.hp <= 0:
		terminal = "DEAD"
	elif _escape_request:
		terminal = "ESCAPED"
	elif tick >= K_MAX:
		terminal = "TIMEOUT"
	if terminal != "NONE":
		terminal_tick = tick
	_escape_request = false


## Vizinha-4 na direção cardinal mais próxima de angle; abre DOOR_CLOSED e,
## com a chave, DOOR_LOCKED (a chave fica no inventário).
func _use_door() -> void:
	var dir: int = ((player.angle + 512) & 4095) >> 10
	var rel: int = ((player.angle - dir * 1024 + 2048) & 4095) - 2048
	if FixedMath.abs_i(rel) > 512:
		return
	var dxs: Array[int] = [1, 0, -1, 0]
	var dzs: Array[int] = [0, 1, 0, -1]
	var tx: int = player.cell_x() + dxs[dir]
	var tz: int = player.cell_z() + dzs[dir]
	var t: int = grid.get_cell(tx, tz)
	if t != Grid.DOOR_CLOSED and not (t == Grid.DOOR_LOCKED and player.has_key):
		return
	grid.set_cell(tx, tz, Grid.DOOR_OPEN)
	if player.box_hits(grid):
		grid.set_cell(tx, tz, t)
	else:
		_flow_cell = -1


## Campo de fluxo (cache fora do hash): refeito quando o jogador muda de
## célula ou quando uma porta muda de estado.
func flow() -> PackedInt32Array:
	var c: int = player.cell_z() * Grid.SIZE + player.cell_x()
	if c != _flow_cell:
		_flow = EnemySim.flow_field(grid, player.cell_x(), player.cell_z())
		_flow_cell = c
	return _flow


## A caixa do inimigo em (x, z) intersecta célula opaca, outro inimigo vivo ou o jogador?
func entity_blocked(e: EnemySim, x: int, z: int) -> bool:
	var h: int = e.half()
	if grid.box_hits_blocking(x - h, x + h, z - h, z + h):
		return true
	if EnemySim.boxes_overlap(x, z, h, player.pos_x, player.pos_z, PlayerSim.PLAYER_HALF):
		return true
	for o in enemies:
		if o.id != e.id and o.alive() and EnemySim.boxes_overlap(x, z, h, o.pos_x, o.pos_z, o.half()):
			return true
	return false


## Invariantes de entidades (plano §8.3); "" se tudo certo.
func entity_violation() -> String:
	var p: PlayerSim = player
	if p.stamina < 0 or p.stamina > p.stamina_max:
		return "stamina fora de [0, %d]: %d" % [p.stamina_max, p.stamina]
	if p.hp < 0 or p.hp > p.hp_max:
		return "hp fora de [0, %d]: %d" % [p.hp_max, p.hp]
	for i in range(enemies.size()):
		var e: EnemySim = enemies[i]
		if e.id != i:
			return "enemies fora de ordem no índice %d (id %d)" % [i, e.id]
		if not e.alive():
			continue
		var h: int = e.half()
		if grid.box_hits_blocking(e.pos_x - h, e.pos_x + h, e.pos_z - h, e.pos_z + h):
			return "inimigo %d intersecta célula opaca em (%d, %d)" % [e.id, e.pos_x, e.pos_z]
		if EnemySim.boxes_overlap(e.pos_x, e.pos_z, h, p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF):
			return "inimigo %d intersecta o jogador" % e.id
		for j in range(i + 1, enemies.size()):
			var o: EnemySim = enemies[j]
			if o.alive() and EnemySim.boxes_overlap(e.pos_x, e.pos_z, h, o.pos_x, o.pos_z, o.half()):
				return "inimigos %d e %d se intersectam" % [e.id, o.id]
	return ""


func doors_state() -> Array:
	var out: Array = []
	for d: Dictionary in dungeon.doors:
		out.append({"id": d.id, "cx": d.cx, "cz": d.cz, "state": grid.get_cell(d.cx, d.cz)})
	return out


## Cópia profunda de s_k (somente leitura para a apresentação).
func snapshot() -> Dictionary:
	return {
		"schema_version": StateHash.SCHEMA_VERSION,
		"tick": tick,
		"terminal": terminal,
		"player": player.to_state_dict(),
		"dungeon": {"grid_sha256": grid.sha256(), "doors": doors_state()},
		"enemies": enemies_state(),
		"items": items_state(),
		"automap": {"visited_sha256": automap.sha256()},
		"rng": {"dungeon_state": dungeon.rng.state_hex() if dungeon.rng != null else "", "ai_state": _ai_state},
	}


func items_state() -> Array:
	var out: Array = []
	for it: Dictionary in items:
		out.append(it.duplicate())
	return out


func enemies_state() -> Array:
	var out: Array = []
	for e in enemies:
		out.append(e.to_dict())
	return out


func last_hash() -> String:
	return _last_hash


func chain() -> String:
	return _chain
