extends CanvasLayer
## M3: barra inferior estilo Daggerfall com retrato, Vida, Vigor, bússola e
## mensagem (plano R3 §3.8). Placeholder procedural: o perfil free não tem moldura.
## C7/M6 (plano R4 §4.10): rótulos de Vida/Vigor, nível, XP, ouro, inventário e
## mensagens de coleta/nível, deduzidas da diferença entre estados lidos.
## C8/M3 (plano R5 §2): bússola com 120° visíveis, 8 rumos e nenhum rótulo cortado.
## C16/M6 (plano R6 §6.1): nível/XP/ouro, inventário e mensagens no corpo 10.

const AssetLib = preload("res://view/asset_lib.gd")

const PANEL_RECT: Rect2 = Rect2(0, 312, 640, 48)
const BAR_H: int = 40
const HP_BG_POS: Vector2 = Vector2(48, 316)
const SP_BG_POS: Vector2 = Vector2(62, 316)
const BAR_W: int = 10
const COMPASS_RECT: Rect2 = Rect2(272, 322, 96, 22)
## 96 px cobrem 120° (1365 BAM): 45° viram 32 px.
const COMPASS_PX_PER_BAM: float = 96.0 / 1365.0
const COMPASS_LABELS: Dictionary = {
	0: "L", 512: "NE", 1024: "N", 1536: "NO", 2048: "O", 2560: "SO", 3072: "S", 3584: "SE",
}
const COMPASS_FONT_SIZE: int = 10
## Largura estimada por caractere no corpo 10 da fonte padrão, com folga.
const LABEL_CHAR_W: float = 7.0
const COMPASS_MARGIN: float = 2.0
const COMPASS_CENTER_BAM: int = 16
const TEXT_COLOR: Color = Color("#e0d0b0")
const HP_TEXT_RECT: Rect2 = Rect2(76, 318, 60, 12)
const SP_TEXT_RECT: Rect2 = Rect2(76, 334, 60, 12)
const LEVEL_TEXT_RECT: Rect2 = Rect2(140, 316, 128, 14)
const INV_TEXT_RECT: Rect2 = Rect2(140, 333, 128, 14)
const M6_FONT_SIZE: int = 10
const MESSAGE_TICKS: int = 120

var panel: Panel
var portrait: TextureRect
var hp_fill: ColorRect
var sp_fill: ColorRect
var compass: Control
var message: Label
var hp_text: Label
var sp_text: Label
var level_text: Label
var inv_text: Label
var _heading: int = 0
var _prev: Dictionary = {}
var _event_msg: String = ""
var _event_until: int = -1


func _ready() -> void:
	layer = 2
	panel = Panel.new()
	panel.name = "Panel"
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#3a3530")
	sb.border_color = Color("#1a1714")
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	var frame := ColorRect.new()
	frame.name = "PortraitFrame"
	frame.color = Color("#1a1714")
	frame.position = Vector2(7, 319)
	frame.size = Vector2(34, 34)
	add_child(frame)
	portrait = TextureRect.new()
	portrait.name = "Portrait"
	portrait.texture = AssetLib.load_texture("ui.portrait")
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.stretch_mode = TextureRect.STRETCH_SCALE
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.position = Vector2(8, 320)
	portrait.size = Vector2(32, 32)
	add_child(portrait)
	hp_fill = _make_bar("Hp", HP_BG_POS, Color("#200808"), Color("#b02020"))
	sp_fill = _make_bar("Stamina", SP_BG_POS, Color("#082008"), Color("#20a040"))
	compass = Control.new()
	compass.name = "Compass"
	compass.position = COMPASS_RECT.position
	compass.size = COMPASS_RECT.size
	compass.clip_contents = true
	compass.draw.connect(_draw_compass)
	add_child(compass)
	message = Label.new()
	message.name = "Message"
	message.position = Vector2(384, 318)
	message.size = Vector2(248, 36)
	message.add_theme_font_size_override("font_size", M6_FONT_SIZE)
	message.add_theme_color_override("font_color", Color("#e0d0b0"))
	message.autowrap_mode = TextServer.AUTOWRAP_WORD
	add_child(message)
	hp_text = _make_text("HpText", HP_TEXT_RECT)
	sp_text = _make_text("SpText", SP_TEXT_RECT)
	level_text = _make_text("LevelText", LEVEL_TEXT_RECT, M6_FONT_SIZE)
	inv_text = _make_text("InvText", INV_TEXT_RECT, M6_FONT_SIZE)


