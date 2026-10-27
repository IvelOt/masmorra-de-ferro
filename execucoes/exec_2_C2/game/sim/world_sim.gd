extends RefCounted
## Orquestra step() na ordem fixa do GDD §2.2 (marcos M1 a M6).

const Grid = preload("res://sim/grid.gd")
const DungeonGen = preload("res://sim/dungeon_gen.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
const StateHash = preload("res://sim/state_hash.gd")
const Trig = preload("res://sim/trig_table.gd")
const FM = preload("res://sim/fixed_math.gd")
const Combat = preload("res://sim/combat.gd")
const AutomapSim = preload("res://sim/automap_sim.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const ItemsSim = preload("res://sim/items_sim.gd")
const Pcg32 = preload("res://sim/rng_pcg32.gd")

const SCHEMA_VERSION: int = 3
const K_MAX: int = 18000

var grid: Grid = null
var player: PlayerSim = null
var tick: int = 0
var terminal: String = "NONE"
var terminal_tick: int = -1
var seed_value: int = 0
var dungeon_rng_state: int = 0
var last_hash: String = ""
var chain: String = ""
var hash_error: bool = false
## Entidades em ordem crescente de id: {id, type, pos_x, pos_z, half, hp, hp_max, state, state_ticks, awake}.
var enemies: Array = []
## Itens em ordem crescente de id: {id, type, cell_x, cell_z, amount, taken}.
var items: Array = []
## XP dos abates do passo 5, consumido no passo 8; pedido de fuga do passo 3, consumido no passo 10.
## Ambos valem sempre 0/false no instante do hash, por isso não entram no estado canônico.
var pending_xp: int = 0
var escape_pending: bool = false
## Campo de fluxo BFS a partir do jogador (fora do hash: função pura da grade e da célula do jogador)
## e a chave (célula, sha256 da grade) com que foi calculado.
var flow: PackedInt32Array = PackedInt32Array()
var flow_key: String = ""
## Pcg32(seed, STREAM_AI): não consumido nesta versão (a IA não sorteia); fica no hash pelo contrato.
var ai_rng: Pcg32 = null
## Fila de golpes recebidos {dmg, src_x, src_z}: consumida inteira no passo 7 do próximo step().
## No instante do hash (passo 11) está sempre vazia, por isso não entra no estado canônico.
var incoming_hits: Array = []
var automap: AutomapSim = null
## to_dict() do IntInput do último tick (só para a apresentação; fora do hash).
var last_input: Dictionary = {}


func setup_test(kind: String = "room") -> void:
	if kind == "door":
		_setup_grid(DungeonGen.test_door_room(), 0, 0)
	elif kind == "combat":
		# sala de demonstração: test_room(), jogador no spawn, boneco no centro de (8, 7)
		_setup_grid(DungeonGen.test_room(), 0, 0)
		spawn_dummy(Grid.cell_center(8), Grid.cell_center(7))
	elif kind == "arena":
		_setup_arena()
	else:
		_setup_grid(DungeonGen.test_room(), 0, 0)


func setup_seed(s: int) -> void:
	var gen: DungeonGen = DungeonGen.new()
	var g: Grid = gen.generate(s)
	_setup_grid(g, s, gen.rng.get_state())
	# populate continua o mesmo rng; generate() não muda (grid_sha256 de M2-A5 preservado)
	ItemsSim.populate(self, gen.rng)
	dungeon_rng_state = gen.rng.get_state()
	_reset_chain()


## Arena de demonstração (plano §4.9): entidades e itens fixos, sem RNG.
func _setup_arena() -> void:
	_setup_grid(DungeonGen.test_arena(), 0, 0)
	spawn_enemy("rat", Grid.cell_center(9), Grid.cell_center(6))
	spawn_enemy("skeleton", Grid.cell_center(12), Grid.cell_center(9))
	spawn_enemy("guardian", Grid.cell_center(20), Grid.cell_center(7))
	add_item("potion_hp", 6, 9, 0)
	add_item("gold", 8, 3, 25)
	add_item("key", 11, 3, 0)
	add_item("potion_sp", 4, 10, 0)


func _setup_grid(g: Grid, s: int, rng_state: int) -> void:
	grid = g
	seed_value = s
	dungeon_rng_state = rng_state
	player = PlayerSim.new()
	player.place(g.spawn_x, g.spawn_z, g.spawn_angle)
	tick = 0
	terminal = "NONE"
	terminal_tick = -1
	hash_error = false
	last_hash = ""
	enemies = []
	items = []
	incoming_hits = []
	pending_xp = 0
	escape_pending = false
	flow = PackedInt32Array()
	flow_key = ""
	ai_rng = Pcg32.new(s, Pcg32.STREAM_AI)
	automap = AutomapSim.new()
	last_input = {}
	_reset_chain()


func _reset_chain() -> void:
	chain = StateHash.chain_init(seed_value, SCHEMA_VERSION)


## Cria uma entidade do tipo dado (EnemySim.TYPES) e devolve o id.
func spawn_enemy(type: String, pos_x: int, pos_z: int) -> int:
	var t: Dictionary = EnemySim.TYPES[type]
	var id: int = enemies.size()
	enemies.append({
		"id": id,
		"type": type,
		"pos_x": pos_x,
		"pos_z": pos_z,
		"half": int(t.half),
		"hp": int(t.hp),
		"hp_max": int(t.hp),
		"state": "IDLE",
		"state_ticks": 0,
		"awake": false,
	})
	return id


## Boneco de treino (sem IA; bloqueia o corpo desde M4). Devolve o id.
func spawn_dummy(pos_x: int, pos_z: int) -> int:
	return spawn_enemy("dummy", pos_x, pos_z)


## Acrescenta um item na célula (cell_x, cell_z); `amount` = ouro da pilha (0 nos outros tipos).
func add_item(type: String, cell_x: int, cell_z: int, amount: int) -> int:
	var id: int = items.size()
	items.append({"id": id, "type": type, "cell_x": cell_x, "cell_z": cell_z, "amount": amount, "taken": false})
	return id


## Dano atual da espada: 25 + 5·(nível − 1).
func sword_damage() -> int:
	return ItemsSim.sword_damage(player.level)


## Enfileira um golpe recebido (API dos gates nesta rodada e dos inimigos de M4 no STRIKE).
func inject_hit(dmg: int, src_x: int, src_z: int) -> void:
	incoming_hits.append({"dmg": dmg, "src_x": src_x, "src_z": src_z})


func step(inp: RefCounted) -> void:
	# 1. tick; estado terminal congela tudo exceto o contador
	tick += 1
	last_input = inp.to_dict()
	if terminal == "NONE":
		var was_stunned: bool = player.stun_ticks > 0
		# 2. jogador (bloqueio efetivo reduz o empuxo pela metade; entidades vivas bloqueiam o corpo)
		player.blocking = Combat.effective_block(player, inp.block, was_stunned)
		player.step(inp, grid, player.blocking, EnemySim.blockers(self))
		# 3. interação: portas (trancadas com a chave) -> coleta -> pedido de fuga
		if inp.use:
			_use_doors()
		ItemsSim.collect(self)
		if inp.use:
			ItemsSim.try_escape(self)
		# 4. poções
		ItemsSim.quaff(self, inp.quaff)
		# 5. combate do jogador (abate -> pending_xp)
		Combat.swing_step(self, inp.attack, was_stunned)
		# 6. inimigos (percepção -> movimento -> ataque)
		EnemySim.step_all(self)
		# 7. dano recebido (golpes dos STRIKE do passo 6)
		Combat.resolve_incoming(self)
		# 8. atordoamento e vigor -> XP e nível
		Combat.stamina_step(self, was_stunned)
		ItemsSim.xp_step(self)
		# 9. automapa
		automap.mark(grid, Grid.cell_of(player.pos_x), Grid.cell_of(player.pos_z))
		# 10. condições terminais
		ItemsSim.terminal_step(self, K_MAX)
	# 11. hash
	_update_hash()


## Abre a primeira DOOR_CLOSED (ou DOOR_LOCKED com a chave) de frente a distância Chebyshev <= 1,
## em ordem de índice. A chave não é consumida (a Sala da Saída pode ter várias portas trancadas).
func _use_doors() -> void:
	var pcx: int = Grid.cell_of(player.pos_x)
	var pcz: int = Grid.cell_of(player.pos_z)
	var ca: int = Trig.cos_q16(player.angle)
	var sa: int = Trig.sin_q16(player.angle)
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var cx: int = pcx + dx
			var cz: int = pcz + dz
			if not Grid.in_bounds(cx, cz):
				continue
			var t: int = grid.get_cell(cx, cz)
			if t != Grid.DOOR_CLOSED and t != Grid.DOOR_LOCKED:
				continue
			var ddx: int = Grid.cell_center(cx) - player.pos_x
			var ddz: int = Grid.cell_center(cz) - player.pos_z
			var along: int = (ddx * ca + ddz * sa) >> 16
			var side: int = FM.abs_i(ddx * sa - ddz * ca) >> 16
			if along <= 0 or side > along:
				continue
			if t == Grid.DOOR_CLOSED or int(player.inventory.key) > 0:
				grid.set_cell(cx, cz, Grid.DOOR_OPEN)
				return


func canonical_state() -> Dictionary:
	var doors: Array = []
	for d: Dictionary in grid.doors():
		doors.append({"id": d.id, "type": d.type})
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": tick,
		"terminal": terminal,
		"player": player.to_dict(),
		"dungeon": {"grid_sha256": grid.sha256(), "doors": doors},
		"enemies": enemies.duplicate(true),
		"items": items.duplicate(true),
		"automap": {"visited_sha256": automap.sha256()},
		"rng": {"dungeon_state": dungeon_rng_state, "ai_state": ai_rng.get_state()},
	}


func _update_hash() -> void:
	var h: String = StateHash.hash_state(canonical_state())
	if h == "":
		hash_error = true
	last_hash = h
	chain = StateHash.chain_next(chain, h)


func player_box_hits_solid() -> bool:
	return player.box_hits(grid)


## Cópia profunda, somente leitura, para a apresentação.
func get_snapshot() -> Dictionary:
	return {
		"tick": tick,
		"terminal": terminal,
		"terminal_tick": terminal_tick,
		"player": player.to_dict(),
		"cells": grid.cells.duplicate(),
		"doors": grid.doors(),
		"exit_room": grid.exit_room,
		"rooms": grid.rooms.duplicate(true),
		"enemies": enemies.duplicate(true),
		"items": items.duplicate(true),
		"visited": automap.visited.duplicate(),
		"last_input": last_input.duplicate(),
	}
