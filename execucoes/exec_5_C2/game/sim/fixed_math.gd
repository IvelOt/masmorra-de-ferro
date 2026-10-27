class_name FixedMath
extends RefCounted
## Aritmética inteira com semântica de divisão explícita (GDD §3.2).


static func abs_i(a: int) -> int:
	return -a if a < 0 else a


static func sign_i(a: int) -> int:
	if a > 0:
		return 1
	if a < 0:
		return -1
	return 0


static func min_i(a: int, b: int) -> int:
	return a if a < b else b


static func max_i(a: int, b: int) -> int:
	return a if a > b else b


static func clamp_i(v: int, lo: int, hi: int) -> int:
	if v < lo:
		return lo
	if v > hi:
		return hi
	return v


## Quociente truncado em direção a zero (independe do `/` do motor para negativos).
static func div_trunc(a: int, b: int) -> int:
	var q: int = abs_i(a) / abs_i(b)
	if (a < 0) != (b < 0):
		return -q
	return q


## Quociente arredondado para -infinito.
static func div_floor(a: int, b: int) -> int:
	var q: int = div_trunc(a, b)
	if q * b != a and ((a < 0) != (b < 0)):
		return q - 1
	return q


## Produto Q16 com deslocamento aritmético (GDD §3.2).
static func mul_q16(a: int, b: int) -> int:
	return (a * b) >> 16
