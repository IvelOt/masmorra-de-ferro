class_name GateM3
extends RefCounted
## M3-A1..A8 na sala de teste, sem inimigos além do boneco (plano da iteração 2 §5.1).

const SPAWN_X: int = 9216
const SPAWN_Z: int = 15360


static func run(r: GateReport) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)
	_a7(r)
	_a8(r)


static func _room() -> WorldSim:
	return WorldSim.new(1, true)


static func _swing() -> Array:
	return [IntInput.new(0, 0, 0, true)] + GateTraces.repeat(23, IntInput.new())


static func _a1(r: GateReport) -> void:
	var inputs: Array = GateTraces.load_inputs("m3_a1_swing.jsonl")
	var trace_ok: bool = GateTraces.same_inputs(inputs, GateTraces.fixed()["m3_a1_swing.jsonl"])
	var sim: WorldSim = _room()
	var states: Array = []
	var stamina1: int = -1
	for inp: IntInput in inputs:
		sim.step(inp)
		states.append(sim.player.swing_state)
		if sim.tick == 1:
			stamina1 = sim.player.stamina
	var ok: bool = trace_ok and states.size() == 31
	var active: Array = []
	for t: int in range(1, states.size() + 1):
		var want: int = 0
		if t <= 6:
			want = Combat.WINDUP
		elif t <= 12:
			want = Combat.ACTIVE
		elif t <= 24:
			want = Combat.RECOVERY
		if int(states[t - 1]) != want:
			ok = false
		if int(states[t - 1]) == Combat.ACTIVE:
			active.append(t)
	r.check("M3-A1", ok and stamina1 == 88 and active == [7, 8, 9, 10, 11, 12],
		"estados=%s ativo=%s stamina(t1)=%d" % [str(states.slice(0, 26)), str(active), stamina1])


static func _a2(r: GateReport) -> void:
	var a: WorldSim = _room()
	var ida: int = a.add_enemy(EnemySim.DUMMY, SPAWN_X + 1229, SPAWN_Z)
	for inp: IntInput in _swing():
		a.step(inp)
	var hpa: int = (a.enemies[ida] as EnemySim.Enemy).hp
	r.check("M3-A2a", hpa == 75, "boneco a 1,2 m de frente: hp=%d (esperado 75)" % hpa)
	var b: WorldSim = _room()
	var idb: int = b.add_enemy(EnemySim.DUMMY, SPAWN_X + 615, SPAWN_Z + 1064)
	for inp: IntInput in _swing():
		b.step(inp)
	var hpb: int = (b.enemies[idb] as EnemySim.Enemy).hp
	r.check("M3-A2b", hpb == 100, "boneco a 1,2 m e 60°: hp=%d (esperado 100)" % hpb)


static func _a3(r: GateReport) -> void:
	var sim: WorldSim = _room()
	var id: int = sim.add_enemy(EnemySim.DUMMY, SPAWN_X + 1229, SPAWN_Z)
	var dummy: EnemySim.Enemy = sim.enemies[id]
	var drops: Array = []
	var hits_ok: bool = true
	var prev: int = dummy.hp
	for inp: IntInput in _swing():
		sim.step(inp)
		if dummy.hp != prev:
			drops.append([sim.tick, prev - dummy.hp])
			prev = dummy.hp
		if sim.tick >= 7 and sim.tick <= 24 and sim.player.swing_hits != [id]:
			hits_ok = false
	var first_ok: bool = drops.size() == 1 and int(drops[0][1]) == 25 \
		and int(drops[0][0]) >= 7 and int(drops[0][0]) <= 12
	var reset_ok: bool = false
	for inp: IntInput in _swing() + [IntInput.new()]:
		sim.step(inp)
		if sim.tick == 25:
			reset_ok = sim.player.swing_hits.is_empty()
	r.check("M3-A3", first_ok and hits_ok and reset_ok and dummy.hp == 50,
		"quedas no 1º golpe=%s swing_hits==[id] em 7..24=%s; após o 2º hp=%d" % [str(drops), hits_ok, dummy.hp])


static func _a4(r: GateReport) -> void:
	var a: WorldSim = _room()
	a.player.stamina = 11
	a.step(IntInput.new(0, 0, 0, true))
	var b: WorldSim = _room()
	b.player.stamina = 12
	b.step(IntInput.new(0, 0, 0, true))
	r.check("M3-A4", a.tick == 1 and a.player.swing_state == 0 and a.player.stamina == 11
		and b.player.swing_state == Combat.WINDUP and b.player.stamina == 0,
		"stamina 11: estado=%d vigor=%d; stamina 12: estado=%d vigor=%d" % [
			a.player.swing_state, a.player.stamina, b.player.swing_state, b.player.stamina])


## Um golpe de `dmg` vindo de (dx, dz) relativo ao jogador, com block mantido.
static func _blocked_hit(dx: int, dz: int, dmg: int) -> Array:
	var sim: WorldSim = _room()
	sim.queue_hit(sim.player.pos_x + dx, sim.player.pos_z + dz, dmg)
	sim.step(IntInput.new(0, 0, 0, false, true))
	return [sim.player.hp, sim.player.stamina]


