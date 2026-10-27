extends CanvasLayer
## Barra inferior estilo Daggerfall (CanvasLayer 2): retrato, Vida/Vigor verticais com rótulos numéricos,
## poções, chave, nível, ouro/XP, bússola e mensagens. Somente leitura: eventos vêm de get_events() e
## de diferenças entre leituras consecutivas. Prioridade das mensagens no mesmo tick:
## terminal > nível > chave/destranca > coleta > poção > morte de inimigo > golpe recebido > despertar > demais.

const BAR_H: int = 40
const BAR_BASE_Y: int = 356
const MSG_SECONDS: float = 2.0
const SECTORS: Array = ["L", "NE", "N", "NO", "O", "SO", "S", "SE"]
## Nomes de apresentação (não vêm do núcleo): [nome, despertar, abatido].
const NAME_BY_TYPE: Dictionary = {
	"rat": ["rato", "Um rato desperta!", "Rato abatido"],
	"skeleton": ["esqueleto", "Um esqueleto desperta!", "Esqueleto abatido"],
	"guardian": ["Guardião", "O Guardião desperta!", "Guardião abatido"],
}
const ITEM_PICKUP_TEXT: Dictionary = {
	"potion_hp": "Pegou Poção de Vida", "potion_sp": "Pegou Poção de Vigor",
	"key": "Pegou a Chave da Saída!", "gold": "+10 de ouro",
}
const TERMINAL_TEXT: Dictionary = {"ESCAPED": "Você escapou!", "DEAD": "Você morreu", "TIMEOUT": "O tempo acabou"}
const KEY_ON := Color("#ffd84a")
const KEY_OFF := Color("#e0d0a0")
const PRIO_TERMINAL: int = 8
const PRIO_LEVEL: int = 7
const PRIO_KEY: int = 6
const PRIO_PICKUP: int = 5
const PRIO_POTION: int = 4
const PRIO_DEATH: int = 3
const PRIO_HIT: int = 2
const PRIO_WAKE: int = 1
const PRIO_OTHER: int = 0

@onready var hp_fill: ColorRect = $Frame/HpBack/Fill
@onready var sp_fill: ColorRect = $Frame/SpBack/Fill
@onready var compass: Label = $Frame/Compass
@onready var message: Label = $Frame/Message
@onready var portrait: TextureRect = $Frame/Portrait
@onready var hp_text: Label = $Frame/HpText
@onready var sp_text: Label = $Frame/SpText
@onready var pot_text: Label = $Frame/PotText
@onready var key_text: Label = $Frame/KeyText
@onready var lvl_text: Label = $Frame/LvlText
@onready var stat_text: Label = $Frame/StatText

var _last: Dictionary = {}
var _last_enemy: Dictionary = {}  # id -> último dicionário de get_enemies()
var _msg_t: float = 0.0
var _last_terminal: String = "NONE"


func _ready() -> void:
	portrait.texture = AssetResolver.texture("ui.portrait")
	message.text = ""


static func bar_height(value: int, maximum: int) -> int:
	if maximum <= 0:
		return 0
	return clampi(floori(BAR_H * value / float(maximum)), 0, BAR_H)


static func compass_text(angle: int) -> String:
	var sector: int = ((angle + 256) & 4095) >> 9
	return "%s %d°" % [SECTORS[sector], roundi(angle * 360.0 / 4096.0) % 360]


static func _set_bar(fill: ColorRect, h: int) -> void:
	fill.position = Vector2(0, BAR_H - h)
	fill.size = Vector2(8, h)


static func stat_line(inv: Dictionary) -> String:
	if inv["level"] >= ItemsSim.LEVEL_MAX:
		return "Ouro %d · XP %d (máx)" % [inv["gold"], inv["xp"]]
	return "Ouro %d · XP %d/%d" % [inv["gold"], inv["xp"], ItemsSim.LEVEL_XP[inv["level"] + 1]]


func show_message(text: String) -> void:
	message.text = text
	_msg_t = MSG_SECONDS


