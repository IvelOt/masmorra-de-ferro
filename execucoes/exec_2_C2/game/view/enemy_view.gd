extends Node3D
## Entidades do snapshot em billboard (GDD §7.2; plano da rodada 3 §8.1): um Sprite3D `Enemy_<id>`
## por entidade, textura e tamanho por tipo, base no piso. Só lê o snapshot.
## Conversão núcleo -> Godot igual à de player_view.gd: (pos_x/1024, y, -pos_z/1024).
## O perfil `free` tem um quadro por tipo: as 8 direções usam o mesmo quadro, com flip_h quando o
## último deslocamento vai para a esquerda da câmera. Efeitos por estado só visuais (_process).

const AssetResolver = preload("res://view/asset_resolver.gd")

const UNITS_PER_M: float = 1024.0
## Por tipo: [textura, pixel_size]; quadro de 32 px -> altura 32·pixel_size, centro em 16·pixel_size.
const TYPE_LOOK: Dictionary = {
	"rat": ["enemy.rat", 0.03],
	"skeleton": ["enemy.skeleton", 0.05],
	"guardian": ["enemy.guardian", 0.065],
	"dummy": ["enemy.dummy", 0.05],
}
## Preparação (ticks) por tipo, para a interpolação do aviso de WINDUP (espelho de EnemySim.TYPES).
const WINDUP_TICKS: Dictionary = {"rat": 8, "skeleton": 18, "guardian": 30}
const FRAME_PX: float = 32.0
const HIT_FRAMES: int = 6
const DEAD_FRAMES: int = 30
const STRIKE_FRAMES: int = 8
const HIT_COLOR: Color = Color("#ff6060")
const DEAD_COLOR: Color = Color("#606060")
const WINDUP_COLOR: Color = Color("#ffd060")
const WINDUP_SCALE: float = 1.12
const BOB_AMP: float = 0.04
const BOB_HZ: float = 3.0
const STRIKE_LUNGE: float = 0.35
const DEAD_SINK: float = 0.6

var _resolver: AssetResolver = null
## id -> {base: Vector3, type, state, ticks, moving, hit, dead, strike, phase}
var _fx: Dictionary = {}


func setup(resolver: AssetResolver, snapshot: Dictionary) -> void:
	_resolver = resolver
	for c: Node in get_children():
		remove_child(c)
		c.queue_free()
	_fx.clear()
	for e: Dictionary in snapshot.enemies:
		add_child(_make_sprite(e))


static func pixel_size_of(type: String) -> float:
	return float(TYPE_LOOK.get(type, TYPE_LOOK.dummy)[1])


static func base_position(e: Dictionary) -> Vector3:
	var y: float = 16.0 * pixel_size_of(e.type)
	return Vector3(float(e.pos_x) / UNITS_PER_M, y, -float(e.pos_z) / UNITS_PER_M)


func _make_sprite(e: Dictionary) -> Sprite3D:
	var look: Array = TYPE_LOOK.get(e.type, TYPE_LOOK.dummy)
	var sp: Sprite3D = Sprite3D.new()
	sp.name = "Enemy_%d" % int(e.id)
	sp.texture = _resolver.texture(look[0])
	sp.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sp.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sp.shaded = false
	sp.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sp.pixel_size = look[1]
	sp.position = base_position(e)
	if e.state == "DEAD":
		sp.visible = false
	_fx[int(e.id)] = {"base": sp.position, "type": e.type, "state": e.state, "ticks": int(e.state_ticks),
		"moving": false, "hit": 0, "dead": 0, "strike": 0, "phase": 0.0}
	return sp


## Chamado uma vez por tick: detecta deslocamento, dano, golpe e morte comparando snapshots.
func update(prev: Dictionary, cur: Dictionary) -> void:
	var before: Dictionary = {}
	for e: Dictionary in prev.get("enemies", []):
		before[e.id] = e
	var cam: Camera3D = get_viewport().get_camera_3d() if is_inside_tree() else null
	for e: Dictionary in cur.enemies:
		var id: int = e.id
		var sp: Sprite3D = get_node_or_null("Enemy_%d" % id)
		if sp == null:
			sp = _make_sprite(e)
			add_child(sp)
		var fx: Dictionary = _fx[id]
		var old: Dictionary = before.get(e.id, e)
		var base: Vector3 = base_position(e)
		var disp: Vector3 = base - (fx.base as Vector3)
		fx.moving = disp.length_squared() > 0.0
		if fx.moving and cam != null:
			var right: Vector3 = cam.global_transform.basis.x
			var lateral: float = disp.dot(right)
			if absf(lateral) > 0.0001:
				sp.flip_h = lateral < 0.0
		fx.base = base
		fx.state = e.state
		fx.ticks = int(e.state_ticks)
		if int(e.hp) < int(old.hp):
			fx.hit = HIT_FRAMES
		if e.state == "STRIKE" and old.state != "STRIKE":
			fx.strike = STRIKE_FRAMES
		if e.state == "DEAD" and old.state != "DEAD":
			fx.dead = DEAD_FRAMES


func _process(delta: float) -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	for node: Node in get_children():
		var s: Sprite3D = node as Sprite3D
		if s == null:
			continue
		var id: int = s.name.get_slice("_", 1).to_int()
		if not _fx.has(id):
			continue
		var fx: Dictionary = _fx[id]
		var pos: Vector3 = fx.base
		var col: Color = Color.WHITE
		var sc: float = 1.0
		if fx.state == "DEAD":
			if int(fx.dead) > 0:
				fx.dead = int(fx.dead) - 1
				var k: float = 1.0 - float(fx.dead) / float(DEAD_FRAMES)
				pos.y -= DEAD_SINK * k
				col = DEAD_COLOR
				if int(fx.dead) == 0:
					s.visible = false
			s.modulate = col
			s.position = pos
			continue
		if fx.state == "CHASE" and fx.moving:
			fx.phase = float(fx.phase) + TAU * BOB_HZ * delta
			pos.y += BOB_AMP * sin(float(fx.phase))
		if fx.state == "WINDUP":
			var wk: float = clampf(float(fx.ticks) / float(WINDUP_TICKS.get(fx.type, 1)), 0.0, 1.0)
			col = Color.WHITE.lerp(WINDUP_COLOR, wk)
			sc = lerpf(1.0, WINDUP_SCALE, wk)
		if int(fx.strike) > 0:
			fx.strike = int(fx.strike) - 1
			if cam != null:
				var to_cam: Vector3 = cam.global_position - pos
				to_cam.y = 0.0
				if to_cam.length_squared() > 0.0:
					pos += to_cam.normalized() * STRIKE_LUNGE
		if int(fx.hit) > 0:
			fx.hit = int(fx.hit) - 1
			col = HIT_COLOR
		# escala a partir da base no piso
		pos.y += (sc - 1.0) * 16.0 * s.pixel_size
		s.scale = Vector3(sc, sc, sc)
		s.modulate = col
		s.position = pos
