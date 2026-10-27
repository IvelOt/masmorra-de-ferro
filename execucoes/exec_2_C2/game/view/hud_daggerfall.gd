extends Control
## HUD inferior estilo Daggerfall (plano da rodada 3 §8.3): barra de pedra 640 × 48 em y = 312
## desenhada em código, retrato, barras verticais de Vida e Vigor (12 × 40) com valores numéricos,
## nível/XP, bússola rolante com a rosa dos ventos internacional, inventário e linha de mensagens.
## Só lê o snapshot; os rótulos da bússola ficam todos aqui (núcleo: +X = Leste, +Z = Norte).

const AssetResolver = preload("res://view/asset_resolver.gd")

const BAR_Y: int = 312
const BAR_H: int = 48
const STONE: Color = Color("#3a3632")
const BEVEL_LIGHT: Color = Color("#5a554e")
const BEVEL_DARK: Color = Color("#1e1c1a")
const HP_COLOR: Color = Color("#c02020")
const SP_COLOR: Color = Color("#20a040")
const SP_STUN_COLOR: Color = Color("#d0c020")
const BAR_INNER_W: int = 10
const BAR_INNER_H: int = 38
const COMPASS_CENTER: Vector2 = Vector2(320, 336)
const COMPASS_SIZE: Vector2 = Vector2(96, 20)
## Rosa dos ventos internacional em ordem crescente de ângulo (BAM): 0 = E, 1024 = N, 2048 = W, 3072 = S.
const HEADINGS: Array = [["E", 0], ["NE", 512], ["N", 1024], ["NW", 1536], ["W", 2048], ["SW", 2560], ["S", 3072], ["SE", 3584]]
## Pixels por BAM na faixa da bússola (512 BAM = 30 px).
const COMPASS_PX_PER_BAM: float = 30.0 / 512.0
const MSG_SECONDS: float = 2.0
const FONT_SIZE: int = 10
const LEVEL_XP: Array = [0, 100, 250]
const KILL_MSG: Dictionary = {
	"rat": "Rato abatido (+10 XP)",
	"skeleton": "Esqueleto abatido (+25 XP)",
	"guardian": "Guardião abatido (+100 XP)",
	"dummy": "Boneco destruído",
}
const ITEM_MSG: Dictionary = {"potion_hp": "Poção de Vida", "potion_sp": "Poção de Vigor", "key": "Chave da Saída!"}
const CELL_U: float = 2048.0
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4

@onready var _portrait: TextureRect = $Portrait
@onready var _hp_fill: ColorRect = $HpBar/Fill
@onready var _sp_fill: ColorRect = $StaminaBar/Fill
@onready var _hp_label: Label = $HpLabel
@onready var _sp_label: Label = $StaminaLabel
@onready var _lvl_label: Label = $LevelLabel
@onready var _msg: Label = $Message
@onready var _inv_icons: Array = [$InvPotionHp, $InvPotionSp, $InvKey, $InvGold]
@onready var _inv_counts: Array = [$InvPotionHp/Count, $InvPotionSp/Count, $InvKey/Count, $InvGold/Count]

var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _msg_left: float = 0.0
## Mensagem fixa (modo de atração): ocupa a linha enquanto não for vazia.
var _fixed_msg: String = ""


func _ready() -> void:
	var res: AssetResolver = AssetResolver.new()
	_portrait.texture = res.texture("ui.portrait")
	var ids: Array = ["item.potion_hp", "item.potion_sp", "item.key", "item.gold"]
	for i in range(_inv_icons.size()):
		(_inv_icons[i] as TextureRect).texture = res.texture(ids[i])
	_msg.text = ""


## Rótulo da rosa dos ventos mais próximo do ângulo (BAM, 0 = E, 1024 = N).
static func heading_label(angle: int) -> String:
	var idx: int = (((angle + 256) & 4095) >> 9) & 7
	return HEADINGS[idx][0]


