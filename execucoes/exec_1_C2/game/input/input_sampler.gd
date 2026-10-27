class_name InputSampler
extends RefCounted
## Teclado/mouse -> IntInput, amostrado uma vez por tick físico. O float do
## mouse fica aqui; só o inteiro quantizado chega ao núcleo.

const MOUSE_BAM_PER_PX: float = 2.0
const TURN_KEY: int = 48

var _mouse_acc: float = 0.0


func handle_event(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_acc += (event as InputEventMouseMotion).relative.x


func sample() -> IntInput:
	var i: IntInput = IntInput.new()
	i.move = int(Input.is_action_pressed("move_forward")) - int(Input.is_action_pressed("move_back"))
	i.strafe = int(Input.is_action_pressed("strafe_right")) - int(Input.is_action_pressed("strafe_left"))
	var key_turn: int = (int(Input.is_action_pressed("turn_left")) - int(Input.is_action_pressed("turn_right"))) * TURN_KEY
	var raw: float = _mouse_acc * MOUSE_BAM_PER_PX
	var mouse_bam: int = clampi(int(raw), -128, 128)
	_mouse_acc = (raw - float(mouse_bam)) / MOUSE_BAM_PER_PX
	# mouse para a direita = turn negativo
	i.turn = clampi(key_turn - mouse_bam, -128, 128)
	i.attack = Input.is_action_just_pressed("attack")  # borda de subida (GDD §1.3)
	i.block = Input.is_action_pressed("block")
	i.use = Input.is_action_just_pressed("use")
	if Input.is_action_just_pressed("quaff_hp"):
		i.quaff = 1
	elif Input.is_action_just_pressed("quaff_sp"):
		i.quaff = 2
	return i
