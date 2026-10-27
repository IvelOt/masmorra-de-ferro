class_name HudDaggerfall
extends CanvasLayer
## HUD estilo Daggerfall (GDD §7.5, plano da iteração 5 §4.1): barra inferior
## 640×48 em y = 312..360 com retrato, barras verticais de Vida e Vigor, atributos,
## inventário, mensagens/objetivo e bússola. Moldura procedural; só lê o estado.

const BAR_Y: int = 312
const BAR_H: int = 48
const FILL_W: int = 12
const FILL_H: int = 38
const FRAME_W: int = 2
const COL_BG: Color = Color("#2b2622")
const COL_BORDER: Color = Color("#6b5a45")
const COL_INNER: Color = Color("#14110f")
const COL_HP: Color = Color("#b02020")
const COL_SP: Color = Color("#20a040")
const COL_STATS: Color = Color("#e0d0b0")
const COL_MSG: Color = Color("#f0e0a0")
const COL_GOAL: Color = Color("#a09070")
const COL_FRAME: Color = Color("#a08a60")
const COL_TICK: Color = Color("#857a66")
const COL_NORTH: Color = Color("#f2cc66")
const MSG_SECONDS: float = 2.0
const GOAL_KEY: String = "Objetivo: ache a Chave"
const GOAL_EXIT: String = "Objetivo: Portal de Fuga"
const COMPASS_RECT: Rect2 = Rect2(524, 316, 110, 40)
## 110 px cobrem 120° (janela de ±60°).
const COMPASS_PX_PER_DEG: float = 110.0 / 120.0
const COMPASS_FONT: int = 14
const COMPASS_LETTER_W: float = 14.0
## Uma letra só aparece com o centro em [10, 100] dentro da caixa.
const COMPASS_MIN_X: float = 10.0
const COMPASS_MAX_X: float = 100.0
const COMPASS_TICK_DEG: int = 15
const INV_IDS: Array = ["item.potion_hp", "item.potion_sp", "item.key", "item.gold"]
## Prioridade das mensagens no mesmo tick (maior vence): nível > chave > porta >
## poção > ouro > XP > combate.
const PRIO_LEVEL: int = 7
const PRIO_KEY: int = 6
const PRIO_DOOR: int = 5
const PRIO_POTION: int = 4
const PRIO_GOLD: int = 3
const PRIO_XP: int = 2
const PRIO_COMBAT: int = 1

var _hp_fill: ColorRect = null
var _sp_fill: ColorRect = null
var _stats: Array = []
var _inv_counts: Array = []
var _key_icon: TextureRect = null
var _msg: Label = null
var _msg_left: float = 0.0
var _goal: String = GOAL_KEY
var _compass_strip: Control = null
## Rumo em graus -> Label (cardinais N/L/S/O).
var _compass_labels: Dictionary = {}
## Rumo em graus -> ColorRect 1×6 (traços a cada 15° entre as cardinais).
var _compass_ticks: Dictionary = {}
var _vignette: ColorRect = null
var _flash: ColorRect = null
var _flash_left: float = 0.0
var _stunned: bool = false
var _font: Font = null


