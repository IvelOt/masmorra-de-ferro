class_name WorldSim
extends RefCounted
## Orquestra step(IntInput) na ordem fixa do GDD §2.2: 1 (tick), 2 (jogador),
## 3 (portas, Portal e coleta), 4 (poções), 5 (golpe), 6 (inimigos), 7 (dano
## recebido), 8 (vigor, atordoamento e XP), 9 (automapa), 10 (terminal) e 11 (hash).

const SCHEMA_VERSION: int = 1
const K_MAX: int = 18000
const ESCAPED: String = "ESCAPED"
const DEAD: String = "DEAD"
const TIMEOUT: String = "TIMEOUT"
const DUMMY_X: int = 9216 + 4096
const DUMMY_Z: int = 15360

var seed_value: int = 0
var tick: int = 0
var terminal: String = ""
## Tick em que o terminal foi atingido (-1 em jogo); fora de s_k, para o runner.
var terminal_tick: int = -1
var grid: Grid = null
var player: PlayerSim = PlayerSim.new()
var dungeon_rng_state: int = 0
var ai_rng: RngPcg32 = null
var last_hash: String = ""
## true se algum estado violou a guarda de tipos (o runner sai com código 1).
var guard_failed: bool = false
var chain: String = ""
var automap: AutomapSim = AutomapSim.new()
## Inimigos (EnemySim.Enemy) em ordem crescente de id.
var enemies: Array = []
## Itens (ItemsSim.Item) em ordem crescente de id.
var items: Array = []
## Golpes a resolver no passo 7: {origin_x, origin_z, dmg}. Esvaziada no próprio
## tick (os de queue_hit entram antes do step seguinte); fora do estado.
var pending_hits: Array = []
## Incrementado quando uma porta muda de estado; invalida o campo de fluxo.
var grid_version: int = 0
# Campo de fluxo derivado (fora do estado): recalculado só quando a célula do
# jogador ou grid_version mudam.
var _flow: PackedInt32Array = PackedInt32Array()
var _flow_cx: int = -1
var _flow_cz: int = -1
var _flow_version: int = -1


func _init(p_seed: int = 1, use_test_room: bool = false, spawn_enemies: bool = true) -> void:
	seed_value = p_seed
	if use_test_room:
		grid = DungeonGen.test_room()
		dungeon_rng_state = 0
	else:
		var gen: DungeonGen = DungeonGen.new()
		grid = gen.generate(p_seed)
		# Continua o RNG da masmorra depois da grade pronta (grid_sha256 intacto):
		# primeiro os inimigos, depois os itens (M6).
		var rng: RngPcg32 = RngPcg32.new(p_seed, DungeonGen.STREAM_DUNGEON)
		rng.state = gen.rng_state
		if spawn_enemies:
			enemies = EnemySim.spawn_for_dungeon(grid, rng)
		items = ItemsSim.place(grid, rng)
		dungeon_rng_state = rng.state
	ai_rng = RngPcg32.new(p_seed, DungeonGen.STREAM_AI)
	player.set_pose(grid.spawn_x, grid.spawn_z, grid.spawn_angle)
	chain = StateHash.chain_start(seed_value, SCHEMA_VERSION)


## Reposiciona o jogador (usado por gates/trilhas com pose inicial no cabeçalho).
func set_player_pose(x: int, z: int, a: int) -> void:
	player.set_pose(x, z, a)


## Boneco de treino da sala de teste: 2 m à frente do spawn (--dummy). Devolve o id.
func add_training_dummy() -> int:
	return add_enemy(EnemySim.DUMMY, DUMMY_X, DUMMY_Z)


## Acrescenta um inimigo (boneco de treino, gates); devolve o id.
func add_enemy(type: int, pos_x: int, pos_z: int) -> int:
	var id: int = enemies.size()
	enemies.append(EnemySim.make(id, type, pos_x, pos_z))
	return id


## API de teste de M6 (como add_enemy): item na célula (cx, cz); devolve o id.
func add_item(type: int, cx: int, cz: int) -> int:
	var id: int = items.size()
	items.append(ItemsSim.make(id, type, cx, cz))
	return id


## API de teste de M3: golpe resolvido no passo 7 do próximo step(). A view não a chama.
func queue_hit(origin_x: int, origin_z: int, dmg: int) -> void:
	pending_hits.append({"origin_x": origin_x, "origin_z": origin_z, "dmg": dmg})


## Campo de fluxo atualizado para a célula corrente do jogador.
func flow() -> PackedInt32Array:
	var pcx: int = FixedMath.div_floor(player.pos_x, Grid.CELL)
	var pcz: int = FixedMath.div_floor(player.pos_z, Grid.CELL)
	if pcx != _flow_cx or pcz != _flow_cz or grid_version != _flow_version:
		_flow = EnemySim.flow_field(grid, pcx, pcz)
		_flow_cx = pcx
		_flow_cz = pcz
		_flow_version = grid_version
	return _flow


## Força o recálculo do campo de fluxo (gates que editam a grade diretamente).
func invalidate_flow() -> void:
	grid_version += 1


func step(inp: IntInput) -> void:
	# 1. tick
	tick += 1
	if terminal == "":
		_advance(inp)
	else:
		# Congelado (M6-A4): só o tick avança; golpes enfileirados são descartados.
		pending_hits = []
	_emit_hash()


