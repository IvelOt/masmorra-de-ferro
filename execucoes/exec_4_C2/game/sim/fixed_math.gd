class_name FixedMath
extends RefCounted
## Aritmética inteira do núcleo (GDD §3.2). Nunca usar `/` ou `%` do GDScript
## sobre valores possivelmente negativos: usar div_trunc / div_floor.


static func abs_i(a: int) -> int:
	return -a if a < 0 else a


static func clamp_i(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## Divisão truncada em direção a zero (-7/2 = -3).
static func div_trunc(a: int, b: int) -> int:
	var q: int = abs_i(a) / abs_i(b)
	if (a < 0) != (b < 0):
		return -q
	return q


## Divisão arredondada para baixo (-7/2 = -4).
static func div_floor(a: int, b: int) -> int:
	var q: int = div_trunc(a, b)
	if q * b != a and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Produto Q16: (a * q) >> 16, shift aritmético (GDD §3.2).
static func mul_q16(a: int, q: int) -> int:
	return (a * q) >> 16
