class_name DungeonView
extends Node3D
## Malha da masmorra a partir da grade (somente leitura). Um ArrayMesh por
## material; painéis de porta e o portal são nós próprios para que a troca de
## estado de uma porta não reconstrua a masmorra.

const CELL_M: float = 2.0
const WALL_H: float = 3.0
const DOOR_H: float = 2.0

var _door_panels: Dictionary = {}   # index da célula -> MeshInstance3D
var _door_types: Dictionary = {}    # index da célula -> último tipo visto
var _materials: Dictionary = {}


func build(grid: Grid) -> void:
	for c in get_children():
		c.queue_free()
	_door_panels.clear()
	_door_types.clear()
	var tools: Dictionary = {}
	for id in ["wall.dungeon.stone01", "wall.dungeon.stone02", "floor.dungeon.01", "ceiling.dungeon.01"]:
		var st: SurfaceTool = SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[id] = st
	var dxs: Array[int] = [1, -1, 0, 0]
	var dzs: Array[int] = [0, 0, 1, -1]
	for cz in range(Grid.SIZE):
		for cx in range(Grid.SIZE):
			var t: int = grid.get_cell(cx, cz)
			if t == Grid.SOLID:
				continue
			var x0: float = cx * CELL_M
			var x1: float = x0 + CELL_M
			var z0: float = -cz * CELL_M          # borda sim cz (Godot z = -2cz)
			var z1: float = z0 - CELL_M           # borda sim cz+1
			_quad(tools["floor.dungeon.01"], Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3.UP, 1.0, 1.0)
			if Grid.is_door_type(t):
				_build_door(grid, cx, cz, t, tools["wall.dungeon.stone01"])
			else:
				_quad(tools["ceiling.dungeon.01"], Vector3(x0, WALL_H, z0), Vector3(x1, WALL_H, z0), Vector3(x1, WALL_H, z1), Vector3(x0, WALL_H, z1), Vector3.DOWN, 1.0, 1.0)
			for k in range(4):
				var nx: int = cx + dxs[k]
				var nz: int = cz + dzs[k]
				if grid.get_cell(nx, nz) != Grid.SOLID:
					continue
				var wid: String = "wall.dungeon.stone02" if (nx * 7 + nz * 13) % 5 == 0 else "wall.dungeon.stone01"
				_wall_face(tools[wid], cx, cz, dxs[k], dzs[k], 0.0, WALL_H)
			if t == Grid.EXIT:
				_add_portal(cx, cz)
	for id: String in tools:
		var mesh: ArrayMesh = (tools[id] as SurfaceTool).commit()
		if mesh.get_surface_count() == 0:
			continue
		var mi: MeshInstance3D = MeshInstance3D.new()
		mi.name = id.replace(".", "_")
		mi.mesh = mesh
		mi.material_override = _material(id)
		add_child(mi)


## Mostra/esconde painéis conforme o tipo atual das portas (lista do snapshot).
func sync_doors(doors: Array) -> void:
	for d: Dictionary in doors:
		var idx: int = int(d.cz) * Grid.SIZE + int(d.cx)
		var t: int = int(d.state)
		if _door_types.get(idx, -1) == t:
			continue
		_door_types[idx] = t
		var panel: MeshInstance3D = _door_panels.get(idx)
		if panel == null:
			continue
		panel.visible = t != Grid.DOOR_OPEN
		if t != Grid.DOOR_OPEN:
			panel.material_override = _material("door.locked" if t == Grid.DOOR_LOCKED else "door.closed")


