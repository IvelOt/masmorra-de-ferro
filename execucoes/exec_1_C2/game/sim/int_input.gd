class_name IntInput
extends RefCounted
## Entrada inteira de um tick (GDD §5.2).

var move: int = 0      # {-1,0,1}
var strafe: int = 0    # {-1,0,1} (+1 = direita)
var turn: int = 0      # [-128,128], BAM por tick
var attack: bool = false
var block: bool = false
var use: bool = false  # borda de subida
var quaff: int = 0     # {0,1,2}


## Campos ausentes ficam no padrão. Números do JSON chegam como float e são
## convertidos para int aqui, na fronteira.
static func from_dict(d: Dictionary) -> IntInput:
	var i: IntInput = IntInput.new()
	i.move = int(d.get("move", 0))
	i.strafe = int(d.get("strafe", 0))
	i.turn = int(d.get("turn", 0))
	i.attack = bool(d.get("attack", false))
	i.block = bool(d.get("block", false))
	i.use = bool(d.get("use", false))
	i.quaff = int(d.get("quaff", 0))
	return i


func to_dict() -> Dictionary:
	return {
		"move": move, "strafe": strafe, "turn": turn, "attack": attack,
		"block": block, "use": use, "quaff": quaff,
	}


## Cópia com os campos saturados nas faixas válidas.
func clamped() -> IntInput:
	var i: IntInput = IntInput.new()
	i.move = FixedMath.clamp_i(move, -1, 1)
	i.strafe = FixedMath.clamp_i(strafe, -1, 1)
	i.turn = FixedMath.clamp_i(turn, -128, 128)
	i.attack = attack
	i.block = block
	i.use = use
	i.quaff = FixedMath.clamp_i(quaff, 0, 2)
	return i