func update(prev: Dictionary, cur: Dictionary) -> void:
	_prev = prev
	_cur = cur
	var p0: Dictionary = prev.player
	var p1: Dictionary = cur.player
	_set_fill(_hp_fill, int(p1.hp), int(p1.hp_max))
	_set_fill(_sp_fill, int(p1.stamina), int(p1.stamina_max))
	_hp_label.text = "Vida %d/%d" % [int(p1.hp), int(p1.hp_max)]
	_sp_label.text = "Vigor %d/%d" % [int(p1.stamina), int(p1.stamina_max)]
	var lvl: int = int(p1.get("level", 1))
	var xp: int = int(p1.get("xp", 0))
	if lvl >= LEVEL_XP.size():
		_lvl_label.text = "Nv %d  XP %d" % [lvl, xp]
	else:
		_lvl_label.text = "Nv %d  XP %d/%d" % [lvl, xp, int(LEVEL_XP[lvl])]
	var inv: Dictionary = p1.get("inventory", {})
	var counts: Array = [int(inv.get("potion_hp", 0)), int(inv.get("potion_sp", 0)), int(inv.get("key", 0)),
		int(p1.get("gold", 0))]
	for i in range(counts.size()):
		(_inv_counts[i] as Label).text = "×%d" % counts[i]
	(_inv_icons[2] as TextureRect).modulate.a = 1.0 if counts[2] > 0 else 0.25
	_detect_messages(prev, cur)
	queue_redraw()


## Mensagens (uma por vez, 2 s), detectadas comparando snapshots; a última detectada vence.
func _detect_messages(prev: Dictionary, cur: Dictionary) -> void:
	var p0: Dictionary = prev.player
	var p1: Dictionary = cur.player
	var li: Dictionary = cur.get("last_input", {})
	if int(p0.stun_ticks) == 0 and int(p1.stun_ticks) > 0:
		show_message("Guarda quebrada!")
	elif int(p1.hp) < int(p0.hp) and p1.blocking:
		show_message("Bloqueado")
	elif li.get("attack", false) and p0.swing_state == "IDLE" and p1.swing_state == "IDLE" \
			and int(p0.stamina) < 12 and not p1.blocking and int(p0.stun_ticks) == 0:
		show_message("Sem vigor!")
	var before: Dictionary = {}
	for e: Dictionary in prev.get("enemies", []):
		before[e.id] = e.state
	for e: Dictionary in cur.get("enemies", []):
		if e.state == "DEAD" and before.get(e.id, "DEAD") != "DEAD":
			show_message(KILL_MSG.get(e.type, "Inimigo abatido"))
	var taken_before: Dictionary = {}
	for it: Dictionary in prev.get("items", []):
		taken_before[it.id] = it.taken
	for it: Dictionary in cur.get("items", []):
		if it.taken and not taken_before.get(it.id, true):
			if it.type == "gold":
				show_message("+%d de ouro" % int(it.amount))
			else:
				show_message(ITEM_MSG.get(it.type, ""))
	var doors_before: Dictionary = {}
	for d: Dictionary in prev.get("doors", []):
		doors_before[d.id] = d.type
	var unlocked: bool = false
	for d: Dictionary in cur.get("doors", []):
		if d.type == DOOR_OPEN and doors_before.get(d.id, DOOR_OPEN) == DOOR_LOCKED:
			unlocked = true
	if unlocked:
		show_message("Porta destrancada")
	elif li.get("use", false) and int(p1.get("inventory", {}).get("key", 0)) == 0 \
			and facing_locked(p1, cur.get("doors", [])):
		show_message("Porta trancada: falta a chave")
	if int(p1.get("level", 1)) > int(p0.get("level", 1)):
		show_message("Nível %d!" % int(p1.level))


## DOOR_LOCKED a Chebyshev ≤ 1 célula e de frente (|ângulo relativo| ≤ 45°).
static func facing_locked(p: Dictionary, doors: Array) -> bool:
	var pcx: int = floori(float(p.pos_x) / CELL_U)
	var pcz: int = floori(float(p.pos_z) / CELL_U)
	var a: float = TAU * float(p.angle) / 4096.0
	var f: Vector2 = Vector2(cos(a), sin(a))
	for d: Dictionary in doors:
		if d.type != DOOR_LOCKED or absi(int(d.cx) - pcx) > 1 or absi(int(d.cz) - pcz) > 1:
			continue
		var dv: Vector2 = Vector2((d.cx + 0.5) * CELL_U - p.pos_x, (d.cz + 0.5) * CELL_U - p.pos_z)
		var along: float = dv.dot(f)
		if along > 0.0 and absf(dv.cross(f)) <= along:
			return true
	return false


