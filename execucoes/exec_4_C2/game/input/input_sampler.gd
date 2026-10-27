class_name InputSampler
extends RefCounted
## Teclado/mouse -> IntInput. A quantização (float) acontece só aqui, fora do núcleo.

const SENS: float = 0.5  # BAM por pixel
const TURN_KEY: int = 48

var _mouse_acc: float = 0.0
var _prev_attack: bool = false
var _prev_use: bool = false
var _prev_quaff_hp: bool = false
var _prev_quaff_sp: bool = false


## Chamado pela cena com InputEventMouseMotion.relative.x (só com mouse capturado).
func add_mouse_motion(dx: float) -> void:
	_mouse_acc += dx


func sample() -> IntInput:
	var move: int = int(Input.is_action_pressed("move_forward")) - int(Input.is_action_pressed("move_back"))
	var strafe: int = int(Input.is_action_pressed("strafe_right")) - int(Input.is_action_pressed("strafe_left"))
	var turn: int = 0
	if Input.is_action_pressed("turn_left"):
		turn += TURN_KEY
	if Input.is_action_pressed("turn_right"):
		turn -= TURN_KEY
	# Mouse para a direita -> turn negativo; o resto fracionário fica para o próximo tick.
	var scaled: float = _mouse_acc * SENS
	var whole: int = int(scaled)
	_mouse_acc = (scaled - float(whole)) / SENS
	turn -= whole
	var attack_now: bool = Input.is_action_pressed("attack")
	var use_now: bool = Input.is_action_pressed("use")
	var qhp: bool = Input.is_action_pressed("quaff_hp")
	var qsp: bool = Input.is_action_pressed("quaff_sp")
	var quaff: int = 0
	if qhp and not _prev_quaff_hp:
		quaff = 1
	elif qsp and not _prev_quaff_sp:
		quaff = 2
	var inp: IntInput = IntInput.new(move, strafe, turn,
		attack_now and not _prev_attack, Input.is_action_pressed("block"),
		use_now and not _prev_use, quaff)
	_prev_attack = attack_now
	_prev_use = use_now
	_prev_quaff_hp = qhp
	_prev_quaff_sp = qsp
	return inp
