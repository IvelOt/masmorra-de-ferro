class_name Combat
extends RefCounted
## M3: golpe do jogador (passo 5), dano recebido com bloqueio (passo 7) e regeneração de vigor (passo 8).

const WINDUP_TICKS: int = 6
const ACTIVE_TICKS: int = 6
const RECOVERY_TICKS: int = 12
const SWING_COST: int = 12
const SWORD_DAMAGE: int = 25
const SWORD_REACH: int = 1638
const TAN40_NUM: int = 859
const TAN40_DEN: int = 1024
const TAN60_NUM: int = 1774
const TAN60_DEN: int = 1024
const STUN_TICKS: int = 20
const REGEN_PERIOD: int = 3


static func sword_damage(level: int) -> int:
	return SWORD_DAMAGE + 5 * (level - 1)


## Passo 5: avança o golpe em curso, inicia um novo e aplica a hitbox na janela ativa.
static func step_player_swing(world: WorldSim, input: IntInput) -> void:
	var p: PlayerSim = world.player
	# (a) avançar golpe em curso
	if p.swing_state != "IDLE":
		p.swing_ticks += 1
		if p.swing_state == "WINDUP" and p.swing_ticks > WINDUP_TICKS:
			p.swing_state = "ACTIVE"
			p.swing_ticks = 1
		elif p.swing_state == "ACTIVE" and p.swing_ticks > ACTIVE_TICKS:
			p.swing_state = "RECOVERY"
			p.swing_ticks = 1
		elif p.swing_state == "RECOVERY" and p.swing_ticks > RECOVERY_TICKS:
			p.swing_state = "IDLE"
			p.swing_ticks = 0
			p.swing_hits = []
	# (b) iniciar golpe
	if p.swing_state == "IDLE" and input.attack and not p.blocking and not p.stunned_now \
			and p.stamina >= SWING_COST:
		p.swing_state = "WINDUP"
		p.swing_ticks = 1
		p.stamina -= SWING_COST
		p.swing_hits = []
	# (c) hitbox na janela ativa (enemies já em ordem crescente de id, logo swing_hits fica ordenado)
	if p.swing_state == "ACTIVE":
		for i in range(world.enemies.size()):
			var e: EntitySim = world.enemies[i]
			if e.state == "DEAD" or p.swing_hits.has(e.id):
				continue
			if hit_test(p, e):
				e.hp -= sword_damage(p.level)
				p.swing_hits.append(e.id)
			if e.hp <= 0:
				e.hp = 0
				e.state = "DEAD"
				world.killed_now.append(e.id)   # M6: XP no passo 8


## Setor frontal de ±40° até alcance + raio do alvo, ou sobreposição das caixas (semiaberta).
static func hit_test(p: PlayerSim, e: EntitySim) -> bool:
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var dx: int = e.pos_x - p.pos_x
	var dz: int = e.pos_z - p.pos_z
	var along: int = (dx * fx + dz * fz) >> 16
	var side: int = FixedMath.abs_i(dx * fz - dz * fx) >> 16
	var r: int = EntitySim.HALF[e.type]
	var sector: bool = along > 0 and along <= SWORD_REACH + r and side * TAN40_DEN <= along * TAN40_NUM
	var overlap: bool = FixedMath.abs_i(dx) < PlayerSim.PLAYER_HALF + r \
		and FixedMath.abs_i(dz) < PlayerSim.PLAYER_HALF + r
	return (sector or overlap) and vertical_ok(p, e)


## Faixa vertical da espada [0,2 m; 1,8 m] contra a faixa do alvo. Todos estão no chão hoje (GDD §4.3).
static func vertical_ok(_p: PlayerSim, _e: EntitySim) -> bool:
	return true


## Passo 7: consome pending_hits em ordem de inserção e esvazia o canal.
static func resolve_incoming(world: WorldSim) -> void:
	var p: PlayerSim = world.player
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	for i in range(world.pending_hits.size()):
		var h: Dictionary = world.pending_hits[i]
		var dmg: int = h["dmg"]
		var dx: int = int(h["src_x"]) - p.pos_x
		var dz: int = int(h["src_z"]) - p.pos_z
		var along: int = (dx * fx + dz * fz) >> 16
		var side: int = FixedMath.abs_i(dx * fz - dz * fx) >> 16
		var frontal: bool = along > 0 and side * TAN60_DEN <= along * TAN60_NUM
		if p.blocking and frontal:
			var cost: int = FixedMath.div_trunc(dmg, 2) + 5
			if p.stamina >= cost:
				p.stamina -= cost
				p.hp -= dmg - FixedMath.div_trunc(dmg * 3, 4)
			else:
				# Quebra de guarda: dano integral e atordoamento. Decisão da rodada 2:
				# o vigor NÃO é debitado na quebra. Golpes seguintes do mesmo tick levam dano integral.
				p.hp -= dmg
				p.stun_ticks = STUN_TICKS
				p.blocking = false
		else:
			p.hp -= dmg
		p.hp = FixedMath.max_i(p.hp, 0)
	world.pending_hits = []


## Passo 8: +1 de vigor a cada 3 ticks globais, fora de golpe e de bloqueio.
static func regen(world: WorldSim) -> void:
	var p: PlayerSim = world.player
	if world.tick % REGEN_PERIOD == 0 and p.swing_state == "IDLE" and not p.blocking:
		p.stamina = FixedMath.min_i(p.stamina + 1, p.stamina_max)
