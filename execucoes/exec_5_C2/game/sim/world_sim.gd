class_name WorldSim
extends RefCounted
## Orquestra step() na ordem fixa do GDD §2.2. Único ponto de avanço do tick.

var seed_value: int = 0
var tick: int = 0
var terminal: String = "NONE"
var dungeon: DungeonGen.Dungeon
var player: PlayerSim
var rng_dungeon: RngPcg32
var rng_ai: RngPcg32
var last_hash: String = ""
var chain: String = ""
var type_error: bool = false
var enemies: Array = []          # EntitySim em ordem crescente de id
var pending_hits: Array = []     # {src_x, src_z, dmg}: dano ao jogador, consumido no passo 7 (vazio no passo 11)
var automap: AutomapSim
# Cache NÃO hasheado do campo de fluxo (derivado da grade + célula do jogador; M4).
var flow_dist: PackedInt32Array = PackedInt32Array()
var flow_cell: int = -1
var flow_dirty: bool = true
var flow_recalcs: int = 0        # contador só para teste (M4-AUX-3)
var items: Array = []            # M6: {id, type, cell_x, cell_z, taken} em ordem crescente de id
# Transitórios M6 NÃO hasheados, zerados no início de cada step() (depois do tick += 1).
var killed_now: Array = []       # ids abatidos pelo jogador no passo 5 deste tick
var exit_used: bool = false      # `use` sobre o EXIT com chave neste tick (passo 3)
var events: Array = []           # Strings só para a view e os gates; o núcleo nunca lê


static func create(p_seed: int, use_test_room: bool, fixture: String = "") -> WorldSim:
	var w := WorldSim.new()
	w.seed_value = p_seed
	if fixture == "automap":
		w.dungeon = DungeonGen.automap_fixture(p_seed)
	elif use_test_room:
		w.dungeon = DungeonGen.test_room(p_seed)
	else:
		w.dungeon = DungeonGen.generate(p_seed)
	w.automap = AutomapSim.new()
	w.rng_dungeon = w.dungeon.rng
	w.rng_ai = RngPcg32.create(p_seed, RngPcg32.STREAM_AI)
	w.player = PlayerSim.new()
	w.player.pos_x = w.dungeon.player_start["pos_x"]
	w.player.pos_z = w.dungeon.player_start["pos_z"]
	w.player.angle = w.dungeon.player_start["angle"]
	w.chain = StateHash.chain_init(p_seed)
	if fixture == "" and not use_test_room:
		EnemySim.spawn(w)
		ItemsSim.spawn(w)          # depois dos inimigos; consome só rng_dungeon
	return w


## Acrescenta um boneco de treino; devolve o id (ordem de inserção a partir de 0).
func add_dummy(pos_x: int, pos_z: int) -> int:
	var id: int = enemies.size()
	enemies.append(EntitySim.make_dummy(id, pos_x, pos_z))
	return id


## Acrescenta um inimigo de M4 (rat/skeleton/guardian); devolve o id.
func add_enemy(type: String, pos_x: int, pos_z: int) -> int:
	var id: int = enemies.size()
	enemies.append(EntitySim.make(id, type, pos_x, pos_z))
	return id


## Dano ao jogador vindo de (src_x, src_z); chamado antes de step(), vale para o próximo tick.
func inject_hit(src_x: int, src_z: int, dmg: int) -> void:
	pending_hits.append({"src_x": src_x, "src_z": src_z, "dmg": dmg})


func step(input: IntInput) -> void:
	input.clamp_self()
	tick += 1                       # 1
	killed_now = []
	exit_used = false
	events = []
	if terminal != "NONE":
		_step_hash()
		return
	player.pre_step(input)          # 2
	player.step(input, dungeon.grid)
	_step_use(input)                # 3
	ItemsSim.collect(self)
	_step_quaff(input)              # 4
	Combat.step_player_swing(self, input)  # 5
	_step_enemies()                 # 6
	Combat.resolve_incoming(self)   # 7
	Combat.regen(self)              # 8
	ItemsSim.apply_xp(self)
	automap.mark(player.cell_x(), player.cell_z(), dungeon)  # 9
	_step_terminal()                # 10
	_step_hash()                    # 11


