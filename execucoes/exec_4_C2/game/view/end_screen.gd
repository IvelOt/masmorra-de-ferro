class_name EndScreen
extends CanvasLayer
## M6: tela final em pergaminho (CanvasLayer layer 4, Main/EndScreen). Aparece no
## primeiro estado com terminal != "". Enter: nova partida com a semente seguinte
## (só UI; desligado quando a cena é dirigida por runner/gates).

const PANEL_RECT: Rect2 = Rect2(140, 64, 360, 200)
const COL_PARCH: Color = Color("#d8c8a0")
const COL_BORDER: Color = Color("#6b5a45")
const COL_INNER: Color = Color("#3a2a18")
const COL_TEXT: Color = Color("#2b1a0a")
const COL_DEAD: Color = Color("#8a1010")
const TITLES: Dictionary = {
	"ESCAPED": "VOCÊ ESCAPOU!",
	"DEAD": "VOCÊ MORREU",
	"TIMEOUT": "TEMPO ESGOTADO",
}

## Chamado com a próxima semente quando o jogador pressiona Enter.
var on_restart: Callable = Callable()
var driven: bool = false
var _seed: int = 1
var _root: Control = null
var _title: Label = null
var _body: Array = []
var _footer: Label = null
var _font: Font = null


func _ready() -> void:
	layer = 4
	_font = HudDaggerfall.pixel_font()
	_root = Control.new()
	_root.name = "Root"
	_root.size = Vector2(640, 360)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)
	var dim: ColorRect = ColorRect.new()
	dim.name = "Dim"
	dim.size = Vector2(640, 360)
	dim.color = Color(0, 0, 0, 0.5)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var panel: Panel = Panel.new()
	panel.name = "Panel"
	panel.position = PANEL_RECT.position
	panel.size = PANEL_RECT.size
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = COL_PARCH
	sb.border_color = COL_BORDER
	sb.set_border_width_all(3)
	panel.add_theme_stylebox_override("panel", sb)
	_root.add_child(panel)
	var inner: Panel = Panel.new()
	inner.name = "Inner"
	inner.position = Vector2(3, 3)
	inner.size = PANEL_RECT.size - Vector2(6, 6)
	var sbi: StyleBoxFlat = StyleBoxFlat.new()
	sbi.draw_center = false
	sbi.border_color = COL_INNER
	sbi.set_border_width_all(1)
	inner.add_theme_stylebox_override("panel", sbi)
	panel.add_child(inner)
	_title = _label(panel, "Title", Rect2(0, 14, 360, 28), 20)
	for i: int in range(5):
		_body.append(_label(panel, "Line%d" % i, Rect2(0, 52 + i * 18, 360, 16), 10))
	_footer = _label(panel, "Footer", Rect2(0, 172, 360, 16), 10)
	visible = false


func _label(parent: Node, n: String, r: Rect2, font_size: int) -> Label:
	var l: Label = Label.new()
	l.name = n
	l.position = r.position
	l.size = r.size
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_font_override("font", _font)
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", COL_TEXT)
	parent.add_child(l)
	return l


func title() -> String:
	return _title.text


func panel() -> Panel:
	return _root.get_node("Panel") as Panel


## Estado completo e semente da partida; mostra a tela no primeiro terminal.
func push_state(s: Dictionary, p_seed: int) -> void:
	var term: String = String(s["terminal"])
	if term == "":
		visible = false
		return
	if visible:
		return
	_seed = p_seed
	var p: Dictionary = s["player"]
	var ticks: int = int(s["tick"])
	var secs: int = ticks / 60
	_title.text = String(TITLES.get(term, term))
	_title.add_theme_color_override("font_color", COL_DEAD if term == "DEAD" else COL_TEXT)
	(_body[0] as Label).text = "Nível %d" % int(p["level"])
	(_body[1] as Label).text = "XP %d" % int(p["xp"])
	(_body[2] as Label).text = "Ouro %d" % int(p["gold"])
	(_body[3] as Label).text = "Tempo %d:%02d (%d ticks)" % [secs / 60, secs % 60, ticks]
	(_body[4] as Label).text = "Semente %d" % p_seed
	_footer.text = "Enter: nova partida (semente %d)" % (p_seed + 1)
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible or driven:
		return
	if event is InputEventKey and (event as InputEventKey).pressed and not (event as InputEventKey).echo:
		var k: Key = (event as InputEventKey).keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			if on_restart.is_valid():
				on_restart.call(_seed + 1)
