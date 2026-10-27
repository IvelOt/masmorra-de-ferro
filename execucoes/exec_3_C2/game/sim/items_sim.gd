class_name ItemsSim
extends RefCounted
## M6: tabela de itens, coleta automática, poções, XP e níveis (GDD §4.6, plano R4 §4).
## Item canônico: {"id", "type", "cell_x", "cell_z", "amount", "taken"}.

const POTION_HP_HEAL: int = 40
const POTION_SP_GAIN: int = 50
const GOLD_MIN: int = 10
const GOLD_SPAN: int = 21
## XP acumulado para os níveis 1, 2 e 3.
const LEVEL_XP: Array = [0, 100, 250]
const LEVEL_MAX: int = 3
const LEVEL_HP_BONUS: int = 20
const LEVEL_SP_BONUS: int = 10
const LEVEL_DMG_BONUS: int = 5
const TYPES: Array = ["potion_hp", "potion_sp", "key", "gold"]


static func make(id: int, type: String, cx: int, cz: int, amount: int = 1) -> Dictionary:
	return {"id": id, "type": type, "cell_x": cx, "cell_z": cz, "amount": amount, "taken": false}


## Passo 3 (1): coleta, em ordem de id, todo item não coletado na célula do jogador.
static func collect(items: Array, p: Variant) -> void:
	var pcx: int = p.cell_x()
	var pcz: int = p.cell_z()
	for it: Dictionary in items:
		if it["taken"] or it["cell_x"] != pcx or it["cell_z"] != pcz:
			continue
		it["taken"] = true
		match it["type"]:
			"potion_hp":
				p.potion_hp += 1
			"potion_sp":
				p.potion_sp += 1
			"key":
				p.has_key = true
			"gold":
				p.gold += int(it["amount"])


## Passo 4: quaff 1 = Poção de Vida, 2 = Poção de Vigor. Inventário vazio: sem efeito.
static func quaff(p: Variant, q: int) -> void:
	if q == 1 and p.potion_hp > 0:
		p.potion_hp -= 1
		p.hp = mini(p.hp + POTION_HP_HEAL, p.hp_max)
	elif q == 2 and p.potion_sp > 0:
		p.potion_sp -= 1
		p.stamina = mini(p.stamina + POTION_SP_GAIN, p.stamina_max)


## Passo 8 (depois da regeneração): soma o XP pendente e aplica as subidas de nível.
static func apply_xp(p: Variant, pending: int) -> void:
	p.xp += pending
	while p.level < LEVEL_MAX and p.xp >= int(LEVEL_XP[p.level]):
		p.level += 1
		p.hp_max += LEVEL_HP_BONUS
		p.stamina_max += LEVEL_SP_BONUS
		p.hp = p.hp_max
