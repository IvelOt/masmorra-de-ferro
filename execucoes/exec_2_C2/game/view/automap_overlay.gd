extends Control
## Automapa translúcido (plano §6.5): Control 640 × 312 no CanvasLayer layer = 3, nunca cobre a HUD.
## Tab (`toggle_map`) alterna a visibilidade; o jogo não pausa e o núcleo não sabe que o mapa existe.
## Desenha a partir do snapshot, centrado no jogador, norte (+Z do núcleo) para cima, 6 px por célula.

signal toggled(open: bool)

const GRID_W: int = 64
const GRID_H: int = 64
const CELL_U: float = 2048.0
const PX: float = 6.0
const CENTER: Vector2 = Vector2(320, 156)
const SOLID: int = 0
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5
const PARCHMENT: Color = Color("#d8c8a0")
const INK: Color = Color("#3a2a18")
const DOOR_COLORS: Dictionary = {DOOR_CLOSED: Color("#7a4a20"), DOOR_OPEN: Color("#c89050"), DOOR_LOCKED: Color("#c02020")}
const EXIT_COLOR: Color = Color("#4060ff")
const PLAYER_COLOR: Color = Color("#202020")
const ARROW_LEN: float = 7.0
## Itens não coletados em células visitadas (plano da rodada 3 §8.6); inimigos não aparecem.
const ITEM_COLORS: Dictionary = {
	"key": Color("#e0c020"), "potion_hp": Color("#c02020"), "potion_sp": Color("#20a040"), "gold": Color("#c0a040"),
}

var _snap: Dictionary = {}


func _ready() -> void:
	visible = false
	modulate.a = 0.6
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map") and not event.is_echo():
		set_open(not visible)
		get_viewport().set_input_as_handled()


func set_open(open: bool) -> void:
	if open == visible:
		return
	visible = open
	toggled.emit(open)
	if visible:
		queue_redraw()


func set_snapshot(snap: Dictionary) -> void:
	_snap = snap
	if visible:
		queue_redraw()


func _cell(cells: PackedByteArray, cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= GRID_W or cz >= GRID_H:
		return SOLID
	return cells[cz * GRID_W + cx]


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), PARCHMENT)
	if _snap.is_empty():
		return
	var cells: PackedByteArray = _snap.cells
	var visited: PackedByteArray = _snap.visited
	var p: Dictionary = _snap.player
	var pc: Vector2 = Vector2(float(p.pos_x) / CELL_U, float(p.pos_z) / CELL_U)
	for cz in range(GRID_H):
		for cx in range(GRID_W):
			var i: int = cz * GRID_W + cx
			var t: int = cells[i]
			if visited[i] == 0 or t == SOLID:
				continue
			# canto inferior-esquerdo da célula no núcleo -> tela (y invertido)
			var x0: float = roundf(CENTER.x + (cx - pc.x) * PX)
			var y1: float = roundf(CENTER.y - (cz - pc.y) * PX)
			var x1: float = x0 + PX
			var y0: float = y1 - PX
			if x1 < 0.0 or x0 > size.x or y1 < 0.0 or y0 > size.y:
				continue
			if _cell(cells, cx + 1, cz) == SOLID:
				draw_line(Vector2(x1, y0), Vector2(x1, y1), INK, 1.0)
			if _cell(cells, cx - 1, cz) == SOLID:
				draw_line(Vector2(x0, y0), Vector2(x0, y1), INK, 1.0)
			if _cell(cells, cx, cz + 1) == SOLID:
				draw_line(Vector2(x0, y0), Vector2(x1, y0), INK, 1.0)
			if _cell(cells, cx, cz - 1) == SOLID:
				draw_line(Vector2(x0, y1), Vector2(x1, y1), INK, 1.0)
			var mid: Vector2 = Vector2(x0 + PX * 0.5, y0 + PX * 0.5)
			if DOOR_COLORS.has(t):
				draw_rect(Rect2(mid - Vector2(2, 2), Vector2(4, 4)), DOOR_COLORS[t])
			elif t == EXIT:
				draw_circle(mid, 3.0, EXIT_COLOR)
	for it: Dictionary in _snap.get("items", []):
		var icx: int = it.cell_x
		var icz: int = it.cell_z
		if it.taken or visited[icz * GRID_W + icx] == 0:
			continue
		var ix: float = roundf(CENTER.x + (icx + 0.5 - pc.x) * PX)
		var iy: float = roundf(CENTER.y - (icz + 0.5 - pc.y) * PX)
		draw_rect(Rect2(ix - 1.0, iy - 1.0, 3.0, 3.0), ITEM_COLORS.get(it.type, INK))
	# jogador: seta apontando (cos θ, −sin θ)
	var th: float = TAU * float(p.angle) / 4096.0
	var f: Vector2 = Vector2(cos(th), -sin(th))
	var side: Vector2 = Vector2(-f.y, f.x)
	var tip: Vector2 = CENTER + f * (ARROW_LEN * 0.5)
	var back: Vector2 = CENTER - f * (ARROW_LEN * 0.5)
	draw_colored_polygon(PackedVector2Array([tip, back + side * 3.0, back - side * 3.0]), PLAYER_COLOR)
