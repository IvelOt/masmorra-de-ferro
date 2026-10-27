extends RefCounted
## Acceptance Gate de M3 (plano da rodada 2, §8.2): M3-A1 a M3-A7 e a trilha
## dourada m3_dummy_4_swings.jsonl.

const GateM1 = preload("res://tests/gates/gate_m1.gd")
const TRACES: String = "res://tests/traces/"


static func run(results: Array[Dictionary]) -> void:
	_trace_4_swings(results)
	_a1(results)
	_a2(results)
	_a3(results)
	_a4(results)
	_a5(results)
	_a6(results)
	_a7(results)


static func _inp(attack: bool = false, block: bool = false) -> IntInput:
	var i: IntInput = IntInput.new()
	i.attack = attack
	i.block = block
	return i


static func _trace_4_swings(results: Array[Dictionary]) -> void:
	var trace: Array[IntInput] = TraceIO.load_trace(TRACES + "m3_dummy_4_swings.jsonl")
	var w: WorldSim = WorldSim.create(1, "combat")
	var got: Dictionary = {}
	for inp in trace:
		w.step(inp)
		if w.tick in [7, 31, 55, 79]:
			got["hp%d" % w.tick] = w.enemies[0].hp
		if w.tick == 79:
			got["dead79"] = w.enemies[0].state == EnemySim.DEAD
		if w.tick == 96 or w.tick == 100:
			got["st%d" % w.tick] = w.player.stamina
	var exp: Dictionary = {"hp7": 75, "hp31": 50, "hp55": 25, "hp79": 0, "dead79": true, "st96": 52, "st100": 53}
	GateM1.check(results, "M3-TRACE", trace.size() == 100 and got == exp, exp, got)


static func _a1(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "combat")
	var non_idle: Array[int] = []
	var active: Array[int] = []
	var idle25: bool = false
	for t in range(1, 26):
		w.step(_inp(t == 1))
		if w.player.swing_state != Combat.S_IDLE:
			non_idle.append(t)
		if w.player.swing_state == Combat.S_ACTIVE:
			active.append(t)
		if t == 25:
			idle25 = w.player.swing_state == Combat.S_IDLE
	var ok: bool = str(non_idle) == str(range(1, 25)) and str(active) == str([7, 8, 9, 10, 11, 12]) and idle25
	GateM1.check(results, "M3-A1", ok, "não-IDLE 1-24, ACTIVE 7-12, IDLE em 25",
		"não-IDLE %s, ACTIVE %s, IDLE em 25=%s" % [str(non_idle), str(active), idle25])


static func _a2(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "combat")
	var hp_at: Dictionary = {}
	for t in range(1, 25):
		w.step(_inp(t == 1))
		hp_at[t] = w.enemies[0].hp
	var front_ok: bool = hp_at[6] == 100 and hp_at[7] == 75 and hp_at[24] == 75
	var w2: WorldSim = WorldSim.create(1, "test")
	w2.add_enemy(EnemySim.DUMMY, 5120 + 614, 15360 + 1064)
	for t in range(1, 25):
		w2.step(_inp(t == 1))
	var side_ok: bool = w2.enemies[0].hp == 100
	GateM1.check(results, "M3-A2", front_ok and side_ok,
		"frente: 100 -> 75 no tick 7 e 75 no 24; 60 graus: 100",
		"frente: tick6=%d tick7=%d tick24=%d; 60 graus: %d" % [hp_at[6], hp_at[7], hp_at[24], w2.enemies[0].hp])


static func _a3(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "combat")
	for t in range(1, 25):
		w.step(_inp(t == 1))
	var dmg: int = 100 - w.enemies[0].hp
	GateM1.check(results, "M3-A3", dmg == 25 and str(w.player.swing_hits) == str([0]),
		"dano 25, swing_hits [0]", "dano %d, swing_hits %s" % [dmg, str(w.player.swing_hits)])


static func _a4(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "combat")
	w.player.stamina = 11
	w.step(_inp(true))
	GateM1.check(results, "M3-A4", w.player.swing_state == Combat.S_IDLE and w.player.stamina == 11,
		"IDLE e stamina 11", "swing_state %d, stamina %d" % [w.player.swing_state, w.player.stamina])


static func _a5(results: Array[Dictionary]) -> void:
	var trace: Array[IntInput] = TraceIO.load_trace(TRACES + "m3_block_front.jsonl")
	var f: WorldSim = WorldSim.create(1, "test")
	f.inject_hit(5120 + 1500, 15360, 25)
	f.step(trace[0])
	var b: WorldSim = WorldSim.create(1, "test")
	b.inject_hit(5120 - 1500, 15360, 25)
	b.step(trace[0])
	var ok: bool = f.player.hp == 93 and f.player.stamina == 83 and b.player.hp == 75 and b.player.stamina == 100
	GateM1.check(results, "M3-A5", ok, "frente hp 93 stamina 83; costas hp 75 stamina 100",
		"frente hp %d stamina %d; costas hp %d stamina %d" % [f.player.hp, f.player.stamina, b.player.hp, b.player.stamina])


static func _a6(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "test")
	w.player.stamina = 10
	w.inject_hit(5120 + 1500, 15360, 25)
	w.step(_inp(false, true))
	var p: PlayerSim = w.player
	var first: bool = p.hp == 75 and p.stamina == 0 and p.stun_ticks == 20 and not p.blocking
	var detail: String = "tick1 hp=%d stamina=%d stun=%d blocking=%s" % [p.hp, p.stamina, p.stun_ticks, p.blocking]
	w.player.stamina = 100
	var refused: bool = true
	for t in range(2, 22):
		w.step(_inp(true, true))
		if w.player.swing_state != Combat.S_IDLE or w.player.blocking:
			refused = false
			detail += "; aceito no tick %d" % t
			break
	w.step(_inp(true))
	var accepted: bool = w.player.swing_state == Combat.S_WINDUP
	detail += "; tick22 swing_state=%d" % w.player.swing_state
	GateM1.check(results, "M3-A6", first and refused and accepted,
		"hp 75, stamina 0, stun 20, blocking false; attack/block recusados 2-21; WINDUP no 22", detail)


static func _a7(results: Array[Dictionary]) -> void:
	var w: WorldSim = WorldSim.create(1, "combat")
	var rng: RngPcg32 = RngPcg32.create(2, RngPcg32.STREAM_PILOT)
	var bad: String = ""
	for k in range(600):
		var inp: IntInput = IntInput.new()
		inp.move = rng.next_range(3) - 1
		inp.strafe = rng.next_range(3) - 1
		inp.turn = rng.next_range(257) - 128
		inp.attack = rng.next_range(8) == 0
		inp.block = rng.next_range(3) == 0
		if k % 20 == 0:
			var fx: int = TrigTable.cos_q16(w.player.angle)
			var fz: int = TrigTable.sin_q16(w.player.angle)
			w.inject_hit(w.player.pos_x + ((1500 * fx) >> 16), w.player.pos_z + ((1500 * fz) >> 16), 12)
		w.step(inp)
		var p: PlayerSim = w.player
		if p.stamina < 0 or p.stamina > p.stamina_max or p.hp < 0 or p.hp > p.hp_max \
				or p.stun_ticks < 0 or p.stun_ticks > 20:
			bad = "tick %d: stamina=%d hp=%d stun=%d" % [w.tick, p.stamina, p.hp, p.stun_ticks]
			break
	GateM1.check(results, "M3-A7", bad == "", "invariantes de stamina/hp/stun em 600 ticks", bad)
