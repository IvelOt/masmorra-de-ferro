class_name InputSampler
extends Node
## Teclado/mouse -> IntInput (fora do núcleo). Mouse: 0,5 BAM/px com resto fracionário carregado.

const MOUSE_BAM_PER_PX: float = 0.5

var _mouse_acc: float = 0.0
var _prev_use: bool = false
var _prev_attack: bool = false
var _prev_quaff_hp: bool = false
var _prev_quaff_sp: bool = false


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		# mouse para a direita -> giro à direita -> turn negativo
		_mouse_acc -= (event as InputEventMouseMotion).relative.x * MOUSE_BAM_PER_PX
	elif event is InputEventMouseButton and event.pressed:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and (event as InputEventKey).keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _axis(neg: String, pos: String) -> int:
	return (1 if Input.is_action_pressed(pos) else 0) - (1 if Input.is_action_pressed(neg) else 0)


func sample() -> IntInput:
	var i := IntInput.new()
	i.move = _axis("move_back", "move_forward")
	i.strafe = _axis("strafe_left", "strafe_right")
	var key_turn: int = _axis("turn_right", "turn_left") * PlayerSim.TURN_KEY
	var mouse_turn: int = int(_mouse_acc)
	_mouse_acc -= mouse_turn
	i.turn = key_turn + mouse_turn
	var use_now: bool = Input.is_action_pressed("use")
	var attack_now: bool = Input.is_action_pressed("attack")
	i.use = use_now and not _prev_use
	i.attack = attack_now and not _prev_attack
	_prev_use = use_now
	_prev_attack = attack_now
	i.block = Input.is_action_pressed("block")
	# Poções por borda de subida: segurar a tecla bebe uma só (M6-AUX-7).
	var qhp_now: bool = Input.is_action_pressed("quaff_hp")
	var qsp_now: bool = Input.is_action_pressed("quaff_sp")
	if qhp_now and not _prev_quaff_hp:
		i.quaff = 1
	elif qsp_now and not _prev_quaff_sp:
		i.quaff = 2
	_prev_quaff_hp = qhp_now
	_prev_quaff_sp = qsp_now
	i.clamp_self()
	return i
