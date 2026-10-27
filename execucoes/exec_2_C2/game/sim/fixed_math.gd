extends RefCounted
## Aritmética inteira explícita do núcleo (GDD §3.2).
## Nenhum arquivo de sim/ usa `/` diretamente sobre valores possivelmente negativos.


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


## Quociente truncado em direção a zero.
@warning_ignore("integer_division")
static func div_trunc(a: int, b: int) -> int:
	if b == 0:
		push_error("div_trunc: divisão por zero")
		return 0
	var q: int = abs_i(a) / abs_i(b)
	return -q if (a < 0) != (b < 0) else q


## Quociente arredondado para menos infinito.
static func div_floor(a: int, b: int) -> int:
	var q: int = div_trunc(a, b)
	if q * b != a and ((a < 0) != (b < 0)):
		q -= 1
	return q


## Produto Q16: (a * q) >> 16, deslocamento aritmético.
static func mul_q16(a: int, q: int) -> int:
	return (a * q) >> 16
