class_name GateM1
extends RefCounted
## M1-A1..A6 na sala de teste, mais fixed_math e PCG32.

const TERMINAL_FWD: int = 139


static func run(r: GateReport) -> void:
	_pre(r)
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)


static func _pre(r: GateReport) -> void:
	r.check("M1-FM", FixedMath.div_trunc(-7, 2) == -3 and FixedMath.div_floor(-7, 2) == -4
		and FixedMath.div_trunc(58, 64) == 0 and FixedMath.div_trunc(-58, 64) == 0
		and FixedMath.div_floor(7, 2) == 3 and FixedMath.div_floor(-8, 2) == -4
		and FixedMath.div_floor(7, -2) == -4, "div_trunc/div_floor")
	var rng: RngPcg32 = RngPcg32.new(42, 54)
	var expect: Array = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	var got: Array = []
	for i: int in range(6):
		got.append(rng.next_u32())
	r.check("M1-PCG", got == expect, "pcg32(42,54) = %s" % str(got.map(func(v: int) -> String: return "%08x" % v)))


static func _replay(name: String) -> WorldSim:
	var inputs: Array = GateTraces.load_inputs(name)
	var sim: WorldSim = WorldSim.new(1, true)
	for inp: IntInput in inputs:
		sim.step(inp)
	return sim


static func _a1(r: GateReport) -> void:
	var inputs: Array = GateTraces.load_inputs("m1_a1_forward.jsonl")
	var sim: WorldSim = WorldSim.new(1, true)
	var terminal_tick: int = -1
	var held: bool = true
	for inp: IntInput in inputs:
		sim.step(inp)
		if sim.player.vel_x == TERMINAL_FWD and terminal_tick < 0:
			terminal_tick = sim.tick
		elif terminal_tick > 0 and sim.player.vel_x != TERMINAL_FWD:
			held = false
	var p: PlayerSim = sim.player
	r.check("M1-A1", inputs.size() == 120 and p.pos_x == 24740 and p.pos_z == 15360
		and p.vel_x == 139 and p.vel_z == 0,
		"pos=(%d,%d) vel=(%d,%d)" % [p.pos_x, p.pos_z, p.vel_x, p.vel_z])
	r.check("M1-A1-terminal", terminal_tick == 32 and held, "terminal 139 no tick %d, mantida=%s" % [terminal_tick, held])


static func _a2(r: GateReport) -> void:
	var sim: WorldSim = _replay("m1_a2_strafe.jsonl")
	var p: PlayerSim = sim.player
	r.check("M1-A2", sim.tick == 60 and p.pos_x == 9216 and p.pos_z == 9258 and p.vel_z == -118 and p.vel_x == 0,
		"pos=(%d,%d) vel=(%d,%d)" % [p.pos_x, p.pos_z, p.vel_x, p.vel_z])


static func _a3(r: GateReport) -> void:
	var inputs: Array = GateTraces.load_inputs("m1_a3_turn.jsonl")
	var sim: WorldSim = WorldSim.new(1, true)
	var after1: int = -1
	var mid: int = -1
	for i: int in range(inputs.size()):
		sim.step(inputs[i])
		if i == 31:
			mid = sim.player.angle
		if i == 63:
			after1 = sim.player.angle
	r.check("M1-A3", inputs.size() == 128 and after1 == 0 and sim.player.angle == 0 and mid == 2048,
		"angle após +64×64=%d, após -64×64=%d (meio=%d)" % [after1, sim.player.angle, mid])


static func _no_overlap_run(sim: WorldSim, inputs: Array) -> int:
	if sim.player.box_hits(sim.grid):
		return 0
	for inp: IntInput in inputs:
		sim.step(inp)
		if sim.player.box_hits(sim.grid):
			return sim.tick
	return -1


static func _a4(r: GateReport) -> void:
	var inputs: Array = GateTraces.load_inputs("m1_a4_random.jsonl")
	var expected: Array = GateTraces.random_inputs(4242, 600, false)
	var sim: WorldSim = WorldSim.new(1, true)
	var bad: int = _no_overlap_run(sim, inputs)
	r.check("M1-A4", inputs.size() == 600 and GateTraces.same_inputs(inputs, expected) and bad < 0,
		"600 ticks PCG(4242,3), primeiro tick violado=%d" % bad)
	# Contra paredes: frente até a parede leste, giro e corrida em diagonal até quinas/pilar.
	var wall: WorldSim = WorldSim.new(1, true)
	var drive: Array = GateTraces.repeat(400, IntInput.new(1, 0, 0))
	var bad2: int = _no_overlap_run(wall, drive)
	r.check("M1-A4-wall", bad2 < 0 and wall.player.pos_x == 30 * 2048 - 384 and wall.player.vel_x == 0,
		"pos_x encostado=%d (esperado %d)" % [wall.player.pos_x, 30 * 2048 - 384])
	var diag: WorldSim = WorldSim.new(1, true)
	diag.set_player_pose(9216, 15360, 3584)  # sudeste
	var seq: Array = GateTraces.repeat(300, IntInput.new(1, 1, 0)) + GateTraces.repeat(300, IntInput.new(1, -1, 7))
	var bad3: int = _no_overlap_run(diag, seq)
	var touched: bool = diag.player.pos_z - 384 == 2 * 2048 or diag.player.pos_x + 384 == 30 * 2048
	r.check("M1-A4-corner", bad3 < 0, "diagonal/quinas sem interseção (tick violado=%d, encostou=%s)" % [bad3, touched])
	var pil: WorldSim = WorldSim.new(1, true)
	pil.set_player_pose(39 * 1024, 21 * 1024, 0)  # oeste do pilar [20,21]×[10,11]
	var bad4: int = _no_overlap_run(pil, GateTraces.repeat(120, IntInput.new(1, 0, 0)))
	r.check("M1-A4-pillar", bad4 < 0 and pil.player.pos_x == 20 * 2048 - 384,
		"pos_x no pilar=%d (esperado %d)" % [pil.player.pos_x, 20 * 2048 - 384])


static func _a5(r: GateReport) -> void:
	var inputs: Array = GateTraces.load_inputs("m1_a5_stop.jsonl")
	var sim: WorldSim = WorldSim.new(1, true)
	var at_release: int = -1
	var zero_after: int = -1
	for i: int in range(inputs.size()):
		sim.step(inputs[i])
		if i == 39:
			at_release = sim.player.vel_x
		if i >= 40 and zero_after < 0 and sim.player.vel_x == 0:
			zero_after = i - 39
	r.check("M1-A5", inputs.size() == 80 and at_release == TERMINAL_FWD and zero_after == 32,
		"vel na soltura=%d, zera após %d ticks sem comando" % [at_release, zero_after])


static func _a6(r: GateReport) -> void:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(4096 * 4)
	for i: int in range(4096):
		bytes.encode_s32(i * 4, TrigTable.SIN_Q16[i])
	var h: String = StateHash.sha256_bytes(bytes)
	var ref: String = "dd6a64fbcbc4bfb38e59940b6ed273b1fc828b19111416444b3066e9b09d43c1"
	r.check("M1-A6", h == ref and TrigTable.TABLE_SHA256 == ref, "sha=%s" % h)
