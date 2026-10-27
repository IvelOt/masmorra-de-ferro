class_name HudDaggerfall
extends CanvasLayer
## Barra inferior estilo Daggerfall (M3 + M6), procedural: retrato, Vida e Vigor
## em barras verticais 10x32 preenchidas de baixo para cima, valores, nível e
## XP, ouro, chave, poções, duas linhas de mensagem e a bússola de faixa.

const BAR_TOP: int = 324
const BAR_H: int = 32
const BAR_W: int = 10
const STONE: Color = Color(0.23, 0.21, 0.19)
const STONE_EDGE: Color = Color(0.45, 0.40, 0.33)
const SHADOW: Color = Color(0.08, 0.07, 0.06)
const HP_COLOR: Color = Color(0.75, 0.10, 0.10)
const SP_COLOR: Color = Color(0.15, 0.65, 0.20)
const BAR_BG: Color = Color(0.08, 0.08, 0.08)
const BORDER: Color = Color(0.05, 0.05, 0.05)
const STUN_BORDER: Color = Color(0.9, 0.8, 0.2)
const TEXT: Color = Color(0.92, 0.86, 0.70)
const FONT_SIZE: int = 10
const MSG_FRAMES: int = 180

var _hp_fill: ColorRect
var _sp_fill: ColorRect
var _borders: Array[ColorRect] = []
var _hp_label: Label
var _sp_label: Label
var _lvl_label: Label
var _gold_label: Label
var _key_icon: TextureRect
var _php_label: Label
var _psp_label: Label
var _msg_label: Label
var _compass: Compass
var _messages: Array[Dictionary] = []   # {text, frames}


func _ready() -> void:
	var panel: Panel = Panel.new()
	panel.name = "Bar"
	panel.position = Vector2(0, 320)
	panel.size = Vector2(640, 40)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = STONE
	sb.border_color = STONE_EDGE
	sb.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", sb)
	add_child(panel)
	# sombra interna de 1 px logo dentro da borda
	var inner: Panel = Panel.new()
	inner.position = Vector2(2, 322)
	inner.size = Vector2(636, 36)
	inner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var isb: StyleBoxFlat = StyleBoxFlat.new()
	isb.draw_center = false
	isb.border_color = SHADOW
	isb.set_border_width_all(1)
	inner.add_theme_stylebox_override("panel", isb)
	add_child(inner)
	_rect(Vector2(7, 323), Vector2(34, 34), BORDER)
	var portrait: TextureRect = TextureRect.new()
	portrait.name = "Portrait"
	portrait.texture = AssetResolver.texture("ui.portrait")
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.position = Vector2(8, 324)
	portrait.size = Vector2(32, 32)
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(portrait)
	_hp_fill = _bar(46, HP_COLOR)
	_sp_fill = _bar(60, SP_COLOR)
	_hp_label = _label(Vector2(76, 323), Vector2(80, 14))
	_sp_label = _label(Vector2(76, 339), Vector2(80, 14))
	_lvl_label = _label(Vector2(160, 323), Vector2(100, 14))
	_gold_label = _label(Vector2(160, 339), Vector2(100, 14))
	_key_icon = _icon("item.key", Vector2(262, 328))
	_icon("item.potion_hp", Vector2(284, 328))
	_php_label = _label(Vector2(300, 330), Vector2(22, 14))
	_icon("item.potion_sp", Vector2(322, 328))
	_psp_label = _label(Vector2(338, 330), Vector2(24, 14))
	_msg_label = _label(Vector2(364, 322), Vector2(180, 34))
	_msg_label.clip_text = true
	_compass = Compass.new()
	_compass.name = "Compass"
	_compass.position = Vector2(552, 324)
	add_child(_compass)


func _label(pos: Vector2, sz: Vector2) -> Label:
	var l: Label = Label.new()
	l.position = pos
	l.size = sz
	l.add_theme_font_size_override("font_size", FONT_SIZE)
	l.add_theme_color_override("font_color", TEXT)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 1)
	l.add_theme_constant_override("line_spacing", 0)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func _icon(id: String, pos: Vector2) -> TextureRect:
	var r: TextureRect = TextureRect.new()
	r.texture = AssetResolver.texture(id)
	r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.position = pos
	r.size = Vector2(16, 16)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _rect(pos: Vector2, sz: Vector2, c: Color) -> ColorRect:
	var r: ColorRect = ColorRect.new()
	r.position = pos
	r.size = sz
	r.color = c
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(r)
	return r


func _bar(x: int, c: Color) -> ColorRect:
	_borders.append(_rect(Vector2(x - 1, BAR_TOP - 1), Vector2(BAR_W + 2, BAR_H + 2), BORDER))
	_rect(Vector2(x, BAR_TOP), Vector2(BAR_W, BAR_H), BAR_BG)
	return _rect(Vector2(x, BAR_TOP + BAR_H), Vector2(BAR_W, 0), c)


static func fill_height(value: int, maximum: int) -> int:
	if maximum <= 0:
		return 0
	return clampi((BAR_H * value) / maximum, 0, BAR_H)


## p: dicionário "player" do snapshot.
func apply(p: Dictionary) -> void:
	_set_fill(_hp_fill, fill_height(int(p.hp), int(p.hp_max)))
	_set_fill(_sp_fill, fill_height(int(p.stamina), int(p.stamina_max)))
	var c: Color = STUN_BORDER if int(p.stun_ticks) > 0 else BORDER
	for b in _borders:
		b.color = c
	_hp_label.text = "PV %d/%d" % [int(p.hp), int(p.hp_max)]
	_sp_label.text = "VG %d/%d" % [int(p.stamina), int(p.stamina_max)]
	_lvl_label.text = level_text(int(p.level), int(p.xp))
	_gold_label.text = "Ouro %d" % int(p.gold)
	var inv: Dictionary = p.inventory
	_key_icon.modulate.a = 1.0 if bool(inv.key) else 0.25
	_php_label.text = "x%d" % int(inv.potion_hp)
	_psp_label.text = "x%d" % int(inv.potion_sp)
	_compass.set_angle(int(p.angle))


static func level_text(level: int, xp: int) -> String:
	if level >= ItemsSim.LEVEL_MAX:
		return "Nv %d  XP %d" % [level, xp]
	return "Nv %d  XP %d/%d" % [level, xp, ItemsSim.LEVEL_XP[level]]


func push_message(text: String) -> void:
	_messages.append({"text": text, "frames": MSG_FRAMES})
	while _messages.size() > 2:
		_messages.pop_front()
	_refresh_messages()


func _process(_dt: float) -> void:
	if _messages.is_empty():
		return
	var changed: bool = false
	for m in _messages:
		m.frames = int(m.frames) - 1
	while not _messages.is_empty() and int(_messages[0].frames) <= 0:
		_messages.pop_front()
		changed = true
	if changed:
		_refresh_messages()


func _refresh_messages() -> void:
	var lines: PackedStringArray = PackedStringArray()
	for m in _messages:
		lines.append(str(m.text))
	_msg_label.text = "\n".join(lines)


func _set_fill(r: ColorRect, h: int) -> void:
	r.position.y = BAR_TOP + BAR_H - h
	r.size.y = h
