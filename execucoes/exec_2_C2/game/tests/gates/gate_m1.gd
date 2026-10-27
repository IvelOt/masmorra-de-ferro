extends RefCounted
## Gate M1 (sala test_room()): M1-A1..A6 e verificações internas X1..X3.

const WorldSim = preload("res://sim/world_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const Pcg32 = preload("res://sim/rng_pcg32.gd")
const FM = preload("res://sim/fixed_math.gd")
const Trig = preload("res://sim/trig_table.gd")
const Report = preload("res://tests/gates/gate_report.gd")

## Valor impresso por `python3 tools/gen_trig_table.py`.
const EXPECTED_TRIG_SHA256: String = "dd6a64fbcbc4bfb38e59940b6ed273b1fc828b19111416444b3066e9b09d43c1"
const A4_SEEDS_FROM: int = 1234
const A4_SEEDS_COUNT: int = 10
const A4_TICKS: int = 600
const A4_HOLD: int = 15


static func new_world() -> WorldSim:
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	return w


static func _note_error(r: Report, w: WorldSim) -> void:
	if w.hash_error:
		r.runtime_error = true


## Trilha de M1-A4: input aleatório do fluxo PCG do piloto, trocado a cada 15 ticks.
static func random_trace(seed_value: int) -> Array:
	var rng: Pcg32 = Pcg32.new(seed_value, Pcg32.STREAM_PILOT)
	var out: Array = []
	var cur: IntInput = IntInput.new()
	for t in range(A4_TICKS):
		if t % A4_HOLD == 0:
			var mv: int = rng.next_bounded(3) - 1
			var st: int = rng.next_bounded(3) - 1
			var tu: int = rng.next_bounded(257) - 128
			cur = IntInput.new(mv, st, tu)
		out.append(cur)
	return out


static func run(r: Report) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)
	_x1(r)
	_x2(r)
	_x3(r)


static func _a1(r: Report) -> void:
	var w: WorldSim = new_world()
	var terminal_ok: bool = true
	for t in range(1, 121):
		w.step(IntInput.new(1, 0, 0))
		if t >= 32 and w.player.vel_x != 139:
			terminal_ok = false
	_note_error(r, w)
	var p: Dictionary = w.player.to_dict()
	r.check("M1-A1", p.pos_x == 22692 and p.vel_x == 139 and p.pos_z == 15360 and p.vel_z == 0 and terminal_ok,
		"pos_x=%d vel_x=%d pos_z=%d vel_z=%d terminal_desde_32=%s" % [p.pos_x, p.vel_x, p.pos_z, p.vel_z, terminal_ok])


static func _a2(r: Report) -> void:
	var w: WorldSim = new_world()
	var vx_zero: bool = true
	for _t in range(60):
		w.step(IntInput.new(0, 1, 0))
		if w.player.vel_x != 0 or w.player.pos_x != 7168:
			vx_zero = false
	_note_error(r, w)
	var p: Dictionary = w.player.to_dict()
	r.check("M1-A2", vx_zero and p.pos_z == 9258 and p.vel_z == -118,
		"pos_x=%d vel_x_zero=%s pos_z=%d vel_z=%d" % [p.pos_x, vx_zero, p.pos_z, p.vel_z])


static func _a3(r: Report) -> void:
	var detail: String = ""
	var ok: bool = true
	for start: int in [0, 1000]:
		var w: WorldSim = new_world()
		w.player.angle = start
		for _t in range(64):
			w.step(IntInput.new(0, 0, 64))
		var after_pos: int = w.player.angle
		for _t in range(64):
			w.step(IntInput.new(0, 0, -64))
		var after_neg: int = w.player.angle
		_note_error(r, w)
		ok = ok and after_pos == start and after_neg == start
		detail += "ini=%d +64x64=%d -64x64=%d; " % [start, after_pos, after_neg]
	r.check("M1-A3", ok, detail)


