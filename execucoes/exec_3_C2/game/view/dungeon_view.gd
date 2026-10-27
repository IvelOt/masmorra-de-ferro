class_name DungeonView
extends Node3D
## Malha da masmorra construída lendo a grade (somente leitura do núcleo).
## Reconstrói só quando grid_sha256 muda.

const Grid = preload("res://sim/grid.gd")
const AssetLib = preload("res://view/asset_lib.gd")

const WALL_HEIGHT: float = 2.0
const CELL_M: float = 2.0
const CEILING_ALBEDO: Color = Color(1.8, 1.8, 1.8)

const SURFACES: Array[String] = ["floor", "ceiling", "wall1", "wall2", "door_closed", "door_locked"]
const SURFACE_ASSET: Dictionary = {
	"floor": "floor.dungeon.01",
	"ceiling": "ceiling.dungeon.01",
	"wall1": "wall.dungeon.stone01",
	"wall2": "wall.dungeon.stone02",
	"door_closed": "door.closed",
	"door_locked": "door.locked",
}

var _sha: String = ""
var _materials: Dictionary = {}
var _mesh_instance: MeshInstance3D
var _exit_sprite: Sprite3D


func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_exit_sprite = Sprite3D.new()
	_exit_sprite.texture = load_texture("exit.portal")
	_exit_sprite.pixel_size = 0.05
	_exit_sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	_exit_sprite.shaded = false
	_exit_sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	_exit_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_exit_sprite.visible = false
	add_child(_exit_sprite)
	for s: String in SURFACES:
		var m := StandardMaterial3D.new()
		m.albedo_texture = load_texture(SURFACE_ASSET[s])
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		if s == "ceiling":
			# C6 (plano R4): teto mais claro; demais superfícies continuam brancas
			m.albedo_color = CEILING_ALBEDO
		_materials[s] = m


func get_material(surface: String) -> StandardMaterial3D:
	return _materials.get(surface)


func load_texture(id: String) -> Texture2D:
	return AssetLib.load_texture(id)


func refresh(cells: PackedByteArray, sha: String) -> void:
	if sha == _sha:
		return
	_sha = sha
	_build(cells)


static func _cell(cells: PackedByteArray, x: int, z: int) -> int:
	if not Grid.in_bounds(x, z):
		return Grid.SOLID
	return cells[z * Grid.SIZE + x]


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var uvs: Array[Vector2] = [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var vs: Array[Vector3] = [a, b, c, d]
	for i: int in [0, 1, 2, 0, 2, 3]:
		st.set_normal(n)
		st.set_uv(uvs[i])
		st.add_vertex(vs[i])


func _face_surface(code: int, nx: int, nz: int) -> String:
	match code:
		Grid.DOOR_CLOSED:
			return "door_closed"
		Grid.DOOR_LOCKED:
			return "door_locked"
		Grid.SOLID:
			return "wall2" if (nx * 7 + nz * 13) % 5 == 0 else "wall1"
	return ""


func _build(cells: PackedByteArray) -> void:
	var tools: Dictionary = {}
	var counts: Dictionary = {}
	for s: String in SURFACES:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		tools[s] = st
		counts[s] = 0
	var H: float = WALL_HEIGHT
	_exit_sprite.visible = false
	for z in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var c: int = _cell(cells, x, z)
			if not Grid.is_passable(c):
				continue
			# célula (x, z) ocupa X em [2x, 2x+2], Z em [-2(z+1), -2z]
			var x0: float = CELL_M * x
			var x1: float = x0 + CELL_M
			var z0: float = -CELL_M * (z + 1)
			var z1: float = -CELL_M * z
			_quad(tools["floor"], Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1), Vector3.UP)
			counts["floor"] += 1
			_quad(tools["ceiling"], Vector3(x0, H, z1), Vector3(x1, H, z1), Vector3(x1, H, z0), Vector3(x0, H, z0), Vector3.DOWN)
			counts["ceiling"] += 1
			# vizinhos: +x, -x, +z (sim) = -Z (Godot), -z (sim) = +Z (Godot)
			var faces: Array = [
				[x + 1, z, Vector3(x1, H, z1), Vector3(x1, H, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3.LEFT],
				[x - 1, z, Vector3(x0, H, z0), Vector3(x0, H, z1), Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3.RIGHT],
				[x, z + 1, Vector3(x0, H, z0), Vector3(x1, H, z0), Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.BACK],
				[x, z - 1, Vector3(x1, H, z1), Vector3(x0, H, z1), Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.FORWARD],
			]
			for f: Array in faces:
				var s: String = _face_surface(_cell(cells, f[0], f[1]), f[0], f[1])
				if s.is_empty():
					continue
				_quad(tools[s], f[2], f[3], f[4], f[5], f[6])
				counts[s] += 1
			if c == Grid.EXIT:
				_exit_sprite.position = Vector3(x0 + CELL_M / 2.0, 0.8, z0 + CELL_M / 2.0)
				_exit_sprite.visible = true
	var mesh := ArrayMesh.new()
	for s: String in SURFACES:
		if counts[s] == 0:
			continue
		var st: SurfaceTool = tools[s]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _materials[s])
	_mesh_instance.mesh = mesh
