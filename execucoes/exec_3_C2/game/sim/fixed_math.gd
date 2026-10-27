class_name FixedMath
extends RefCounted
## Aritmética inteira com semântica de divisão explícita (GDD §3.2).


static func abs_i(a: int) -> int:
	return -a if a < 0 else a


static func clamp_i(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## Divisão truncada em direção a zero (7/2 = 3, -7/2 = -3).
static func div_trunc(a: int, b: int) -> int:
	@warning_ignore("integer_division")
	var q: int = abs_i(a) / abs_i(b)
	return -q if (a < 0) != (b < 0) else q


## Divisão arredondada para baixo (-7/2 = -4).
static func div_floor(a: int, b: int) -> int:
	var q: int = div_trunc(a, b)
	if q * b != a and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Produto Q16: (a * b) >> 16, com shift aritmético.
static func mul_q16(a: int, b_q16: int) -> int:
	return (a * b_q16) >> 16
