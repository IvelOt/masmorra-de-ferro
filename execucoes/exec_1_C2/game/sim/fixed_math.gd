class_name FixedMath
extends RefCounted
## Aritmética inteira com semântica de divisão explícita (GDD §3.2).


## Divisão truncando em direção a zero.
static func div_trunc(a: int, b: int) -> int:
	var q: int = abs_i(a) / abs_i(b)
	if (a < 0) != (b < 0):
		return -q
	return q


## Divisão arredondando para baixo.
static func div_floor(a: int, b: int) -> int:
	var q: int = div_trunc(a, b)
	if a - q * b != 0 and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Resto com o sinal do divisor (par de div_floor).
static func mod_floor(a: int, b: int) -> int:
	return a - div_floor(a, b) * b


static func abs_i(a: int) -> int:
	return -a if a < 0 else a


static func mul_q16(a: int, b: int) -> int:
	return (a * b) >> 16


static func clamp_i(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v