func _advance(inp: IntInput) -> void:
	# 2. jogador (com bloqueio)
	player.step(inp, grid)
	# 3. interação: portas, Portal de Fuga e coleta automática
	var escape_flag: bool = false
	if inp.use:
		_use_door()
		escape_flag = on_exit_cell() and player.has_key
	ItemsSim.collect(player, items)
	# 4. poções
	ItemsSim.quaff(player, inp.quaff)
	# 5. combate do jogador
	var killed: Array = Combat.player_step(player, inp, enemies)
	# 6. inimigos
	EnemySim.step_all(grid, enemies, player, flow(), pending_hits)
	# 7. dano recebido
	var stun_set: bool = Combat.resolve_hits(player, pending_hits)
	pending_hits = []
	# 8. vigor, atordoamento e XP dos abates do passo 5
	Combat.regen_step(player, tick, stun_set)
	for e: EnemySim.Enemy in enemies:
		if killed.has(e.id):
			player.gain_xp(int(EnemySim.XP[e.type]))
	# 9. automapa
	automap.mark(grid, player.pos_x, player.pos_z)
	# 10. terminal (fuga resolvida no passo 3, antes do dano do passo 7)
	if escape_flag:
		terminal = ESCAPED
	elif player.hp <= 0:
		terminal = DEAD
	elif tick >= K_MAX:
		terminal = TIMEOUT
	if terminal != "":
		terminal_tick = tick


## true se o centro do jogador está na célula EXIT.
func on_exit_cell() -> bool:
	return grid.get_cell(FixedMath.div_floor(player.pos_x, Grid.CELL),
		FixedMath.div_floor(player.pos_z, Grid.CELL)) == Grid.EXIT


func _emit_hash() -> void:
	# 11. hash canônico e cadeia
	var s: Dictionary = get_state()
	if not StateHash.type_guard(s):
		push_error("WorldSim: guarda de tipos violada no tick %d" % tick)
		guard_failed = true
	last_hash = StateHash.state_hash(s)
	chain = StateHash.chain_next(chain, last_hash)


## Célula de porta alvo do `use`: vizinha-4 da célula do jogador, de frente (<=45°).
## Varredura N, L, S, O; devolve [cx, cz] ou [] se nenhuma.
func use_target() -> Array:
	var pcx: int = FixedMath.div_floor(player.pos_x, Grid.CELL)
	var pcz: int = FixedMath.div_floor(player.pos_z, Grid.CELL)
	var fx: int = TrigTable.cos_q16(player.angle)
	var fz: int = TrigTable.sin_q16(player.angle)
	for d: Array in DungeonGen.DIRS:
		var cx: int = pcx + int(d[0])
		var cz: int = pcz + int(d[1])
		if not Grid.is_door_type(grid.get_cell(cx, cz)):
			continue
		var dx: int = cx * Grid.CELL + Grid.CELL / 2 - player.pos_x
		var dz: int = cz * Grid.CELL + Grid.CELL / 2 - player.pos_z
		var dot: int = dx * fx + dz * fz
		var cross: int = dx * fz - dz * fx
		if dot >= 0 and FixedMath.abs_i(cross) <= dot:
			return [cx, cz]
	return []


func _use_door() -> void:
	var t: Array = use_target()
	if t.is_empty():
		return
	var cx: int = int(t[0])
	var cz: int = int(t[1])
	var cell: int = grid.get_cell(cx, cz)
	# DOOR_LOCKED exige a chave, que não é consumida (ainda serve no EXIT).
	if cell == Grid.DOOR_CLOSED or (cell == Grid.DOOR_LOCKED and player.has_key):
		grid.set_cell(cx, cz, Grid.DOOR_OPEN)
		grid_version += 1


func get_state() -> Dictionary:
	var en: Array = []
	for e: EnemySim.Enemy in enemies:
		en.append(e.to_dict())
	var it: Array = []
	for i: ItemsSim.Item in items:
		it.append(i.to_dict())
	return {
		"schema_version": SCHEMA_VERSION,
		"tick": tick,
		"terminal": terminal,
		"player": {
			"pos_x": player.pos_x, "pos_z": player.pos_z,
			"vel_x": player.vel_x, "vel_z": player.vel_z,
			"angle": player.angle,
			"hp": player.hp, "hp_max": player.hp_max,
			"stamina": player.stamina, "stamina_max": player.stamina_max,
			"swing_state": player.swing_state, "swing_ticks": player.swing_ticks,
			"swing_hits": player.swing_hits.duplicate(),
			"blocking": player.blocking, "stun_ticks": player.stun_ticks,
			"level": player.level, "xp": player.xp, "gold": player.gold,
			"inventory": {"potion_hp": player.potion_hp, "potion_sp": player.potion_sp, "key": player.has_key},
		},
		"dungeon": {
			"grid_sha256": grid.grid_sha256(),
			"doors": grid.doors(),
		},
		"enemies": en,
		"items": it,
		"automap": {"visited_sha256": automap.sha256()},
		"rng": {"dungeon_state": dungeon_rng_state, "ai_state": ai_rng.state},
	}
