extends RefCounted
## Entrada inteira de um tick (GDD §5.2).
## attack (borda de subida) e block (nível) têm efeito desde M3; quaff (1 = vida, 2 = vigor) desde M6.

const FM = preload("res://sim/fixed_math.gd")

var move: int = 0
var strafe: int = 0
var turn: int = 0
var attack: bool = false
var block: bool = false
var use: bool = false
var quaff: int = 0


func _init(p_move: int = 0, p_strafe: int = 0, p_turn: int = 0, p_use: bool = false) -> void:
	move = FM.clamp_i(p_move, -1, 1)
	strafe = FM.clamp_i(p_strafe, -1, 1)
	turn = FM.clamp_i(p_turn, -128, 128)
	use = p_use


static func from_dict(d: Dictionary) -> RefCounted:
	var r: RefCounted = new()
	r.move = FM.clamp_i(int(d.get("move", 0)), -1, 1)
	r.strafe = FM.clamp_i(int(d.get("strafe", 0)), -1, 1)
	r.turn = FM.clamp_i(int(d.get("turn", 0)), -128, 128)
	r.attack = bool(d.get("attack", false))
	r.block = bool(d.get("block", false))
	r.use = bool(d.get("use", false))
	r.quaff = FM.clamp_i(int(d.get("quaff", 0)), 0, 2)
	return r


func to_dict() -> Dictionary:
	return {
		"move": move,
		"strafe": strafe,
		"turn": turn,
		"attack": attack,
		"block": block,
		"use": use,
		"quaff": quaff,
	}
