extends RefCounted
## PCG32 XSH-RR (referência O'Neill), implementado só com int de 64 bits.
## Deslocamentos à direita são tornados lógicos por máscara depois do `>>` aritmético.

const MULT: int = 6364136223846793005
const STREAM_DUNGEON: int = 1
const STREAM_AI: int = 2
const STREAM_PILOT: int = 3

var state: int = 0
var inc: int = 1


func _init(seed_value: int = 0, stream: int = 0) -> void:
	seed_with(seed_value, stream)


func seed_with(seed_value: int, stream: int) -> void:
	state = 0
	inc = (stream << 1) | 1
	next_u32()
	state += seed_value
	next_u32()


func next_u32() -> int:
	var old: int = state
	state = old * MULT + inc
	var xorshifted: int = ((((old >> 18) & 0x3FFFFFFFFFFF) ^ old) >> 27) & 0xFFFFFFFF
	var rot: int = (old >> 59) & 31
	return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & 0xFFFFFFFF


## Inteiro uniforme em [0, n) por rejeição (sem viés).
func next_bounded(n: int) -> int:
	if n <= 0:
		push_error("next_bounded: n deve ser positivo")
		return 0
	var threshold: int = (0x100000000 - n) % n
	while true:
		var r: int = next_u32()
		if r >= threshold:
			return r % n
	return 0


func range_incl(lo: int, hi: int) -> int:
	return lo + next_bounded(hi - lo + 1)


func chance(num: int, den: int) -> bool:
	return next_bounded(den) < num


func get_state() -> int:
	return state
