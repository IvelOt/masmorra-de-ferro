class_name PCG32
extends RefCounted
## PCG-XSH-RR 64/32 próprio. O estado de 64 bits fica em duas metades de 32 bits
## sem sinal, e toda multiplicação é feita em limbs de 16 bits, para não depender
## de overflow do inteiro com sinal do GDScript.

const M32: int = 0xFFFFFFFF
const MULT_HI: int = 0x5851F42D
const MULT_LO: int = 0x4C957F2D

const STREAM_DUNGEON: int = 1
const STREAM_AI: int = 2
const STREAM_PILOT: int = 3

var state_hi: int = 0
var state_lo: int = 0
var inc_hi: int = 0
var inc_lo: int = 1


func _init(seed_value: int = 0, stream: int = 0) -> void:
	init(seed_value, stream)


## Igual a pcg32_srandom(seed, stream).
func init(seed_value: int, stream: int) -> void:
	state_hi = 0
	state_lo = 0
	inc_lo = ((stream << 1) | 1) & M32
	inc_hi = (stream >> 31) & M32
	next_u32()
	var lo: int = state_lo + (seed_value & M32)
	var carry: int = lo >> 32
	state_lo = lo & M32
	state_hi = (state_hi + ((seed_value >> 32) & M32) + carry) & M32
	next_u32()


## Produto completo de dois valores de 32 bits: [hi, lo].
static func _mul32_full(x: int, y: int) -> PackedInt64Array:
	var x0: int = x & 0xFFFF
	var x1: int = (x >> 16) & 0xFFFF
	var y0: int = y & 0xFFFF
	var y1: int = (y >> 16) & 0xFFFF
	var mid: int = x0 * y1 + x1 * y0
	var lo: int = x0 * y0 + ((mid & 0xFFFF) << 16)
	var carry: int = lo >> 32
	lo &= M32
	var hi: int = (x1 * y1 + (mid >> 16) + carry) & M32
	return PackedInt64Array([hi, lo])


static func _mul32_lo(x: int, y: int) -> int:
	return _mul32_full(x, y)[1]


func next_u32() -> int:
	var old_hi: int = state_hi
	var old_lo: int = state_lo
	# state = state * MULT + inc (mod 2^64)
	var p: PackedInt64Array = _mul32_full(old_lo, MULT_LO)
	var hi: int = (p[0] + _mul32_lo(old_hi, MULT_LO) + _mul32_lo(old_lo, MULT_HI)) & M32
	var lo: int = p[1] + inc_lo
	var carry: int = lo >> 32
	state_lo = lo & M32
	state_hi = (hi + inc_hi + carry) & M32
	# saída: xorshifted = ((old >> 18) ^ old) >> 27, rot = old >> 59
	var sh_hi: int = old_hi >> 18
	var sh_lo: int = ((old_hi << 14) & M32) | (old_lo >> 18)
	var v_hi: int = old_hi ^ sh_hi
	var v_lo: int = old_lo ^ sh_lo
	var xorshifted: int = ((v_hi << 5) | (v_lo >> 27)) & M32
	var rot: int = (old_hi >> 27) & 0x1F
	return ((xorshifted >> rot) | (xorshifted << ((-rot) & 31))) & M32


## Inteiro uniforme em [0, n), por rejeição sem viés.
func bounded(n: int) -> int:
	var threshold: int = (0x100000000 - n) % n
	while true:
		var r: int = next_u32()
		if r >= threshold:
			return r % n
	return 0


func state_hex() -> String:
	return "%08x%08x" % [state_hi, state_lo]