## `input` é o IntInput do tick (só leitura), usado para "Sem vigor".
func refresh(world: WorldSim, input: IntInput = null) -> void:
	var st: Dictionary = world.get_player_status()
	_set_bar(hp_fill, bar_height(st["hp"], st["hp_max"]))
	_set_bar(sp_fill, bar_height(st["stamina"], st["stamina_max"]))
	hp_text.text = "Vida %d/%d" % [st["hp"], st["hp_max"]]
	sp_text.text = "Vigor %d/%d" % [st["stamina"], st["stamina_max"]]
	compass.text = compass_text(world.get_angle())
	var inv: Dictionary = world.get_inventory()
	pot_text.text = "PV %d  PF %d" % [inv["potion_hp"], inv["potion_sp"]]
	key_text.text = "Chave: SIM" if inv["key"] else "Chave: não"
	key_text.add_theme_color_override("font_color", KEY_ON if inv["key"] else KEY_OFF)
	lvl_text.text = "Nível %d" % inv["level"]
	stat_text.text = stat_line(inv)
	var best: Array = [-1, ""]
	_offer_m6(best, world, input)
	for e: Dictionary in world.get_enemies():
		var prev: Dictionary = _last_enemy.get(e["id"], e)
		var names: Array = NAME_BY_TYPE.get(e["type"], [])
		if e["hp"] < prev["hp"]:
			if names.is_empty():
				_offer(best, PRIO_OTHER, "Acertou o boneco (−%d)" % (prev["hp"] - e["hp"]))
			elif e["state"] != "DEAD":
				_offer(best, PRIO_OTHER, "Acertou o %s (−%d)" % [names[0], prev["hp"] - e["hp"]])
		if not names.is_empty():
			if e["state"] == "DEAD" and prev["state"] != "DEAD":
				_offer(best, PRIO_DEATH, names[2])
			if e["awake"] and not prev["awake"]:
				_offer(best, PRIO_WAKE, names[1])
		_last_enemy[e["id"]] = e
	if not _last.is_empty():
		var lost: int = _last["hp"] - st["hp"]
		if _last["stun_ticks"] == 0 and st["stun_ticks"] > 0:
			_offer(best, PRIO_HIT, "Guarda quebrada!")
		elif lost > 0 and st["blocking"]:
			_offer(best, PRIO_HIT, "Bloqueado (−%d)" % lost)
		elif lost > 0:
			_offer(best, PRIO_HIT, "Atingido (−%d)" % lost)
		if input != null and input.attack and _last["swing_state"] == "IDLE" \
				and st["swing_state"] == "IDLE" and _last["stamina"] < Combat.SWING_COST:
			_offer(best, PRIO_OTHER, "Sem vigor")
	if best[0] >= 0:
		show_message(best[1])
	_last = st


## Mensagens de M6 a partir de get_events(), da borda de get_terminal() e do `use` sobre o EXIT sem chave.
func _offer_m6(best: Array, world: WorldSim, input: IntInput) -> void:
	var t: String = world.get_terminal()
	if t != _last_terminal and t != "NONE":
		_offer(best, PRIO_TERMINAL, TERMINAL_TEXT[t])
	_last_terminal = t
	var items: Array = world.get_items()
	for ev: String in world.get_events():
		var parts: PackedStringArray = ev.split(":")
		match parts[0]:
			"level":
				_offer(best, PRIO_LEVEL, "Nível %s! Vida restaurada" % parts[1])
			"unlock":
				_offer(best, PRIO_KEY, "A porta da saída se abre")
			"locked_no_key":
				_offer(best, PRIO_KEY, "Trancada. Encontre a chave")
			"pickup":
				var it: Dictionary = items[parts[1].to_int()]
				_offer(best, PRIO_KEY if it["type"] == "key" else PRIO_PICKUP, ITEM_PICKUP_TEXT[it["type"]])
			"quaff":
				_offer(best, PRIO_POTION, "Bebeu Poção de %s (+%s)" % ["Vida" if parts[1] == "1" else "Vigor", parts[2]])
			"quaff_empty":
				_offer(best, PRIO_POTION, "Sem poções")
	if input != null and input.use and t == "NONE" and not world.get_inventory()["key"]:
		var ec: Dictionary = world.get_exit_cell()
		var pp: Array = world.get_player_pos()
		if floori(pp[0] / 2048.0) == ec["cx"] and floori(pp[1] / 2048.0) == ec["cz"]:
			_offer(best, PRIO_KEY, "Você precisa da Chave da Saída")


## Guarda em `best` a mensagem de maior prioridade do tick (a primeira vence em empate).
static func _offer(best: Array, prio: int, text: String) -> void:
	if prio > best[0]:
		best[0] = prio
		best[1] = text


func _process(delta: float) -> void:
	if _msg_t > 0.0:
		_msg_t -= delta
		if _msg_t <= 0.0:
			message.text = ""
