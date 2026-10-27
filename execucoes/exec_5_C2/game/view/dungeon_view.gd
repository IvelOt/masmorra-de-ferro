extends Node3D
## Malha da masmorra (ArrayMesh) construída a partir da grade; portas, portal e tochas.
## Somente leitura: consulta os getters de WorldSim e nunca escreve no núcleo.

const CELL_M: float = 2.0
const WALL_H: float = 3.0
const DOOR_H: float = 2.0
const TORCH_FPS: float = 8.0
const EXIT_DIM := Color(0.5, 0.5, 0.5)
const EXIT_PULSE_HZ: float = 1.5

var _world: WorldSim
var _mat_wall: StandardMaterial3D
var _mat_wall2: StandardMaterial3D
var _mat_floor: StandardMaterial3D
var _mat_ceil: StandardMaterial3D
var _mat_door: Dictionary = {}       # código da célula -> material
var _mat_lintel: StandardMaterial3D
var _door_nodes: Dictionary = {}     # id -> MeshInstance3D
var _door_state: Dictionary = {}     # id -> último código lido
var _torches: Array = []
var _torch_frames: Array = []
var _torch_t: float = 0.0
var _exit: Sprite3D = null
var _exit_ready: bool = false


static func _material(id: String, cull: BaseMaterial3D.CullMode, alpha: bool = false) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = AssetResolver.texture(id)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.cull_mode = cull
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.5
	return m


func build(world: WorldSim) -> void:
	_world = world
	for c in get_children():
		c.queue_free()
	_door_nodes.clear()
	_door_state.clear()
	_torches.clear()
	_mat_wall = _material("wall.dungeon.stone01", BaseMaterial3D.CULL_BACK)
	_mat_wall2 = _material("wall.dungeon.stone02", BaseMaterial3D.CULL_BACK)
	_mat_floor = _material("floor.dungeon.01", BaseMaterial3D.CULL_BACK)
	_mat_ceil = _material("ceiling.dungeon.01", BaseMaterial3D.CULL_BACK)
	_mat_lintel = _material("wall.dungeon.stone01", BaseMaterial3D.CULL_DISABLED)
	_mat_door = {
		Grid.DOOR_CLOSED: _material("door.closed", BaseMaterial3D.CULL_DISABLED),
		Grid.DOOR_LOCKED: _material("door.locked", BaseMaterial3D.CULL_DISABLED),
		Grid.DOOR_OPEN: _material("door.open", BaseMaterial3D.CULL_DISABLED, true),
	}
	_build_static(world.get_grid())
	_build_doors(world)
	_build_exit(world)
	_build_torches(world)


## Acrescenta um quad (a, b, c, d em sequência) com a face frontal voltada para `n`.
## O Godot usa ordem horária para faces frontais.
static func _quad(st: SurfaceTool, p: Array, uv: Array, n: Vector3) -> void:
	var order: Array = [0, 1, 2, 0, 2, 3]
	if (p[1] - p[0]).cross(p[2] - p[0]).dot(n) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_normal(n)
		st.set_uv(uv[i])
		st.add_vertex(p[i])


func _build_static(g: Grid) -> void:
	var sts: Array = []
	for _k in range(4):
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		sts.append(st)
	var wall_uv: Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1.5), Vector2(0, 1.5)]
	var flat_uv: Array = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var dirs: Array = [[0, -1], [1, 0], [0, 1], [-1, 0]]
	for cz in range(Grid.H):
		for cx in range(Grid.W):
			if not g.is_passable(cx, cz):
				continue
			var x0: float = cx * CELL_M
			var x1: float = x0 + CELL_M
			var z0: float = -cz * CELL_M          # borda sim z = cz
			var z1: float = z0 - CELL_M           # borda sim z = cz + 1
			_quad(sts[2], [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)], flat_uv, Vector3.UP)
			_quad(sts[3], [Vector3(x0, WALL_H, z0), Vector3(x1, WALL_H, z0), Vector3(x1, WALL_H, z1), Vector3(x0, WALL_H, z1)], flat_uv, Vector3.DOWN)
			for d: Array in dirs:
				var nx: int = cx + d[0]
				var nz: int = cz + d[1]
				if g.get_cell(nx, nz) != Grid.SOLID:
					continue
				var variant: int = 1 if ((nx * 7 + nz * 13) & 3) == 0 else 0
				var pts: Array
				var normal: Vector3
				if d[1] == -1:    # norte (sim z-1 -> Godot z maior)
					pts = [Vector3(x0, WALL_H, z0), Vector3(x1, WALL_H, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z0)]
					normal = Vector3(0, 0, -1)
				elif d[1] == 1:   # sul
					pts = [Vector3(x1, WALL_H, z1), Vector3(x0, WALL_H, z1), Vector3(x0, 0, z1), Vector3(x1, 0, z1)]
					normal = Vector3(0, 0, 1)
				elif d[0] == 1:   # leste
					pts = [Vector3(x1, WALL_H, z0), Vector3(x1, WALL_H, z1), Vector3(x1, 0, z1), Vector3(x1, 0, z0)]
					normal = Vector3(-1, 0, 0)
				else:             # oeste
					pts = [Vector3(x0, WALL_H, z1), Vector3(x0, WALL_H, z0), Vector3(x0, 0, z0), Vector3(x0, 0, z1)]
					normal = Vector3(1, 0, 0)
				_quad(sts[variant], pts, wall_uv, normal)
	var mesh := ArrayMesh.new()
	var mats: Array = [_mat_wall, _mat_wall2, _mat_floor, _mat_ceil]
	for i in range(4):
		var arrays: Array = (sts[i] as SurfaceTool).commit_to_arrays()
		if (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).is_empty():
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[i])
	var mi := MeshInstance3D.new()
	mi.name = "Level"
	mi.mesh = mesh
	add_child(mi)


