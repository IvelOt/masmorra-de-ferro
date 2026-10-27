class_name M3Gates
extends RefCounted
## Acceptance Gate de M3 (plano 2 §6.1) sobre DungeonGen.test_room(), mais testes auxiliares.
## Jogador em (5120, 15360), angle = 0; 1,2 m à frente = (6349, 15360).

const FRONT: Array = [6349, 15360]
const DEG60: Array = [5733, 16424]
const DEG30: Array = [6184, 15973]
const BACK: Array = [3891, 15360]


static func run() -> Array:
	var out: Array = []
	out.append(_a1())
	out.append(_a2())
	out.append(_a3())
	out.append(_a4())
	out.append(_a5())
	out.append(_a6())
	out.append(_a7())
	out.append_array(_aux())
	return out


static func inp(attack: bool, block: bool, move: int = 0) -> IntInput:
	var i := IntInput.make(move, 0, 0)
	i.attack = attack
	i.block = block
	return i


static func world_with(dummies: Array) -> WorldSim:
	var w := WorldSim.create(1, true)
	for d: Array in dummies:
		w.add_dummy(d[0], d[1])
	return w


static func _expected_swing(t: int) -> String:
	if t <= 6:
		return "WINDUP"
	if t <= 12:
		return "ACTIVE"
	if t <= 24:
		return "RECOVERY"
	return "IDLE"


static func _a1() -> Dictionary:
	var ok: bool = true
	var detail: String = ""
	for second: bool in [false, true]:
		var w := world_with([])
		for t in range(1, 26):
			w.step(inp(t == 1 or (second and t == 25), false))
			var want: String = _expected_swing(t)
			if second and t == 25:
				want = "WINDUP"
			if t == 1 and w.player.stamina != 88:
				ok = false
				detail += " stamina=%d no tick 1" % w.player.stamina
			if w.player.swing_state != want:
				ok = false
				detail += " caso%d tick %d: %s != %s" % [2 if second else 1, t, w.player.swing_state, want]
				break
	return GateUtil.res("M3-A1", ok, detail if detail != "" else "WINDUP 1-6, ACTIVE 7-12, RECOVERY 13-24, IDLE 25; reataque no 25")


static func _a2() -> Dictionary:
	var w := world_with([FRONT])
	var hp_by_tick: Array = []
	for t in range(1, 26):
		w.step(inp(t == 1, false))
		hp_by_tick.append(w.enemies[0].hp)
	var front_ok: bool = hp_by_tick[5] == 100 and hp_by_tick[6] == 75 and hp_by_tick[24] == 75
	var w2 := world_with([DEG60])
	for t in range(1, 26):
		w2.step(inp(t == 1, false))
	var side_ok: bool = w2.enemies[0].hp == 100
	return GateUtil.res("M3-A2", front_ok and side_ok, "frente: hp t6=%d t7=%d t25=%d; 60°: hp=%d" % [hp_by_tick[5], hp_by_tick[6], hp_by_tick[24], w2.enemies[0].hp])


static func _a3() -> Dictionary:
	var w := world_with([[5120 + 300, 15360], FRONT])
	var ok: bool = true
	var detail: String = ""
	for t in range(1, 25):
		w.step(inp(t == 1, false))
		if t >= 7:
			var hp0: int = w.enemies[0].hp
			var hp1: int = w.enemies[1].hp
			if hp0 != 75 or hp1 != 75 or w.player.swing_hits != [0, 1]:
				ok = false
				detail = "tick %d: hp=%d,%d hits=%s" % [t, hp0, hp1, w.player.swing_hits]
				break
	return GateUtil.res("M3-A3", ok, detail if detail != "" else "hp=75,75 ticks 7-24; swing_hits=[0, 1]")


static func _a4() -> Dictionary:
	var w := world_with([])
	w.player.stamina = 11
	w.step(inp(true, false))
	var ok: bool = w.player.swing_state == "IDLE" and w.player.stamina == 11
	return GateUtil.res("M3-A4", ok, "swing=%s stamina=%d" % [w.player.swing_state, w.player.stamina])


static func _a5() -> Dictionary:
	var a := world_with([])
	a.inject_hit(FRONT[0], FRONT[1], 25)
	a.step(inp(false, true))
	var a_ok: bool = a.player.hp == 93 and a.player.stamina == 83 and a.player.blocking
	var b := world_with([])
	b.inject_hit(BACK[0], BACK[1], 25)
	b.step(inp(false, true))
	var b_ok: bool = b.player.hp == 75 and b.player.stamina == 100
	var c := world_with([])
	c.inject_hit(FRONT[0], FRONT[1], 25)
	c.step(inp(false, false))
	var c_ok: bool = c.player.hp == 75
	return GateUtil.res("M3-A5", a_ok and b_ok and c_ok, "(a) hp=%d st=%d blk=%s (b) hp=%d st=%d (c) hp=%d" % [
		a.player.hp, a.player.stamina, a.player.blocking, b.player.hp, b.player.stamina, c.player.hp])


