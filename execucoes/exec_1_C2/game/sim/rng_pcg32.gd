class_name RngPcg32
extends RefCounted
## PCG-XSH-RR 64/32 (O'Neill). O estado de 64 bits fica em duas metades de
## 32 bits sem sinal, para não depender de overflow nem do >> aritmético do
## int de 64 bits com sinal do GDScript.

const STREAM_DUNGEON: int = 1
const STREAM_AI: int = 2
const STREAM_PILOT: int = 3

const M32: int = 0xFFFFFFFF
const MUL_HI: int = 0x5851F42D
const MUL_LO: int = 0x4C957F2D

var state_hi: int = 0
var state_lo: int = 0
var inc_hi: int = 0
var inc_lo: int = 0


static func create(initstate: int, initseq: int) -> RngPcg32:
	var r: RngPcg32 = RngPcg32.new()
	r.seed(initstate, initseq)
	return r


func seed(initstate: int, initseq: int) -> void:
	state_hi = 0
	state_lo = 0
	# inc = (initseq << 1) | 1, mod 2^64
	inc_lo = ((initseq << 1) | 1) & M32
	inc_hi = (initseq >> 31) & M32
	next_u32()
	var lo: int = state_lo + (initstate & M32)
	state_hi = (state_hi + ((initstate >> 32) & M32) + (lo >> 32)) & M32
	state_lo = lo & M32
	next_u32()


func next_u32() -> int:
	var old_hi: int = state_hi
	var old_lo: int = state_lo
	_advance()
	# xorshifted = ((old >> 18) ^ old) >> 27, truncado a 32 bits
	var sh_lo: int = (old_lo >> 18) | ((old_hi << 14) & M32)
	var sh_hi: int = old_hi >> 18
	var v_lo: int = old_lo ^ sh_lo
	var v_hi: int = old_hi ^ sh_hi
	var xorshifted: int = ((v_lo >> 27) | (v_hi << 5)) & M32
	var rot: int = old_hi >> 27
	return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & M32


## pcg32_boundedrand: inteiro uniforme em [0, n).
func next_range(n: int) -> int:
	var threshold: int = (0x100000000 - n) % n
	while true:
		var r: int = next_u32()
		if r >= threshold:
			return r % n
	return 0


## state = state * MUL + inc (mod 2^64)
func _advance() -> void:
	var p: Array[int] = _mul32_full(state_lo, MUL_LO)
	var hi: int = p[0] + _mul32_lo(state_hi, MUL_LO) + _mul32_lo(state_lo, MUL_HI)
	var lo: int = p[1] + inc_lo
	hi += inc_hi + (lo >> 32)
	state_lo = lo & M32
	state_hi = hi & M32


## Produto completo de dois valores de 32 bits: [hi32, lo32].
static func _mul32_full(x: int, y: int) -> Array[int]:
	var t0: int = x * (y & 0xFFFF)
	var t1: int = x * (y >> 16)
	var lo: int = (t0 & M32) + ((t1 & 0xFFFF) << 16)
	var hi: int = (t0 >> 32) + (t1 >> 16) + (lo >> 32)
	return [hi & M32, lo & M32]


## Produto de dois valores de 32 bits, mod 2^32.
static func _mul32_lo(x: int, y: int) -> int:
	var t0: int = x * (y & 0xFFFF)
	var t1: int = x * (y >> 16)
	return (t0 + ((t1 & 0xFFFF) << 16)) & M32


## Estado de 64 bits como texto hexadecimal (diagnóstico).
func state_hex() -> String:
	return "%08x%08x" % [state_hi, state_lo]