func _make_text(node_name: String, r: Rect2, font_size: int = 8) -> Label:
	var l := Label.new()
	l.name = node_name
	l.clip_text = true
	l.add_theme_font_override("font", ThemeDB.fallback_font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", TEXT_COLOR)
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	# o cache de tema só é atualizado no próximo quadro; sem isto a altura mínima
	# ainda seria a da fonte padrão (23 px) e o rótulo passaria da altura do retângulo
	l.notification(Control.NOTIFICATION_THEME_CHANGED)
	l.position = r.position
	l.size = r.size
	return l


func _make_bar(prefix: String, pos: Vector2, bg_color: Color, fill_color: Color) -> ColorRect:
	var bg := ColorRect.new()
	bg.name = prefix + "Bg"
	bg.color = bg_color
	bg.position = pos
	bg.size = Vector2(BAR_W, BAR_H)
	add_child(bg)
	var fill := ColorRect.new()
	fill.name = prefix + "Fill"
	fill.color = fill_color
	fill.position = pos + Vector2(0, BAR_H)
	fill.size = Vector2(BAR_W, 0)
	add_child(fill)
	return fill


static func bar_height(v: int, vmax: int) -> int:
	if vmax <= 0:
		return 0
	return roundi(float(BAR_H) * float(v) / float(vmax))


func _set_fill(fill: ColorRect, bg_pos: Vector2, v: int, vmax: int) -> void:
	var h: int = bar_height(v, vmax)
	fill.size = Vector2(BAR_W, h)
	fill.position = bg_pos + Vector2(0, BAR_H - h)


func apply_state(p: Dictionary, tick: int = 0) -> void:
	_set_fill(hp_fill, HP_BG_POS, p["hp"], p["hp_max"])
	_set_fill(sp_fill, SP_BG_POS, p["stamina"], p["stamina_max"])
	if int(p["angle"]) != _heading:
		_heading = p["angle"]
		compass.queue_redraw()
	var inv: Dictionary = p.get("inventory", {"potion_hp": 0, "potion_sp": 0, "key": false})
	hp_text.text = "V %d/%d" % [p["hp"], p["hp_max"]]
	sp_text.text = "G %d/%d" % [p["stamina"], p["stamina_max"]]
	level_text.text = "Nv %d  XP %d  Ouro %d" % [p.get("level", 1), p.get("xp", 0), p.get("gold", 0)]
	inv_text.text = "PV %d  PG %d  %s" % [inv["potion_hp"], inv["potion_sp"], "Chave" if inv["key"] else "-"]
	_detect_events(p, inv, tick)
	var stun: int = p["stun_ticks"]
	if stun == 20:
		message.text = "Guarda quebrada!"
	elif stun > 0:
		message.text = "Atordoado!"
	elif tick < _event_until:
		message.text = _event_msg
	else:
		message.text = ""


## Mensagens de coleta e de nível pela diferença entre o estado anterior e o atual.
func _detect_events(p: Dictionary, inv: Dictionary, tick: int) -> void:
	if _prev.is_empty():
		_prev = p.duplicate(true)
		return
	var pinv: Dictionary = _prev.get("inventory", inv)
	var msg: String = ""
	if int(p.get("level", 1)) > int(_prev.get("level", 1)):
		msg = "Nível %d!" % int(p["level"])
	elif inv["key"] and not pinv["key"]:
		msg = "Chave da Saída!"
	elif int(inv["potion_hp"]) > int(pinv["potion_hp"]):
		msg = "Poção de Vida"
	elif int(inv["potion_sp"]) > int(pinv["potion_sp"]):
		msg = "Poção de Vigor"
	elif int(p.get("gold", 0)) > int(_prev.get("gold", 0)):
		msg = "+%d de ouro" % (int(p["gold"]) - int(_prev.get("gold", 0)))
	if not msg.is_empty():
		_event_msg = msg
		_event_until = tick + MESSAGE_TICKS
	_prev = p.duplicate(true)


## Rótulos da bússola que cabem inteiros no retângulo: [{label, x, w}], x = centro.
## Pura: sem nó e sem fonte, para os gates headless.
static func compass_marks(heading: int) -> Array:
	var out: Array = []
	var cx: float = COMPASS_RECT.size.x / 2.0
	var right: float = COMPASS_RECT.size.x - COMPASS_MARGIN
	for b: int in COMPASS_LABELS:
		var diff: int = wrapi(heading - b, -2048, 2048)
		var x: float = cx + float(diff) * COMPASS_PX_PER_BAM
		var label: String = COMPASS_LABELS[b]
		var w: float = LABEL_CHAR_W * label.length()
		if x - w / 2.0 >= COMPASS_MARGIN and x + w / 2.0 <= right:
			out.append({"label": label, "x": x, "w": w})
	out.sort_custom(func(a: Dictionary, c: Dictionary) -> bool: return a["x"] < c["x"])
	return out


func _draw_compass() -> void:
	var w: float = COMPASS_RECT.size.x
	var h: float = COMPASS_RECT.size.y
	compass.draw_rect(Rect2(0, 0, w, h), Color("#1a1714"))
	# traço curto a cada 22,5° (256 BAM) sem rótulo; ângulo maior fica à esquerda
	for k in range(16):
		var b: int = k * 256
		if COMPASS_LABELS.has(b):
			continue
		var x: float = w / 2.0 + float(wrapi(_heading - b, -2048, 2048)) * COMPASS_PX_PER_BAM
		if x < 1.0 or x > w - 1.0:
			continue
		compass.draw_line(Vector2(x, 2.0), Vector2(x, 6.0), Color("#8a7a60"))
	var font: Font = ThemeDB.fallback_font
	for m: Dictionary in compass_marks(_heading):
		var x: float = m["x"]
		var centered: bool = absf(x - w / 2.0) < float(COMPASS_CENTER_BAM) * COMPASS_PX_PER_BAM
		var color: Color = Color("#ffe8a0") if centered else TEXT_COLOR
		compass.draw_string(font, Vector2(x - float(m["w"]) / 2.0, 17.0), m["label"],
			HORIZONTAL_ALIGNMENT_LEFT, -1, COMPASS_FONT_SIZE, color)
	compass.draw_rect(Rect2(0, 0, w, h), Color("#8a7a60"), false, 1.0)
	compass.draw_colored_polygon(PackedVector2Array([
		Vector2(w / 2.0 - 3.0, 0.0), Vector2(w / 2.0 + 3.0, 0.0), Vector2(w / 2.0, 4.0),
	]), Color("#b02020"))