## Eventos por diferença de estados (compartilhados com o áudio).
static func events(prev: Dictionary, curr: Dictionary, inp: IntInput) -> Dictionary:
	var pp: Dictionary = prev["player"]
	var cp: Dictionary = curr["player"]
	var ev: Dictionary = {
		"swing_start": int(cp["swing_state"]) == Combat.WINDUP and int(cp["swing_ticks"]) == 1,
		"hit": (cp["swing_hits"] as Array).size() > (pp["swing_hits"] as Array).size(),
		"guard_break": int(cp["stun_ticks"]) == Combat.STUN_TICKS and int(pp["stun_ticks"]) < Combat.STUN_TICKS,
		"hurt": int(cp["hp"]) < int(pp["hp"]),
		"blocked": false,
		"no_stamina": false,
		"woke": [],
		"died": [],
		"picked": [],
		"quaffed": 0,
		"quaff_gain": 0,
		"unlocked": false,
		"level_up": 0,
		"xp_gain": int(cp["xp"]) - int(pp["xp"]),
		"terminal": "",
	}
	# Vigor só cai sob bloqueio pelo custo do bloqueio (o golpe não começa bloqueando).
	ev["blocked"] = bool(cp["blocking"]) and int(cp["stamina"]) < int(pp["stamina"]) and not ev["guard_break"]
	ev["no_stamina"] = inp != null and inp.attack and not ev["swing_start"] \
		and int(pp["swing_state"]) == Combat.IDLE and int(pp["stamina"]) < Combat.SWING_COST
	var old: Dictionary = {}
	for e: Dictionary in prev["enemies"]:
		old[int(e["id"])] = e
	for e: Dictionary in curr["enemies"]:
		var o: Dictionary = old.get(int(e["id"]), e)
		var nm: String = String(EnemySim.NAMES[int(e["type"])])
		if bool(e["awake"]) and not bool(o["awake"]):
			(ev["woke"] as Array).append(nm)
		if int(e["state"]) == EnemySim.DEAD and int(o["state"]) != EnemySim.DEAD:
			(ev["died"] as Array).append(nm)
	var old_items: Dictionary = {}
	for it: Dictionary in prev.get("items", []):
		old_items[int(it["id"])] = it
	for it: Dictionary in curr.get("items", []):
		var oi: Dictionary = old_items.get(int(it["id"]), it)
		if bool(it["taken"]) and not bool(oi["taken"]):
			(ev["picked"] as Array).append(int(it["type"]))
	var pi: Dictionary = pp["inventory"]
	var ci: Dictionary = cp["inventory"]
	if int(ci["potion_hp"]) < int(pi["potion_hp"]):
		ev["quaffed"] = 1
		ev["quaff_gain"] = int(cp["hp"]) - int(pp["hp"])
	elif int(ci["potion_sp"]) < int(pi["potion_sp"]):
		ev["quaffed"] = 2
		ev["quaff_gain"] = int(cp["stamina"]) - int(pp["stamina"])
	var old_doors: Dictionary = {}
	for d: Dictionary in prev["dungeon"]["doors"]:
		old_doors[int(d["id"])] = int(d["state"])
	for d: Dictionary in curr["dungeon"]["doors"]:
		if int(d["state"]) == Grid.DOOR_OPEN and int(old_doors.get(int(d["id"]), -1)) == Grid.DOOR_LOCKED:
			ev["unlocked"] = true
	if int(cp["level"]) > int(pp["level"]):
		ev["level_up"] = int(cp["level"])
	if String(curr["terminal"]) != "" and String(prev["terminal"]) == "":
		ev["terminal"] = String(curr["terminal"])
	return ev