static func _a4(r: Report) -> void:
	var ok: bool = true
	var detail: String = ""
	for s in range(A4_SEEDS_FROM, A4_SEEDS_FROM + A4_SEEDS_COUNT):
		var w: WorldSim = new_world()
		var trace: Array = random_trace(s)
		var bad_tick: int = -1
		for inp: IntInput in trace:
			w.step(inp)
			if w.player_box_hits_solid():
				bad_tick = w.tick
				break
		_note_error(r, w)
		if bad_tick >= 0:
			ok = false
			detail += "semente %d viola no tick %d; " % [s, bad_tick]
	if ok:
		detail = "sementes %d..%d, %d ticks cada, sem interseção" % [A4_SEEDS_FROM, A4_SEEDS_FROM + A4_SEEDS_COUNT - 1, A4_TICKS]
	r.check("M1-A4", ok, detail)


## Ticks até a velocidade do eixo zerar (e permanecer zero por mais 60 ticks); -1 se não zerar.
static func _decay_ticks(w: WorldSim, axis_x: bool) -> int:
	var zero_at: int = -1
	for t in range(1, 121):
		w.step(IntInput.new())
		var v: int = w.player.vel_x if axis_x else w.player.vel_z
		if v == 0 and zero_at < 0:
			zero_at = t
		elif v != 0 and zero_at >= 0:
			return -1
	return zero_at


static func _a5(r: Report) -> void:
	var w: WorldSim = new_world()
	for _t in range(60):
		w.step(IntInput.new(1, 0, 0))
	var vf: int = w.player.vel_x
	var nf: int = _decay_ticks(w, true)
	_note_error(r, w)
	var w2: WorldSim = new_world()
	for _t in range(60):
		w2.step(IntInput.new(0, 1, 0))
	var vs: int = w2.player.vel_z
	var ns: int = _decay_ticks(w2, false)
	_note_error(r, w2)
	r.check("M1-A5", nf == 32 and ns == 31,
		"frente: %d -> 0 em %d ticks; lateral: %d -> 0 em %d ticks" % [vf, nf, vs, ns])


static func _a6(r: Report) -> void:
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(Trig.SIN_Q16.to_byte_array())
	var got: String = ctx.finish().hex_encode()
	r.check("M1-A6", Trig.SIN_Q16.size() == 4096 and got == EXPECTED_TRIG_SHA256,
		"sha256=%s" % got)


static func _x1(r: Report) -> void:
	var a: Pcg32 = Pcg32.new(42, 54)
	var got_a: Array = []
	for _i in range(6):
		got_a.append(a.next_u32())
	var exp_a: Array = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	var b: Pcg32 = Pcg32.new(1, 1)
	var got_b: Array = [b.next_u32(), b.next_u32(), b.next_u32()]
	var exp_b: Array = [3380776849, 361947764, 3223725655]
	r.check("M1-X1", got_a == exp_a and got_b == exp_b, "42/54=%s 1/1=%s" % [str(got_a), str(got_b)])


static func _x2(r: Report) -> void:
	var a: int = FM.div_trunc(-1 * 58, 64)
	var b: int = FM.div_floor(-58, 64)
	var c: int = FM.div_trunc(7, -2)
	r.check("M1-X2", a == 0 and b == -1 and c == -3, "div_trunc(-58,64)=%d div_floor(-58,64)=%d div_trunc(7,-2)=%d" % [a, b, c])


static func _x3(r: Report) -> void:
	var trace: Array = random_trace(A4_SEEDS_FROM)
	var w1: WorldSim = new_world()
	var w2: WorldSim = new_world()
	for inp: IntInput in trace:
		w1.step(inp)
	for inp: IntInput in trace:
		w2.step(inp)
	_note_error(r, w1)
	_note_error(r, w2)
	r.check("M1-X3", w1.chain == w2.chain and w1.chain != "", "C_K=%s" % w1.chain)