static func _a5(r: GateReport) -> void:
	var f: Array = _blocked_hit(1024, 0, 25)
	r.check("M3-A5a", f == [93, 83], "frontal 25 com bloqueio: hp=%d vigor=%d (esperado 93, 83)" % f)
	var b: Array = _blocked_hit(-1024, 0, 25)
	r.check("M3-A5b", b == [75, 100], "costas 25 com bloqueio: hp=%d vigor=%d (esperado 75, 100)" % b)
	var c12: Array = _blocked_hit(1024, 0, 12)
	var c5: Array = _blocked_hit(1024, 0, 5)
	r.check("M3-A5c", c12 == [97, 89] and c5 == [98, 93],
		"frontal 12 -> perde %d (vigor %d); frontal 5 -> perde %d (vigor %d). Fórmula dano - div_trunc(dano*3,4) prevalece sobre o '25%%' do GDD" % [
			100 - int(c12[0]), c12[1], 100 - int(c5[0]), c5[1]])


static func _a6(r: GateReport) -> void:
	var inputs: Array = GateTraces.load_inputs("m3_a6_guardbreak.jsonl")
	var trace_ok: bool = GateTraces.same_inputs(inputs, GateTraces.m3_a6_inputs())
	var sim: WorldSim = _room()
	sim.player.stamina = 10
	sim.queue_hit(sim.player.pos_x + 1024, sim.player.pos_z, 25)
	var hp_t: int = -1
	var stun_t: int = -1
	var guard_off: bool = true
	var state_t20: int = -1
	var state_t21: int = -1
	for inp: IntInput in inputs:
		sim.step(inp)
		var t: int = sim.tick
		if t == 1:
			hp_t = sim.player.hp
			stun_t = sim.player.stun_ticks
		elif t >= 2 and t <= 21 and sim.player.blocking:
			guard_off = false
		if t == 21:
			state_t20 = sim.player.swing_state
		if t == 22:
			state_t21 = sim.player.swing_state
	r.check("M3-A6", trace_ok and hp_t == 75 and stun_t == 20 and guard_off
		and state_t20 == 0 and state_t21 == Combat.WINDUP,
		"T=1: hp=%d stun=%d; sem guarda em T+1..T+20=%s; attack em T+20 -> %d, em T+21 -> %d" % [
			hp_t, stun_t, guard_off, state_t20, state_t21])


static func _a7(r: GateReport) -> void:
	var rng: RngPcg32 = RngPcg32.new(4343, DungeonGen.STREAM_PILOT)
	var inputs: Array = GateTraces.random_inputs_rng(rng, 600, false, true)
	var trace: Array = GateTraces.load_inputs("m3_a7_random.jsonl")
	var trace_ok: bool = GateTraces.same_inputs(trace, inputs)
	var sim: WorldSim = _room()
	sim.add_enemy(EnemySim.DUMMY, SPAWN_X + 1229, SPAWN_Z)
	var bad: int = -1
	var why: String = ""
	var hits: int = 0
	for inp: IntInput in trace:
		if (sim.tick + 1) - FixedMath.div_floor(sim.tick + 1, 15) * 15 == 0:
			var p: PlayerSim = sim.player
			# Golpe frontal: origem 1 m à frente; dano sorteado no mesmo fluxo depois das entradas.
			sim.queue_hit(p.pos_x + ((TrigTable.cos_q16(p.angle) * 1024) >> 16),
				p.pos_z + ((TrigTable.sin_q16(p.angle) * 1024) >> 16), rng.range_i(5, 25))
			hits += 1
		sim.step(inp)
		var pl: PlayerSim = sim.player
		if pl.stamina < 0 or pl.stamina > PlayerSim.STAMINA_MAX:
			why = "stamina=%d" % pl.stamina
		elif pl.hp < 0:
			why = "hp=%d" % pl.hp
		elif pl.swing_ticks < 0 or pl.swing_ticks > Combat.SWING_TOTAL:
			why = "swing_ticks=%d" % pl.swing_ticks
		elif pl.stun_ticks < 0 or pl.stun_ticks > Combat.STUN_TICKS:
			why = "stun_ticks=%d" % pl.stun_ticks
		elif pl.box_hits(sim.grid):
			why = "caixa em célula sólida"
		if why != "":
			bad = sim.tick
			break
	r.check("M3-A7", trace_ok and trace.size() == 600 and bad < 0,
		"600 ticks PCG(4343,3) com attack/block e %d golpes; primeiro tick violado=%d %s" % [hits, bad, why])


static func _a8(r: GateReport) -> void:
	var sub: GateReport = GateReport.new()
	sub.quiet = true
	GateM1.run(sub)
	r.check("M3-A8", sub.failed == 0 and sub.passed > 0,
		"M1-A1..A6 reexecutados com block=false: %d PASS, %d FAIL" % [sub.passed, sub.failed])