## Mensagem de maior prioridade dos eventos do tick ("" se nenhuma).
static func message_for(ev: Dictionary) -> String:
	var best: int = 0
	var text: String = ""
	var cands: Array = []
	if int(ev.get("level_up", 0)) > 0:
		cands.append([PRIO_LEVEL, "Subiu para o nível %d!" % int(ev["level_up"])])
	var picked: Array = ev.get("picked", [])
	if picked.has(ItemsSim.KEY):
		cands.append([PRIO_KEY, "Pegou a Chave da Saída!"])
	if bool(ev.get("unlocked", false)):
		cands.append([PRIO_DOOR, "Porta destrancada!"])
	if bool(ev.get("locked_no_key", false)):
		cands.append([PRIO_DOOR, "Porta trancada — precisa da chave"])
	if bool(ev.get("exit_no_key", false)):
		cands.append([PRIO_DOOR, "Portal: precisa da chave"])
	if int(ev.get("quaffed", 0)) == 1:
		cands.append([PRIO_POTION, "Bebeu Poção de Vida (+%d)" % int(ev["quaff_gain"])])
	elif int(ev.get("quaffed", 0)) == 2:
		cands.append([PRIO_POTION, "Bebeu Poção de Vigor (+%d)" % int(ev["quaff_gain"])])
	if picked.has(ItemsSim.POTION_HP):
		cands.append([PRIO_POTION, "Pegou Poção de Vida"])
	elif picked.has(ItemsSim.POTION_SP):
		cands.append([PRIO_POTION, "Pegou Poção de Vigor"])
	if picked.has(ItemsSim.GOLD):
		cands.append([PRIO_GOLD, "+%d de ouro" % ItemsSim.GOLD_VALUE])
	if int(ev.get("xp_gain", 0)) > 0:
		cands.append([PRIO_XP, "+%d XP" % int(ev["xp_gain"])])
	if bool(ev.get("guard_break", false)):
		cands.append([PRIO_COMBAT, "Guarda quebrada!"])
	elif bool(ev.get("blocked", false)):
		cands.append([PRIO_COMBAT, "Bloqueado!"])
	elif bool(ev.get("hit", false)):
		cands.append([PRIO_COMBAT, "Golpe acertou!"])
	elif bool(ev.get("no_stamina", false)):
		cands.append([PRIO_COMBAT, "Sem vigor"])
	for nm: String in ev.get("died", []):
		cands.append([PRIO_COMBAT, "%s morreu" % nm])
	for nm: String in ev.get("woke", []):
		cands.append([PRIO_COMBAT, "%s te viu" % nm])
	for c: Array in cands:
		if int(c[0]) > best:
			best = int(c[0])
			text = String(c[1])
	return text


## Fonte do tema sem antialias (pixel), compartilhada com automapa e tela final.
static func pixel_font() -> Font:
	var base: Font = ThemeDB.fallback_font
	if base is FontFile:
		var ff: FontFile = (base as FontFile).duplicate() as FontFile
		ff.antialiasing = TextServer.FONT_ANTIALIASING_NONE
		ff.hinting = TextServer.HINTING_NONE
		return ff
	var sf: SystemFont = SystemFont.new()
	sf.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	return sf


func _ready() -> void:
	layer = 2
	_font = pixel_font()
	_vignette = _rect(self, "StunVignette", Rect2(0, 0, 640, 360), Color(0.8, 0.0, 0.0, 0.15))
	_vignette.visible = false
	_flash = _rect(self, "HurtFlash", Rect2(0, 0, 640, 360), Color(1.0, 0.0, 0.0, 0.3))
	_flash.visible = false
	var panel: Panel = _framed(self, "Bar", Rect2(0, BAR_Y, 640, BAR_H), COL_BG, COL_BORDER, 2)
	var inner: Panel = _framed(panel, "Inner", Rect2(2, 2, 636, BAR_H - 4), Color(0, 0, 0, 0), COL_INNER, 1)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_portrait()
	_hp_fill = _bar("Vida", Rect2(52, 315, 16, 42), COL_HP, "V")
	_sp_fill = _bar("Vigor", Rect2(72, 315, 16, 42), COL_SP, "G")
	_build_stats()
	_build_inventory()
	_msg = _label(self, "Message", Rect2(332, 316, 186, 40), 10, COL_GOAL)
	_msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_msg.max_lines_visible = 2
	_build_compass()


func _rect(parent: Node, n: String, r: Rect2, c: Color) -> ColorRect:
	var cr: ColorRect = ColorRect.new()
	cr.name = n
	cr.position = r.position
	cr.size = r.size
	cr.color = c
	cr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(cr)
	return cr


func _framed(parent: Node, n: String, r: Rect2, bg: Color, border: Color, width: int) -> Panel:
	var p: Panel = Panel.new()
	p.name = n
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = bg
	sb.draw_center = bg.a > 0.0
	sb.border_color = border
	sb.set_border_width_all(width)
	p.add_theme_stylebox_override("panel", sb)
	parent.add_child(p)
	return p


