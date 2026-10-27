class_name InputSampler
extends RefCounted
## Teclado/mouse -> IntInput. Float só existe aqui; o núcleo recebe inteiros.

const IntInput = preload("res://sim/int_input.gd")
const PlayerSim = preload("res://sim/player_sim.gd")

## 0,15°/px em BAM (4096 / 360 * 0,15).
const MOUSE_BAM_PER_PX: float = 1.7067

var _mouse_px: float = 0.0
var _mouse_rest: float = 0.0


func add_mouse_dx(dx: float) -> void:
	_mouse_px += dx


## Chamado uma vez por tick físico.
func sample() -> IntInput:
	var inp := IntInput.new()
	inp.move = int(Input.is_action_pressed("move_forward")) - int(Input.is_action_pressed("move_back"))
	inp.strafe = int(Input.is_action_pressed("strafe_right")) - int(Input.is_action_pressed("strafe_left"))
	var key_turn: int = 0
	if Input.is_action_pressed("turn_left"):
		key_turn += PlayerSim.TURN_KEY
	if Input.is_action_pressed("turn_right"):
		key_turn -= PlayerSim.TURN_KEY
	# ângulo crescente = girar à esquerda; mouse para a direita gira à direita
	_mouse_rest += -_mouse_px * MOUSE_BAM_PER_PX
	_mouse_px = 0.0
	var mouse_turn: int = int(_mouse_rest)
	_mouse_rest -= mouse_turn
	inp.turn = clampi(key_turn + mouse_turn, -128, 128)
	inp.attack = Input.is_action_just_pressed("attack")
	inp.block = Input.is_action_pressed("block")
	inp.use = Input.is_action_just_pressed("use")
	if Input.is_action_just_pressed("quaff_hp"):
		inp.quaff = 1
	elif Input.is_action_just_pressed("quaff_sp"):
		inp.quaff = 2
	return inp
