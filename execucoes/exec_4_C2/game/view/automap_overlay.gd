class_name AutomapOverlay
extends CanvasLayer
## M5: automapa translúcido (CanvasLayer layer 3) sobre a área do mundo (640×312),
## sem cobrir a HUD. Tab alterna Map.visible; o jogo não pausa. Só LÊ o núcleo:
## main.advance() chama push() depois do step.

const MAP_W: int = 640
const MAP_H: int = 312
const CELL_PX: float = 6.0
const ALPHA: float = 0.6
const COL_PARCH: Color = Color("#d8c8a0")
const COL_FLOOR: Color = Color("#b8a47a")
const COL_WALL: Color = Color("#3a2a18")
const COL_DOOR: Color = Color("#8a5a2a")
const COL_LOCKED: Color = Color("#c02020")
const COL_EXIT: Color = Color("#2080c0")
const COL_PLAYER: Color = Color("#ffd040")
const TITLE: String = "MAPA — Tab fecha"

## Contadores expostos aos gates (M5-A4/M5-A6).
var draw_count: int = 0
var toggles: int = 0
## Nó de áudio opcional com play_ui(nome) (farfalhar de papel).
var audio: Node = null
var _map: Control = null
var _automap: AutomapSim = null
var _grid: Grid = null
var _player: Dictionary = {}
var _font: Font = null


func _ready() -> void:
	layer = 3
	_map = get_node_or_null("Map") as Control
	if _map == null:
		_map = Control.new()
		_map.name = "Map"
		add_child(_map)
	_map.position = Vector2.ZERO
	_map.size = Vector2(MAP_W, MAP_H)
	_map.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map.visible = false
	_map.modulate.a = ALPHA
	_map.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_font = HudDaggerfall.pixel_font()
	_map.draw.connect(_on_map_draw)


func is_open() -> bool:
	return _map.visible


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).echo:
		return
	if event.is_action_pressed("toggle_map"):
		toggle()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func toggle() -> void:
	set_open(not _map.visible)


func set_open(v: bool) -> void:
	if _map.visible == v:
		return
	_map.visible = v
	toggles += 1
	if v:
		_map.queue_redraw()
	if audio != null:
		audio.call("play_ui", "paper")


## Estado só para leitura (referências do núcleo e dicionário do jogador).
func push(automap: AutomapSim, grid: Grid, state: Dictionary) -> void:
	_automap = automap
	_grid = grid
	_player = state["player"]
	if _map.visible:
		_map.queue_redraw()


## Centro da célula na tela (norte = +z da simulação = cima; leste = +x = direita).
func cell_screen(cx: int, cz: int) -> Vector2:
	var px: float = float(int(_player["pos_x"]))
	var pz: float = float(int(_player["pos_z"]))
	var sx: float = MAP_W / 2.0 + (float(cx * Grid.CELL + Grid.CELL / 2) - px) * CELL_PX / Grid.CELL
	var sy: float = MAP_H / 2.0 - (float(cz * Grid.CELL + Grid.CELL / 2) - pz) * CELL_PX / Grid.CELL
	return Vector2(sx, sy)


func _on_map_draw() -> void:
	draw_count += 1
	_map.draw_rect(Rect2(0, 0, MAP_W, MAP_H), COL_PARCH)
	if _automap != null and _grid != null and not _player.is_empty():
		_draw_cells()
		_draw_player()
	_map.draw_string(_font, Vector2(8, 6 + 10), TITLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, COL_WALL)


func _draw_cells() -> void:
	var h: float = CELL_PX / 2.0
	for cz: int in range(Grid.H):
		for cx: int in range(Grid.W):
			if not _automap.is_visited(cx, cz):
				continue
			var t: int = _grid.get_cell(cx, cz)
			if t == Grid.SOLID:
				continue
			var c: Vector2 = cell_screen(cx, cz)
			if c.x < -CELL_PX or c.x > MAP_W + CELL_PX or c.y < -CELL_PX or c.y > MAP_H + CELL_PX:
				continue
			_map.draw_rect(Rect2(c.x - h, c.y - h, CELL_PX, CELL_PX), COL_FLOOR)
			if _grid.get_cell(cx + 1, cz) == Grid.SOLID:
				_map.draw_line(Vector2(c.x + h, c.y - h), Vector2(c.x + h, c.y + h), COL_WALL, 2.0, false)
			if _grid.get_cell(cx - 1, cz) == Grid.SOLID:
				_map.draw_line(Vector2(c.x - h, c.y - h), Vector2(c.x - h, c.y + h), COL_WALL, 2.0, false)
			if _grid.get_cell(cx, cz + 1) == Grid.SOLID:
				_map.draw_line(Vector2(c.x - h, c.y - h), Vector2(c.x + h, c.y - h), COL_WALL, 2.0, false)
			if _grid.get_cell(cx, cz - 1) == Grid.SOLID:
				_map.draw_line(Vector2(c.x - h, c.y + h), Vector2(c.x + h, c.y + h), COL_WALL, 2.0, false)
			var door: Rect2 = Rect2(c.x - 2, c.y - 2, 4, 4)
			if t == Grid.DOOR_CLOSED:
				_map.draw_rect(door, COL_DOOR)
			elif t == Grid.DOOR_OPEN:
				_map.draw_rect(door, COL_DOOR, false, 1.0)
			elif t == Grid.DOOR_LOCKED:
				_map.draw_rect(door, COL_LOCKED)
			elif t == Grid.EXIT:
				_map.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -h), c + Vector2(h, 0),
					c + Vector2(0, h), c + Vector2(-h, 0)]), COL_EXIT)


## Triângulo de 10 px × 7 px apontando para `angle` (tela: (cos a, −sin a)).
func _draw_player() -> void:
	var a: float = TAU * float(int(_player["angle"])) / 4096.0
	var f: Vector2 = Vector2(cos(a), -sin(a))
	var r: Vector2 = Vector2(-f.y, f.x)
	var c: Vector2 = Vector2(MAP_W / 2.0, MAP_H / 2.0)
	var tip: Vector2 = c + f * 6.0
	var back: Vector2 = c - f * 4.0
	var pts: PackedVector2Array = PackedVector2Array([tip, back + r * 3.5, back - r * 3.5])
	_map.draw_colored_polygon(pts, COL_PLAYER)
	_map.draw_polyline(PackedVector2Array([tip, back + r * 3.5, back - r * 3.5, tip]), Color.BLACK, 1.0, false)
