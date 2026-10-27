class_name M1Gates
extends RefCounted
## Acceptance Gate de M1 (plano §6.2) sobre DungeonGen.test_room(), mais testes auxiliares.


static func run() -> Array:
	var out: Array = []
	out.append(_a1())
	out.append(_a2())
	out.append(_a3())
	out.append(_a4())
	out.append(_a5())
	out.append(_a6())
	out.append_array(_aux())
	return out


static func _a1() -> Dictionary:
	var w := WorldSim.create(1, true)
	GateUtil.run(w, GateUtil.repeat(120, 1, 0, 0))
	var p := w.player
	var ok: bool = p.pos_x == 20644 and p.pos_z == 15360 and p.vel_x == 139
	return GateUtil.res("M1-A1", ok, "pos_x=%d pos_z=%d vel_x=%d" % [p.pos_x, p.pos_z, p.vel_x])


static func _a2() -> Dictionary:
	var w := WorldSim.create(1, true)
	GateUtil.run(w, GateUtil.repeat(60, 0, 1, 0))
	var p := w.player
	var ok: bool = p.pos_x == 5120 and p.pos_z == 9258
	return GateUtil.res("M1-A2", ok, "pos_x=%d pos_z=%d" % [p.pos_x, p.pos_z])


static func _a3() -> Dictionary:
	var details: Array = []
	var ok: bool = true
	for t: int in [64, -64]:
		var w := WorldSim.create(1, true)
		GateUtil.run(w, GateUtil.repeat(64, 0, 0, t))
		var p := w.player
		var good: bool = p.angle == 0 and p.pos_x == 5120 and p.pos_z == 15360
		ok = ok and good
		details.append("turn=%d angle=%d pos=(%d,%d)" % [t, p.angle, p.pos_x, p.pos_z])
	return GateUtil.res("M1-A3", ok, "; ".join(details))


static func random_inputs(n: int) -> Array:
	var rng := RngPcg32.create(7, 99)
	var out: Array = []
	for _k in range(n):
		var m: int = rng.bounded(3) - 1
		var s: int = rng.bounded(3) - 1
		var t: int = rng.bounded(97) - 48
		out.append(IntInput.make(m, s, t))
	return out


static func _a4() -> Dictionary:
	var w := WorldSim.create(1, true)
	var bad: int = GateUtil.run_checked(w, random_inputs(600))
	var p := w.player
	if bad >= 0:
		return GateUtil.res("M1-A4", false, "colisão no tick %d" % bad)
	return GateUtil.res("M1-A4", true, "600 ticks sem interseção; final=(%d,%d)" % [p.pos_x, p.pos_z])


static func _a5() -> Dictionary:
	var w := WorldSim.create(1, true)
	GateUtil.run(w, GateUtil.repeat(120, 1, 0, 0))
	var v0: int = w.player.vel_x
	var stop_tick: int = -1
	var stays: bool = true
	for k in range(1, 121):
		w.step(IntInput.new())
		if stop_tick < 0 and w.player.vel_x == 0:
			stop_tick = k
		elif stop_tick >= 0 and w.player.vel_x != 0:
			stays = false
	var ok: bool = v0 == 139 and stop_tick == 32 and stays
	return GateUtil.res("M1-A5", ok, "v0=%d parou em %d ticks, permanece=%s" % [v0, stop_tick, stays])


static func table_sha() -> String:
	var arr := PackedInt32Array()
	arr.resize(4096)
	for i in range(4096):
		arr[i] = TrigTable.sin_q16(i)
	return Grid.sha256_bytes(arr.to_byte_array())


static func _a6() -> Dictionary:
	var sha: String = table_sha()
	var ctl: bool = TrigTable.sin_q16(0) == 0 and TrigTable.sin_q16(1024) == 65536 \
		and TrigTable.sin_q16(2048) == 0 and TrigTable.sin_q16(3072) == -65536
	return GateUtil.res("M1-A6", sha == TrigTable.TABLE_SHA256 and ctl, "sha=%s controle=%s" % [sha, ctl])


static func _aux() -> Array:
	var out: Array = []
	# PCG32 vetor de referência
	var rng := RngPcg32.create(42, 54)
	var expect: Array = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
	var got: Array = []
	for _k in range(6):
		got.append(rng.next_u32())
	var hexs: Array = got.map(func(v: int) -> String: return "%08x" % v)
	out.append(GateUtil.res("AUX-PCG32", got == expect, ",".join(hexs)))
	# divisões
	var dok: bool = FixedMath.div_trunc(-7, 2) == -3 and FixedMath.div_floor(-7, 2) == -4 \
		and FixedMath.div_trunc(58, 64) == 0 and FixedMath.div_trunc(-58, 64) == 0 \
		and FixedMath.div_floor(-58, 64) == -1
	out.append(GateUtil.res("AUX-DIV", dok, ""))
	# contato de face não colide
	var g: Grid = DungeonGen.test_room().grid
	var face_x: int = 15 * Grid.CELL - PlayerSim.PLAYER_HALF
	var touch: bool = g.box_hits_solid(face_x - 384, 5 * 2048, face_x + 384, 5 * 2048 + 768)
	var over: bool = g.box_hits_solid(face_x - 383, 5 * 2048, face_x + 385, 5 * 2048 + 768)
	out.append(GateUtil.res("AUX-FACE", not touch and over, "encostado=%s invadindo=%s" % [touch, over]))
	# terminal frontal / lateral e parada lateral
	# (angle = 1024: o vetor direito aponta para +X, ao longo da câmara A)
	var w := WorldSim.create(1, true)
	GateUtil.run(w, GateUtil.repeat(16, 0, 0, 64))
	GateUtil.run(w, GateUtil.repeat(180, 0, 1, 0))
	var vx: int = w.player.vel_x
	var n: int = 0
	while w.player.vel_x != 0 and n < 200:
		w.step(IntInput.new())
		n += 1
	out.append(GateUtil.res("AUX-STRAFE-TERM", vx == 118 and n == 31, "vel_x=%d parada=%d" % [vx, n]))
	# R1: duas instâncias, mesma trilha
	var ins: Array = random_inputs(600)
	var w1 := WorldSim.create(1, true)
	var w2 := WorldSim.create(1, true)
	GateUtil.run(w1, ins)
	GateUtil.run(w2, ins)
	out.append(GateUtil.res("R1-M1", w1.chain == w2.chain and not w1.type_error, w1.chain))
	return out
