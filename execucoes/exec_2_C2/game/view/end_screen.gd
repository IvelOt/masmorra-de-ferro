extends CanvasLayer
## Pergaminho de fim de partida (plano da rodada 3 §8.5), CanvasLayer layer = 4: retângulo
## (120, 50)–(520, 290), não cobre a HUD. Invisível até `terminal != "NONE"`. Só lê o snapshot.

const TITLES: Dictionary = {"ESCAPED": "VOCÊ ESCAPOU!", "DEAD": "VOCÊ MORREU", "TIMEOUT": "TEMPO ESGOTADO"}
const TICKS_PER_SECOND: int = 60

@onready var _title: Label = $Panel/Title
@onready var _lines: Label = $Panel/Lines
@onready var _footer: Label = $Panel/Footer

## Fora do modo de atração mostra "Tecle Enter para nova partida".
var show_footer: bool = true


func _ready() -> void:
	visible = false


func update(cur: Dictionary) -> void:
	var term: String = cur.get("terminal", "NONE")
	if term == "NONE":
		visible = false
		return
	var p: Dictionary = cur.player
	var kills: int = 0
	for e: Dictionary in cur.get("enemies", []):
		if e.state == "DEAD" and e.type != "dummy":
			kills += 1
	var secs: int = int(cur.get("terminal_tick", 0)) / TICKS_PER_SECOND
	_title.text = TITLES.get(term, term)
	_lines.text = "Nível: %d\nXP: %d\nOuro: %d\nInimigos abatidos: %d\nTempo: %02d:%02d" % [
		int(p.get("level", 1)), int(p.get("xp", 0)), int(p.get("gold", 0)), kills, secs / 60, secs % 60]
	_footer.text = "Tecle Enter para nova partida" if show_footer else ""
	visible = true