func _label(parent: Node, n: String, r: Rect2, font_size: int, c: Color) -> Label:
	var l: Label = Label.new()
	l.name = n
	l.position = r.position
	l.size = r.size
	l.clip_text = true
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_constant_override("line_spacing", -2)
	parent.add_child(l)
	return l


func _build_portrait() -> void:
	var frame: Panel = _framed(self, "Portrait", Rect2(6, 316, 40, 40), Color(0, 0, 0), COL_FRAME, 2)
	var tr: TextureRect = TextureRect.new()
	tr.name = "Face"
	tr.texture = AssetResolver.resolve("ui.portrait")
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.position = Vector2(4, 4)
	tr.size = Vector2(32, 32)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	frame.add_child(tr)


## Barra vertical com moldura de 2 px, fundo preto e rótulo no topo, por cima do
## preenchimento; devolve o preenchimento 12×38.
func _bar(n: String, r: Rect2, c: Color, tag: String) -> ColorRect:
	var frame: Panel = _framed(self, n, r, Color(0, 0, 0), COL_FRAME, FRAME_W)
	var fill: ColorRect = _rect(frame, "Fill", Rect2(FRAME_W, FRAME_W, FILL_W, FILL_H), c)
	var l: Label = _label(frame, "Label", Rect2(FRAME_W, FRAME_W, FILL_W, 10), 8, COL_MSG)
	l.text = tag
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	return fill


func _build_stats() -> void:
	var box: Control = Control.new()
	box.name = "Stats"
	box.position = Vector2(94, 315)
	box.size = Vector2(108, 42)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	for i: int in range(3):
		_stats.append(_label(box, "Line%d" % i, Rect2(0, i * 14, 108, 14), 10, COL_STATS))


func _build_inventory() -> void:
	var box: Control = Control.new()
	box.name = "Inventory"
	box.position = Vector2(206, 316)
	box.size = Vector2(120, 40)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	for i: int in range(4):
		var cell: Control = Control.new()
		cell.name = "Cell%d" % i
		cell.position = Vector2((i & 1) * 60, (i >> 1) * 20)
		cell.size = Vector2(56, 18)
		cell.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(cell)
		var icon: TextureRect = TextureRect.new()
		icon.name = "Icon"
		icon.texture = AssetResolver.resolve(String(INV_IDS[i]))
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.position = Vector2(0, 1)
		icon.size = Vector2(16, 16)
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cell.add_child(icon)
		_inv_counts.append(_label(cell, "Count", Rect2(18, 1, 38, 16), 10, COL_STATS))
		if i == ItemsSim.KEY:
			_key_icon = icon


func _build_compass() -> void:
	var box: Panel = _framed(self, "Compass", COMPASS_RECT, COL_INNER, COL_BORDER, 1)
	box.clip_contents = true
	_compass_strip = Control.new()
	_compass_strip.name = "Strip"
	_compass_strip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_compass_strip)
	for deg: int in range(0, 360, COMPASS_TICK_DEG):
		if deg % 90 == 0:
			continue
		var t: ColorRect = _rect(_compass_strip, "T%d" % deg, Rect2(0, 20, 1, 6), COL_TICK)
		_compass_ticks[deg] = t
	for pair: Array in [[0, "N"], [90, "L"], [180, "S"], [270, "O"]]:
		var col: Color = COL_NORTH if pair[0] == 0 else Color(0.85, 0.8, 0.7)
		var l: Label = _label(_compass_strip, "H%d" % int(pair[0]), Rect2(0, 13, COMPASS_LETTER_W, 20), COMPASS_FONT, col)
		l.text = String(pair[1])
		l.clip_text = false
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_compass_labels[int(pair[0])] = l
	# Marcador central vermelho de 1×8 px no topo.
	_rect(box, "Mark", Rect2(floorf(COMPASS_RECT.size.x / 2.0), 1, 1, 8), Color(0.9, 0.2, 0.15))


## Rumo em graus (0 = norte = +z da simulação, sentido horário) para `angle` BAM.
static func heading_deg(angle: int) -> float:
	return fposmod(90.0 - float(angle) * 360.0 / 4096.0, 360.0)


