extends Node
## Teclado/mouse -> IntInput. Toda quantização (inclusive o float do mouse) acontece aqui,
## fora do núcleo; o resto fracionário do mouse é carregado para o tick seguinte.

const IntInput = preload("res://sim/int_input.gd")

const TURN_KEY: int = 48
const MOUSE_BAM_PER_PX: float = 4.0

var interactive: bool = true
var _mouse_acc: float = 0.0
var _use_pending: bool = false
var _attack_pending: bool = false
## Borda de quaff: 1 = poção de vida (tecla 1), 2 = poção de vigor (tecla 2); 0 = nada.
var _quaff_pending: int = 0


func _ready() -> void:
	if interactive:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_acc += -(event as InputEventMouseMotion).relative.x * MOUSE_BAM_PER_PX
	elif event.is_action_pressed("use") and not event.is_echo():
		_use_pending = true
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and interactive and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		# o clique que recaptura o mouse não vira golpe
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("attack") and not event.is_echo():
		_attack_pending = true
	elif event.is_action_pressed("quaff_hp") and not event.is_echo():
		_quaff_pending = 1
	elif event.is_action_pressed("quaff_sp") and not event.is_echo():
		_quaff_pending = 2


## Chamado uma vez por tick físico.
func sample() -> IntInput:
	var mv: int = int(Input.is_action_pressed("move_forward")) - int(Input.is_action_pressed("move_back"))
	var st: int = int(Input.is_action_pressed("strafe_right")) - int(Input.is_action_pressed("strafe_left"))
	var tu: int = 0
	if Input.is_action_pressed("turn_left"):
		tu += TURN_KEY
	if Input.is_action_pressed("turn_right"):
		tu -= TURN_KEY
	var whole: int = int(_mouse_acc)
	_mouse_acc -= whole
	tu = clampi(tu + whole, -128, 128)
	var inp: IntInput = IntInput.new(mv, st, tu, _use_pending)
	# attack é borda de subida (como use); block é nível
	inp.attack = _attack_pending
	inp.block = Input.is_action_pressed("block")
	inp.quaff = _quaff_pending
	_use_pending = false
	_attack_pending = false
	_quaff_pending = 0
	return inp