## Preenche de baixo para cima com altura div(38·v, v_max).
func _set_fill(fill: ColorRect, v: int, v_max: int) -> void:
	var h: int = floori(BAR_INNER_H * float(v) / float(maxi(v_max, 1)))
	fill.size = Vector2(BAR_INNER_W, h)
	fill.position = Vector2(1, 1 + BAR_INNER_H - h)


func show_message(text: String) -> void:
	if text == "":
		return
	_msg.text = text
	_msg_left = MSG_SECONDS


## Mensagem fixa (modo de atração); "" volta às mensagens normais.
func set_fixed_message(text: String) -> void:
	_fixed_msg = text
	_msg.text = text
	_msg_left = 0.0


func _process(delta: float) -> void:
	if _msg_left > 0.0:
		_msg_left -= delta
		if _msg_left <= 0.0:
			_msg.text = _fixed_msg
	elif _fixed_msg != "":
		_msg.text = _fixed_msg
	if _cur.is_empty():
		return
	var stunned: bool = int(_cur.player.stun_ticks) > 0
	var blink_on: bool = int(Time.get_ticks_msec() / 125.0) % 2 == 0
	_sp_fill.color = SP_STUN_COLOR if stunned and blink_on else SP_COLOR
	queue_redraw()


func _draw() -> void:
	# barra de pedra com chanfro de 2 px
	draw_rect(Rect2(0, 0, 640, BAR_H), STONE)
	draw_rect(Rect2(0, 0, 640, 2), BEVEL_LIGHT)
	draw_rect(Rect2(0, 0, 2, BAR_H), BEVEL_LIGHT)
	draw_rect(Rect2(0, BAR_H - 2, 640, 2), BEVEL_DARK)
	draw_rect(Rect2(638, 0, 2, BAR_H), BEVEL_DARK)
	# moldura do retrato
	draw_rect(Rect2(7.5, 7.5, 33, 33), BEVEL_DARK, false, 1.0)
	_draw_compass()


func _draw_compass() -> void:
	var c: Vector2 = COMPASS_CENTER - Vector2(0, BAR_Y)
	var rect: Rect2 = Rect2(c - COMPASS_SIZE * 0.5, COMPASS_SIZE)
	draw_rect(rect, BEVEL_DARK)
	draw_rect(rect, BEVEL_LIGHT, false, 1.0)
	if _cur.is_empty():
		return
	var a0: int = _prev.player.angle
	var da: int = ((int(_cur.player.angle) - a0 + 2048) & 4095) - 2048
	var heading: float = a0 + da * Engine.get_physics_interpolation_fraction()
	var font: Font = ThemeDB.fallback_font
	for h: Array in HEADINGS:
		# rótulo à esquerda quando está a um giro à esquerda (ângulo maior) do rumo atual
		var d: float = fposmod(float(h[1]) - heading + 2048.0, 4096.0) - 2048.0
		var x: float = c.x - d * COMPASS_PX_PER_BAM
		if absf(x - c.x) > COMPASS_SIZE.x * 0.5 - 6.0:
			continue
		var label: String = h[0]
		var w: float = font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		var col: Color = Color("#f0e0b0") if label == heading_label(int(heading)) else Color("#a09070")
		draw_string(font, Vector2(roundf(x - w * 0.5), c.y + 4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE, col)
	# marca fixa no centro
	draw_line(Vector2(c.x, rect.position.y), Vector2(c.x, rect.position.y + 3), Color("#c02020"), 1.0)
	draw_line(Vector2(c.x, rect.end.y - 3), Vector2(c.x, rect.end.y), Color("#c02020"), 1.0)
