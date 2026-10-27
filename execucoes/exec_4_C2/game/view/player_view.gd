class_name PlayerView
extends CharacterBody3D
## Casca de apresentação do jogador (GDD §7.1): a pose é ESCRITA a partir do
## estado inteiro; nenhuma física do motor participa da lógica.

const EYE_HEIGHT: float = 1.5

@onready var camera: Camera3D = $Camera3D
@onready var torch_light: OmniLight3D = $Camera3D/TorchLight

var _prev: Dictionary = {}
var _curr: Dictionary = {}


static func sim_to_world(x: int, z: int) -> Vector3:
	return Vector3(float(x) / 1024.0, 0.0, -float(z) / 1024.0)


static func angle_to_yaw(a: float) -> float:
	return TAU * a / 4096.0 - PI / 2.0


## Novo estado do jogador (dicionário "player" de get_state()).
func push_state(p: Dictionary, snap: bool = false) -> void:
	_prev = p if (snap or _curr.is_empty()) else _curr
	_curr = p
	_apply(1.0)


func _process(_dt: float) -> void:
	if _curr.is_empty():
		return
	_apply(Engine.get_physics_interpolation_fraction())
	# Tremulação só visual, derivada do contador de quadros (nunca do RNG do núcleo).
	var f: int = Engine.get_frames_drawn()
	torch_light.light_energy = 2.2 + 0.08 * sin(float(f) * 0.37) + 0.05 * sin(float(f) * 1.13)


func _apply(t: float) -> void:
	var a0: Vector3 = sim_to_world(int(_prev["pos_x"]), int(_prev["pos_z"]))
	var a1: Vector3 = sim_to_world(int(_curr["pos_x"]), int(_curr["pos_z"]))
	position = a0.lerp(a1, t)
	var ang0: int = int(_prev["angle"])
	var ang1: int = int(_curr["angle"])
	var diff: int = ((ang1 - ang0 + 2048) & 4095) - 2048
	rotation = Vector3(0.0, angle_to_yaw(float(ang0) + float(diff) * t), 0.0)
