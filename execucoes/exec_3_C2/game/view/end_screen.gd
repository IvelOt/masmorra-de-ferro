extends CanvasLayer
## M6: tela final em pergaminho estilo Daggerfall (plano R4 §4.10). Só lê o estado.
## C16 (plano R6 §6.2): título no corpo 24 e estatísticas no corpo 12.

const PARCHMENT_RECT: Rect2 = Rect2(160, 66, 320, 180)
const TITLES: Dictionary = {
	"ESCAPED": "VOCÊ ESCAPOU!",
	"DEAD": "VOCÊ MORREU",
	"TIMEOUT": "TEMPO ESGOTADO",
}

var parchment: Panel
var title: Label
var stats: Label


func _ready() -> void:
	layer = 4
	parchment = Panel.new()
	parchment.name = "Parchment"
	parchment.position = PARCHMENT_RECT.position
	parchment.size = PARCHMENT_RECT.size
	parchment.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#d8c8a0")
	sb.border_color = Color("#5a4020")
	sb.set_border_width_all(3)
	parchment.add_theme_stylebox_override("panel", sb)
	add_child(parchment)
	title = Label.new()
	title.name = "Title"
	title.position = Vector2(0, 14)
	title.size = Vector2(PARCHMENT_RECT.size.x, 32)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("#3a2a18"))
	parchment.add_child(title)
	stats = Label.new()
	stats.name = "Stats"
	stats.position = Vector2(0, 56)
	stats.size = Vector2(PARCHMENT_RECT.size.x, 112)
	stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stats.add_theme_font_size_override("font_size", 12)
	stats.add_theme_color_override("font_color", Color("#3a2a18"))
	parchment.add_child(stats)
	visible = false


func apply_state(terminal: String, terminal_tick: int, p: Dictionary) -> void:
	visible = terminal != "NONE"
	if not visible:
		return
	title.text = TITLES.get(terminal, terminal)
	stats.text = "Nível %d\nOuro %d\nXP %d\nTicks %d" % [p["level"], p["gold"], p["xp"], terminal_tick]
