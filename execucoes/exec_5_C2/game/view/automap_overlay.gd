extends Control
## Automapa translúcido (Control no CanvasLayer 3). Tab alterna `visible`; não pausa,
## não consome input e não chama nada que escreva no núcleo. Norte = +Z da simulação (topo).

signal toggled(open: bool)

const PX: int = 6
const CENTER: Vector2 = Vector2(320, 156)
const PARCH: Rect2 = Rect2(64, 12, 512, 288)
const C_PARCH: Color = Color("#d8c08c")
const C_PARCH_EDGE: Color = Color("#5a4026")
const C_FLOOR: Color = Color("#c8ac78")
const C_WALL: Color = Color("#3a2410")
const C_DOOR: Color = Color("#8b5a2b")
const C_LOCKED: Color = Color("#c01818")
const C_EXIT: Color = Color("#9a30e0")
const C_PLAYER: Color = Color("#202020")

var _grid: Grid
var _visited: PackedByteArray
var _pcx: int = 0
var _pcz: int = 0
var _angle: int = 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_map"):
		visible = not visible
		toggled.emit(visible)
		if visible:
			queue_redraw()


func refresh(world: WorldSim) -> void:
	_grid = world.get_grid()
	_visited = world.get_visited()
	var pos: Array = world.get_player_pos()
	_pcx = floori(pos[0] / float(Grid.CELL))
	_pcz = floori(pos[1] / float(Grid.CELL))
	_angle = world.get_angle()
	if visible:
		queue_redraw()


func _seen(cx: int, cz: int) -> bool:
	return cx >= 0 and cz >= 0 and cx < Grid.W and cz < Grid.H and _visited[cz * Grid.W + cx] == 1


## Centro da célula na tela.
func cell_to_screen(cx: int, cz: int) -> Vector2:
	return CENTER + Vector2((cx - _pcx) * PX, -(cz - _pcz) * PX)


func _draw() -> void:
	draw_rect(PARCH, C_PARCH)
	draw_rect(PARCH, C_PARCH_EDGE, false, 2.0)
	if _grid == null:
		return
	var half: float = PX / 2.0
	var inner: Rect2 = PARCH.grow(-2)
	for cz in range(Grid.H):
		for cx in range(Grid.W):
			if not _seen(cx, cz):
				continue
			var code: int = _grid.get_cell(cx, cz)
			if code == Grid.SOLID:
				continue
			var c: Vector2 = cell_to_screen(cx, cz)
			var r := Rect2(c - Vector2(half, half), Vector2(PX, PX))
			if not inner.encloses(r):
				continue
			draw_rect(r, C_FLOOR)
			# bordas com SOLID: norte (+z) em cima, sul (-z) embaixo
			if _grid.get_cell(cx, cz + 1) == Grid.SOLID:
				draw_line(r.position, r.position + Vector2(PX, 0), C_WALL, 1.0)
			if _grid.get_cell(cx, cz - 1) == Grid.SOLID:
				draw_line(r.end - Vector2(PX, 0), r.end, C_WALL, 1.0)
			if _grid.get_cell(cx - 1, cz) == Grid.SOLID:
				draw_line(r.position, r.position + Vector2(0, PX), C_WALL, 1.0)
			if _grid.get_cell(cx + 1, cz) == Grid.SOLID:
				draw_line(r.end - Vector2(0, PX), r.end, C_WALL, 1.0)
			var door := Rect2(c - Vector2(2, 2), Vector2(4, 4))
			match code:
				Grid.DOOR_CLOSED:
					draw_rect(door, C_DOOR)
				Grid.DOOR_OPEN:
					draw_rect(door, C_DOOR, false, 1.0)
				Grid.DOOR_LOCKED:
					draw_rect(door, C_LOCKED)
				Grid.EXIT:
					draw_colored_polygon(PackedVector2Array([
						c + Vector2(0, -2.5), c + Vector2(2.5, 0), c + Vector2(0, 2.5), c + Vector2(-2.5, 0)]), C_EXIT)
	var a: float = TAU * _angle / 4096.0
	var f := Vector2(cos(a), -sin(a))
	var s := Vector2(-f.y, f.x)
	draw_colored_polygon(PackedVector2Array([
		CENTER + f * 4.0, CENTER - f * 3.0 + s * 3.0, CENTER - f * 3.0 - s * 3.0]), C_PLAYER)
