class_name EndScreen
extends CanvasLayer
## Tela final em pergaminho (M6): aparece com fade de 30 quadros quando o
## snapshot entra num terminal. Enter recarrega a cena só no modo interativo.

const PARCHMENT: Color = Color(0.86, 0.78, 0.58)
const BORDER: Color = Color(0.40, 0.28, 0.14)
const INK: Color = Color(0.25, 0.15, 0.08)
const FADE_FRAMES: int = 30
const TITLES: Dictionary = {"ESCAPED": "VOCÊ ESCAPOU!", "DEAD": "VOCÊ MORREU", "TIMEOUT": "TEMPO ESGOTADO"}

var interactive: bool = true
var shown: bool = false
var _fade: int = 0

@onready var _panel: Panel = $Panel
@onready var _title: Label = $Panel/Title
@onready var _body: Label = $Panel/Body
@onready var _footer: Label = $Panel/Footer


func _ready() -> void:
	visible = false
	var sb: StyleBoxFlat = StyleBoxFlat.new()
	sb.bg_color = PARCHMENT
	sb.border_color = BORDER
	sb.set_border_width_all(3)
	_panel.add_theme_stylebox_override("panel", sb)
	for l: Label in [_title, _body, _footer]:
		l.add_theme_color_override("font_color", INK)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.add_theme_font_size_override("font_size", 16)
	_body.add_theme_font_size_override("font_size", 10)
	_footer.add_theme_font_size_override("font_size", 10)


## snapshot: s_k; seed_value: semente da partida.
func show_result(snapshot: Dictionary, seed_value: int) -> void:
	if shown:
		return
	shown = true
	var p: Dictionary = snapshot.player
	var t: int = int(snapshot.tick)
	_title.text = str(TITLES.get(str(snapshot.terminal), str(snapshot.terminal)))
	_body.text = "Nível %d\nXP %d\nOuro %d\nTempo: %d ticks (%d s)\nSemente %d" % [
		int(p.level), int(p.xp), int(p.gold), t, t / 60, seed_value]
	_footer.text = "Enter: nova partida" if interactive else ""
	_footer.visible = interactive
	_fade = 0
	_panel.modulate.a = 0.0
	visible = true


func _process(_dt: float) -> void:
	if visible and _fade < FADE_FRAMES:
		_fade += 1
		_panel.modulate.a = float(_fade) / float(FADE_FRAMES)


func _unhandled_input(event: InputEvent) -> void:
	if not shown or not interactive:
		return
	if event is InputEventKey and event.pressed and not event.is_echo() \
			and ((event as InputEventKey).keycode == KEY_ENTER or (event as InputEventKey).keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
