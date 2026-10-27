extends Node3D
## Malha da masmorra a partir da grade (somente leitura do núcleo).
## Célula (cx, cz) ocupa X ∈ [2cx, 2cx+2], Z ∈ [-2(cz+1), -2cz]; paredes de 3 m.

const CELL_M: float = 2.0
const WALL_H: float = 3.0
const TORCH_FPS: float = 8.0
const CEILING_GAIN: Color = Color(5.0, 4.6, 4.2)
## Portal de Fuga: altura visível 2,20 m com a base no piso; pulso de 2 s.
const PORTAL_M: float = 2.20
const PORTAL_PULSE_S: float = 2.0

var _grid: Grid = null
var _door_nodes: Dictionary = {}   # id -> Node3D
var _door_state: Dictionary = {}   # id -> estado
var _mats: Dictionary = {}
var _torches: Array = []
var _torch_frames: Array = []
var _portal: Sprite3D = null


static func make_material(tex: Texture2D) -> StandardMaterial3D:
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = tex
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	return m


func build(grid: Grid) -> void:
	_grid = grid
	for c: Node in get_children():
		c.queue_free()
	_door_nodes.clear()
	_door_state.clear()
	_torches.clear()
	_portal = null
	for id: String in ["wall.dungeon.stone01", "wall.dungeon.stone02", "floor.dungeon.01",
			"ceiling.dungeon.01", "door.closed", "door.locked", "door.open"]:
		_mats[id] = make_material(AssetResolver.resolve(id))
	# O teto do perfil free é quase preto (média 15/255): o problema do "teto preto
	# chapado" vinha da textura, não do culling (o material já é CULL_DISABLED e o
	# quad do teto tem normal -Y com winding oposto ao do piso). Ganho de albedo
	# só no teto, para a variação da textura aparecer.
	(_mats["ceiling.dungeon.01"] as StandardMaterial3D).albedo_color = CEILING_GAIN
	_torch_frames = []
	for i: int in range(4):
		_torch_frames.append(AssetResolver.resolve("torch.%d" % i))
	_build_static_mesh()
	for d: Dictionary in grid.doors():
		_set_door(int(d["id"]), int(d["cell_x"]), int(d["cell_z"]), int(d["state"]))
	_build_exit()
	_build_torches()


## Atualiza portas a partir de get_state().dungeon.doors; devolve ids que abriram
## (fechadas ou trancadas que passaram a abertas, pelo mesmo caminho visual).
func update_doors(doors: Array) -> Array:
	var opened: Array = []
	for d: Dictionary in doors:
		var id: int = int(d["id"])
		var st: int = int(d["state"])
		if _door_state.get(id, -1) != st:
			var was: int = int(_door_state.get(id, -1))
			if (was == Grid.DOOR_CLOSED or was == Grid.DOOR_LOCKED) and st == Grid.DOOR_OPEN:
				opened.append(id)
			_set_door(id, int(d["cell_x"]), int(d["cell_z"]), st)
	return opened


func door_count() -> int:
	return _door_nodes.size()


func _process(_dt: float) -> void:
	if _portal != null:
		var k: float = 0.5 + 0.5 * sin(TAU * float(Time.get_ticks_msec()) / 1000.0 / PORTAL_PULSE_S)
		var v: float = lerpf(0.8, 1.0, k)
		_portal.modulate = Color(v, v, v, 1.0)
	if _torches.is_empty():
		return
	var frame: int = int(float(Time.get_ticks_msec()) / 1000.0 * TORCH_FPS) % 4
	for t: Sprite3D in _torches:
		t.texture = _torch_frames[frame]


func _is_room_cell(cx: int, cz: int) -> bool:
	for r: Dictionary in _grid.rooms:
		if DungeonGen.in_room(r, cx, cz):
			return true
	return false


func _build_static_mesh() -> void:
	var st_room: SurfaceTool = SurfaceTool.new()
	var st_corr: SurfaceTool = SurfaceTool.new()
	var st_floor: SurfaceTool = SurfaceTool.new()
	var st_ceil: SurfaceTool = SurfaceTool.new()
	for st: SurfaceTool in [st_room, st_corr, st_floor, st_ceil]:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cz: int in range(Grid.H):
		for cx: int in range(Grid.W):
			if _grid.get_cell(cx, cz) == Grid.SOLID:
				continue
			var x0: float = CELL_M * cx
			var x1: float = x0 + CELL_M
			var z0: float = -CELL_M * (cz + 1)  # lado norte (sim +z)
			var z1: float = -CELL_M * cz        # lado sul
			_quad(st_floor, Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3(x0, 0, z0),
				Vector3.UP, 1.0, 1.0)
			_quad(st_ceil, Vector3(x0, WALL_H, z0), Vector3(x1, WALL_H, z0), Vector3(x1, WALL_H, z1),
				Vector3(x0, WALL_H, z1), Vector3.DOWN, 1.0, 1.0)
			var wst: SurfaceTool = st_room if _is_room_cell(cx, cz) else st_corr
			if _grid.get_cell(cx + 1, cz) == Grid.SOLID:
				_wall(wst, Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3.LEFT)
			if _grid.get_cell(cx - 1, cz) == Grid.SOLID:
				_wall(wst, Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3.RIGHT)
			if _grid.get_cell(cx, cz + 1) == Grid.SOLID:
				_wall(wst, Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.BACK)
			if _grid.get_cell(cx, cz - 1) == Grid.SOLID:
				_wall(wst, Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.FORWARD)
	var mesh: ArrayMesh = ArrayMesh.new()
	var pairs: Array = [[st_room, "wall.dungeon.stone01"], [st_corr, "wall.dungeon.stone02"],
		[st_floor, "floor.dungeon.01"], [st_ceil, "ceiling.dungeon.01"]]
	for p: Array in pairs:
		var st: SurfaceTool = p[0]
		var arrays: Array = st.commit_to_arrays()
		# Superfície vazia (ex.: sala de teste sem corredores) devolve null no vértice.
		var verts: Variant = arrays[Mesh.ARRAY_VERTEX]
		if verts == null or (verts as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[p[1]])
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "DungeonMesh"
	mi.mesh = mesh
	add_child(mi)