## Posição X (local ao quadro) do centro do rótulo do rumo `deg` para `angle`.
static func compass_x(deg: int, angle: int) -> float:
	var rel: float = fposmod(float(deg) - heading_deg(angle) + 180.0, 360.0) - 180.0
	return COMPASS_RECT.size.x / 2.0 + rel * COMPASS_PX_PER_DEG


func _update_compass(angle: int) -> void:
	for deg: int in _compass_labels.keys():
		var l: Label = _compass_labels[deg]
		var x: float = roundf(compass_x(deg, angle))
		l.position = Vector2(x - l.size.x / 2.0, 13)
		l.visible = x >= COMPASS_MIN_X and x <= COMPASS_MAX_X
	for deg: int in _compass_ticks.keys():
		var t: ColorRect = _compass_ticks[deg]
		var tx: float = roundf(compass_x(deg, angle))
		t.position = Vector2(tx, 20)
		t.visible = tx >= 1.0 and tx <= COMPASS_RECT.size.x - 2.0


func compass_label(deg: int) -> Label:
	return _compass_labels.get(deg, null)


## Atualização por tick: barras, atributos, inventário, bússola e mensagens.
func on_tick(curr: Dictionary, ev: Dictionary) -> void:
	var p: Dictionary = curr["player"]
	_set_fill(_hp_fill, int(p["hp"]), int(p["hp_max"]))
	_set_fill(_sp_fill, int(p["stamina"]), int(p["stamina_max"]))
	(_stats[0] as Label).text = "VIDA %d/%d" % [int(p["hp"]), int(p["hp_max"])]
	(_stats[1] as Label).text = "VIGOR %d/%d" % [int(p["stamina"]), int(p["stamina_max"])]
	(_stats[2] as Label).text = "NV %d  XP %d" % [int(p["level"]), int(p["xp"])]
	var inv: Dictionary = p["inventory"]
	var has_key: bool = bool(inv["key"])
	(_inv_counts[0] as Label).text = "×%d" % int(inv["potion_hp"])
	(_inv_counts[1] as Label).text = "×%d" % int(inv["potion_sp"])
	(_inv_counts[2] as Label).text = "×%d" % (1 if has_key else 0)
	(_inv_counts[3] as Label).text = "×%d" % int(p["gold"])
	_key_icon.modulate.a = 1.0 if has_key else 0.3
	_update_compass(int(p["angle"]))
	_stunned = int(p["stun_ticks"]) > 0
	_goal = GOAL_EXIT if has_key else GOAL_KEY
	if _msg_left <= 0.0:
		_show_goal()
	if ev.is_empty():
		return
	var text: String = message_for(ev)
	if text != "":
		_say(text)
	if ev["hurt"]:
		_flash_left = 0.1


func message() -> String:
	return _msg.text


func _say(t: String) -> void:
	_msg.text = t
	_msg.add_theme_color_override("font_color", COL_MSG)
	_msg_left = MSG_SECONDS


## Sem mensagem ativa, o painel mostra o objetivo corrente.
func _show_goal() -> void:
	_msg.text = _goal
	_msg.add_theme_color_override("font_color", COL_GOAL)


func _set_fill(fill: ColorRect, v: int, vmax: int) -> void:
	var h: int = roundi(float(FILL_H) * float(clampi(v, 0, vmax)) / float(maxi(vmax, 1)))
	fill.size = Vector2(FILL_W, h)
	fill.position = Vector2(FRAME_W, FRAME_W + FILL_H - h)


func _process(dt: float) -> void:
	if _msg_left > 0.0:
		_msg_left -= dt
		if _msg_left <= 0.0:
			_show_goal()
	_flash.visible = _flash_left > 0.0
	if _flash_left > 0.0:
		_flash_left -= dt
	_vignette.visible = _stunned and (Engine.get_frames_drawn() / 8) % 2 == 0
