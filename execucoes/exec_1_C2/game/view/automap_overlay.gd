class_name AutomapOverlay
extends CanvasLayer
## Sobreposição translúcida do automapa (M5, Tab). Só lê o snapshot, o bitmap
## visited e a grade; o estado "aberto" é só de interface e não pausa o jogo.
## Projeção centrada no jogador, norte fixo (+Z da simulação para cima), 8 px por célula.

signal toggled(open: bool)

const PX_PER_CELL: float = 8.0
const CENTER: Vector2 = Vector2(320, 160)
const FLOOR_C: Color = Color(0.70, 0.60, 0.42)
const EDGE_C: Color = Color(0.25, 0.15, 0.08)
const DOOR_C: Color = Color(0.55, 0.35, 0.15)
const LOCKED_C: Color = Color(0.80, 0.10, 0.10)
const EXIT_C: Color = Color(0.60, 0.20, 0.80)
const PLAYER_C: Color = Color(0.85, 0.10, 0.10)

var _player: Dictionary = {}
var _prev_player: Dictionary = {}
var _visited: PackedByteArray = PackedByteArray()
var _grid: Grid = null
var _frac: float = 1.0

@onready var _canvas: Control = $Map/Canvas


func _ready() -> void:
	add_to_group("automap")
	_canvas.draw.connect(_draw_map)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map") and not event.is_echo():
		toggle()


func toggle() -> void:
	visible = not visible
	toggled.emit(visible)
	if visible and _canvas != null:
		_canvas.queue_redraw()


## Chamado por main.gd a cada quadro, só quando visível.
func apply(prev_player: Dictionary, player: Dictionary, visited: PackedByteArray, grid: Grid, frac: float) -> void:
	_prev_player = prev_player
	_player = player
	_visited = visited
	_grid = grid
	_frac = frac
	_canvas.queue_redraw()


func _draw_map() -> void:
	if _grid == null or _player.is_empty() or _visited.size() != Grid.SIZE * Grid.SIZE:
		return
	var px: float = lerpf(float(_prev_player.pos_x), float(_player.pos_x), _frac) / float(Grid.CELL)
	var pz: float = lerpf(float(_prev_player.pos_z), float(_player.pos_z), _frac) / float(Grid.CELL)
	var c: Control = _canvas
	var x_lo: int = maxi(int(px) - 41, 0)
	var x_hi: int = mini(int(px) + 41, Grid.SIZE - 1)
	var z_lo: int = maxi(int(pz) - 21, 0)
	var z_hi: int = mini(int(pz) + 21, Grid.SIZE - 1)
	var doors: Array[Vector2i] = []
	for cz in range(z_lo, z_hi + 1):
		for cx in range(x_lo, x_hi + 1):
			if _visited[cz * Grid.SIZE + cx] == 0:
				continue
			var t: int = _grid.get_cell(cx, cz)
			if t == Grid.SOLID:
				continue
			# canto superior esquerdo na tela = (x mínimo, z máximo) da célula
			var tl: Vector2 = _to_screen(float(cx), float(cz + 1), px, pz)
			c.draw_rect(Rect2(tl, Vector2(PX_PER_CELL, PX_PER_CELL)), FLOOR_C)
			if Grid.is_door_type(t):
				doors.append(Vector2i(cx, cz))
	for cz in range(z_lo, z_hi + 1):
		for cx in range(x_lo, x_hi + 1):
			if _visited[cz * Grid.SIZE + cx] == 0 or _grid.get_cell(cx, cz) == Grid.SOLID:
				continue
			var tl: Vector2 = _to_screen(float(cx), float(cz + 1), px, pz)
			var s: float = PX_PER_CELL
			if _grid.get_cell(cx + 1, cz) == Grid.SOLID:
				c.draw_line(tl + Vector2(s, 0), tl + Vector2(s, s), EDGE_C, 2.0)
			if _grid.get_cell(cx - 1, cz) == Grid.SOLID:
				c.draw_line(tl, tl + Vector2(0, s), EDGE_C, 2.0)
			if _grid.get_cell(cx, cz + 1) == Grid.SOLID:
				c.draw_line(tl, tl + Vector2(s, 0), EDGE_C, 2.0)
			if _grid.get_cell(cx, cz - 1) == Grid.SOLID:
				c.draw_line(tl + Vector2(0, s), tl + Vector2(s, s), EDGE_C, 2.0)
			if _grid.get_cell(cx, cz) == Grid.EXIT:
				var m: Vector2 = tl + Vector2(s, s) * 0.5
				c.draw_colored_polygon(PackedVector2Array([m + Vector2(0, -3), m + Vector2(3, 0), m + Vector2(0, 3), m + Vector2(-3, 0)]), EXIT_C)
	for d in doors:
		_draw_door(d.x, d.y, px, pz)
	# jogador: triângulo de 10 px de comprimento e 7 de base, na direção (cos a, -sin a)
	var a: float = TAU * lerpf(float(_prev_player.angle), float(_player.angle), _frac) / 4096.0
	if absf(float(_player.angle) - float(_prev_player.angle)) > 2048.0:
		a = TAU * float(_player.angle) / 4096.0
	var f: Vector2 = Vector2(cos(a), -sin(a))
	var r: Vector2 = Vector2(-f.y, f.x)
	c.draw_colored_polygon(PackedVector2Array([CENTER + f * 6.0, CENTER - f * 4.0 + r * 3.5, CENTER - f * 4.0 - r * 3.5]), PLAYER_C)
	c.draw_string(ThemeDB.fallback_font, Vector2(316, 12), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, EDGE_C)


func _draw_door(cx: int, cz: int, px: float, pz: float) -> void:
	var t: int = _grid.get_cell(cx, cz)
	var tl: Vector2 = _to_screen(float(cx), float(cz + 1), px, pz)
	var along_x: bool = _grid.get_cell(cx + 1, cz) != Grid.SOLID and _grid.get_cell(cx - 1, cz) != Grid.SOLID
	# barra atravessando a passagem: passagem em X -> barra vertical
	var rect: Rect2 = Rect2(tl + Vector2(2.5, 0), Vector2(3, 8)) if along_x else Rect2(tl + Vector2(0, 2.5), Vector2(8, 3))
	if t == Grid.DOOR_OPEN:
		_canvas.draw_rect(rect, DOOR_C, false, 1.0)
	else:
		_canvas.draw_rect(rect, LOCKED_C if t == Grid.DOOR_LOCKED else DOOR_C)


## (x, z) em células da simulação -> pixel da tela; +Z da simulação para cima.
func _to_screen(x: float, z: float, px: float, pz: float) -> Vector2:
	return Vector2(CENTER.x + (x - px) * PX_PER_CELL, CENTER.y - (z - pz) * PX_PER_CELL)