func _build_doors(world: WorldSim) -> void:
	var root := Node3D.new()
	root.name = "Doors"
	add_child(root)
	var g: Grid = world.get_grid()
	for dr: Dictionary in world.get_doors():
		var cx: int = dr["cx"]
		var cz: int = dr["cz"]
		# corredor N-S (norte e sul atravessáveis): lâmina no plano z constante
		var ns: bool = g.is_passable(cx, cz - 1) and g.is_passable(cx, cz + 1)
		var h: float = CELL_M / 2.0
		var blade: Array
		var lintel: Array
		var n: Vector3
		if ns:
			blade = [Vector3(-h, DOOR_H, 0), Vector3(h, DOOR_H, 0), Vector3(h, 0, 0), Vector3(-h, 0, 0)]
			lintel = [Vector3(-h, WALL_H, 0), Vector3(h, WALL_H, 0), Vector3(h, DOOR_H, 0), Vector3(-h, DOOR_H, 0)]
			n = Vector3(0, 0, 1)
		else:
			blade = [Vector3(0, DOOR_H, h), Vector3(0, DOOR_H, -h), Vector3(0, 0, -h), Vector3(0, 0, h)]
			lintel = [Vector3(0, WALL_H, h), Vector3(0, WALL_H, -h), Vector3(0, DOOR_H, -h), Vector3(0, DOOR_H, h)]
			n = Vector3(1, 0, 0)
		var st_b := SurfaceTool.new()
		st_b.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st_b, blade, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], n)
		var st_l := SurfaceTool.new()
		st_l.begin(Mesh.PRIMITIVE_TRIANGLES)
		_quad(st_l, lintel, [Vector2(0, 0), Vector2(1, 0), Vector2(1, 0.5), Vector2(0, 0.5)], n)
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st_b.commit_to_arrays())
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, st_l.commit_to_arrays())
		mesh.surface_set_material(1, _mat_lintel)
		var mi := MeshInstance3D.new()
		mi.name = "door_%d" % dr["id"]
		mi.mesh = mesh
		mi.position = Vector3(cx * CELL_M + h, 0, -cz * CELL_M - h)
		mi.set_surface_override_material(0, _mat_door.get(dr["state"], _mat_door[Grid.DOOR_CLOSED]))
		root.add_child(mi)
		_door_nodes[dr["id"]] = mi
		_door_state[dr["id"]] = dr["state"]


func _build_exit(world: WorldSim) -> void:
	var ec: Dictionary = world.get_exit_cell()
	if ec["cx"] < 0:
		return
	var s := Sprite3D.new()
	s.name = "ExitPortal"
	s.texture = AssetResolver.texture("exit.portal")
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.shaded = false
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.pixel_size = 0.0625
	s.position = Vector3(ec["cx"] * CELL_M + 1.0, 1.0, -ec["cz"] * CELL_M - 1.0)
	s.modulate = EXIT_DIM
	add_child(s)
	_exit = s


## M6: portal apagado (0,5) sem a chave; aceso com pulso quando a saída está disponível.
func set_exit_ready(is_ready: bool) -> void:
	_exit_ready = is_ready
	if _exit != null and not is_ready:
		_exit.modulate = EXIT_DIM


## Uma tocha por sala na parede norte; coluna escolhida por função pura da posição.
func _build_torches(world: WorldSim) -> void:
	_torch_frames = []
	for k in range(4):
		_torch_frames.append(AssetResolver.texture("torch.%d" % k))
	var g: Grid = world.get_grid()
	for r: Dictionary in world.get_rooms():
		var w: int = r["w"]
		var start: int = (r["x"] * 7 + r["z"] * 13) % w
		for k in range(w):
			var cx: int = r["x"] + (start + k) % w
			if g.get_cell(cx, r["z"] - 1) != Grid.SOLID:
				continue
			var s := Sprite3D.new()
			s.name = "torch_%d" % r["id"]
			s.texture = _torch_frames[0]
			s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
			s.shaded = false
			s.pixel_size = 0.025
			s.position = Vector3(cx * CELL_M + 1.0, 1.4 + 0.4, -r["z"] * CELL_M - 0.02)
			add_child(s)
			_torches.append(s)
			break


## Atualiza portas comparando com o último estado lido (sem sinais). Retorna portas recém-abertas.
func refresh(world: WorldSim) -> Array:
	var opened: Array = []
	for dr: Dictionary in world.get_doors():
		var id: int = dr["id"]
		if _door_state.get(id, -1) != dr["state"]:
			if _door_state.get(id, -1) == Grid.DOOR_CLOSED and dr["state"] == Grid.DOOR_OPEN:
				opened.append(id)
			_door_state[id] = dr["state"]
			var mi: MeshInstance3D = _door_nodes[id]
			mi.set_surface_override_material(0, _mat_door.get(dr["state"], _mat_door[Grid.DOOR_CLOSED]))
	return opened


func _process(delta: float) -> void:
	_torch_t += delta
	if _exit != null and _exit_ready:
		var g: float = 1.0 + 0.3 * (0.5 + 0.5 * sin(_torch_t * TAU * EXIT_PULSE_HZ))
		_exit.modulate = Color(g, g, g)
	if _torches.is_empty():
		return
	var frame: int = int(_torch_t * TORCH_FPS) % 4
	for s: Sprite3D in _torches:
		s.texture = _torch_frames[frame]
