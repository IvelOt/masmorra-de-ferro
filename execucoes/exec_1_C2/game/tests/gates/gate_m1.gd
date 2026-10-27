extends RefCounted
## Acceptance Gate de M1 (plano §4.5): M1-A1 a M1-A6 na sala de teste fixa.

const TRACES: String = "res://tests/traces/"
const START_X: int = 5120
const START_Z: int = 15360


static func run(results: Array[Dictionary]) -> void:
	_a1(results)
	_a2(results)
	_a3(results)
	_a4(results)
	_a5(results)
	_a6(results)


static func check(results: Array[Dictionary], id: String, ok: bool, expected: Variant, got: Variant) -> void:
	results.append({"id": id, "pass": ok, "detail": "" if ok else "esperado %s, obtido %s" % [str(expected), str(got)]})


static func replay(trace_name: String) -> WorldSim:
	var w: WorldSim = WorldSim.create(1, "test")
	for inp in TraceIO.load_trace(TRACES + trace_name):
		w.step(inp)
	return w


static func _a1(results: Array[Dictionary]) -> void:
	var w: WorldSim = replay("m1_forward_120.jsonl")
	var exp: Dictionary = {"pos_x": 20644, "pos_z": 15360, "vel_x": 139, "vel_z": 0, "angle": 0}
	check(results, "M1-A1", w.tick == 120 and w.player.to_dict() == exp, exp, w.player.to_dict())


static func _a2(results: Array[Dictionary]) -> void:
	var w: WorldSim = replay("m1_strafe_60.jsonl")
	var exp: Dictionary = {"pos_x": 5120, "pos_z": 9258, "vel_x": 0, "vel_z": -118, "angle": 0}
	check(results, "M1-A2", w.tick == 60 and w.player.to_dict() == exp, exp, w.player.to_dict())


static func _a3(results: Array[Dictionary]) -> void:
	var trace: Array[IntInput] = TraceIO.load_trace(TRACES + "m1_turn_roundtrip.jsonl")
	var w: WorldSim = WorldSim.create(1, "test")
	var angles: Array[int] = []
	for k in range(trace.size()):
		w.step(trace[k])
		if k == 63 or k == 127:
			angles.append(w.player.angle)
	var still: bool = w.player.pos_x == START_X and w.player.pos_z == START_Z \
		and w.player.vel_x == 0 and w.player.vel_z == 0
	check(results, "M1-A3", trace.size() == 128 and angles == [0, 0] and still,
		"angle [0, 0] em (5120, 15360)", "angle %s em (%d, %d)" % [str(angles), w.player.pos_x, w.player.pos_z])


## 600 ticks aleatórios do PCG32(seed=1, seq=3); invariante checado a cada tick.
static func _a4(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "test")
	var rng: RngPcg32 = RngPcg32.create(1, RngPcg32.STREAM_PILOT)
	var bad_tick: int = -1
	for k in range(600):
		var inp: IntInput = IntInput.new()
		inp.move = rng.next_range(3) - 1
		inp.strafe = rng.next_range(3) - 1
		inp.turn = rng.next_range(257) - 128
		w.step(inp)
		if w.player.box_hits(w.grid) or w.player.angle < 0 or w.player.angle >= 4096:
			bad_tick = w.tick
			break
	check(results, "M1-A4", bad_tick < 0, "nenhuma interseção em 600 ticks", "interseção no tick %d" % bad_tick)


## Para em exatamente 32 ticks após A1 (31 após A2) e permanece parado.
static func _a5(results: Array[Dictionary]) -> void:
	var trace: Array[IntInput] = TraceIO.load_trace(TRACES + "m1_forward_stop.jsonl")
	var w: WorldSim = WorldSim.create(1, "test")
	var stop_x: int = -1
	for k in range(trace.size()):
		w.step(trace[k])
		if k >= 120 and stop_x < 0 and w.player.vel_x == 0:
			stop_x = w.tick - 120
		if stop_x >= 0 and w.player.vel_x != 0:
			stop_x = -2
			break
	var strafe: WorldSim = replay("m1_strafe_60.jsonl")
	var stop_z: int = -1
	for k in range(40):
		strafe.step(IntInput.new())
		if stop_z < 0 and strafe.player.vel_z == 0:
			stop_z = k + 1
		if stop_z >= 0 and strafe.player.vel_z != 0:
			stop_z = -2
			break
	check(results, "M1-A5", stop_x == 32 and stop_z == 31, "frente 32, strafe 31", "frente %d, strafe %d" % [stop_x, stop_z])


static func _a6(results: Array[Dictionary]) -> void:
	const REF: String = "dd6a64fbcbc4bfb38e59940b6ed273b1fc828b19111416444b3066e9b09d43c1"
	var ctx: HashingContext = HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(TrigTable.SIN_Q16.size() * 4)
	for i in range(TrigTable.SIN_Q16.size()):
		bytes.encode_s32(i * 4, TrigTable.SIN_Q16[i])
	ctx.update(bytes)
	var runtime: String = ctx.finish().hex_encode()
	check(results, "M1-A6", TrigTable.TABLE_SHA256 == REF and runtime == REF, REF,
		"const %s, calculado %s" % [TrigTable.TABLE_SHA256, runtime])
