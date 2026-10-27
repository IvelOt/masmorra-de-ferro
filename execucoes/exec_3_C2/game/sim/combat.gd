class_name Combat
extends RefCounted
## M3: máquina do golpe, hitbox da espada, bloqueio, dano recebido e regeneração
## (GDD §3.4, plano R3 §3.3–§3.6). Tudo inteiro.

const FixedMath = preload("res://sim/fixed_math.gd")
const TrigTable = preload("res://sim/trig_table.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
const ItemsSim = preload("res://sim/items_sim.gd")

const HP_MAX: int = 100
const STAMINA_MAX: int = 100
const SWING_WINDUP: int = 6
const SWING_ACTIVE: int = 6
const SWING_RECOVERY: int = 12
const SWING_TOTAL: int = SWING_WINDUP + SWING_ACTIVE + SWING_RECOVERY
const SWING_COST: int = 12
const SWORD_DAMAGE: int = 25
const SWORD_REACH: int = 1638
const TAN40_NUM: int = 859
const TAN40_DEN: int = 1024
const TAN60_NUM: int = 1774
const TAN60_DEN: int = 1024
const STUN_TICKS: int = 20
const REGEN_PERIOD: int = 3
const SWORD_BAND_LO: int = 205
const SWORD_BAND_HI: int = 1843


## M6: dano da espada por nível (25 / 30 / 35).
static func sword_damage(p: Variant) -> int:
	return SWORD_DAMAGE + ItemsSim.LEVEL_DMG_BONUS * (p.level - 1)


## Estado do golpe derivado do contador (0 = parado).
static func swing_state_of(ticks: int) -> String:
	if ticks <= 0:
		return "IDLE"
	if ticks <= SWING_WINDUP:
		return "WINDUP"
	if ticks <= SWING_WINDUP + SWING_ACTIVE:
		return "ACTIVE"
	return "RECOVERY"


## Passo 5: combate do jogador. `world` fornece player e enemies (ordem crescente de id).
static func player_step(world: Variant, inp: Variant) -> void:
	var p: Variant = world.player
	if p.stun_ticks > 0:
		# (a) atordoado no início do tick: não ataca nem bloqueia neste tick
		p.stun_ticks -= 1
		p.blocking = false
		return
	# (b)
	if p.swing_state != "IDLE":
		p.swing_ticks += 1
		if p.swing_ticks > SWING_TOTAL:
			p.swing_state = "IDLE"
			p.swing_ticks = 0
	# (c)
	if p.swing_state == "IDLE" and inp.attack and not inp.block and p.stamina >= SWING_COST:
		p.stamina -= SWING_COST
		p.swing_ticks = 1
		p.swing_hits = []
	# (d)
	p.swing_state = swing_state_of(p.swing_ticks)
	# (e)
	p.blocking = inp.block and p.stun_ticks == 0 and p.swing_state != "WINDUP" and p.swing_state != "ACTIVE"
	# (f)
	if p.swing_state != "ACTIVE":
		return
	for e: Variant in world.enemies:
		if e.state == "DEAD" or p.swing_hits.has(e.id):
			continue
		if hit(p, e):
			e.hp -= sword_damage(p)
			p.swing_hits.append(e.id)
			p.swing_hits.sort()
			if e.hp <= 0:
				e.state = "DEAD"
				e.state_ticks = 0
				world.pending_xp += e.stat("xp")


## Hitbox da espada: setor de ±40° até SWORD_REACH + meia largura do alvo, ou
## sobreposição de caixas; mais a faixa vertical (plano R3 §3.4).
static func hit(p: Variant, e: Variant) -> bool:
	var dx: int = e.pos_x - p.pos_x
	var dz: int = e.pos_z - p.pos_z
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	var along: int = (dx * fx + dz * fz) >> 16
	var side: int = FixedMath.abs_i(dx * fz - dz * fx) >> 16
	var reach_ok: bool = along > 0 and along <= SWORD_REACH + e.half()
	var sector: bool = reach_ok and side * TAN40_DEN <= along * TAN40_NUM
	var reach_box: int = PlayerSim.PLAYER_HALF + e.half()
	var overlap: bool = FixedMath.abs_i(dx) < reach_box and FixedMath.abs_i(dz) < reach_box
	var vertical: bool = SWORD_BAND_LO < e.height() and 0 < SWORD_BAND_HI
	return (sector or overlap) and vertical


## Passo 7: aplica world.pending_hits em ordem e esvazia a lista.
static func resolve_hits(world: Variant) -> void:
	var p: Variant = world.player
	var fx: int = TrigTable.cos_q16(p.angle)
	var fz: int = TrigTable.sin_q16(p.angle)
	for h: Dictionary in world.pending_hits:
		var damage: int = h["damage"]
		var ex: int = int(h["src_x"]) - p.pos_x
		var ez: int = int(h["src_z"]) - p.pos_z
		var a: int = (ex * fx + ez * fz) >> 16
		var s: int = FixedMath.abs_i(ex * fz - ez * fx) >> 16
		var frontal: bool = (ex == 0 and ez == 0) or (a > 0 and s * TAN60_DEN <= a * TAN60_NUM)
		var taken: int = damage
		if p.blocking and frontal:
			var cost: int = FixedMath.div_trunc(damage, 2) + 5
			if p.stamina >= cost:
				p.stamina -= cost
				taken = damage - FixedMath.div_trunc(damage * 3, 4)
			else:
				# quebra de guarda
				p.stamina = 0
				p.stun_ticks = STUN_TICKS
				p.blocking = false
				p.swing_state = "IDLE"
				p.swing_ticks = 0
		p.hp = maxi(p.hp - taken, 0)
	world.pending_hits = []


## Passo 8: +1 de vigor a cada REGEN_PERIOD ticks, parado e sem bloquear.
static func regen(world: Variant) -> void:
	var p: Variant = world.player
	if world.tick % REGEN_PERIOD == 0 and p.swing_state == "IDLE" and not p.blocking:
		p.stamina = mini(p.stamina + 1, p.stamina_max)
