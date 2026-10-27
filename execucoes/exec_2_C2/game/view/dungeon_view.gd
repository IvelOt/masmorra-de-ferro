extends Node3D
## Malha da masmorra a partir da grade do snapshot (somente leitura).
##
## Conversão núcleo -> Godot (plano §5.1; a view espelha Z):
##   posição:      godot.x = pos_x / 1024.0, godot.z = -pos_z / 1024.0, godot.y = 0 (pés)
##   célula:       x ∈ [2cx, 2cx+2], z ∈ [-2(cz+1), -2cz]
##   yaw:          rotation.y = TAU * angle / 4096.0 - PI / 2

const AssetResolver = preload("res://view/asset_resolver.gd")

const GRID_W: int = 64
const GRID_H: int = 64
const SOLID: int = 0
const DOOR_CLOSED: int = 2
const DOOR_OPEN: int = 3
const DOOR_LOCKED: int = 4
const EXIT: int = 5
const CELL_M: float = 2.0
const HEIGHT_M: float = 3.0

var _resolver: AssetResolver = null
var _door_types: Dictionary = {}
var _materials: Dictionary = {}


static func cell_rect_x0(cx: int) -> float:
	return CELL_M * cx


static func cell_rect_z0(cz: int) -> float:
	return -CELL_M * (cz + 1)


func build(snapshot: Dictionary, resolver: AssetResolver) -> void:
	_resolver = resolver
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_door_types.clear()
	var cells: PackedByteArray = snapshot.cells
	var st_floor: SurfaceTool = _new_st()
	var st_ceil: SurfaceTool = _new_st()
	var st_wall: Array = [_new_st(), _new_st()]
	for cz in range(GRID_H):
		for cx in range(GRID_W):
			if _cell(cells, cx, cz) == SOLID:
				continue
			var x0: float = cell_rect_x0(cx)
			var x1: float = x0 + CELL_M
			var z0: float = cell_rect_z0(cz)
			var z1: float = z0 + CELL_M
			_quad(st_floor, [Vector3(x0, 0, z0), Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3(x0, 0, z1)],
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector3.UP)
			_quad(st_ceil, [Vector3(x0, HEIGHT_M, z0), Vector3(x1, HEIGHT_M, z0), Vector3(x1, HEIGHT_M, z1), Vector3(x0, HEIGHT_M, z1)],
				[Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)], Vector3.DOWN)
			# vizinhos no núcleo: +cx -> +X; -cx -> -X; +cz -> -Z (Godot); -cz -> +Z (Godot)
			if _cell(cells, cx + 1, cz) == SOLID:
				_wall(st_wall[(cx + 1 + cz) & 1], Vector3(x1, 0, z0), Vector3(x1, 0, z1), Vector3.LEFT)
			if _cell(cells, cx - 1, cz) == SOLID:
				_wall(st_wall[(cx - 1 + cz) & 1], Vector3(x0, 0, z1), Vector3(x0, 0, z0), Vector3.RIGHT)
			if _cell(cells, cx, cz + 1) == SOLID:
				_wall(st_wall[(cx + cz + 1) & 1], Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.BACK)
			if _cell(cells, cx, cz - 1) == SOLID:
				_wall(st_wall[(cx + cz - 1) & 1], Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.FORWARD)
			if _cell(cells, cx, cz) == EXIT:
				_add_exit_sprite(cx, cz)
	var mesh: ArrayMesh = ArrayMesh.new()
	var surfaces: Array = [
		[st_floor, "floor.dungeon.01"],
		[st_ceil, "ceiling.dungeon.01"],
		[st_wall[0], "wall.dungeon.stone01"],
		[st_wall[1], "wall.dungeon.stone02"],
	]
	for s: Array in surfaces:
		var st: SurfaceTool = s[0]
		st.commit(mesh)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _material(s[1]))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Level"
	mi.mesh = mesh
	add_child(mi)
	update_doors(snapshot)


