extends CanvasLayer
## Tela final em pergaminho (CanvasLayer 4; GDD §4.6). Oculta enquanto terminal == "NONE".
## Somente leitura do núcleo. Enter pede nova partida (semente + 1) à main; Esc fecha o jogo.

signal restart_requested

const TITLES: Dictionary = {
	"ESCAPED": ["VOCÊ ESCAPOU!", Color("#205020")],
	"DEAD": ["VOCÊ MORREU", Color("#801818")],
	"TIMEOUT": ["O TEMPO ACABOU", Color("#604010")],
}
const TICKS_PER_SECOND: int = 60

@onready var title: Label = $Panel/Title
@onready var lines: Label = $Panel/Lines

var _shown: String = "NONE"


func _ready() -> void:
	visible = false
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#d8c8a0")
	sb.border_color = Color("#5a4630")
	sb.set_border_width_all(4)
	($Panel as Panel).add_theme_stylebox_override("panel", sb)


static func time_text(ticks: int) -> String:
	var secs: int = ticks / TICKS_PER_SECOND
	return "Tempo %d ticks (%02d:%02d)" % [ticks, secs / 60, secs % 60]


func refresh(world: WorldSim) -> void:
	var t: String = world.get_terminal()
	if t == "NONE":
		visible = false
		_shown = "NONE"
		return
	if t == _shown:
		return
	_shown = t
	var inv: Dictionary = world.get_inventory()
	var kills: int = 0
	for e: Dictionary in world.get_enemies():
		if e["type"] != "dummy" and e["state"] == "DEAD":
			kills += 1
	title.text = TITLES[t][0]
	title.add_theme_color_override("font_color", TITLES[t][1])
	lines.text = "Nível %d\nOuro %d\nInimigos abatidos %d\n%s\n\nEnter: nova partida (semente+1) · Esc: sair" % [
		inv["level"], inv["gold"], kills, time_text(world.get_tick())]
	visible = true


func _unhandled_input(event: InputEvent) -> void:
	if not visible or DisplayServer.get_name() == "headless":
		return
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = (event as InputEventKey).keycode
		if k == KEY_ENTER or k == KEY_KP_ENTER:
			get_viewport().set_input_as_handled()
			restart_requested.emit()
		elif k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			get_tree().quit()
