class_name Combat
extends RefCounted
## M3: máquina do golpe do Guerreiro, hitbox em setor, bloqueio, vigor e fila
## de dano recebido (plano da iteração 2 §2). Funções estáticas sobre PlayerSim.

const IDLE: int = 0
const WINDUP: int = 1
const ACTIVE: int = 2
const RECOVERY: int = 3

const SWING_WINDUP: int = 6
const SWING_ACTIVE: int = 6
const SWING_RECOVERY: int = 12
const SWING_TOTAL: int = SWING_WINDUP + SWING_ACTIVE + SWING_RECOVERY
const SWING_COST: int = 12
const SWORD_DAMAGE: int = 25
const SWORD_REACH: int = 1638
const LEVEL_DAMAGE_BONUS: int = 5
## tan 40° ≈ 859/1024 (arco do golpe) e tan 60° ≈ 1774/1024 (arco do bloqueio).
const TAN40_NUM: int = 859
const TAN40_DEN: int = 1024
const TAN60_NUM: int = 1774
const TAN60_DEN: int = 1024
const STUN_TICKS: int = 20
const REGEN_PERIOD: int = 3
## Faixa vertical da lâmina em u (0,2 m a 1,8 m).
const BLADE_Y0: int = 205
const BLADE_Y1: int = 1843


## Fase do golpe para swing_ticks em 1..24.
static func phase_for(ticks: int) -> int:
	if ticks <= SWING_WINDUP:
		return WINDUP
	if ticks <= SWING_WINDUP + SWING_ACTIVE:
		return ACTIVE
	return RECOVERY


## Caixas semiabertas sobrepostas no plano XZ.
static func boxes_overlap(ax: int, az: int, ahalf: int, bx: int, bz: int, bhalf: int) -> bool:
	return FixedMath.abs_i(bx - ax) < ahalf + bhalf and FixedMath.abs_i(bz - az) < ahalf + bhalf


## Contrato da faixa vertical [205, 1843] u contra [0, height_u] do alvo. Todos
## os alvos estão no chão, então a interseção sempre existe; fica explícito para
## extensões (alvos voadores ou abaixo do piso).
static func vertical_overlap(height_u: int) -> bool:
	return BLADE_Y0 < height_u and 0 < BLADE_Y1


## Dano da espada por nível (25 / 30 / 35).
static func sword_damage(p: PlayerSim) -> int:
	return SWORD_DAMAGE + LEVEL_DAMAGE_BONUS * (p.level - 1)


## Passo 5: avança o golpe, inicia um novo e aplica a hitbox na janela ativa.
## Devolve os ids que foram a DEAD neste tick pelo golpe, em ordem crescente.
static func player_step(p: PlayerSim, inp: IntInput, enemies: Array) -> Array:
	var killed: Array = []
	# 5.1 avança
	if p.swing_state != IDLE:
		p.swing_ticks += 1
		if p.swing_ticks > SWING_TOTAL:
			p.swing_state = IDLE
			p.swing_ticks = 0
			p.swing_hits = []
		else:
			p.swing_state = phase_for(p.swing_ticks)
	# 5.2 inicia (o attack já chega como borda de subida)
	if inp.attack and p.swing_state == IDLE and not p.blocking and not p.stunned \
			and p.stamina >= SWING_COST:
		p.stamina = FixedMath.clamp_i(p.stamina - SWING_COST, 0, p.stamina_max)
		p.swing_state = WINDUP
		p.swing_ticks = 1
		p.swing_hits = []
	# 5.3 hitbox
	if p.swing_state != ACTIVE:
		return killed
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	for e: EnemySim.Enemy in enemies:
		if e.state == EnemySim.DEAD or p.swing_hits.has(e.id):
			continue
		var half: int = EnemySim.half_of(e.type)
		var dx: int = e.pos_x - p.pos_x
		var dz: int = e.pos_z - p.pos_z
		var along: int = (dx * fx + dz * fz) >> 16
		var side: int = FixedMath.abs_i(dx * fz - dz * fx) >> 16
		var in_sector: bool = along > 0 and along <= SWORD_REACH + half \
			and side * TAN40_DEN <= along * TAN40_NUM
		var hit: bool = in_sector or boxes_overlap(p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF, e.pos_x, e.pos_z, half)
		if not hit or not vertical_overlap(EnemySim.height_of(e.type)):
			continue
		e.hp -= sword_damage(p)
		p.swing_hits.append(e.id)
		if e.hp <= 0:
			e.hp = 0
			e.state = EnemySim.DEAD
			e.state_ticks = 0
			killed.append(e.id)
	return killed


## true se a origem do golpe está no arco frontal de ±60° do jogador.
static func is_frontal(p: PlayerSim, origin_x: int, origin_z: int) -> bool:
	var dx: int = origin_x - p.pos_x
	var dz: int = origin_z - p.pos_z
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var dot: int = dx * fx + dz * fz
	var cross: int = FixedMath.abs_i(dx * fz - dz * fx)
	return dot > 0 and cross * TAN60_DEN <= dot * TAN60_NUM


## Passo 7: resolve a fila em ordem de inserção. Devolve true se a guarda quebrou.
static func resolve_hits(p: PlayerSim, pending: Array) -> bool:
	var broke: bool = false
	for h: Dictionary in pending:
		var dmg: int = int(h["dmg"])
		var taken: int = dmg
		if p.blocking and is_frontal(p, int(h["origin_x"]), int(h["origin_z"])):
			var cost: int = FixedMath.div_trunc(dmg, 2) + 5
			if p.stamina >= cost:
				p.stamina = FixedMath.clamp_i(p.stamina - cost, 0, p.stamina_max)
				taken = dmg - FixedMath.div_trunc(dmg * 3, 4)
			else:
				# Quebra de guarda: dano integral, vigor inalterado.
				p.stun_ticks = STUN_TICKS
				p.blocking = false
				broke = true
		p.hp = FixedMath.clamp_i(p.hp - taken, 0, p.hp_max)
	return broke


## Passo 8: regeneração de vigor e contagem do atordoamento.
static func regen_step(p: PlayerSim, tick: int, stun_set_this_tick: bool) -> void:
	if p.swing_state == IDLE and not p.blocking \
			and tick - FixedMath.div_floor(tick, REGEN_PERIOD) * REGEN_PERIOD == 0:
		p.stamina = FixedMath.clamp_i(p.stamina + 1, 0, p.stamina_max)
	if p.stun_ticks > 0 and not stun_set_this_tick:
		p.stun_ticks -= 1
