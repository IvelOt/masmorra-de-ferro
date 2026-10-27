extends CanvasLayer
## Espada e escudo em 1ª pessoa (M3), em coordenadas de 640×360. Pose derivada
## de swing_state/swing_ticks, blocking e stun_ticks; balanço proporcional à
## velocidade. Só apresentação: lê o estado, nunca escreve no núcleo.
## Iteração 5 (§4.2): espada ×4 a 0° (a arte já é diagonal) com o cabo abaixo do
## recorte (y = 312) e manopla procedural no punho; escudo ×4 com a borda inferior
## cortada; centros simétricos em torno de x = 328 ± 8; sem sombra projetada.

const SWORD_SCALE: int = 4
const SHIELD_SCALE: int = 4
const SHIELD_UP_SCALE: int = 5
const CLIP_H: int = 312
const SWORD_BASE: Vector2 = Vector2(452, 280)
const SWORD_BASE_ROT: float = 0.0
const SWORD_WINDUP: Vector2 = SWORD_BASE + Vector2(48, -22)
const SWORD_WINDUP_ROT: float = -30.0
const SWORD_SWEEP_FROM: Vector2 = SWORD_BASE + Vector2(28, -60)
const SWORD_SWEEP_TO: Vector2 = SWORD_BASE + Vector2(-172, 10)
const SWORD_SWEEP_ROT_TO: float = 75.0
const SWORD_STUN: Vector2 = SWORD_BASE + Vector2(18, 38)
const SWORD_STUN_ROT: float = 15.0
const SHIELD_BASE: Vector2 = Vector2(204, 300)
const SHIELD_BASE_ROT: float = 6.0
const SHIELD_UP: Vector2 = Vector2(268, 250)
const SHIELD_DOWN: Vector2 = SHIELD_BASE + Vector2(-18, 46)
## Manopla em coordenadas de textura (punho ≈ 7×6 texels a partir de (2, 22)).
const HAND_TEXELS: Array = [[2, 23], [5, 21], [9, 22], [9, 26], [6, 28], [2, 27]]
const COL_HAND: Color = Color("#7d828c")
const COL_HAND_LINE: Color = Color("#25262b")
const SHIELD_RAISE_FRAMES: float = 4.0
const BOB_AMP: float = 6.0
const BOB_RATE: float = 0.18
const TERMINAL_SPEED: float = 139.0

var _clip: Control = null
var _sword: Sprite2D = null
var _shield: Sprite2D = null
var _prev: Dictionary = {}
var _curr: Dictionary = {}
var _raise: float = 0.0
var _phi: float = 0.0


func _ready() -> void:
	layer = 1
	# Recorte acima da barra da HUD (y <= 312).
	_clip = Control.new()
	_clip.name = "Clip"
	_clip.position = Vector2.ZERO
	_clip.size = Vector2(640, CLIP_H)
	_clip.clip_contents = true
	_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_clip)
	_shield = _make_sprite("Shield", "weapon.shield", SHIELD_SCALE)
	_sword = _make_sprite("Sword", "weapon.sword", SWORD_SCALE)
	_sword.position = SWORD_BASE
	_sword.rotation_degrees = SWORD_BASE_ROT
	_shield.position = SHIELD_BASE
	_shield.rotation_degrees = SHIELD_BASE_ROT
	_make_hand()


## Manopla de metal (filha da espada: herda posição, rotação e escala).
func _make_hand() -> void:
	var half: Vector2 = _sword.texture.get_size() / 2.0 if _sword.texture != null else Vector2(16, 16)
	var pts: PackedVector2Array = PackedVector2Array()
	for t: Array in HAND_TEXELS:
		pts.append(Vector2(float(t[0]), float(t[1])) - half)
	var hand: Polygon2D = Polygon2D.new()
	hand.name = "Hand"
	hand.polygon = pts
	hand.color = COL_HAND
	_sword.add_child(hand)
	var line: Line2D = Line2D.new()
	line.name = "Outline"
	line.points = pts
	line.closed = true
	line.width = 1.0
	line.default_color = COL_HAND_LINE
	hand.add_child(line)