func _build_door(grid: Grid, cx: int, cz: int, t: int, lintel: SurfaceTool) -> void:
	var along_x: bool = grid.get_cell(cx + 1, cz) != Grid.SOLID and grid.get_cell(cx - 1, cz) != Grid.SOLID
	# verga: face inferior e as duas faces voltadas para a passagem
	var x0: float = cx * CELL_M
	var x1: float = x0 + CELL_M
	var z0: float = -cz * CELL_M
	var z1: float = z0 - CELL_M
	_quad(lintel, Vector3(x0, DOOR_H, z0), Vector3(x1, DOOR_H, z0), Vector3(x1, DOOR_H, z1), Vector3(x0, DOOR_H, z1), Vector3.DOWN, 1.0, 0.5)
	if along_x:
		_wall_face(lintel, cx + 1, cz, -1, 0, DOOR_H, WALL_H)
		_wall_face(lintel, cx - 1, cz, 1, 0, DOOR_H, WALL_H)
	else:
		_wall_face(lintel, cx, cz + 1, 0, -1, DOOR_H, WALL_H)
		_wall_face(lintel, cx, cz - 1, 0, 1, DOOR_H, WALL_H)
	# painel no plano médio, perpendicular à passagem
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var xm: float = x0 + CELL_M * 0.5
	var zm: float = z0 - CELL_M * 0.5
	if along_x:
		_quad(st, Vector3(xm, DOOR_H, z0), Vector3(xm, DOOR_H, z1), Vector3(xm, 0, z1), Vector3(xm, 0, z0), Vector3.LEFT, 1.0, 1.0)
	else:
		_quad(st, Vector3(x0, DOOR_H, zm), Vector3(x1, DOOR_H, zm), Vector3(x1, 0, zm), Vector3(x0, 0, zm), Vector3.BACK, 1.0, 1.0)
	var panel: MeshInstance3D = MeshInstance3D.new()
	panel.name = "door_%d_%d" % [cx, cz]
	panel.mesh = st.commit()
	panel.material_override = _material("door.locked" if t == Grid.DOOR_LOCKED else "door.closed")
	panel.visible = t != Grid.DOOR_OPEN
	add_child(panel)
	var idx: int = cz * Grid.SIZE + cx
	_door_panels[idx] = panel
	_door_types[idx] = t


## Face da célula aberta (cx, cz) voltada para a vizinha (cx+dx, cz+dz), entre y0 e y1.
func _wall_face(st: SurfaceTool, cx: int, cz: int, dx: int, dz: int, y0: float, y1: float) -> void:
	var x0: float = cx * CELL_M
	var x1: float = x0 + CELL_M
	var z0: float = -cz * CELL_M
	var z1: float = z0 - CELL_M
	var v: float = (y1 - y0) / CELL_M
	if dx == 1:
		_quad(st, Vector3(x1, y1, z0), Vector3(x1, y1, z1), Vector3(x1, y0, z1), Vector3(x1, y0, z0), Vector3.LEFT, 1.0, v)
	elif dx == -1:
		_quad(st, Vector3(x0, y1, z1), Vector3(x0, y1, z0), Vector3(x0, y0, z0), Vector3(x0, y0, z1), Vector3.RIGHT, 1.0, v)
	elif dz == 1:
		_quad(st, Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x1, y0, z1), Vector3.BACK, 1.0, v)
	else:
		_quad(st, Vector3(x0, y1, z0), Vector3(x1, y1, z0), Vector3(x1, y0, z0), Vector3(x0, y0, z0), Vector3.FORWARD, 1.0, v)


## Quad p0-p1-p2-p3 com UV (0,0)-(u,0)-(u,v)-(0,v).
func _quad(st: SurfaceTool, p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, n: Vector3, u: float, v: float) -> void:
	var pts: Array[Vector3] = [p0, p1, p2, p0, p2, p3]
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(u, 0), Vector2(u, v), Vector2(0, 0), Vector2(u, v), Vector2(0, v)]
	for i in range(6):
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(pts[i])


func _add_portal(cx: int, cz: int) -> void:
	var s: Sprite3D = Sprite3D.new()
	s.name = "exit_portal"
	s.texture = AssetResolver.texture("exit.portal")
	s.pixel_size = 0.0625
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	# base do portal no piso: (16 - 1 linha vazia) x 0,0625
	s.position = Vector3(cx * CELL_M + 1.0, 0.9375, -cz * CELL_M - 1.0)
	add_child(s)


func _material(id: String) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = AssetResolver.texture(id)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_materials[id] = m
	return m
