class_name RngPcg32
extends RefCounted
## PCG32 (O'Neill, pcg32_random_r) com aritmética mod 2^64 em limbs de 32 bits.

const STREAM_DUNGEON: int = 1
const STREAM_AI: int = 2
const STREAM_PILOT: int = 3

const MASK32: int = 0xFFFFFFFF
const MULT_HI: int = 0x5851F42D
const MULT_LO: int = 0x4C957F2D

var state: int = 0
var inc: int = 1


static func create(initstate: int, initseq: int) -> RngPcg32:
	var r := RngPcg32.new()
	r.seed(initstate, initseq)
	return r


## Igual a pcg32_srandom_r.
func seed(initstate: int, initseq: int) -> void:
	state = 0
	inc = (initseq << 1) | 1
	next_u32()
	state = _add64(state, initstate)
	next_u32()


## Deslocamento lógico à direita de um valor de 64 bits.
static func _shr(v: int, n: int) -> int:
	if n == 0:
		return v
	return (v >> n) & ((1 << (64 - n)) - 1)


static func _add64(a: int, b: int) -> int:
	var lo: int = (a & MASK32) + (b & MASK32)
	var hi: int = (_shr(a, 32) + _shr(b, 32) + (lo >> 32)) & MASK32
	return (hi << 32) | (lo & MASK32)


## (a * b) mod 2^64 via limbs de 32 bits (16 bits nos produtos cruzados).
static func _mul64(a: int, b: int) -> int:
	var a_lo: int = a & MASK32
	var a_hi: int = _shr(a, 32)
	var b_lo: int = b & MASK32
	var b_hi: int = _shr(b, 32)
	# a_lo*b_lo pode chegar a 2^64: dividir a_lo em metades de 16 bits.
	var a0: int = a_lo & 0xFFFF
	var a1: int = _shr(a_lo, 16)
	var p0: int = a0 * b_lo           # < 2^48
	var p1: int = a1 * b_lo           # < 2^48, deslocado 16
	var lo_full_lo: int = p0 + ((p1 & 0xFFFF) << 16)
	var low32: int = lo_full_lo & MASK32
	var carry: int = _shr(lo_full_lo, 32) + _shr(p1, 16)
	var cross: int = ((a_lo * (b_hi & 0xFFFF)) + (((a_lo * _shr(b_hi, 16)) & 0xFFFF) << 16)) & MASK32
	var cross2: int = ((b_lo * (a_hi & 0xFFFF)) + (((b_lo * _shr(a_hi, 16)) & 0xFFFF) << 16)) & MASK32
	var high32: int = (carry + cross + cross2) & MASK32
	return (high32 << 32) | low32


func next_u32() -> int:
	var old: int = state
	state = _add64(_mul64(old, (MULT_HI << 32) | MULT_LO), inc)
	var xorshifted: int = (_shr(_shr(old, 18) ^ old, 27)) & MASK32
	var rot: int = _shr(old, 59) & 31
	return ((xorshifted >> rot) | (xorshifted << ((32 - rot) & 31))) & MASK32


## Igual a pcg32_boundedrand_r.
func bounded(n: int) -> int:
	var threshold: int = ((1 << 32) - n) % n
	while true:
		var r: int = next_u32()
		if r >= threshold:
			return r % n
	return 0


func state_hex() -> String:
	return "%08x%08x" % [_shr(state, 32), state & MASK32]
