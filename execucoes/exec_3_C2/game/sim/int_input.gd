class_name IntInput
extends RefCounted
## Entrada inteira de um tick (GDD §5.2). use/attack já chegam como borda de subida.

const FixedMath = preload("res://sim/fixed_math.gd")
const PCG32 = preload("res://sim/rng_pcg32.gd")
## Referência a si mesmo sem depender do cache global de class_name.
const IntInputScript = preload("res://sim/int_input.gd")

var move: int = 0
var strafe: int = 0
var turn: int = 0
var attack: bool = false
var block: bool = false
var use: bool = false
var quaff: int = 0


func clamped() -> IntInputScript:
	var c := IntInputScript.new()
	c.move = FixedMath.clamp_i(move, -1, 1)
	c.strafe = FixedMath.clamp_i(strafe, -1, 1)
	c.turn = FixedMath.clamp_i(turn, -128, 128)
	c.attack = attack
	c.block = block
	c.use = use
	c.quaff = FixedMath.clamp_i(quaff, 0, 2)
	return c


func to_dict() -> Dictionary:
	return {
		"move": move, "strafe": strafe, "turn": turn,
		"attack": attack, "block": block, "use": use, "quaff": quaff,
	}


static func from_dict(d: Dictionary) -> IntInputScript:
	var i := IntInputScript.new()
	i.move = int(d.get("move", 0))
	i.strafe = int(d.get("strafe", 0))
	i.turn = int(d.get("turn", 0))
	i.attack = bool(d.get("attack", false))
	i.block = bool(d.get("block", false))
	i.use = bool(d.get("use", false))
	i.quaff = int(d.get("quaff", 0))
	return i


## Input aleatório do piloto provisório (regra do M1-A4).
static func from_pilot(rng: PCG32) -> IntInputScript:
	var i := IntInputScript.new()
	i.move = rng.bounded(3) - 1
	i.strafe = rng.bounded(3) - 1
	i.turn = rng.bounded(257) - 128
	return i


## Input do piloto com combate (plano R3 §6.1, M3-A7): from_pilot + attack/block.
static func from_pilot_combat(rng: PCG32) -> IntInputScript:
	var i: IntInputScript = from_pilot(rng)
	i.attack = rng.bounded(8) == 0
	i.block = rng.bounded(4) == 0
	return i
