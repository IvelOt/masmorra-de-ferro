class_name Combat
extends RefCounted
## Combate do Guerreiro (M3): máquina do golpe, hitbox em setor, bloqueio,
## dano recebido e regeneração de vigor. Só inteiros.

const HP_MAX: int = 100
const STAMINA_MAX: int = 100

const SWING_WINDUP: int = 6
const SWING_ACTIVE: int = 6
const SWING_RECOVERY: int = 12
const SWING_TOTAL: int = SWING_WINDUP + SWING_ACTIVE + SWING_RECOVERY

const SWING_COST: int = 12
const SWING_DAMAGE: int = 25
const SWING_REACH: int = 1638
const ARC_TAN_NUM: int = 859       # tan 40 graus x 1024
const BLOCK_TAN_NUM: int = 1774    # tan 60 graus x 1024
const GUARD_BREAK_STUN: int = 20
const REGEN_PERIOD: int = 3

const S_IDLE: int = 0
const S_WINDUP: int = 1
const S_ACTIVE: int = 2
const S_RECOVERY: int = 3


static func phase(swing_ticks: int) -> int:
	if swing_ticks <= SWING_WINDUP:
		return S_WINDUP
	if swing_ticks <= SWING_WINDUP + SWING_ACTIVE:
		return S_ACTIVE
	return S_RECOVERY


## Início do passo 2 (§4.4).
static func compute_blocking(p: PlayerSim, inp: IntInput) -> bool:
	return inp.block and p.swing_state != S_WINDUP and p.swing_state != S_ACTIVE and p.stun_ticks == 0


## Dano da espada por nível (M6): 25 / 30 / 35.
static func swing_damage(level: int) -> int:
	return SWING_DAMAGE + ItemsSim.LEVEL_DMG * (level - 1)


## Passo 5 (§4.2), na ordem (a) avanço, (b) início, (c) hitbox, (d) atordoamento.
## Devolve a soma de XP dos inimigos mortos neste tick.
static func player_step(p: PlayerSim, inp: IntInput, enemies: Array[EnemySim]) -> int:
	var xp_gain: int = 0
	if p.swing_state != S_IDLE:
		p.swing_ticks += 1
		if p.swing_ticks > SWING_TOTAL:
			p.swing_state = S_IDLE
			p.swing_ticks = 0
		else:
			p.swing_state = phase(p.swing_ticks)
	if inp.attack and p.swing_state == S_IDLE and not p.blocking and p.stun_ticks == 0 \
			and p.stamina >= SWING_COST:
		p.stamina -= SWING_COST
		p.swing_state = S_WINDUP
		p.swing_ticks = 1
		p.swing_hits = []
	if p.swing_state == S_ACTIVE:
		for e in enemies:
			if not e.alive() or p.swing_hits.has(e.id):
				continue
			if in_hitbox(p, e):
				e.take_hit(swing_damage(p.level))
				p.swing_hits.append(e.id)
				if not e.alive():
					xp_gain += EnemySim.XP[e.type]
	if p.stun_ticks > 0:
		p.stun_ticks -= 1
	return xp_gain


## Setor cilíndrico de 40 graus e alcance 1638 + HALF, ou caixas sobrepostas.
## Faixa vertical: todos estão no chão, então o teste de altura é sempre verdadeiro.
static func in_hitbox(p: PlayerSim, e: EnemySim) -> bool:
	var dx: int = e.pos_x - p.pos_x
	var dz: int = e.pos_z - p.pos_z
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var along: int = (dx * fx + dz * fz) >> 16
	var side: int = FixedMath.abs_i((dx * fz - dz * fx) >> 16)
	var r: int = e.half()
	if along > 0 and along <= SWING_REACH + r and side * 1024 <= along * ARC_TAN_NUM:
		return true
	return EnemySim.boxes_overlap(p.pos_x, p.pos_z, PlayerSim.PLAYER_HALF, e.pos_x, e.pos_z, r)


## Passo 7 (§4.5): resolve a fila em ordem de inserção.
static func resolve_hits(p: PlayerSim, hits: Array[Dictionary]) -> void:
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	for h: Dictionary in hits:
		var dmg: int = h.dmg
		var dx: int = int(h.src_x) - p.pos_x
		var dz: int = int(h.src_z) - p.pos_z
		var along: int = (dx * fx + dz * fz) >> 16
		var side: int = FixedMath.abs_i((dx * fz - dz * fx) >> 16)
		var frontal: bool = along > 0 and side * 1024 <= along * BLOCK_TAN_NUM
		if p.blocking and frontal:
			var cost: int = FixedMath.div_trunc(dmg, 2) + 5
			if p.stamina >= cost:
				p.stamina -= cost
				p.hp -= dmg - FixedMath.div_trunc(dmg * 3, 4)
			else:
				p.stamina = 0
				p.hp -= dmg
				p.stun_ticks = GUARD_BREAK_STUN
				p.blocking = false
		else:
			p.hp -= dmg
		p.hp = maxi(p.hp, 0)


## Passo 8 (§4.6).
static func regen(p: PlayerSim, tick: int) -> void:
	if FixedMath.mod_floor(tick, REGEN_PERIOD) == 0 and p.swing_state == S_IDLE and not p.blocking:
		p.stamina = mini(p.stamina + 1, p.stamina_max)
