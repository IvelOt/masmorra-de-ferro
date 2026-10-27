extends RefCounted
## Combate do Guerreiro (M3, GDD §3.4 e §4.3): máquina do golpe, hitbox da espada,
## dano recebido com bloqueio frontal, atordoamento e regeneração de vigor.
## Só inteiros; os passos 5, 7 e 8 de world_sim.step() chamam as funções abaixo.

const FM = preload("res://sim/fixed_math.gd")
const Trig = preload("res://sim/trig_table.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")

const SWING_WINDUP: int = 6
const SWING_ACTIVE: int = 6
const SWING_RECOVERY: int = 12
const SWING_COST: int = 12
const SWORD_DAMAGE: int = 25
## 1,6 m em unidades de simulação.
const SWORD_REACH: int = 1638
## tan(40°) × 1024: meia-abertura do setor do golpe.
const SWING_TAN_Q10: int = 859
## tan(60°) × 1024, arredondado: arco frontal do bloqueio (±60°) sem trigonometria inversa.
const BLOCK_TAN_Q10: int = 1774
const BLOCK_COST_ADD: int = 5
const STUN_TICKS: int = 20
const REGEN_PERIOD: int = 3
const DUMMY_HP: int = 100
const DUMMY_HALF: int = 384
## Faixas verticais (u): espada 0,2–1,8 m; alvo 0–1,6 m.
const SWORD_Y_MIN: int = 205
const SWORD_Y_MAX: int = 1843
const TARGET_Y_MIN: int = 0
const TARGET_Y_MAX: int = 1638

const IDLE: String = "IDLE"
const WINDUP: String = "WINDUP"
const ACTIVE: String = "ACTIVE"
const RECOVERY: String = "RECOVERY"


## Bloqueio efetivo do passo 2: não durante WINDUP/ACTIVE nem atordoado.
static func effective_block(player: RefCounted, block_input: bool, was_stunned: bool) -> bool:
	return block_input and player.swing_state != WINDUP and player.swing_state != ACTIVE and not was_stunned


## Passo 5. `attack` é borda de subida; sem buffer (attack fora de IDLE é descartado).
## Dano = world.sword_damage() (25 + 5·(nível − 1)); abate soma o XP do tipo em world.pending_xp.
static func swing_step(world: RefCounted, attack: bool, was_stunned: bool) -> void:
	var p: RefCounted = world.player
	if p.swing_state == IDLE:
		if attack and not p.blocking and not was_stunned and p.stamina >= SWING_COST:
			p.stamina -= SWING_COST
			p.swing_state = WINDUP
			p.swing_ticks = 1
			p.swing_hits = []
	else:
		p.swing_ticks += 1
		if p.swing_state == WINDUP and p.swing_ticks > SWING_WINDUP:
			p.swing_state = ACTIVE
			p.swing_ticks = 1
		elif p.swing_state == ACTIVE and p.swing_ticks > SWING_ACTIVE:
			p.swing_state = RECOVERY
			p.swing_ticks = 1
		elif p.swing_state == RECOVERY and p.swing_ticks > SWING_RECOVERY:
			p.swing_state = IDLE
			p.swing_ticks = 0
	if p.swing_state == ACTIVE:
		for e: Dictionary in world.enemies:
			if e.state == "DEAD" or p.swing_hits.has(e.id):
				continue
			if sword_hits(p.pos_x, p.pos_z, p.angle, e.pos_x, e.pos_z, e.half, PlayerSim.PLAYER_HALF):
				e.hp = int(e.hp) - int(world.sword_damage())
				p.swing_hits.append(e.id)
				p.swing_hits.sort()
				if e.hp <= 0:
					e.hp = 0
					e.state = "DEAD"
					e.state_ticks = 0
					world.pending_xp += int(EnemySim.TYPES[e.type].xp)


## Sobreposição das faixas verticais da espada e do alvo (sempre verdadeira hoje; contrato de M4).
static func vertical_overlap() -> bool:
	return SWORD_Y_MIN < TARGET_Y_MAX and TARGET_Y_MIN < SWORD_Y_MAX


## Hitbox da espada (plano §4.6): setor frontal ±40° até SWORD_REACH + half, ou caixas sobrepostas.
static func sword_hits(px: int, pz: int, angle: int, ex: int, ez: int, half: int, player_half: int) -> bool:
	var dx: int = ex - px
	var dz: int = ez - pz
	var fx: int = Trig.cos_q16(angle)
	var fz: int = Trig.sin_q16(angle)
	var along: int = (dx * fx + dz * fz) >> 16
	var side: int = FM.abs_i(dx * fz - dz * fx) >> 16
	var sector: bool = along > 0 and along <= SWORD_REACH + half and side * 1024 <= along * SWING_TAN_Q10
	var overlap: bool = FM.abs_i(dx) < player_half + half and FM.abs_i(dz) < player_half + half
	return (sector or overlap) and vertical_overlap()


## Passo 7: consome a fila de golpes recebidos na ordem de inserção.
static func resolve_incoming(world: RefCounted) -> void:
	var p: RefCounted = world.player
	var fx: int = Trig.cos_q16(p.angle)
	var fz: int = Trig.sin_q16(p.angle)
	for h: Dictionary in world.incoming_hits:
		var dmg: int = h.dmg
		var dx: int = int(h.src_x) - p.pos_x
		var dz: int = int(h.src_z) - p.pos_z
		var along: int = (dx * fx + dz * fz) >> 16
		var side: int = FM.abs_i(dx * fz - dz * fx) >> 16
		var frontal: bool = along > 0 and side * 1024 <= along * BLOCK_TAN_Q10
		var taken: int = dmg
		if p.blocking and frontal:
			var cost: int = FM.div_trunc(dmg, 2) + BLOCK_COST_ADD
			if p.stamina >= cost:
				p.stamina -= cost
				taken = dmg - FM.div_trunc(dmg * 3, 4)
			else:
				# quebra de guarda: dano cheio, atordoado; o vigor não muda
				p.stun_ticks = STUN_TICKS
				p.blocking = false
		p.hp = FM.max_i(p.hp - taken, 0)
	world.incoming_hits = []


## Passo 8: consome um tick de atordoamento e regenera o vigor (+1 a cada REGEN_PERIOD ticks).
static func stamina_step(world: RefCounted, was_stunned: bool) -> void:
	var p: RefCounted = world.player
	if was_stunned:
		p.stun_ticks -= 1
	if p.swing_state == IDLE and not p.blocking:
		p.regen_ticks += 1
		if p.regen_ticks >= REGEN_PERIOD:
			p.regen_ticks = 0
			p.stamina = FM.min_i(p.stamina + 1, p.stamina_max)
	else:
		p.regen_ticks = 0