static func _a6() -> Dictionary:
	var ok: bool = true
	var detail: String = ""
	for last_block: bool in [true, false]:
		var w := world_with([])
		w.player.stamina = 10
		w.inject_hit(FRONT[0], FRONT[1], 25)
		w.step(inp(false, true))
		var p := w.player
		if not (p.hp == 75 and p.stun_ticks == 20 and p.stamina == 10 and not p.blocking):
			return GateUtil.res("M3-A6", false, "após T: hp=%d stun=%d st=%d blk=%s" % [p.hp, p.stun_ticks, p.stamina, p.blocking])
		for k in range(1, 21):
			w.step(inp(true, true))
			if p.stun_ticks != 20 - k or p.blocking or p.swing_state != "IDLE":
				return GateUtil.res("M3-A6", false, "k=%d: stun=%d blk=%s swing=%s" % [k, p.stun_ticks, p.blocking, p.swing_state])
		w.step(inp(true, last_block))
		if last_block:
			ok = ok and p.blocking and p.swing_state == "IDLE"
			detail += "tick22 block: blk=%s swing=%s; " % [p.blocking, p.swing_state]
		else:
			ok = ok and p.swing_state == "WINDUP"
			detail += "tick22 só attack: swing=%s st=%d" % [p.swing_state, p.stamina]
	return GateUtil.res("M3-A6", ok, detail)


static func _a7() -> Dictionary:
	var rng := RngPcg32.create(13, 99)
	var dmgs: Array = [5, 12, 25]
	var w := world_with([FRONT])
	var p := w.player
	for t in range(1, 601):
		var i := IntInput.make(rng.bounded(3) - 1, rng.bounded(3) - 1, rng.bounded(97) - 48)
		i.attack = rng.bounded(4) == 0
		i.block = rng.bounded(3) == 0
		if t % 37 == 0:
			var sx: int = p.pos_x + ((1229 * TrigTable.cos_q16(p.angle)) >> 16)
			var sz: int = p.pos_z + ((1229 * TrigTable.sin_q16(p.angle)) >> 16)
			w.inject_hit(sx, sz, dmgs[rng.bounded(3)])
		w.step(i)
		if p.stamina < 0 or p.stamina > p.stamina_max or p.hp < 0 or p.hp > p.hp_max:
			return GateUtil.res("M3-A7", false, "violado no tick %d: hp=%d stamina=%d" % [t, p.hp, p.stamina])
	return GateUtil.res("M3-A7", true, "600 ticks; final hp=%d stamina=%d" % [p.hp, p.stamina])


static func _full_swing(w: WorldSim) -> void:
	for t in range(1, 25):
		w.step(inp(t == 1, false))


static func _aux() -> Array:
	var out: Array = []
	# hitbox a 30°: acerta; de costas: não
	var w30 := world_with([DEG30])
	_full_swing(w30)
	out.append(GateUtil.res("AUX-HIT-30", w30.enemies[0].hp == 75, "hp=%d" % w30.enemies[0].hp))
	var wb := world_with([BACK])
	_full_swing(wb)
	out.append(GateUtil.res("AUX-HIT-BACK", wb.enemies[0].hp == 100, "hp=%d" % wb.enemies[0].hp))
	# 4 golpes matam; o 5º não muda nada
	var wk := world_with([FRONT])
	for _s in range(4):
		_full_swing(wk)
		wk.step(inp(false, false))
	var e: EntitySim = wk.enemies[0]
	var dead4: bool = e.hp == 0 and e.state == "DEAD"
	var hits5: bool = false
	for t in range(1, 25):
		wk.step(inp(t == 1, false))
		hits5 = hits5 or not wk.player.swing_hits.is_empty()
	var ok5: bool = dead4 and e.hp == 0 and e.state == "DEAD" and not hits5
	out.append(GateUtil.res("AUX-KILL", ok5, "após 4: hp=%d %s; 5º acertou=%s" % [e.hp, e.state, hits5]))
	# bloqueio reduz o empuxo pela metade
	var wm := world_with([])
	for _t in range(120):
		wm.step(inp(false, true, 1))
	out.append(GateUtil.res("AUX-BLOCK-MOVE", wm.player.pos_x == 12417 and wm.player.vel_x == 65, "pos_x=%d vel_x=%d" % [wm.player.pos_x, wm.player.vel_x]))
	# regeneração: +1 a cada 3 ticks
	var wr := world_with([])
	wr.player.stamina = 50
	GateUtil.run(wr, GateUtil.repeat(30, 0, 0, 0))
	out.append(GateUtil.res("AUX-REGEN", wr.player.stamina == 60, "stamina=%d" % wr.player.stamina))
	# pending_hits vazio após cada step()
	var wp := world_with([])
	var empty: bool = true
	for t in range(1, 41):
		if t % 5 == 0:
			wp.inject_hit(FRONT[0], FRONT[1], 1)
			wp.inject_hit(BACK[0], BACK[1], 1)
		wp.step(inp(false, t % 2 == 0))
		empty = empty and wp.pending_hits.is_empty()
	out.append(GateUtil.res("AUX-PENDING", empty, "hp=%d" % wp.player.hp))
	return out
