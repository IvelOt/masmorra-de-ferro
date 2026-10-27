class_name RngPcg32
extends RefCounted
## PCG32 (O'Neill), XSH-RR 32 bits, estado de 64 bits.
## O int do GDScript é int64 com sinal: o produto faz overflow em complemento de
## dois (igual a uint64 mod 2^64) e `>>` é aritmético, então mascaramos após shifts.

const MULT: int = 6364136223846793005
const MASK32: int = 0xFFFFFFFF

var state: int = 0
var inc: int = 0


## Equivale a pcg32_srandom(initstate, initseq).
func _init(initstate: int = 0, initseq: int = 0) -> void:
	state = 0
	inc = (initseq << 1) | 1
	next_u32()
	state = state + initstate
	next_u32()


func next_u32() -> int:
	var old: int = state
	state = old * MULT + inc
	var xorshifted: int = (((old >> 18) & 0x3FFFFFFFFFFF) ^ old) >> 27
	xorshifted = xorshifted & MASK32
	var rot: int = (old >> 59) & 31
	var res: int = (xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))
	return res & MASK32


## Inteiro uniforme em [lo, hi] (inclusivo), por rejeição, sem viés.
func range_i(lo: int, hi_inclusive: int) -> int:
	var span: int = hi_inclusive - lo + 1
	if span <= 1:
		return lo
	# limite = 2^32 - (2^32 mod span): rejeita a cauda enviesada
	var limit: int = 0x100000000 - (0x100000000 % span)
	var r: int = next_u32()
	while r >= limit:
		r = next_u32()
	return lo + (r % span)
