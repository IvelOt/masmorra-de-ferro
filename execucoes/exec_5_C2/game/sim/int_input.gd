class_name IntInput
extends RefCounted
## Entrada inteira por tick (GDD §5.2). turn > 0 gira para a esquerda (aumenta angle).

var move: int = 0
var strafe: int = 0
var turn: int = 0
var attack: bool = false
var block: bool = false
var use: bool = false
var quaff: int = 0


static func make(p_move: int, p_strafe: int, p_turn: int, p_use: bool = false) -> IntInput:
	var i := IntInput.new()
	i.move = p_move
	i.strafe = p_strafe
	i.turn = p_turn
	i.use = p_use
	i.clamp_self()
	return i


func clamp_self() -> void:
	move = FixedMath.clamp_i(move, -1, 1)
	strafe = FixedMath.clamp_i(strafe, -1, 1)
	turn = FixedMath.clamp_i(turn, -128, 128)
	quaff = FixedMath.clamp_i(quaff, 0, 2)


func to_dict() -> Dictionary:
	return {
		"move": move, "strafe": strafe, "turn": turn,
		"attack": attack, "block": block, "use": use, "quaff": quaff,
	}


static func _as_int(v: Variant) -> int:
	if typeof(v) == TYPE_BOOL:
		return 1 if v else 0
	if typeof(v) == TYPE_INT:
		return v
	if typeof(v) == TYPE_STRING:
		return String(v).to_int()
	# Números de JSON chegam como ponto flutuante: truncar para inteiro.
	return int(v)


static func _as_bool(v: Variant) -> bool:
	if typeof(v) == TYPE_BOOL:
		return v
	return _as_int(v) != 0


static func from_dict(d: Dictionary) -> IntInput:
	var i := IntInput.new()
	i.move = _as_int(d.get("move", 0))
	i.strafe = _as_int(d.get("strafe", 0))
	i.turn = _as_int(d.get("turn", 0))
	i.attack = _as_bool(d.get("attack", false))
	i.block = _as_bool(d.get("block", false))
	i.use = _as_bool(d.get("use", false))
	i.quaff = _as_int(d.get("quaff", 0))
	i.clamp_self()
	return i
