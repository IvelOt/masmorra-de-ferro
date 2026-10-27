extends Control
## M5: automapa translúcido (plano R4 §3.3). Só lê cópias do estado; o estado
## "mapa aberto" é de interface e nunca chega ao WorldSim.
## C13 (plano R6 §3): geometria em cell_rects() pura, cabeçalho e marcador de norte.

const Grid = preload("res://sim/grid.gd")

const AREA: Rect2 = Rect2(0, 0, 640, 312)
const CELL_PX: float = 8.0
const CENTER: Vector2 = Vector2(320, 156)
const ALPHA: float = 0.6
const C_BG: Color = Color("#d8c8a0")
const C_FRAME: Color = Color("#5a4020")
const C_FLOOR: Color = Color("#ece0c0")
const C_WALL: Color = Color("#3a2a18")
const C_DOOR_CLOSED: Color = Color("#8a5a20")
const C_DOOR_OPEN: Color = Color("#c09050")
const C_DOOR_LOCKED: Color = Color("#b02020")
const C_EXIT: Color = Color("#a040c0")
const C_PLAYER: Color = Color("#b02020")
const DIRS: Array = [[1, 0], [-1, 0], [0, 1], [0, -1]]
## Cabeçalho e marcador de norte (plano R6 §3.2).
const HEADER_TEXT: String = "AUTOMAPA  [Tab]"
const HEADER_POS: Vector2 = Vector2(8, 18)
const HEADER_FONT_SIZE: int = 12
const NORTH_POS: Vector2 = Vector2(620, 18)
const NORTH_ARROW_X: float = 624.0

var _visited: PackedByteArray = PackedByteArray()
var _cells: PackedByteArray = PackedByteArray()
var _p: Dictionary = {}


func _ready() -> void:
	position = AREA.position
	size = AREA.size
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false
	modulate = Color(1, 1, 1, ALPHA)
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	clip_contents = true


func toggle() -> void:
	visible = not visible
	if visible:
		queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		toggle()
		if is_inside_tree():
			get_viewport().set_input_as_handled()


func apply_state(visited: PackedByteArray, cells: PackedByteArray, p: Dictionary) -> void:
	_visited = visited.duplicate()
	_cells = cells.duplicate()
	_p = p.duplicate(true)
	if visible:
		queue_redraw()


func _cell(x: int, z: int) -> int:
	if not Grid.in_bounds(x, z) or _cells.is_empty():
		return Grid.SOLID
	return _cells[z * Grid.SIZE + x]


## Canto (x mínimo, z máximo na tela) da célula: norte (+z) para cima.
static func cell_origin_for(x: int, z: int, p: Dictionary) -> Vector2:
	var px: float = float(p.get("pos_x", 0))
	var pz: float = float(p.get("pos_z", 0))
	return Vector2(CENTER.x + (float(x * Grid.CELL) - px) * CELL_PX / float(Grid.CELL),
		CENTER.y - (float(z * Grid.CELL) - pz) * CELL_PX / float(Grid.CELL))


func cell_origin(x: int, z: int) -> Vector2:
	return cell_origin_for(x, z, _p)


## Células visitadas, não sólidas e visíveis na área: [{x, z, rect, kind}]. Pura.
static func cell_rects(visited: PackedByteArray, cells: PackedByteArray, p: Dictionary) -> Array:
	var out: Array = []
	if visited.is_empty() or cells.is_empty():
		return out
	var area := Rect2(Vector2.ZERO, AREA.size)
	for z in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var i: int = z * Grid.SIZE + x
			if visited[i] != 1:
				continue
			var c: int = cells[i]
			if c == Grid.SOLID:
				continue
			var o: Vector2 = cell_origin_for(x, z, p)
			# a célula ocupa [sx, sx+8] x [sy-8, sy]
			var r := Rect2(o.x, o.y - CELL_PX, CELL_PX, CELL_PX)
			if not r.intersects(area):
				continue
			out.append({"x": x, "z": z, "rect": r, "kind": c})
	return out


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, AREA.size), C_BG)
	if not _p.is_empty() and not _visited.is_empty():
		_draw_cells()
		_draw_player()
	_draw_header()
	draw_rect(Rect2(Vector2.ZERO, AREA.size), C_FRAME, false, 2.0)


func _draw_cells() -> void:
	for cr: Dictionary in cell_rects(_visited, _cells, _p):
		var x: int = cr["x"]
		var z: int = cr["z"]
		var c: int = cr["kind"]
		var r: Rect2 = cr["rect"]
		draw_rect(r, C_FLOOR)
		for d: Array in DIRS:
			if _cell(x + d[0], z + d[1]) != Grid.SOLID:
				continue
			match d:
				[1, 0]:
					draw_line(Vector2(r.end.x, r.position.y), r.end, C_WALL, 1.0)
				[-1, 0]:
					draw_line(r.position, Vector2(r.position.x, r.end.y), C_WALL, 1.0)
				[0, 1]:
					draw_line(r.position, Vector2(r.end.x, r.position.y), C_WALL, 1.0)
				[0, -1]:
					draw_line(Vector2(r.position.x, r.end.y), r.end, C_WALL, 1.0)
		match c:
			Grid.DOOR_CLOSED:
				draw_rect(r.grow(-2.0), C_DOOR_CLOSED)
			Grid.DOOR_OPEN:
				draw_rect(r.grow(-2.0), C_DOOR_OPEN)
			Grid.DOOR_LOCKED:
				draw_rect(r.grow(-2.0), C_DOOR_LOCKED)
			Grid.EXIT:
				draw_circle(r.get_center(), 3.0, C_EXIT)


func _draw_header() -> void:
	var font: Font = ThemeDB.fallback_font
	draw_string(font, HEADER_POS, HEADER_TEXT, HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE, C_FRAME)
	draw_string(font, NORTH_POS, "N", HORIZONTAL_ALIGNMENT_LEFT, -1, HEADER_FONT_SIZE, C_FRAME)
	draw_colored_polygon(PackedVector2Array([
		Vector2(NORTH_ARROW_X, 22.0), Vector2(NORTH_ARROW_X + 3.0, 28.0), Vector2(NORTH_ARROW_X - 3.0, 28.0),
	]), C_FRAME)


func _draw_player() -> void:
	var th: float = TAU * float(_p.get("angle", 0)) / 4096.0
	var fwd := Vector2(cos(th), -sin(th))
	var right := Vector2(-fwd.y, fwd.x)
	var tip: Vector2 = CENTER + fwd * 6.0
	var base: Vector2 = CENTER - fwd * 3.0
	draw_colored_polygon(PackedVector2Array([tip, base + right * 3.0, base - right * 3.0]), C_PLAYER)
