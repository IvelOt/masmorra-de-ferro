extends RefCounted
## Gate M3 (combate do Guerreiro): M3-A1..A7, X1..X4 sobre setup_test("room") + spawn_dummy;
## M3-V1 (cena em headless) roda em run_vis() porque precisa da árvore pronta.

const Grid = preload("res://sim/grid.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const Pcg32 = preload("res://sim/rng_pcg32.gd")
const Report = preload("res://tests/gates/gate_report.gd")

const SPAWN_X: int = 7168
const SPAWN_Z: int = 15360
## Boneco a 1,2 m de frente e a 1,2 m a 60° (BAM 683).
const FRONT_X: int = 8397
const FRONT_Z: int = 15360
const SIDE60_X: int = 7781
const SIDE60_Z: int = 16424
const A7_SEED_FROM: int = 4242
const A7_SEED_COUNT: int = 10
const A7_TICKS: int = 600
const A7_HOLD: int = 15
const A7_HIT_EVERY: int = 37
const A7_HIT_DIST: int = 1229
## Os 8 vizinhos (dx, dz) usados como origem dos golpes injetados.
const NEIGHBORS: Array = [[1, 0], [1, 1], [0, 1], [-1, 1], [-1, 0], [-1, -1], [0, -1], [1, -1]]
const MAIN_SCENE: String = "res://view/main.tscn"


static func new_world() -> WorldSim:
	var w: WorldSim = WorldSim.new()
	w.setup_test("room")
	return w


static func _note_error(r: Report, w: WorldSim) -> void:
	if w.hash_error:
		r.runtime_error = true


static func atk() -> IntInput:
	var i: IntInput = IntInput.new()
	i.attack = true
	return i


## Trilha de M3-A7: [{inp, hit}] por tick; `hit` é {dmg, dir} injetado antes do tick, ou {}.
## Ordem do PCG: no início de cada bloco de 15 ticks move, strafe, turn, attack, block;
## a cada 37 ticks (antes do tick) dmg e direção.
static func a7_trace(seed_value: int) -> Array:
	var rng: Pcg32 = Pcg32.new(seed_value, Pcg32.STREAM_PILOT)
	var out: Array = []
	var held: IntInput = IntInput.new()
	for t in range(A7_TICKS):
		var cur: IntInput = held
		if t % A7_HOLD == 0:
			var mv: int = rng.next_bounded(3) - 1
			var st: int = rng.next_bounded(3) - 1
			var tu: int = rng.next_bounded(257) - 128
			var at: bool = rng.next_bounded(4) == 0
			var bl: bool = rng.next_bounded(3) == 0
			held = IntInput.new(mv, st, tu)
			held.block = bl
			cur = IntInput.new(mv, st, tu)
			cur.block = bl
			cur.attack = at
		var hit: Dictionary = {}
		if t % A7_HIT_EVERY == 0:
			hit = {"dmg": rng.next_bounded(30) + 1, "dir": rng.next_bounded(8)}
		out.append({"inp": cur, "hit": hit})
	return out


## Aplica um tick da trilha de A7 (injeta o golpe relativo à posição atual e dá o passo).
static func a7_step(w: WorldSim, e: Dictionary) -> void:
	var hit: Dictionary = e.hit
	if not hit.is_empty():
		var nb: Array = NEIGHBORS[hit.dir]
		w.inject_hit(hit.dmg, w.player.pos_x + int(nb[0]) * A7_HIT_DIST, w.player.pos_z + int(nb[1]) * A7_HIT_DIST)
	w.step(e.inp)


static func run(r: Report) -> void:
	_a1(r)
	_a2(r)
	_a3(r)
	_a4(r)
	_a5(r)
	_a6(r)
	_a7(r)
	_x1(r)
	_x2(r)
	_x3(r)
	_x4(r)


static func _a1(r: Report) -> void:
	var w: WorldSim = new_world()
	var exp_state: Array = []
	var exp_ticks: Array = []
	for i in range(1, 7):
		exp_state.append("WINDUP")
		exp_ticks.append(i)
	for i in range(1, 7):
		exp_state.append("ACTIVE")
		exp_ticks.append(i)
	for i in range(1, 13):
		exp_state.append("RECOVERY")
		exp_ticks.append(i)
	exp_state.append("IDLE")
	exp_ticks.append(0)
	var ok: bool = true
	var first_bad: int = -1
	for t in range(1, 31):
		w.step(atk() if t == 1 else IntInput.new())
		var want_s: String = exp_state[t - 1] if t <= 25 else "IDLE"
		var want_t: int = exp_ticks[t - 1] if t <= 25 else 0
		if w.player.swing_state != want_s or w.player.swing_ticks != want_t:
			ok = false
			if first_bad < 0:
				first_bad = t
	_note_error(r, w)
	r.check("M3-A1", ok, "primeiro tick divergente=%d (−1 = nenhum)" % first_bad)


## HP do boneco por tick (30 ticks, golpe no tick 1).
static func _hp_series(dx: int, dz: int) -> Array:
	var w: WorldSim = new_world()
	w.spawn_dummy(dx, dz)
	var out: Array = []
	for t in range(1, 31):
		w.step(atk() if t == 1 else IntInput.new())
		out.append(int(w.enemies[0].hp))
	return out


static func _a2(r: Report) -> void:
	var front: Array = _hp_series(FRONT_X, FRONT_Z)
	var drop_tick: int = -1
	for i in range(front.size()):
		if front[i] != 100:
			drop_tick = i + 1
			break
	var side: Array = _hp_series(SIDE60_X, SIDE60_Z)
	r.check("M3-A2", front[29] == 75 and drop_tick == 7 and side[29] == 100,
		"frente: hp final=%d queda no tick %d; 60°: hp final=%d" % [front[29], drop_tick, side[29]])


static func _a3(r: Report) -> void:
	var w: WorldSim = new_world()
	w.spawn_dummy(FRONT_X, FRONT_Z)
	var drops: Array = []
	var prev: int = 100
	for t in range(1, 31):
		w.step(atk() if t == 1 else IntInput.new())
		var hp: int = w.enemies[0].hp
		if hp != prev:
			drops.append([t, prev - hp])
		prev = hp
	var one_ok: bool = drops.size() == 1 and int(drops[0][0]) >= 7 and int(drops[0][0]) <= 12 \
		and int(drops[0][1]) == 25 and w.player.swing_hits == [0]
	var w2: WorldSim = new_world()
	w2.spawn_dummy(FRONT_X, FRONT_Z)
	w2.spawn_dummy(FRONT_X, FRONT_Z)
	for t in range(1, 31):
		w2.step(atk() if t == 1 else IntInput.new())
	var two_ok: bool = int(w2.enemies[0].hp) == 75 and int(w2.enemies[1].hp) == 75 and w2.player.swing_hits == [0, 1]
	_note_error(r, w)
	_note_error(r, w2)
	r.check("M3-A3", one_ok and two_ok, "quedas=%s swing_hits=%s; dois bonecos hp=%d,%d hits=%s" % [
		str(drops), str(w.player.swing_hits), w2.enemies[0].hp, w2.enemies[1].hp, str(w2.player.swing_hits)])


static func _a4(r: Report) -> void:
	var w: WorldSim = new_world()
	var twin: WorldSim = new_world()
	w.player.stamina = 11
	twin.player.stamina = 11
	var ok: bool = true
	for t in range(1, 31):
		w.step(atk() if t == 1 else IntInput.new())
		twin.step(IntInput.new())
		if w.player.swing_state != "IDLE" or w.player.stamina != twin.player.stamina:
			ok = false
	r.check("M3-A4", ok, "estado=%s vigor=%d gêmeo=%d" % [w.player.swing_state, w.player.stamina, twin.player.stamina])


static func _block_once(r: Report, src_x: int, src_z: int) -> Array:
	var w: WorldSim = new_world()
	w.inject_hit(25, src_x, src_z)
	var b: IntInput = IntInput.new()
	b.block = true
	w.step(b)
	_note_error(r, w)
	return [w.player.hp, w.player.stamina]


static func _a5(r: Report) -> void:
	var front: Array = _block_once(r, FRONT_X, FRONT_Z)
	var back: Array = _block_once(r, 5939, 15360)
	r.check("M3-A5", front == [93, 83] and back == [75, 100],
		"frontal hp=%d vigor=%d; costas hp=%d vigor=%d" % [front[0], front[1], back[0], back[1]])


static func _a6(r: Report) -> void:
	var w: WorldSim = new_world()
	w.player.stamina = 10
	w.inject_hit(25, FRONT_X, FRONT_Z)
	var both: IntInput = IntInput.new()
	both.block = true
	both.attack = true
	w.step(both)
	var b_ok: bool = w.player.hp == 75 and w.player.stun_ticks == 20 and w.player.stamina == 10
	var mid_ok: bool = true
	for _t in range(2, 22):
		w.step(both)
		if w.player.blocking or w.player.swing_state != "IDLE":
			mid_ok = false
	var end_ok: bool = w.player.stun_ticks == 0 and w.player.stamina == 17
	var st21: int = w.player.stamina
	w.step(atk())
	var t22_ok: bool = w.player.swing_state == "WINDUP" and w.player.stamina == 5
	_note_error(r, w)
	r.check("M3-A6", b_ok and mid_ok and end_ok and t22_ok,
		"B: %s; 2–21 sem bloqueio/golpe: %s; fim de 21: stun=0 vigor=%d %s; 22: %s vigor=%d" % [
			b_ok, mid_ok, st21, end_ok, w.player.swing_state, w.player.stamina])


static func _a7(r: Report) -> void:
	var ok: bool = true
	var detail: String = ""
	for s in range(A7_SEED_FROM, A7_SEED_FROM + A7_SEED_COUNT):
		var w: WorldSim = new_world()
		w.spawn_dummy(FRONT_X, FRONT_Z)
		var bad: int = -1
		for e: Dictionary in a7_trace(s):
			a7_step(w, e)
			var p: RefCounted = w.player
			if p.stamina < 0 or p.stamina > p.stamina_max or p.hp < 0 or p.hp > p.hp_max \
					or p.stun_ticks < 0 or p.stun_ticks > 20 or w.player_box_hits_solid():
				bad = w.tick
				break
		_note_error(r, w)
		if bad >= 0:
			ok = false
			detail += "semente %d viola no tick %d; " % [s, bad]
	if ok:
		detail = "sementes %d..%d, %d ticks: invariantes de vigor/vida/atordoamento e M1-A4 por tick" % [
			A7_SEED_FROM, A7_SEED_FROM + A7_SEED_COUNT - 1, A7_TICKS]
	r.check("M3-A7", ok, detail)


## Regeneração conforme o pseudocódigo normativo de §4.8 (contador zera enquanto o golpe não está
## em IDLE): o golpe volta a IDLE no tick 25, regen_ticks chega a 3 no tick 27.
## Os valores literais de §4.8/§9.2 do plano ("89 no 26, 99 no 58, 100 no 59") são inconsistentes
## entre si com período 3 (10 pontos em 32 ticks); vale o algoritmo: 88 em 1–26, 89 no 27,
## 99 no 57, 100 no 60.
static func _x1(r: Report) -> void:
	var w: WorldSim = new_world()
	var series: Array = []
	for t in range(1, 71):
		w.step(atk() if t == 1 else IntInput.new())
		series.append(w.player.stamina)
	var ok: bool = true
	for t in range(1, 27):
		ok = ok and series[t - 1] == 88
	ok = ok and series[26] == 89 and series[55] == 98 and series[56] == 99 and series[58] == 99 \
		and series[59] == 100 and series[69] == 100
	_note_error(r, w)
	r.check("M3-X1", ok, "vigor t1=%d t25=%d t26=%d t27=%d t57=%d t58=%d t59=%d t60=%d" % [
		series[0], series[24], series[25], series[26], series[56], series[57], series[58], series[59]])


static func _x2(r: Report) -> void:
	var w: WorldSim = new_world()
	var mb: IntInput = IntInput.new(1, 0, 0)
	mb.block = true
	var ok: bool = true
	var v1: int = 0
	var v2: int = 0
	for t in range(1, 121):
		w.step(mb)
		if t == 1:
			v1 = w.player.vel_x
		elif t == 2:
			v2 = w.player.vel_x
		if t >= 32 and w.player.vel_x != 65:
			ok = false
	_note_error(r, w)
	r.check("M3-X2", ok and v1 == 7 and v2 == 13 and w.player.pos_x == 14465,
		"vel_x t1=%d t2=%d terminal 65 desde 32=%s pos_x=%d" % [v1, v2, ok, w.player.pos_x])


static func _single_hit(ex: int, ez: int) -> bool:
	var w: WorldSim = new_world()
	w.spawn_dummy(ex, ez)
	for t in range(1, 31):
		w.step(atk() if t == 1 else IntInput.new())
	return int(w.enemies[0].hp) == 75


static func _x3(r: Report) -> void:
	var at_reach: bool = _single_hit(SPAWN_X + 2022, SPAWN_Z)
	var past_reach: bool = _single_hit(SPAWN_X + 2023, SPAWN_Z)
	var behind: bool = _single_hit(SPAWN_X - 500, SPAWN_Z)
	r.check("M3-X3", at_reach and not past_reach and behind,
		"2022 acerta=%s; 2023 acerta=%s; (6668,15360) sobreposto acerta=%s" % [at_reach, past_reach, behind])


static func _x4(r: Report) -> void:
	var trace: Array = a7_trace(A7_SEED_FROM)
	var w1: WorldSim = new_world()
	var w2: WorldSim = new_world()
	w1.spawn_dummy(FRONT_X, FRONT_Z)
	w2.spawn_dummy(FRONT_X, FRONT_Z)
	for e: Dictionary in trace:
		a7_step(w1, e)
	for e: Dictionary in trace:
		a7_step(w2, e)
	_note_error(r, w1)
	_note_error(r, w2)
	r.check("M3-X4", w1.chain == w2.chain and w1.chain != "", "C_K=%s" % w1.chain)


## M3-V1: main.tscn em headless com a sala de combate.
static func run_vis(r: Report, root: Window) -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.set("start_override", "combat")
	main.set("driven_externally", true)
	root.add_child(main)
	var ok: bool = true
	var detail: String = ""
	var wv: Node = main.get_node_or_null("WeaponView")
	var sprites: Array = []
	if wv != null:
		for c: Node in wv.get_children():
			if c is Sprite2D:
				sprites.append(c)
	var weapon_ok: bool = wv is CanvasLayer and sprites.size() == 2
	# rodada 3 (plano §8.4): o escudo passou para escala 3 (inteiro acima da HUD); a espada segue em 4
	for sp: Sprite2D in sprites:
		var want: Vector2 = Vector2(3, 3) if sp.name == "Shield" else Vector2(4, 4)
		weapon_ok = weapon_ok and sp.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST \
			and sp.scale == want and sp.texture != null
	ok = ok and weapon_ok
	detail += "arma=%s (%d Sprite2D); " % [weapon_ok, sprites.size()]
	var hud: Node = main.get_node_or_null("Hud")
	var hud_ok: bool = hud is CanvasLayer and hud.find_child("HpBar", true, false) != null \
		and hud.find_child("StaminaBar", true, false) != null
	ok = ok and hud_ok
	detail += "hud=%s; " % hud_ok
	var en: Node = main.get_node_or_null("EnemyView/Enemy_0")
	var en_ok: bool = en is Sprite3D and (en as Sprite3D).billboard == BaseMaterial3D.BILLBOARD_FIXED_Y \
		and is_equal_approx((en as Sprite3D).pixel_size, 0.05) and (en as Sprite3D).texture != null
	ok = ok and en_ok
	detail += "Enemy_0 Sprite3D billboard=%s" % en_ok
	root.remove_child(main)
	main.free()
	r.check("M3-V1", ok, detail)