## Parede de 3 m sobre a aresta a->b; UV: 1 repetição por 2 m, 1,5 na vertical (16 px/m).
func _wall(st: SurfaceTool, a: Vector3, b: Vector3, n: Vector3) -> void:
	var up: Vector3 = Vector3(0, WALL_H, 0)
	_quad(st, a, b, b + up, a + up, n, 1.0, WALL_H / CELL_M)


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3,
		u_rep: float, v_rep: float) -> void:
	var uv_a: Vector2 = Vector2(0, v_rep)
	var uv_b: Vector2 = Vector2(u_rep, v_rep)
	var uv_c: Vector2 = Vector2(u_rep, 0)
	var uv_d: Vector2 = Vector2(0, 0)
	for v: Array in [[a, uv_a], [b, uv_b], [c, uv_c], [a, uv_a], [c, uv_c], [d, uv_d]]:
		st.set_normal(n)
		st.set_uv(v[1])
		st.add_vertex(v[0])


func _cell_center(cx: int, cz: int) -> Vector3:
	return Vector3(CELL_M * cx + 1.0, 0.0, -CELL_M * cz - 1.0)


func _set_door(id: int, cx: int, cz: int, st: int) -> void:
	if _door_nodes.has(id):
		var old: Node3D = _door_nodes[id]
		remove_child(old)
		old.queue_free()
	var root: Node3D = Node3D.new()
	root.name = "Door_%d" % id
	root.position = _cell_center(cx, cz)
	# Corredor ao longo de X se leste/oeste são passáveis.
	var along_x: bool = _grid.get_cell(cx + 1, cz) != Grid.SOLID and _grid.get_cell(cx - 1, cz) != Grid.SOLID
	if st == Grid.DOOR_OPEN:
		# Batentes nas paredes laterais.
		for side: int in [-1, 1]:
			var jamb: MeshInstance3D = _panel("door.open")
			if along_x:
				jamb.position = Vector3(0, WALL_H / 2.0, side * (CELL_M / 2.0 - 0.02))
			else:
				jamb.position = Vector3(side * (CELL_M / 2.0 - 0.02), WALL_H / 2.0, 0)
				jamb.rotation.y = PI / 2.0
			root.add_child(jamb)
	else:
		var panel: MeshInstance3D = _panel("door.locked" if st == Grid.DOOR_LOCKED else "door.closed")
		panel.position = Vector3(0, WALL_H / 2.0, 0)
		if along_x:
			panel.rotation.y = PI / 2.0
		root.add_child(panel)
	add_child(root)
	_door_nodes[id] = root
	_door_state[id] = st


func _panel(tex_id: String) -> MeshInstance3D:
	var q: QuadMesh = QuadMesh.new()
	q.size = Vector2(CELL_M, WALL_H)
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = q
	mi.material_override = _mats[tex_id]
	return mi


func _build_exit() -> void:
	for cz: int in range(Grid.H):
		for cx: int in range(Grid.W):
			if _grid.get_cell(cx, cz) != Grid.EXIT:
				continue
			var s: Sprite3D = Sprite3D.new()
			s.name = "ExitPortal"
			s.texture = AssetResolver.resolve("exit.portal")
			s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
			s.shaded = false
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.centered = true
			# Escala pela área opaca (margens transparentes) e base no piso.
			var used: Rect2i = Rect2i(0, 0, 32, 32)
			if s.texture != null:
				used = s.texture.get_image().get_used_rect()
			s.pixel_size = PORTAL_M / float(used.size.y)
			s.position = _cell_center(cx, cz) + Vector3(0, float(used.end.y - 16) * s.pixel_size, 0)
			add_child(s)
			_portal = s


## Uma tocha por sala, na primeira parede norte (sem RNG do núcleo).
func _build_torches() -> void:
	for r: Dictionary in _grid.rooms:
		var zn: int = int(r["z"]) + int(r["h"])  # linha sólida ao norte da sala
		for cx: int in range(int(r["x"]), int(r["x"]) + int(r["w"])):
			if _grid.get_cell(cx, zn) != Grid.SOLID or _grid.get_cell(cx, zn - 1) != Grid.FLOOR:
				continue
			var t: Sprite3D = Sprite3D.new()
			t.name = "Torch_%d" % int(r["id"])
			t.texture = _torch_frames[0]
			t.pixel_size = 0.025
			t.shaded = false
			t.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			t.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			t.position = Vector3(CELL_M * cx + 1.0, 1.9, -CELL_M * zn + 0.06)
			add_child(t)
			_torches.append(t)
			var l: OmniLight3D = OmniLight3D.new()
			l.light_color = Color(1.0, 0.7, 0.4)
			l.light_energy = 1.2
			l.omni_range = 5.0
			l.position = t.position + Vector3(0, 0, 0.3)
			add_child(l)
			break