func _make_sprite(n: String, id: String, sc: int) -> Sprite2D:
	var s: Sprite2D = Sprite2D.new()
	s.name = n
	s.texture = AssetResolver.resolve(id)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(sc, sc)
	_clip.add_child(s)
	return s


## Estado do jogador (get_state().player) a cada tick.
func push_state(p: Dictionary) -> void:
	_prev = p if _curr.is_empty() else _curr
	_curr = p
	_pose(1.0, 0.0)


func _process(dt: float) -> void:
	if _curr.is_empty():
		return
	_pose(Engine.get_physics_interpolation_fraction(), dt)


static func sword_pose(st: int, ticks: float) -> Array:
	if st == Combat.WINDUP:
		var k: float = clampf(ticks / Combat.SWING_WINDUP, 0.0, 1.0)
		return [SWORD_BASE.lerp(SWORD_WINDUP, k), lerpf(SWORD_BASE_ROT, SWORD_WINDUP_ROT, k)]
	if st == Combat.ACTIVE:
		var k2: float = clampf((ticks - Combat.SWING_WINDUP) / Combat.SWING_ACTIVE, 0.0, 1.0)
		return [SWORD_SWEEP_FROM.lerp(SWORD_SWEEP_TO, k2), lerpf(SWORD_WINDUP_ROT, SWORD_SWEEP_ROT_TO, k2)]
	if st == Combat.RECOVERY:
		var k3: float = clampf((ticks - Combat.SWING_WINDUP - Combat.SWING_ACTIVE) / Combat.SWING_RECOVERY, 0.0, 1.0)
		return [SWORD_SWEEP_TO.lerp(SWORD_BASE, k3), lerpf(SWORD_SWEEP_ROT_TO, SWORD_BASE_ROT, k3)]
	return [SWORD_BASE, SWORD_BASE_ROT]


func _pose(t: float, dt: float) -> void:
	var st: int = int(_curr["swing_state"])
	var ticks: float = float(_curr["swing_ticks"])
	if st != Combat.IDLE and int(_prev["swing_state"]) != Combat.IDLE:
		ticks = lerpf(float(_prev["swing_ticks"]), ticks, t)
	var sp: Array = sword_pose(st, ticks)
	var stunned: bool = int(_curr["stun_ticks"]) > 0
	if stunned and st == Combat.IDLE:
		sp = [SWORD_STUN, SWORD_STUN_ROT]
	# Balanço (bob) proporcional à velocidade lida do estado.
	var v: float = float(maxi(absi(int(_curr["vel_x"])), absi(int(_curr["vel_z"]))))
	var vk: float = clampf(v / TERMINAL_SPEED, 0.0, 1.0)
	var frames: float = dt * 60.0
	_phi += BOB_RATE * frames * vk
	var amp: float = BOB_AMP * vk
	var bob: Vector2 = Vector2(amp * sin(2.0 * _phi) / 2.0, amp * absf(sin(_phi)))
	_sword.position = (sp[0] as Vector2) + bob
	_sword.rotation_degrees = float(sp[1])
	# Escudo: ergue em 4 quadros quando bloqueia; cai e treme atordoado.
	var blocking: bool = bool(_curr["blocking"])
	if dt > 0.0:
		var step: float = frames / SHIELD_RAISE_FRAMES
		_raise = clampf(_raise + (step if blocking else -step), 0.0, 1.0)
	elif blocking:
		_raise = 1.0
	if stunned:
		var shake: float = 2.0 * sin(float(Engine.get_frames_drawn()) * 2.3)
		_shield.position = SHIELD_DOWN + Vector2(shake, 0)
		_shield.rotation_degrees = SHIELD_BASE_ROT
		_shield.scale = Vector2(SHIELD_SCALE, SHIELD_SCALE)
	else:
		_shield.position = SHIELD_BASE.lerp(SHIELD_UP, _raise) + bob * 0.5
		_shield.rotation_degrees = lerpf(SHIELD_BASE_ROT, 0.0, _raise)
		# Escala inteira (pixel nítido no stretch inteiro).
		var sc: int = SHIELD_UP_SCALE if _raise >= 0.5 else SHIELD_SCALE
		_shield.scale = Vector2(sc, sc)