## Recria só as portas cujo tipo mudou desde o último snapshot.
func update_doors(snapshot: Dictionary) -> void:
	for d: Dictionary in snapshot.doors:
		var id: int = d.id
		var t: int = d.type
		if _door_types.get(id, -1) == t:
			continue
		_door_types[id] = t
		var old: Node = get_node_or_null("Door_%d" % id)
		if old != null:
			remove_child(old)
			old.queue_free()
		if t == DOOR_CLOSED or t == DOOR_LOCKED:
			add_child(_door_block(id, d.cx, d.cz, t))


func _door_block(id: int, cx: int, cz: int, t: int) -> MeshInstance3D:
	var st: SurfaceTool = _new_st()
	var x0: float = cell_rect_x0(cx)
	var x1: float = x0 + CELL_M
	var z0: float = cell_rect_z0(cz)
	var z1: float = z0 + CELL_M
	var uv: Array = [Vector2(0, 1), Vector2(1, 1), Vector2(1, 0), Vector2(0, 0)]
	for f: Array in [
		[Vector3(x1, 0, z1), Vector3(x1, 0, z0), Vector3.RIGHT],
		[Vector3(x0, 0, z0), Vector3(x0, 0, z1), Vector3.LEFT],
		[Vector3(x0, 0, z1), Vector3(x1, 0, z1), Vector3.BACK],
		[Vector3(x1, 0, z0), Vector3(x0, 0, z0), Vector3.FORWARD],
	]:
		var a: Vector3 = f[0]
		var b: Vector3 = f[1]
		var up: Vector3 = Vector3(0, HEIGHT_M, 0)
		_quad(st, [a, b, b + up, a + up], uv, f[2])
	var mesh: ArrayMesh = st.commit()
	mesh.surface_set_material(0, _material("door.locked" if t == DOOR_LOCKED else "door.closed"))
	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.name = "Door_%d" % id
	mi.mesh = mesh
	return mi


func _add_exit_sprite(cx: int, cz: int) -> void:
	var sp: Sprite3D = Sprite3D.new()
	sp.name = "ExitPortal"
	sp.texture = _resolver.texture("exit.portal")
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.pixel_size = 0.05
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.position = Vector3(cell_rect_x0(cx) + CELL_M * 0.5, 0.8, cell_rect_z0(cz) + CELL_M * 0.5)
	add_child(sp)


## Parede de 3 m sobre a aresta a->b; textura 2 m × 2 m (v ∈ [0, 1,5]).
func _wall(st: SurfaceTool, a: Vector3, b: Vector3, normal: Vector3) -> void:
	var up: Vector3 = Vector3(0, HEIGHT_M, 0)
	var vmax: float = HEIGHT_M / CELL_M
	_quad(st, [a, b, b + up, a + up], [Vector2(0, vmax), Vector2(1, vmax), Vector2(1, 0), Vector2(0, 0)], normal)


## Acrescenta um quad (dois triângulos) com face frontal voltada para `normal`
## (Godot usa ordem horária para a face frontal; a ordem é corrigida aqui).
func _quad(st: SurfaceTool, v: Array, uv: Array, normal: Vector3) -> void:
	var order: Array = [0, 1, 2, 0, 2, 3]
	var a: Vector3 = v[0]
	var b: Vector3 = v[1]
	var c: Vector3 = v[2]
	if (b - a).cross(c - a).dot(normal) > 0.0:
		order = [0, 2, 1, 0, 3, 2]
	for i: int in order:
		st.set_normal(normal)
		st.set_uv(uv[i])
		st.add_vertex(v[i])


func _new_st() -> SurfaceTool:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	return st


func _cell(cells: PackedByteArray, cx: int, cz: int) -> int:
	if cx < 0 or cz < 0 or cx >= GRID_W or cz >= GRID_H:
		return SOLID
	return cells[cz * GRID_W + cx]


func _material(id: String) -> StandardMaterial3D:
	if _materials.has(id):
		return _materials[id]
	var m: StandardMaterial3D = StandardMaterial3D.new()
	m.albedo_texture = _resolver.texture(id)
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.texture_repeat = true
	m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	_materials[id] = m
	return m
