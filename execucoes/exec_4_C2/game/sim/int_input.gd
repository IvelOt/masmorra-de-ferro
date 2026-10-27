class_name IntInput
extends RefCounted
## Entrada inteira por tick (GDD §5.2). Única fronteira de entrada do núcleo.

const TURN_MAX: int = 128

var move: int = 0
var strafe: int = 0
var turn: int = 0
var attack: bool = false
var block: bool = false
var use: bool = false
var quaff: int = 0


func _init(p_move: int = 0, p_strafe: int = 0, p_turn: int = 0, p_attack: bool = false,
		p_block: bool = false, p_use: bool = false, p_quaff: int = 0) -> void:
	move = FixedMath.clamp_i(p_move, -1, 1)
	strafe = FixedMath.clamp_i(p_strafe, -1, 1)
	turn = FixedMath.clamp_i(p_turn, -TURN_MAX, TURN_MAX)
	attack = p_attack
	block = p_block
	use = p_use
	quaff = FixedMath.clamp_i(p_quaff, 0, 2)


func to_dict() -> Dictionary:
	return {
		"move": move, "strafe": strafe, "turn": turn,
		"attack": attack, "block": block, "use": use, "quaff": quaff,
	}


## JSON devolve números como float: converte com int() aqui, na fronteira.
static func from_dict(d: Dictionary) -> IntInput:
	return IntInput.new(
		int(d.get("move", 0)), int(d.get("strafe", 0)), int(d.get("turn", 0)),
		bool(d.get("attack", false)), bool(d.get("block", false)),
		bool(d.get("use", false)), int(d.get("quaff", 0)))
