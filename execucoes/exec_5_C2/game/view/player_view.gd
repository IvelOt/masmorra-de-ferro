extends CharacterBody3D
## Casca de apresentação do jogador: posição/yaw escritos a partir do estado inteiro.
## move_and_slide() não é usado (GDD §7.1).

const EYE_HEIGHT: float = 1.5
const FLICKER: float = 0.08

@onready var camera: Camera3D = $Camera3D
@onready var torch: OmniLight3D = $Camera3D/Torch

var _flicker_t: float = 0.0
var _noise := RandomNumberGenerator.new()


func _ready() -> void:
	_noise.seed = 12345


static func sim_to_godot(pos_x: int, pos_z: int) -> Vector3:
	return Vector3(pos_x / 1024.0, 0.0, -pos_z / 1024.0)


static func yaw_of(angle: int) -> float:
	return TAU * angle / 4096.0 - PI / 2.0


func apply_state(pos: Array, angle: int) -> void:
	position = sim_to_godot(pos[0], pos[1])
	rotation = Vector3(0.0, yaw_of(angle), 0.0)


func _process(delta: float) -> void:
	_flicker_t += delta
	if _flicker_t >= 0.06:
		_flicker_t = 0.0
		torch.light_energy = 1.2 * (1.0 + _noise.randf_range(-FLICKER, FLICKER))