## Passo 3: trata a primeira porta elegível vizinha (Chebyshev <= 1) e de frente (<= 45 graus):
## DOOR_CLOSED abre; DOOR_LOCKED abre só com a chave (que não é consumida); trancada sem chave não
## conta como tratada. Depois, `use` sobre o EXIT com a chave marca exit_used.
func _step_use(input: IntInput) -> void:
	if not input.use:
		return
	var pcx: int = player.cell_x()
	var pcz: int = player.cell_z()
	var fx: int = TrigTable.cos_q16(player.angle)
	var fz: int = TrigTable.sin_q16(player.angle)
	for dr: Dictionary in dungeon.doors:
		var cx: int = dr["cx"]
		var cz: int = dr["cz"]
		var code: int = dungeon.grid.get_cell(cx, cz)
		if code != Grid.DOOR_CLOSED and code != Grid.DOOR_LOCKED:
			continue
		if FixedMath.abs_i(cx - pcx) > 1 or FixedMath.abs_i(cz - pcz) > 1:
			continue
		var dx: int = DungeonGen.cell_center_u(cx) - player.pos_x
		var dz: int = DungeonGen.cell_center_u(cz) - player.pos_z
		var along: int = (dx * fx + dz * fz) >> 16
		var side: int = FixedMath.abs_i(dx * fz - dz * fx) >> 16
		if along > 0 and side <= along:
			if code == Grid.DOOR_LOCKED and not player.key:
				events.append("locked_no_key")
				continue
			if code == Grid.DOOR_LOCKED:
				events.append("unlock:%d" % dr["id"])
			dungeon.grid.set_cell(cx, cz, Grid.DOOR_OPEN)
			flow_dirty = true
			break
	if pcx == dungeon.exit_cell["cx"] and pcz == dungeon.exit_cell["cz"] and player.key:
		exit_used = true


## Passo 4: uma poção por tick com quaff != 0; beber com a barra cheia consome a poção (ganho 0).
func _step_quaff(input: IntInput) -> void:
	if input.quaff == 1:
		if player.potion_hp > 0:
			player.potion_hp -= 1
			var gain: int = FixedMath.min_i(player.hp + ItemsSim.POTION_HP_HEAL, player.hp_max) - player.hp
			player.hp += gain
			events.append("quaff:1:%d" % gain)
		else:
			events.append("quaff_empty:1")
	elif input.quaff == 2:
		if player.potion_sp > 0:
			player.potion_sp -= 1
			var gain_sp: int = FixedMath.min_i(player.stamina + ItemsSim.POTION_SP_GAIN, player.stamina_max) - player.stamina
			player.stamina += gain_sp
			events.append("quaff:2:%d" % gain_sp)
		else:
			events.append("quaff_empty:2")


func _step_enemies() -> void:
	EnemySim.step_all(self)  # M4 (o boneco não age)


## Passo 10: a primeira condição verdadeira vence (morte > fuga > tempo esgotado).
func _step_terminal() -> void:
	if player.hp <= 0:
		terminal = "DEAD"
	elif exit_used:
		terminal = "ESCAPED"
	elif tick >= ItemsSim.K_MAX:
		terminal = "TIMEOUT"


func _step_hash() -> void:
	var s: Dictionary = StateHash.canon(self)
	if not StateHash.assert_types(s):
		type_error = true
		return
	last_hash = StateHash.hash_state(s)
	chain = StateHash.chain_next(chain, last_hash)


# --- getters somente leitura para a apresentação ---

func get_tick() -> int:
	return tick


func get_player_pos() -> Array:
	return [player.pos_x, player.pos_z]


func get_player_vel() -> Array:
	return [player.vel_x, player.vel_z]


func get_angle() -> int:
	return player.angle


func get_grid() -> Grid:
	return dungeon.grid.duplicate_grid()


func get_cell(cx: int, cz: int) -> int:
	return dungeon.grid.get_cell(cx, cz)


func get_doors() -> Array:
	var out: Array = []
	for dr: Dictionary in dungeon.doors:
		out.append({"id": dr["id"], "cx": dr["cx"], "cz": dr["cz"], "state": dungeon.grid.get_cell(dr["cx"], dr["cz"])})
	return out


func get_rooms() -> Array:
	return dungeon.rooms.duplicate(true)


func get_exit_cell() -> Dictionary:
	return dungeon.exit_cell.duplicate()


func get_player_status() -> Dictionary:
	return {
		"hp": player.hp, "hp_max": player.hp_max,
		"stamina": player.stamina, "stamina_max": player.stamina_max,
		"swing_state": player.swing_state, "swing_ticks": player.swing_ticks,
		"blocking": player.blocking, "stun_ticks": player.stun_ticks,
		"level": player.level, "xp": player.xp,
	}


func get_items() -> Array:
	return items.duplicate(true)


func get_inventory() -> Dictionary:
	return {
		"potion_hp": player.potion_hp, "potion_sp": player.potion_sp, "key": player.key,
		"gold": player.gold, "level": player.level, "xp": player.xp,
	}


func get_terminal() -> String:
	return terminal


func get_events() -> Array:
	return events.duplicate()


func get_enemies() -> Array:
	var out: Array = []
	for i in range(enemies.size()):
		out.append((enemies[i] as EntitySim).to_canon())
	return out


func get_enemy_types() -> Dictionary:
	return EnemySim.TYPES.duplicate(true)


func get_visited() -> PackedByteArray:
	return automap.duplicate_bytes()
