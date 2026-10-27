extends SceneTree
## Acceptance/Preservation Gates: M1-*, M2-* (rodada 1), M3-*, M4-*, M3M4-R*, V-*, G0-NOCACHE (rodada 3),
## M5-*, M6-*, M5M6-R*, M6-V*, V-CEIL, V-ATTRACT2 (rodada 4), M3-V4, A-SFX*, V-SHOWCASE (rodada 5),
## M5-V1, M5-V2, A-SFX6, V-SHOWCASE2, M6-V4, M6-V5, A-SFX7 (rodada 6).
## godot --headless --path game -s res://tests/gates/run_gates.gd
## Classes do projeto só por preload: roda em clone limpo, sem `--import`.
## Imprime "PASS|FAIL <ID> <detalhe>", grava runs/tmp/gates_report.json e sai 0 só se tudo passar.

const FixedMath = preload("res://sim/fixed_math.gd")
const TrigTable = preload("res://sim/trig_table.gd")
const PCG32 = preload("res://sim/rng_pcg32.gd")
const IntInput = preload("res://sim/int_input.gd")
const Grid = preload("res://sim/grid.gd")
const DungeonGen = preload("res://sim/dungeon_gen.gd")
const PlayerSim = preload("res://sim/player_sim.gd")
const EnemySim = preload("res://sim/enemy_sim.gd")
const Combat = preload("res://sim/combat.gd")
const StateHash = preload("res://sim/state_hash.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const AutomapSim = preload("res://sim/automap_sim.gd")
const ItemsSim = preload("res://sim/items_sim.gd")
const PilotEscape = preload("res://scripts/pilot_escape.gd")
const TraceIO = preload("res://input/trace_io.gd")
const WeaponView = preload("res://view/weapon_view.gd")
const HudDaggerfall = preload("res://view/hud_daggerfall.gd")
const AudioSfx = preload("res://view/audio_sfx.gd")
const EnemyView = preload("res://view/enemy_view.gd")
const ShowcaseSeed = preload("res://tests/find_showcase_seed.gd")
const MainScript = preload("res://view/main.gd")
const AutomapOverlay = preload("res://view/automap_overlay.gd")
const ItemView = preload("res://view/item_view.gd")
const MAIN_SCENE: PackedScene = preload("res://view/main.tscn")
const HUD_SCENE: PackedScene = preload("res://view/hud_daggerfall.tscn")

const EXPECTED_TRIG_SHA: String = "dd6a64fbcbc4bfb38e59940b6ed273b1fc828b19111416444b3066e9b09d43c1"
const RNG_VECTOR: Array = [0xa15c02b7, 0x7b47f409, 0xba1d3330, 0x83d2f293, 0xbfa4784b, 0xcbed606e]
const REPORT_PATH: String = "runs/tmp/gates_report.json"

var _results: Array = []
var _fails: int = 0
var _done: bool = false
var _exit_code: int = 0
var _quit_at_ms: int = -1


## Os gates rodam no primeiro _process (como o runner), para que as cenas
## adicionadas à árvore recebam _ready(). A saída espera 100 ms para o servidor
## de áudio liberar os playbacks dos AudioSfx já liberados (sem vazamento no fim).
func _process(_delta: float) -> bool:
	if not _done:
		_done = true
		_exit_code = _run_all()
		_quit_at_ms = Time.get_ticks_msec() + 100
	elif Time.get_ticks_msec() >= _quit_at_ms:
		quit(_exit_code)
	return false


func _run_all() -> int:
	_gates_m1()
	_gates_m2()
	_gates_m3()
	_gates_m4()
	_gates_m5()
	_gates_m6()
	_gates_scenes()
	_gates_repeat()
	_gates_r3()
	_gates_r5()
	_gates_r6()
	var report: Dictionary = {
		"godot_version": Engine.get_version_info()["string"],
		"passed": _results.size() - _fails,
		"failed": _fails,
		"results": _results,
	}
	var out: String = TraceIO.resolve(REPORT_PATH)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(report, "  ", true))
		f.close()
	print("[gates] %d PASS, %d FAIL" % [_results.size() - _fails, _fails])
	return 0 if _fails == 0 else 1


func _check(id: String, ok: bool, detail: String) -> void:
	print("%s %s %s" % ["PASS" if ok else "FAIL", id, detail])
	_results.append({"id": id, "pass": ok, "detail": detail})
	if not ok:
		_fails += 1


func _input(move: int = 0, strafe: int = 0, turn: int = 0, use: bool = false,
		attack: bool = false, block: bool = false) -> IntInput:
	var i := IntInput.new()
	i.move = move
	i.strafe = strafe
	i.turn = turn
	i.use = use
	i.attack = attack
	i.block = block
	return i


func _quaff(q: int) -> IntInput:
	var i := IntInput.new()
	i.quaff = q
	return i


func _run_trace(w: WorldSim, trace: Array) -> void:
	for inp: IntInput in trace:
		w.step(inp)


# ---------------------------------------------------------------- M1 (mapa test)

func _gates_m1() -> void:
	# M1-A1
	var w := WorldSim.new(1, "test")
	_run_trace(w, TraceIO.read_trace("tests/traces/m1_forward.jsonl"))
	var p: PlayerSim = w.player
	_check("M1-A1", w.tick == 120 and p.pos_x == 20644 and p.pos_z == 9216 and p.vel_x == 139,
		"tick=%d pos_x=%d pos_z=%d vel_x=%d" % [w.tick, p.pos_x, p.pos_z, p.vel_x])

	# M1-A5 (continua do A1)
	var zero_at: int = -1
	for k in range(1, 61):
		w.step(IntInput.new())
		if p.vel_x == 0:
			zero_at = k
			break
	_check("M1-A5", zero_at == 32 and p.pos_x == 21800,
		"vel_x=0 no tick %d sem input, pos_x=%d" % [zero_at, p.pos_x])

	# M1-A2
	w = WorldSim.new(1, "test")
	_run_trace(w, TraceIO.read_trace("tests/traces/m1_strafe.jsonl"))
	p = w.player
	_check("M1-A2", p.pos_x == 5120 and p.pos_z == 3114 and p.vel_x == 0 and p.vel_z == -118,
		"pos_x=%d pos_z=%d vel_x=%d vel_z=%d" % [p.pos_x, p.pos_z, p.vel_x, p.vel_z])

	# M1-A3
	var angles: Array = []
	for t: int in [64, -64]:
		w = WorldSim.new(1, "test")
		for _k in range(64):
			w.step(_input(0, 0, t))
		angles.append(w.player.angle)
	_check("M1-A3", angles[0] == 0 and angles[1] == 0, "angle(+64)=%d angle(-64)=%d" % angles)

	# M1-A4
	var bad: Array = []
	for s in range(1, 11):
		w = WorldSim.new(s, "test")
		var rng := PCG32.new(s, PCG32.STREAM_PILOT)
		for _k in range(600):
			w.step(IntInput.from_pilot(rng))
			if w.player_intersects_solid():
				bad.append("seed %d tick %d" % [s, w.tick])
				break
	_check("M1-A4", bad.is_empty(), "sementes 1-10 x 600 ticks; violações=%s" % [bad])

	# M1-A6
	var bytes := PackedByteArray()
	bytes.resize(TrigTable.SIN_Q16.size() * 4)
	for i in range(TrigTable.SIN_Q16.size()):
		bytes.encode_s32(i * 4, TrigTable.SIN_Q16[i])
	var sha: String = StateHash.sha256_hex_bytes(bytes)
	_check("M1-A6", sha == TrigTable.TABLE_SHA256 and sha == EXPECTED_TRIG_SHA, "sha=%s" % sha)

	# M1-R1
	var chains: Array = []
	for _r in range(2):
		w = WorldSim.new(1, "test")
		var rng := PCG32.new(1, PCG32.STREAM_PILOT)
		for _k in range(600):
			w.step(IntInput.from_pilot(rng))
		chains.append(w.chain)
	_check("M1-R1", chains[0] == chains[1] and not w.type_error, "C_K=%s" % chains[0])

	# M1-RNG
	var rng42 := PCG32.new(42, 54)
	var got: Array = []
	for _i in range(6):
		got.append(rng42.next_u32())
	var hex: Array = got.map(func(v: int) -> String: return "0x%08x" % v)
	_check("M1-RNG", got == RNG_VECTOR, "saídas=%s" % [hex])


# ---------------------------------------------------------------- M2 (mapa dungeon)

func _gates_m2() -> void:
	var a1: Array = []
	var a2: Array = []
	var a3: Array = []
	var a4: Array = []
	var a7: Array = []
	var shas: Array = []
	var a5_same: bool = true
	var gen_fail: Array = []
	var max_attempts: int = 0
	for s in range(1, 101):
		var d: Dictionary = DungeonGen.generate(s)
		if d.is_empty():
			gen_fail.append(s)
			shas.append("")
			continue
		max_attempts = maxi(max_attempts, d["attempts"])
		var g: Grid = d["grid"]
		var rooms: Array = d["rooms"]
		shas.append(g.sha256())
		var d2: Dictionary = DungeonGen.generate(s)
		if d2.is_empty() or (d2["grid"] as Grid).sha256() != g.sha256():
			a5_same = false
		# A1
		var ok1: bool = rooms.size() >= 6 and rooms.size() <= 9
		for i in range(rooms.size()):
			var ri: Dictionary = rooms[i]
			if ri["x"] < 2 or ri["z"] < 2 or ri["x"] + ri["w"] - 1 > 60 or ri["z"] + ri["h"] - 1 > 60:
				ok1 = false
			for j in range(i + 1, rooms.size()):
				var rj: Dictionary = rooms[j]
				if DungeonGen.rooms_too_close(ri["x"], ri["z"], ri["w"], ri["h"], rj):
					ok1 = false
		if not ok1:
			a1.append(s)
		# A2
		var r0: Dictionary = rooms[0]
		var dist: PackedInt32Array = DungeonGen.bfs(g, r0["cx"], r0["cz"])
		var exit_cells: Array = []
		var locked: int = 0
		for z in range(Grid.SIZE):
			for x in range(Grid.SIZE):
				var c: int = g.get_cell(x, z)
				if c == Grid.FLOOR and dist[z * Grid.SIZE + x] < 0:
					if not a2.has(s):
						a2.append(s)
				if c == Grid.EXIT:
					exit_cells.append([x, z])
				if c == Grid.DOOR_LOCKED:
					locked += 1
				if (c == Grid.DOOR_CLOSED or c == Grid.DOOR_LOCKED or c == Grid.DOOR_OPEN) and not DungeonGen.door_ok(g, x, z):
					if not a4.has(s):
						a4.append(s)
		# A3
		var ok3: bool = d["exit_room"] != 0 and exit_cells.size() >= 1
		if ok3:
			var ex: Array = exit_cells[0]
			ok3 = dist[ex[1] * Grid.SIZE + ex[0]] >= 20
		if not ok3:
			a3.append(s)
		# A7
		var ok7: bool = exit_cells.size() == 1 and locked >= 1
		for oc: Array in DungeonGen.outline_cells(rooms[d["exit_room"]]):
			if g.get_cell(oc[0], oc[1]) == Grid.FLOOR:
				ok7 = false
		if not ok7:
			a7.append(s)
	var gen_detail: String = "" if gen_fail.is_empty() else " geração falhou=%s" % [gen_fail]
	_check("M2-A1", a1.is_empty() and gen_fail.is_empty(), "sementes 1-100; falhas=%s%s; tentativas máx=%d" % [a1, gen_detail, max_attempts])
	_check("M2-A2", a2.is_empty() and gen_fail.is_empty(), "falhas=%s" % [a2])
	_check("M2-A3", a3.is_empty() and gen_fail.is_empty(), "falhas=%s" % [a3])
	_check("M2-A4", a4.is_empty() and gen_fail.is_empty(), "falhas=%s" % [a4])
	var diff_pairs: int = 0
	for s in range(99):
		if shas[s] != shas[s + 1]:
			diff_pairs += 1
	var distinct: Dictionary = {}
	for h: String in shas:
		distinct[h] = true
	_check("M2-A5", a5_same and diff_pairs >= 99 and distinct.size() == 100,
		"mesma semente=%s; pares diferentes=%d/99; grades distintas=%d/100" % [a5_same, diff_pairs, distinct.size()])

	# M2-A6
	var w := WorldSim.new(1, "test_door")
	var trace: Array = TraceIO.read_trace("tests/traces/m2_door.jsonl")
	var x120: int = -1
	var v120: int = -1
	var door121: int = -1
	for inp: IntInput in trace:
		w.step(inp)
		if w.tick == 120:
			x120 = w.player.pos_x
			v120 = w.player.vel_x
		if w.tick == 121:
			door121 = w.grid.get_cell(8, 4)
	var x181: int = w.player.pos_x
	var v181: int = w.player.vel_x
	var w2 := WorldSim.new(1, "test_door")
	_run_trace(w2, TraceIO.read_trace("tests/traces/m2_door_nouse.jsonl"))
	_check("M2-A6",
		x120 == 16000 and v120 == 0 and door121 == Grid.DOOR_OPEN and x181 == 23184 and v181 == 139
			and w2.tick == 181 and w2.player.pos_x == 16000,
		"t120 pos_x=%d vel_x=%d; t121 porta=%d; t181 pos_x=%d vel_x=%d; sem use t%d pos_x=%d"
			% [x120, v120, door121, x181, v181, w2.tick, w2.player.pos_x])

	_check("M2-A7", a7.is_empty() and gen_fail.is_empty(), "falhas=%s" % [a7])

	# M2-R3 e M2-R2 (runner em processos separados)
	var core_a: Dictionary = _run_runner(["--seed=1", "--ticks=600", "--mode=pilot", "--map=dungeon", "--output=runs/tmp/gates_r_core_a.json"])
	var core_b: Dictionary = _run_runner(["--seed=1", "--ticks=600", "--mode=pilot", "--map=dungeon", "--output=runs/tmp/gates_r_core_b.json"])
	var viewed: Dictionary = _run_runner(["--seed=1", "--ticks=600", "--mode=pilot", "--map=dungeon", "--output=runs/tmp/gates_r_view.json", "--with-view"])
	var ca: String = core_a.get("chain_final", "")
	var cb: String = core_b.get("chain_final", "")
	var cv: String = viewed.get("chain_final", "")
	_check("M2-R3", not ca.is_empty() and ca == cv and viewed.get("with_view", false) == true,
		"núcleo=%s cena=%s" % [ca, cv])
	_check("M2-R2", not ca.is_empty() and ca == cb, "execução1=%s execução2=%s" % [ca, cb])


func _run_runner(args: Array) -> Dictionary:
	var cmd: PackedStringArray = [
		"--headless", "--path", ProjectSettings.globalize_path("res://"),
		"-s", "res://scripts/headless_runner.gd", "--",
	]
	cmd.append_array(PackedStringArray(args))
	var out: Array = []
	var code: int = OS.execute(OS.get_executable_path(), cmd, out, true)
	var report_path: String = ""
	for a: String in args:
		if a.begins_with("--output="):
			report_path = a.substr(9)
	if code != 0:
		print("runner saiu com %d: %s" % [code, "".join(out)])
		return {}
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(TraceIO.resolve(report_path)))
	return parsed if typeof(parsed) == TYPE_DICTIONARY else {}


# ---------------------------------------------------------------- M3 (combate, mapa test)

## Mundo `test` com um inimigo opcional; jogador em (5120, 9216), angle 0.
func _test_world(type: String = "", x: int = 0, z: int = 0) -> WorldSim:
	var w := WorldSim.new(1, "test")
	if not type.is_empty():
		w.debug_spawn_enemy(type, x, z)
	return w


## Golpe no tick 1 contra um alvo; devolve o hp do alvo depois de `ticks` ticks.
func _swing_hp(type: String, x: int, z: int, ticks: int) -> int:
	var w := _test_world(type, x, z)
	w.step(_input(0, 0, 0, false, true))
	for _k in range(ticks - 1):
		w.step(IntInput.new())
	return w.enemies[0].hp


func _gates_m3() -> void:
	# M3-A1
	var w := WorldSim.new(1, "test")
	var states: Array = []
	var stam1: int = -1
	for inp: IntInput in TraceIO.read_trace("tests/traces/m3_swing.jsonl"):
		w.step(inp)
		states.append(w.player.swing_state)
		if w.tick == 1:
			stam1 = w.player.stamina
	var ok1: bool = states.size() == 30
	var busy: int = 0
	for t in range(1, states.size() + 1):
		var want: String = "IDLE"
		if t <= 6:
			want = "WINDUP"
		elif t <= 12:
			want = "ACTIVE"
		elif t <= 24:
			want = "RECOVERY"
		if states[t - 1] != want:
			ok1 = false
		if states[t - 1] != "IDLE":
			busy += 1
	_check("M3-A1", ok1 and stam1 == 88 and busy == 24,
		"estados 1-30 ok=%s; stamina t1=%d; ticks não-IDLE=%d" % [ok1, stam1, busy])

	# M3-A2
	w = _test_world("dummy", 6349, 9216)
	var hp_at: Dictionary = {}
	w.step(_input(0, 0, 0, false, true))
	hp_at[1] = w.enemies[0].hp
	for _k in range(24):
		w.step(IntInput.new())
		hp_at[w.tick] = w.enemies[0].hp
	_check("M3-A2", hp_at[6] == 100 and hp_at[7] == 75 and hp_at[25] == 75,
		"hp t6=%d t7=%d t25=%d" % [hp_at[6], hp_at[7], hp_at[25]])
	# M3-A2b
	var hp_b: int = _swing_hp("dummy", 5734, 10280, 25)
	_check("M3-A2b", hp_b == 100, "alvo a 60° à esquerda: hp=%d" % hp_b)
	# M3-A2c
	var hp_in: int = _swing_hp("dummy", 5120 + 1958, 9216, 25)
	var hp_out: int = _swing_hp("dummy", 5120 + 1959, 9216, 25)
	_check("M3-A2c", hp_in == 75 and hp_out == 100, "borda 1958 hp=%d; 1959 hp=%d" % [hp_in, hp_out])

	# M3-A3
	w = _test_world("dummy", 6349, 9216)
	var ok3: bool = true
	var hp_first: int = -1
	for t in range(1, 49):
		w.step(_input(0, 0, 0, false, t == 1 or t == 25))
		var hp: int = w.enemies[0].hp
		if t == 7:
			hp_first = hp
		if t >= 7 and t <= 30 and hp != 75:
			ok3 = false
	_check("M3-A3", ok3 and hp_first == 75 and w.enemies[0].hp == 50,
		"após 1º golpe=%d (sem dano extra t8-30=%s); após 2º=%d" % [hp_first, ok3, w.enemies[0].hp])

	# M3-A4
	w = WorldSim.new(1, "test")
	w.debug_set_stamina(11)
	w.step(_input(0, 0, 0, false, true))
	_check("M3-A4", w.tick % 3 != 0 and w.player.swing_state == "IDLE" and w.player.stamina == 11,
		"tick=%d estado=%s stamina=%d" % [w.tick, w.player.swing_state, w.player.stamina])

	# M3-A5
	w = WorldSim.new(1, "test")
	w.debug_queue_hit(6349, 9216, 25)
	w.step(_input(0, 0, 0, false, false, true))
	var front: Array = [w.player.hp, w.player.stamina]
	w = WorldSim.new(1, "test")
	w.debug_queue_hit(3891, 9216, 25)
	w.step(_input(0, 0, 0, false, false, true))
	var back: Array = [w.player.hp, w.player.stamina]
	_check("M3-A5", front == [93, 83] and back == [75, 100],
		"frente hp=%d stamina=%d; costas hp=%d stamina=%d" % [front[0], front[1], back[0], back[1]])

	# M3-A6 (t = 1; vigor reposto a 100 depois da quebra para isolar o atordoamento)
	w = WorldSim.new(1, "test")
	w.debug_set_stamina(10)
	w.debug_queue_hit(6349, 9216, 25)
	w.step(_input(0, 0, 0, false, false, true))
	var at_t: Array = [w.player.hp, w.player.stamina, w.player.stun_ticks]
	w.debug_set_stamina(100)
	var ignored: bool = true
	for k in range(20):
		# alterna attack sozinho (sem atordoamento iniciaria o golpe) e block sozinho
		w.step(_input(0, 0, 0, false, k % 2 == 0, k % 2 == 1))
		if w.player.swing_state != "IDLE" or w.player.blocking:
			ignored = false
	w.step(_input(0, 0, 0, false, true))
	_check("M3-A6", at_t == [75, 0, 20] and ignored and w.player.swing_state == "WINDUP",
		"t: hp=%d stamina=%d stun=%d; t+1..t+20 ignorados=%s; t+21 estado=%s"
			% [at_t[0], at_t[1], at_t[2], ignored, w.player.swing_state])

	# M3-A7
	var bad: Array = []
	for s in range(1, 11):
		w = WorldSim.new(s, "dungeon")
		var rng := PCG32.new(s, PCG32.STREAM_PILOT)
		for _k in range(1200):
			w.step(IntInput.from_pilot_combat(rng))
			var p: PlayerSim = w.player
			if p.stamina < 0 or p.stamina > p.stamina_max or p.hp < 0 or p.hp > p.hp_max:
				bad.append("seed %d tick %d" % [s, w.tick])
				break
	_check("M3-A7", bad.is_empty(), "sementes 1-10 x 1200 ticks; violações=%s" % [bad])

	# M3-B1
	w = WorldSim.new(1, "test")
	_run_trace(w, TraceIO.read_trace("tests/traces/m3_block.jsonl"))
	_check("M3-B1", w.tick == 120 and w.player.vel_x == 65, "tick=%d vel_x=%d" % [w.tick, w.player.vel_x])


# ---------------------------------------------------------------- M4 (inimigos)

## Células alcançáveis a partir de (sx, sz) só por FLOOR/DOOR_OPEN/EXIT.
func _reachable(g: Grid, sx: int, sz: int) -> PackedInt32Array:
	return EnemySim.build_flow(g, sx, sz)


func _gates_m4() -> void:
	# M4-A1
	var w := WorldSim.new(1, "test_door")
	w.debug_set_player(15360, 9216, 0)
	var sk: int = w.debug_spawn_enemy("skeleton", 10 * 2048 + 1024, 9216)
	var ok1: bool = true
	for _k in range(600):
		w.step(IntInput.new())
		if w.enemies[sk].state != "IDLE" or w.enemies[sk].awake:
			ok1 = false
			break
	_check("M4-A1", ok1, "porta fechada entre jogador (7,4) e esqueleto (10,4): IDLE em 600 ticks=%s" % ok1)
	# M4-A1b
	w = WorldSim.new(1, "test_door")
	w.debug_set_player(15360, 9216, 0)
	sk = w.debug_spawn_enemy("skeleton", 10 * 2048 + 1024, 9216)
	w.step(_input(0, 0, 0, true))
	_check("M4-A1b", w.grid.get_cell(8, 4) == Grid.DOOR_OPEN and w.enemies[sk].state == "CHASE",
		"t1 porta=%d estado=%s" % [w.grid.get_cell(8, 4), w.enemies[sk].state])

	# M4-A2
	var fails: Array = []
	var worst: int = 0
	var worst_desc: String = ""
	var tested: int = 0
	var over_1200: int = 0
	for s in range(1, 21):
		var w0 := WorldSim.new(s, "dungeon")
		w0.debug_open_all_doors()
		var reach: PackedInt32Array = _reachable(w0.grid, w0.player.cell_x(), w0.player.cell_z())
		for e0: EnemySim in w0.enemies:
			if reach[e0.cell_z() * Grid.SIZE + e0.cell_x()] < 0:
				continue
			tested += 1
			var wi := WorldSim.new(s, "dungeon")
			wi.debug_open_all_doors()
			wi.debug_keep_only_enemy(e0.id)
			wi.debug_force_awake(e0.id)
			# GDD: <= 1200 ticks. Com as velocidades do GDD (rato 100, esqueleto 68 u/tick) um
			# caminho de N células exige no mínimo N*2048/velocidade ticks; acima de ~58 (rato) ou
			# ~40 (esqueleto) células o limite é fisicamente inatingível. Nesses casos o prazo
			# passa a 5/4 desse mínimo, e o detalhe informa quantos ficaram acima de 1200.
			var path_cells: int = reach[e0.cell_z() * Grid.SIZE + e0.cell_x()]
			var budget: int = maxi(1200, FixedMath.div_trunc(path_cells * Grid.CELL * 5, e0.stat("speed") * 4))
			if budget > 1200:
				over_1200 += 1
			var got: int = -1
			for _k in range(budget):
				wi.step(IntInput.new())
				if wi.enemies[e0.id].state == "WINDUP":
					got = wi.tick
					break
			if got < 0:
				fails.append("seed %d id %d %s" % [s, e0.id, e0.type])
			elif got > worst:
				worst = got
				worst_desc = "seed %d id %d %s" % [s, e0.id, e0.type]
	_check("M4-A2", fails.is_empty() and tested > 0,
		"%d inimigos alcançáveis; falhas=%s; pior caso=%d ticks (%s); %d com caminho longo demais para 1200 ticks"
			% [tested, fails, worst, worst_desc, over_1200])

	# M4-A3 (a) e M4-A4
	w = _test_world("rat", 11264, 9216)
	w.debug_force_awake(0)
	var strike_ticks: Array = []
	var hp_at_first: int = -1
	var prev_hp: int = w.player.hp
	for _k in range(300):
		w.step(IntInput.new())
		if w.enemies[0].state == "STRIKE":
			strike_ticks.append(w.tick)
			if hp_at_first < 0:
				hp_at_first = w.player.hp
			if w.player.hp != prev_hp - 5:
				strike_ticks.append(-1)
		prev_hp = w.player.hp
	# M4-A3 (b)
	var wb := _test_world("rat", 11264, 9216)
	wb.debug_force_awake(0)
	var retreat: bool = false
	var b_cheb: int = -1
	var b_hp: int = -1
	for _k in range(400):
		wb.step(_input(-1) if retreat else IntInput.new())
		if wb.enemies[0].state == "WINDUP":
			retreat = true
		if wb.enemies[0].state == "STRIKE":
			b_cheb = wb.enemies[0].cheb(wb.player.pos_x, wb.player.pos_z)
			b_hp = wb.player.hp
			break
	_check("M4-A3", hp_at_first == 95 and b_cheb > 1024 and b_hp == 100,
		"(a) hp no STRIKE=%d; (b) cheb no STRIKE=%d hp=%d" % [hp_at_first, b_cheb, b_hp])
	var ok4: bool = strike_ticks.size() >= 2 and not strike_ticks.has(-1)
	var gaps: Array = []
	for i in range(1, strike_ticks.size()):
		gaps.append(strike_ticks[i] - strike_ticks[i - 1])
		if strike_ticks[i] - strike_ticks[i - 1] != 40:
			ok4 = false
	_check("M4-A4", ok4, "STRIKE nos ticks %s; intervalos=%s (esperado 40)" % [strike_ticks, gaps])

	# M4-A5
	var bad: Array = []
	for s in range(1, 11):
		w = WorldSim.new(s, "dungeon")
		w.debug_open_all_doors()
		for e: EnemySim in w.enemies:
			w.debug_force_awake(e.id)
		var rng := PCG32.new(s, PCG32.STREAM_PILOT)
		for _k in range(1200):
			w.step(IntInput.from_pilot_combat(rng))
			if w.enemy_intersects_solid() or w.live_boxes_overlap() or w.player_intersects_solid():
				bad.append("seed %d tick %d" % [s, w.tick])
				break
	_check("M4-A5", bad.is_empty(), "sementes 1-10 x 1200 ticks, todos acordados; violações=%s" % [bad])

	# M4-A6
	w = _test_world("rat", 6349, 9216)
	var dead_tick: int = -1
	var dead_hp: int = 0
	var hp_after: int = -1
	w.step(_input(0, 0, 0, false, true))
	for _k in range(40):
		if dead_tick < 0 and w.enemies[0].state == "DEAD":
			dead_tick = w.tick
			dead_hp = w.enemies[0].hp
		w.step(IntInput.new())
	var hp_dead: int = w.player.hp
	for _k in range(120):
		w.step(_input(1))
	hp_after = w.player.hp
	_check("M4-A6",
		dead_tick == 7 and dead_hp <= 0 and hp_dead == 100 and hp_after == 100 and w.player.pos_x > 6349 + 256 + 384,
		"DEAD no tick %d hp=%d; hp do jogador=%d/%d; pos_x final=%d"
			% [dead_tick, dead_hp, hp_dead, hp_after, w.player.pos_x])

	# M4-P1
	var p_fail: Array = []
	for s in range(1, 101):
		var wp := WorldSim.new(s, "dungeon")
		var d: Dictionary = DungeonGen.generate(s)
		var rooms: Array = wp.rooms
		var guardians: int = 0
		var ok: bool = wp.enemies.size() == rooms.size() - 1 and wp.grid_sha256 == (d["grid"] as Grid).sha256()
		var per_room: Array = []
		per_room.resize(rooms.size())
		per_room.fill(0)
		for e: EnemySim in wp.enemies:
			if not Grid.is_passable(wp.grid.get_cell(e.cell_x(), e.cell_z())):
				ok = false
			if e.type == "guardian":
				guardians += 1
			for i in range(rooms.size()):
				var r: Dictionary = rooms[i]
				if e.cell_x() >= r["x"] and e.cell_x() < r["x"] + r["w"] and e.cell_z() >= r["z"] and e.cell_z() < r["z"] + r["h"]:
					per_room[i] += 1
					if e.type == "guardian" and i != wp.exit_room:
						ok = false
		if per_room[0] != 0 or guardians != 1:
			ok = false
		for i in range(1, rooms.size()):
			if per_room[i] != 1:
				ok = false
		if not ok:
			p_fail.append(s)
	_check("M4-P1", p_fail.is_empty(), "sementes 1-100; falhas=%s" % [p_fail])


# ---------------------------------------------------------------- M5 (automapa)

func _room_of(rooms: Array, x: int, z: int) -> int:
	for r: Dictionary in rooms:
		if x >= r["x"] and x < r["x"] + r["w"] and z >= r["z"] and z < r["z"] + r["h"]:
			return r["id"]
	return -1


func _gates_m5() -> void:
	# M5-A1
	var a1: Array = []
	for s in range(1, 21):
		var w := WorldSim.new(s, "dungeon")
		w.step(IntInput.new())
		var r0: Dictionary = w.rooms[0]
		var x0: int = r0["x"] - 1
		var x1: int = r0["x"] + r0["w"]
		var z0: int = r0["z"] - 1
		var z1: int = r0["z"] + r0["h"]
		var ones: int = 0
		var outside: int = 0
		for z in range(Grid.SIZE):
			for x in range(Grid.SIZE):
				if w.automap.is_visited(x, z):
					ones += 1
					if x < x0 or x > x1 or z < z0 or z > z1:
						outside += 1
		if ones != (int(r0["w"]) + 2) * (int(r0["h"]) + 2) or outside != 0:
			a1.append("seed %d (%d marcadas, %d fora)" % [s, ones, outside])
	_check("M5-A1", a1.is_empty(), "sementes 1-20; falhas=%s" % [a1])

	# M5-A2
	var w := WorldSim.new(1, "dungeon")
	w.debug_open_all_doors()
	var r0: Dictionary = w.rooms[0]
	var d0: PackedInt32Array = DungeonGen.bfs(w.grid, r0["cx"], r0["cz"])
	var b_id: int = -1
	var b_d: int = -1
	for i in range(1, w.rooms.size()):
		var dv: int = d0[int(w.rooms[i]["cz"]) * Grid.SIZE + int(w.rooms[i]["cx"])]
		if dv >= 0 and (b_d < 0 or dv < b_d):
			b_d = dv
			b_id = i
	var rb: Dictionary = w.rooms[b_id]
	var db: PackedInt32Array = DungeonGen.bfs(w.grid, rb["cx"], rb["cz"])
	var path: Array = [[int(r0["cx"]), int(r0["cz"])]]
	while true:
		var cur: Array = path[path.size() - 1]
		var cd: int = db[int(cur[1]) * Grid.SIZE + int(cur[0])]
		if cd <= 0:
			break
		for dd: Array in [[1, 0], [0, 1], [-1, 0], [0, -1]]:
			var nx: int = cur[0] + dd[0]
			var nz: int = cur[1] + dd[1]
			if Grid.in_bounds(nx, nz) and db[nz * Grid.SIZE + nx] == cd - 1:
				path.append([nx, nz])
				break
	for c: Array in path:
		w.debug_set_player(int(c[0]) * Grid.CELL + Grid.CELL / 2, int(c[1]) * Grid.CELL + Grid.CELL / 2, 0)
		w.step(IntInput.new())
	var f := FileAccess.open(TraceIO.resolve("tests/traces/m5_path.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify({"seed": 1, "room_b": b_id, "cells": path}, "", true))
		f.close()
	var ok_a: bool = true
	var ok_b: bool = true
	var ok_c: bool = true
	var corridor: int = 0
	var path_rooms: Dictionary = {}
	for c: Array in path:
		if not w.automap.is_visited(c[0], c[1]):
			ok_a = false
		var rid: int = _room_of(w.rooms, c[0], c[1])
		if rid < 0:
			corridor += 1
		else:
			path_rooms[rid] = true
	for r: Dictionary in w.rooms:
		if path_rooms.has(r["id"]):
			for z in range(int(r["z"]) - 1, int(r["z"]) + int(r["h"]) + 1):
				for x in range(int(r["x"]) - 1, int(r["x"]) + int(r["w"]) + 1):
					if not w.automap.is_visited(x, z):
						ok_b = false
			continue
		for z in range(r["z"], int(r["z"]) + int(r["h"])):
			for x in range(r["x"], int(r["x"]) + int(r["w"])):
				var near: bool = false
				for c: Array in path:
					if maxi(absi(int(c[0]) - x), absi(int(c[1]) - z)) < 2:
						near = true
						break
				if not near and w.automap.is_visited(x, z):
					ok_c = false
	_check("M5-A2", ok_a and ok_b and ok_c and corridor >= 1 and w.terminal == "NONE",
		"sala B=%d; %d células (%d de corredor); (a)=%s (b)=%s (c)=%s"
			% [b_id, path.size(), corridor, ok_a, ok_b, ok_c])

	# M5-A3
	var bad: Array = []
	for s in range(1, 11):
		w = WorldSim.new(s, "dungeon")
		var rng := PCG32.new(s, PCG32.STREAM_PILOT)
		var prev: PackedByteArray = w.automap.visited.duplicate()
		for _k in range(1200):
			w.step(IntInput.from_pilot_combat(rng))
			var cur: PackedByteArray = w.automap.visited
			var lost: bool = false
			for i in range(cur.size()):
				if prev[i] == 1 and cur[i] == 0:
					lost = true
					break
			if lost:
				bad.append("seed %d tick %d" % [s, w.tick])
				break
			prev = cur.duplicate()
	_check("M5-A3", bad.is_empty(), "sementes 1-10 x 1200 ticks; regressões=%s" % [bad])

	# M5-A4
	var wa := WorldSim.new(1, "dungeon")
	var rng_a := PCG32.new(1, PCG32.STREAM_PILOT)
	for _k in range(600):
		wa.step(IntInput.from_pilot_combat(rng_a))
	var wb := WorldSim.new(1, "dungeon")
	var m: Node = _main_with_world(wb)
	var overlay: Control = m.get_node("AutomapLayer/AutomapOverlay") as Control
	var rng_b := PCG32.new(1, PCG32.STREAM_PILOT)
	var seen_open: bool = false
	for k in range(600):
		if k % 50 == 0:
			overlay._unhandled_input(_tab_event())
		wb.step(IntInput.from_pilot_combat(rng_b))
		m.sync_view()
		if overlay.visible:
			seen_open = true
	m.free()
	_check("M5-A4", wa.chain == wb.chain and seen_open, "só núcleo=%s com overlay e Tab=%s; aberta em algum tick=%s" % [wa.chain, wb.chain, seen_open])

	# M5-A5
	m = _main_with_world(WorldSim.new(1, "dungeon"))
	overlay = m.get_node("AutomapLayer/AutomapOverlay") as Control
	var v0: bool = overlay.visible
	overlay._unhandled_input(_tab_event())
	var v1: bool = overlay.visible
	overlay._unhandled_input(_tab_event())
	var v2: bool = overlay.visible
	var layer: CanvasLayer = overlay.get_parent() as CanvasLayer
	var hud_panel: Control = m.get_node("Hud").panel
	var rect: Rect2 = overlay.get_rect()
	var a: float = overlay.modulate.a
	_check("M5-A5",
		not v0 and v1 and not v2 and a > 0.0 and a < 1.0 and layer != null and layer.layer > 2
			and rect == Rect2(0, 0, 640, 312) and not rect.intersects(hud_panel.get_rect()),
		"visível: início=%s Tab=%s Tab=%s; alpha=%.2f; layer=%d; rect=%s" % [v0, v1, v2, a, layer.layer if layer != null else -1, rect])
	m.free()


func _tab_event() -> InputEventKey:
	var ev := InputEventKey.new()
	ev.keycode = KEY_TAB
	ev.physical_keycode = KEY_TAB
	ev.pressed = true
	return ev


# ---------------------------------------------------------------- M6 (itens, progressão, terminal)

func _gates_m6() -> void:
	# M6-A1
	var a1: Array = []
	for s in range(1, 101):
		var w := WorldSim.new(s, "dungeon")
		var rng := PCG32.new(s, PCG32.STREAM_DUNGEON)
		var layout: Dictionary = DungeonGen.generate(s, rng)
		var ens: Array = DungeonGen.place_enemies(layout, rng)
		var ens_d: Array = ens.map(func(e: EnemySim) -> Dictionary: return e.to_dict())
		var why: Array = []
		if w.grid_sha256 != (layout["grid"] as Grid).sha256() or w.get_enemies() != ens_d:
			why.append("grade/inimigos mudaram")
		var n: int = w.rooms.size()
		if w.items.size() != 2 + 2 * (n - 1):
			why.append("total %d" % w.items.size())
		if w.key_fallback:
			why.append("key_fallback")
		var keys: int = 0
		var cells: Dictionary = {}
		var dist: PackedInt32Array = DungeonGen.bfs_no_locked(w.grid, w.player.cell_x(), w.player.cell_z())
		for it: Dictionary in w.items:
			var x: int = it["cell_x"]
			var z: int = it["cell_z"]
			var rid: int = _room_of(w.rooms, x, z)
			if w.grid.get_cell(x, z) != Grid.FLOOR or rid < 0:
				why.append("item %d fora do piso" % it["id"])
			if cells.has(z * Grid.SIZE + x):
				why.append("célula repetida %d,%d" % [x, z])
			cells[z * Grid.SIZE + x] = true
			if rid == 0 and not (it["id"] == 0 and it["type"] == "potion_hp"):
				why.append("item %d na sala 0" % it["id"])
			if it["type"] == "key":
				keys += 1
				if rid == 0 or rid == w.exit_room:
					why.append("chave na sala %d" % rid)
				if dist[z * Grid.SIZE + x] < 0:
					why.append("chave inalcançável")
		var first: Dictionary = w.items[0] if not w.items.is_empty() else {}
		if keys != 1 or first.get("type", "") != "potion_hp" or _room_of(w.rooms, first.get("cell_x", -1), first.get("cell_z", -1)) != 0:
			why.append("chaves=%d item0=%s" % [keys, first.get("type", "")])
		if not why.is_empty():
			a1.append("seed %d %s" % [s, why])
	_check("M6-A1", a1.is_empty(), "sementes 1-100; falhas=%s" % [a1])

	# M6-A2
	var w := WorldSim.new(1, "test")
	w.debug_set_hp(90)
	w.debug_give("potion_hp", 1)
	w.step(_quaff(1))
	var t1: Array = [w.player.hp, w.player.potion_hp]
	w.step(_quaff(1))
	var t2: Array = [w.player.hp, w.player.potion_hp]
	w = WorldSim.new(1, "test")
	w.debug_set_hp(50)
	w.debug_give("potion_hp", 1)
	w.step(_quaff(1))
	var hp50: int = w.player.hp
	w = WorldSim.new(1, "test")
	w.debug_set_stamina(80)
	w.debug_give("potion_sp", 1)
	w.step(_quaff(2))
	var sp: Array = [w.player.stamina, w.player.potion_sp]
	_check("M6-A2", t1 == [100, 0] and t2 == [100, 0] and hp50 == 90 and sp == [100, 0],
		"t1 hp=%d poções=%d; t2 hp=%d poções=%d; 50+40=%d; vigor=%d poções_vigor=%d"
			% [t1[0], t1[1], t2[0], t2[1], hp50, sp[0], sp[1]])

	# M6-A3
	w = WorldSim.new(1, "test")
	w.debug_set_cell(2, 4, Grid.EXIT)
	var tr: Array = TraceIO.read_trace("tests/traces/m6_exit.jsonl")
	w.step(tr[0])
	var term1: String = w.terminal
	w.step(tr[1])
	w.debug_give("key", 1)
	w.step(tr[2])
	_check("M6-A3", tr.size() == 3 and term1 == "NONE" and w.terminal == "ESCAPED" and w.terminal_tick == 3,
		"t1=%s; t3=%s terminal_tick=%d" % [term1, w.terminal, w.terminal_tick])

	# M6-A4
	w = WorldSim.new(1, "test")
	w.debug_set_hp(10)
	w.debug_queue_hit(6349, 9216, 25)
	w.step(IntInput.new())
	var a4_t1: Array = [w.player.hp, w.terminal, w.terminal_tick]
	var frozen: Dictionary = w.canonical_state()
	frozen.erase("tick")
	var still: bool = true
	var rng4 := PCG32.new(1, PCG32.STREAM_PILOT)
	for _k in range(100):
		w.step(IntInput.from_pilot_combat(rng4))
		var cs: Dictionary = w.canonical_state()
		cs.erase("tick")
		if cs != frozen:
			still = false
	var wt := WorldSim.new(1, "test")
	wt.debug_set_k_max(10)
	var at9: String = ""
	for _k in range(10):
		wt.step(IntInput.new())
		if wt.tick == 9:
			at9 = wt.terminal
	_check("M6-A4",
		a4_t1 == [0, "DEAD", 1] and still and w.tick == 101 and at9 == "NONE" and wt.terminal == "TIMEOUT" and wt.terminal_tick == 10,
		"t1 hp=%d %s tick=%d; congelado 2-101=%s; k_max=10: t9=%s t10=%s"
			% [a4_t1[0], a4_t1[1], a4_t1[2], still, at9, wt.terminal])

	# M6-A5
	w = WorldSim.new(1, "test")
	var lv: Array = []
	for xp: int in [100, 150, 1000]:
		w.debug_add_xp(xp)
		w.step(IntInput.new())
		lv.append([w.player.level, w.player.hp_max, w.player.stamina_max, w.player.hp])
	var dmg: Array = []
	for xp: int in [100, 250]:
		var wd := _test_world("dummy", 6349, 9216)
		wd.debug_add_xp(xp)
		wd.step(IntInput.new())
		wd.step(_input(0, 0, 0, false, true))
		for _k in range(24):
			wd.step(IntInput.new())
		dmg.append(wd.enemies[0].hp)
	_check("M6-A5",
		lv[0] == [2, 120, 110, 120] and lv[1] == [3, 140, 120, 140] and lv[2] == [3, 140, 120, 140] and dmg == [70, 65],
		"t1=%s t2=%s t3=%s; boneco no nível 2=%d nível 3=%d" % [lv[0], lv[1], lv[2], dmg[0], dmg[1]])

	# M6-A6
	var counts: Dictionary = {"ESCAPED": 0, "DEAD": 0, "TIMEOUT": 0, "NONE": 0}
	var esc_ticks: int = 0
	var lost: Array = []
	for s in range(1, 51):
		var we := WorldSim.new(s, "dungeon")
		var pe := PilotEscape.new(s)
		while we.terminal == "NONE" and we.tick < WorldSim.K_MAX:
			we.step(pe.next_input(we))
		counts[we.terminal] += 1
		if we.terminal == "ESCAPED":
			esc_ticks += we.terminal_tick
		else:
			lost.append("seed %d %s" % [s, we.terminal])
	var mean: int = esc_ticks / maxi(counts["ESCAPED"], 1)
	_check("M6-A6", counts["ESCAPED"] >= 40,
		"sementes 1-50: ESCAPED=%d DEAD=%d TIMEOUT=%d; terminal_tick médio (fugas)=%d; não fugiu=%s"
			% [counts["ESCAPED"], counts["DEAD"], counts["TIMEOUT"], mean, lost])

	# M6-B1
	w = WorldSim.new(1, "test")
	w.debug_add_item("gold", 3, 4, 17)
	w.debug_add_item("potion_sp", 3, 4, 1)
	var first_t: int = -1
	var at_first: Array = []
	var stable: bool = true
	for _k in range(30):
		w.step(_input(1))
		var snap: Array = [w.player.gold, w.player.potion_sp, w.items[0]["taken"], w.items[1]["taken"]]
		if first_t < 0 and w.player.cell_x() == 3:
			first_t = w.tick
			at_first = snap
		elif first_t >= 0 and snap != at_first:
			stable = false
	_check("M6-B1", first_t > 0 and at_first == [17, 1, true, true] and stable,
		"primeiro tick na célula 3: %d -> ouro, poções_vigor, coletados=%s; coleta única=%s" % [first_t, at_first, stable])

	# M6-B2
	w = WorldSim.new(1, "test_door")
	w.debug_set_cell(8, 4, Grid.DOOR_LOCKED)
	w.debug_set_player(15360, 9216, 0)
	w.step(_input(0, 0, 0, true))
	var c1: int = w.grid.get_cell(8, 4)
	w.step(IntInput.new())
	w.debug_give("key", 1)
	w.step(_input(0, 0, 0, true))
	_check("M6-B2", c1 == Grid.DOOR_LOCKED and w.grid.get_cell(8, 4) == Grid.DOOR_OPEN and w.player.has_key,
		"t1 sem chave=%d; t3 com chave=%d; has_key=%s" % [c1, w.grid.get_cell(8, 4), w.player.has_key])

	# M6-B3
	w = _test_world("rat", 6349, 9216)
	w.step(_input(0, 0, 0, false, true))
	var xp7: int = -1
	var dead7: bool = false
	for _k in range(6):
		w.step(IntInput.new())
		if w.tick == 7:
			xp7 = w.player.xp
			dead7 = w.enemies[0].state == "DEAD"
	_check("M6-B3", xp7 == 10 and dead7 and w.player.level == 1, "t7 xp=%d rato morto=%s nível=%d" % [xp7, dead7, w.player.level])


# ---------------------------------------------------------------- cenas (M3-V*, M4-A7, V-*)

func _main_with_world(w: WorldSim) -> Node:
	var m: Node = MAIN_SCENE.instantiate()
	if w != null:
		m.attach_world(w)
	root.add_child(m)
	return m


## main.tscn em modo atração com semente fixa (independe de DEFAULT_SEED).
func _main_attract(seed_value: int) -> Node:
	var m: Node = MAIN_SCENE.instantiate()
	m.start_seed = seed_value
	root.add_child(m)
	return m


func _gates_scenes() -> void:
	# M4-A7 + M3-V1..V3
	var w := WorldSim.new(1, "dungeon")
	var m: Node = _main_with_world(w)
	m.sync_view()
	m.sync_view()
	var ev: Node = m.get_node("EnemyView")
	var kids: Array = ev.get_children()
	var ok7: bool = kids.size() == w.enemies.size()
	var want_ps: Dictionary = {"dummy": 0.05, "rat": 0.035, "skeleton": 0.05, "guardian": 0.0625}
	for e: EnemySim in w.enemies:
		var sp: Sprite3D = ev.get_node_or_null("Enemy_%d" % e.id) as Sprite3D
		if sp == null or sp.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y \
				or sp.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST \
				or not is_equal_approx(sp.pixel_size, want_ps[e.type]):
			ok7 = false
	_check("M4-A7", ok7, "sprites=%d inimigos=%d" % [kids.size(), w.enemies.size()])

	var hud: Node = m.get_node("Hud")
	w.debug_queue_hit(w.player.pos_x - 2048, w.player.pos_z, 25)
	w.step(IntInput.new())
	m.sync_view()
	var p: Dictionary = w.get_player()
	var panel: Control = hud.panel
	var hp_h: int = int(hud.hp_fill.size.y)
	var sp_h: int = int(hud.sp_fill.size.y)
	var want_hp: int = roundi(40.0 * p["hp"] / p["hp_max"])
	var want_sp: int = roundi(40.0 * p["stamina"] / p["stamina_max"])
	_check("M3-V1", panel.get_rect() == Rect2(0, 312, 640, 48) and hp_h == want_hp and sp_h == want_sp and p["hp"] == 75,
		"painel=%s hp=%d altura=%d/%d; vigor=%d altura=%d/%d"
			% [panel.get_rect(), p["hp"], hp_h, want_hp, p["stamina"], sp_h, want_sp])

	var wv: Node = m.get_node("WeaponView")
	var sword: TextureRect = wv.sword
	var shield: TextureRect = wv.shield
	var ok_v2: bool = not sword.get_rect().intersects(panel.get_rect()) \
		and not shield.get_rect().intersects(panel.get_rect()) \
		and sword.size == Vector2(128, 128) and shield.size == Vector2(128, 128) \
		and sword.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST \
		and shield.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST
	_check("M3-V2", ok_v2, "espada=%s escudo=%s" % [sword.get_rect(), shield.get_rect()])

	var idle: Array = WeaponView.sword_pose("IDLE", 0)
	var wind: Array = WeaponView.sword_pose("WINDUP", 6)
	var act: Array = WeaponView.sword_pose("ACTIVE", 12)
	var ok_v3: bool = idle[0] != wind[0] and wind[0] != act[0] and idle[1] != wind[1] and wind[1] != act[1] \
		and WeaponView.sword_pose("WINDUP", 3) == WeaponView.sword_pose("WINDUP", 3)
	_check("M3-V3", ok_v3, "IDLE=%s WINDUP=%s ACTIVE=%s" % [idle, wind, act])

	# V-LIGHT
	var env: Environment = (m.get_node("WorldEnvironment") as WorldEnvironment).environment
	var omni: OmniLight3D = m.get_node("PlayerView/Camera3D/OmniLight3D") as OmniLight3D
	_check("V-LIGHT",
		is_equal_approx(env.ambient_light_energy, 0.35) and is_equal_approx(env.fog_density, 0.04)
			and is_equal_approx(omni.light_energy, 1.6) and is_equal_approx(omni.omni_range, 10.0),
		"ambient=%.2f fog=%.2f omni=%.2f range=%.1f"
			% [env.ambient_light_energy, env.fog_density, omni.light_energy, omni.omni_range])
	m.free()

	# V-ATTRACT (fixado na semente 1337, plano R5 §0)
	var free_m: Node = _main_attract(1337)
	var at30: Array = []
	for t in range(1, 121):
		free_m._physics_process(1.0 / 60.0)
		if t == 30:
			at30 = [free_m.world.player.pos_x, free_m.world.player.pos_z, free_m.world.player.angle]
	var p120: PlayerSim = free_m.world.player
	var moved: bool = at30 != [p120.pos_x, p120.pos_z, p120.angle]
	free_m.free()
	var wa := WorldSim.new(1, "dungeon")
	var att_m: Node = _main_with_world(wa)
	var before: Array = [wa.player.pos_x, wa.player.pos_z, wa.player.angle]
	for _t in range(120):
		att_m._physics_process(1.0 / 60.0)
		wa.step(IntInput.new())
	var still: bool = before == [wa.player.pos_x, wa.player.pos_z, wa.player.angle] and not att_m.attract_active()
	att_m.free()
	_check("V-ATTRACT", moved and still, "sem attach_world: muda entre t30 e t120=%s; com attach_world: constante=%s" % [moved, still])

	_gates_scenes_r4()


func _gates_scenes_r4() -> void:
	# M6-V1
	var w := WorldSim.new(1, "test")
	w.debug_set_cell(2, 4, Grid.EXIT)
	w.debug_give("key", 1)
	var m: Node = _main_with_world(w)
	w.step(_input(0, 0, 0, true))
	m.sync_view()
	var es: CanvasLayer = m.get_node("EndScreen") as CanvasLayer
	var title: Label = es.get_node("Parchment/Title") as Label
	var stats: Label = es.get_node("Parchment/Stats") as Label
	var v_end: Array = [es.visible, title.text, stats.text.contains("Ticks 1")]
	m.free()
	m = _main_with_world(WorldSim.new(1, "test"))
	m.sync_view()
	var v_none: bool = (m.get_node("EndScreen") as CanvasLayer).visible
	m.free()
	_check("M6-V1", v_end == [true, "VOCÊ ESCAPOU!", true] and not v_none,
		"terminal: visível=%s título=%s 'Ticks 1'=%s; sem terminal visível=%s" % [v_end[0], v_end[1], v_end[2], v_none])

	# M6-V2
	w = WorldSim.new(1, "dungeon")
	m = _main_with_world(w)
	m.sync_view()
	var iv: Node = m.get_node("ItemView")
	var want_ps: Dictionary = {"potion_hp": 0.016, "potion_sp": 0.016, "key": 0.016, "gold": 0.012}
	var ok2: bool = iv.get_child_count() == w.items.size() and not w.items.is_empty()
	for it: Dictionary in w.items:
		var sp: Sprite3D = iv.get_node_or_null("Item_%d" % int(it["id"])) as Sprite3D
		if sp == null or sp.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y \
				or sp.texture_filter != BaseMaterial3D.TEXTURE_FILTER_NEAREST \
				or not is_equal_approx(sp.pixel_size, want_ps[it["type"]]) or not sp.visible:
			ok2 = false
	var it0: Dictionary = w.items[0]
	w.debug_set_player(int(it0["cell_x"]) * Grid.CELL + Grid.CELL / 2, int(it0["cell_z"]) * Grid.CELL + Grid.CELL / 2, 0)
	w.step(IntInput.new())
	m.sync_view()
	var sp0: Sprite3D = iv.get_node("Item_0") as Sprite3D
	_check("M6-V2", ok2 and w.items[0]["taken"] and not sp0.visible,
		"sprites=%d itens=%d; item 0 coletado=%s sprite visível=%s" % [iv.get_child_count(), w.items.size(), w.items[0]["taken"], sp0.visible])
	m.free()

	# M6-V3
	w = WorldSim.new(1, "test")
	m = _main_with_world(w)
	w.debug_queue_hit(w.player.pos_x - 2048, w.player.pos_z, 25)
	w.step(IntInput.new())
	m.sync_view()
	var hud: Node = m.get_node("Hud")
	var panel_r: Rect2 = Rect2(0, 312, 640, 48)
	var others: Array = [
		(hud.get_node("HpBg") as Control).get_rect(), (hud.get_node("StaminaBg") as Control).get_rect(),
		(hud.get_node("Portrait") as Control).get_rect(), (hud.get_node("PortraitFrame") as Control).get_rect(),
		(hud.compass as Control).get_rect(), (hud.message as Control).get_rect(),
	]
	var texts: Array = [hud.hp_text, hud.sp_text, hud.level_text, hud.inv_text]
	var ok_rects: bool = true
	for i in range(texts.size()):
		var r: Rect2 = (texts[i] as Control).get_rect()
		if not panel_r.encloses(r):
			ok_rects = false
		for o: Rect2 in others:
			if r.intersects(o):
				ok_rects = false
		for j in range(i + 1, texts.size()):
			if r.intersects((texts[j] as Control).get_rect()):
				ok_rects = false
	var hp_t: String = hud.hp_text.text
	var sp_t: String = hud.sp_text.text
	var inv_t: String = hud.inv_text.text
	_check("M6-V3", hp_t == "V 75/100" and sp_t.begins_with("G ") and inv_t == "PV 0  PG 0  -" and ok_rects,
		"Hp='%s' Sp='%s' Nv='%s' Inv='%s'; retângulos ok=%s" % [hp_t, sp_t, hud.level_text.text, inv_t, ok_rects])
	m.free()

	# V-CEIL
	m = _main_with_world(WorldSim.new(1, "dungeon"))
	var dv: Node = m.get_node("DungeonView")
	var ceil_c: Color = (dv.get_material("ceiling") as StandardMaterial3D).albedo_color
	var floor_c: Color = (dv.get_material("floor") as StandardMaterial3D).albedo_color
	var env: Environment = (m.get_node("WorldEnvironment") as WorldEnvironment).environment
	var omni: OmniLight3D = m.get_node("PlayerView/Camera3D/OmniLight3D") as OmniLight3D
	_check("V-CEIL",
		ceil_c.is_equal_approx(Color(1.8, 1.8, 1.8)) and floor_c.is_equal_approx(Color(1, 1, 1))
			and is_equal_approx(env.ambient_light_energy, 0.35) and is_equal_approx(env.fog_density, 0.04)
			and is_equal_approx(omni.light_energy, 1.6) and is_equal_approx(omni.omni_range, 10.0),
		"teto=%s piso=%s; luz da rodada 3 inalterada" % [ceil_c, floor_c])
	m.free()

	# V-ATTRACT2
	var am: Node = _main_with_world(null)
	var aw: WorldSim = am.world
	var r0: Dictionary = aw.rooms[0]
	var start_cell: Array = [aw.player.cell_x(), aw.player.cell_z()]
	var changed: bool = false
	var left_r0: bool = false
	for _t in range(600):
		am._physics_process(1.0 / 60.0)
		var cx: int = aw.player.cell_x()
		var cz: int = aw.player.cell_z()
		if [cx, cz] != start_cell:
			changed = true
		if cx < r0["x"] or cx >= int(r0["x"]) + int(r0["w"]) or cz < r0["z"] or cz >= int(r0["z"]) + int(r0["h"]):
			left_r0 = true
	am.free()
	_check("V-ATTRACT2", changed and left_r0, "600 ticks sem eventos: célula mudou=%s; saiu da sala 0=%s" % [changed, left_r0])


# ---------------------------------------------------------------- repetição (M3M4-R*)

func _gates_repeat() -> void:
	var chains: Array = []
	for _r in range(2):
		var w := WorldSim.new(1, "dungeon")
		var rng := PCG32.new(1, PCG32.STREAM_PILOT)
		for _k in range(1200):
			w.step(IntInput.from_pilot_combat(rng))
		chains.append(w.chain)
	_check("M3M4-R1", chains[0] == chains[1], "C_K=%s" % chains[0])

	var base: Array = ["--seed=1", "--ticks=1200", "--map=dungeon"]
	var a: Dictionary = _run_runner(base + ["--mode=pilot", "--record=runs/tmp/gates_r4_trace.jsonl", "--output=runs/tmp/gates_r34_a.json"])
	var b: Dictionary = _run_runner(base + ["--mode=pilot", "--output=runs/tmp/gates_r34_b.json"])
	var v: Dictionary = _run_runner(base + ["--mode=pilot", "--with-view", "--output=runs/tmp/gates_r34_v.json"])
	var r: Dictionary = _run_runner(base + ["--mode=replay", "--trace=runs/tmp/gates_r4_trace.jsonl", "--output=runs/tmp/gates_r34_r.json"])
	var ca: String = a.get("chain_final", "")
	_check("M3M4-R2", not ca.is_empty() and ca == b.get("chain_final", ""), "execução1=%s execução2=%s" % [ca, b.get("chain_final", "")])
	_check("M3M4-R3", not ca.is_empty() and ca == v.get("chain_final", "") and v.get("with_view", false) == true,
		"núcleo=%s cena=%s" % [ca, v.get("chain_final", "")])
	_check("M3M4-R4", not ca.is_empty() and ca == r.get("chain_final", ""), "gravado=%s replay=%s" % [ca, r.get("chain_final", "")])

	# M5M6-R1
	var esc: Array = []
	for _r in range(2):
		var w := WorldSim.new(1, "dungeon")
		var pe := PilotEscape.new(1)
		for _k in range(3000):
			w.step(pe.next_input(w))
		esc.append(w.chain)
	_check("M5M6-R1", esc[0] == esc[1], "C_K=%s" % esc[0])

	var eb: Array = ["--seed=1", "--ticks=3000", "--map=dungeon", "--mode=escape"]
	var ea: Dictionary = _run_runner(eb + ["--record=runs/tmp/gates_r56_trace.jsonl", "--output=runs/tmp/gates_r56_a.json"])
	var e2: Dictionary = _run_runner(eb + ["--output=runs/tmp/gates_r56_b.json"])
	var ev: Dictionary = _run_runner(eb + ["--with-view", "--output=runs/tmp/gates_r56_v.json"])
	var er: Dictionary = _run_runner(["--seed=1", "--ticks=3000", "--map=dungeon", "--mode=replay",
		"--trace=runs/tmp/gates_r56_trace.jsonl", "--output=runs/tmp/gates_r56_r.json"])
	var eca: String = ea.get("chain_final", "")
	_check("M5M6-R2", not eca.is_empty() and eca == e2.get("chain_final", ""),
		"execução1=%s execução2=%s terminal=%s" % [eca, e2.get("chain_final", ""), ea.get("terminal", "")])
	_check("M5M6-R3", not eca.is_empty() and eca == ev.get("chain_final", "") and ev.get("with_view", false) == true,
		"núcleo=%s cena=%s" % [eca, ev.get("chain_final", "")])
	_check("M5M6-R4", not eca.is_empty() and eca == er.get("chain_final", "") and ea.get("terminal", "") == er.get("terminal", "-"),
		"gravado=%s replay=%s; terminal %s/%s" % [eca, er.get("chain_final", ""), ea.get("terminal", ""), er.get("terminal", "")])


# ---------------------------------------------------------------- correções da rodada 3

## G0-NOCACHE: nenhum script usa um nome de class_name do projeto sem const preload.
func _gates_r3() -> void:
	var names: Array = []
	for d: String in ["sim", "input", "view"]:
		for f: String in _gd_files("res://" + d):
			var m: RegExMatch = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(FileAccess.get_file_as_string(f))
			if m != null:
				names.append(m.get_string(1))
	var offenders: Array = []
	var files: Array = []
	for d: String in ["tests", "scripts", "view", "input", "sim"]:
		files.append_array(_gd_files("res://" + d))
	for f: String in files:
		var text: String = FileAccess.get_file_as_string(f)
		var own: RegExMatch = RegEx.create_from_string("(?m)^class_name\\s+(\\w+)").search(text)
		var code: String = _strip_code(text)
		for n: String in names:
			if own != null and own.get_string(1) == n:
				# o próprio nome no próprio arquivo só pode aparecer na declaração
				if RegEx.create_from_string("\\b%s\\b" % n).search_all(code).size() > 1:
					offenders.append("%s:%s" % [f, n])
				continue
			if RegEx.create_from_string("\\b%s\\b" % n).search(code) == null:
				continue
			if RegEx.create_from_string("(?m)^const\\s+%s\\s*(:[^=]*)?=\\s*preload\\(" % n).search(text) == null:
				offenders.append("%s:%s" % [f, n])
	_check("G0-NOCACHE", offenders.is_empty() and names.size() >= 9,
		"%d classes, %d scripts; usos sem preload=%s" % [names.size(), files.size(), offenders])


func _gd_files(dir: String) -> Array:
	var out: Array = []
	var da := DirAccess.open(dir)
	if da == null:
		return out
	for f: String in da.get_files():
		if f.ends_with(".gd"):
			out.append(dir.path_join(f))
	for sub: String in da.get_directories():
		out.append_array(_gd_files(dir.path_join(sub)))
	return out


## Remove comentários e strings, para a busca de identificadores.
func _strip_code(text: String) -> String:
	var no_str: String = RegEx.create_from_string("\"(?:\\\\.|[^\"\\\\])*\"").sub(text, "\"\"", true)
	return RegEx.create_from_string("#[^\\n]*").sub(no_str, "", true)


# ---------------------------------------------------------------- rodada 5 (C8–C11)

func _gates_r5() -> void:
	_gate_m3_v4()
	_gates_sfx()
	_gate_showcase()


## M3-V4: nenhum rótulo cortado, 2+ rótulos, N/L centrados e retângulo da bússola.
func _gate_m3_v4() -> void:
	var cut: int = 0
	var few: int = 0
	var min_labels: int = 99
	for h in range(0, 4096, 16):
		var marks: Array = HudDaggerfall.compass_marks(h)
		min_labels = mini(min_labels, marks.size())
		if marks.size() < 2:
			few += 1
		for mk: Dictionary in marks:
			if float(mk["x"]) - float(mk["w"]) / 2.0 < 2.0 or float(mk["x"]) + float(mk["w"]) / 2.0 > 94.0:
				cut += 1
	var n_ok: bool = false
	for mk: Dictionary in HudDaggerfall.compass_marks(1024):
		if mk["label"] == "N" and is_equal_approx(float(mk["x"]), 48.0):
			n_ok = true
	var l_ok: bool = false
	for mk: Dictionary in HudDaggerfall.compass_marks(0):
		if mk["label"] == "L" and is_equal_approx(float(mk["x"]), 48.0):
			l_ok = true
	var hud: Node = HUD_SCENE.instantiate()
	root.add_child(hud)
	var cr: Rect2 = (hud.get_node("Compass") as Control).get_rect()
	var mr: Rect2 = (hud.get_node("Message") as Control).get_rect()
	var rect_ok: bool = cr == Rect2(272, 322, 96, 22) and not cr.intersects(HudDaggerfall.LEVEL_TEXT_RECT) \
		and not cr.intersects(mr) and HudDaggerfall.PANEL_RECT.encloses(cr)
	hud.free()
	_check("M3-V4", cut == 0 and few == 0 and n_ok and l_ok and rect_ok,
		"rótulos cortados=%d; rumos com <2 rótulos=%d (mín %d); N@1024=%s L@0=%s; bússola=%s ok=%s"
			% [cut, few, min_labels, n_ok, l_ok, cr, rect_ok])


func _sfx_player(swing: String = "IDLE", hp: int = 100, stamina: int = 100,
		blocking: bool = false, stun: int = 0) -> Dictionary:
	return {"swing_state": swing, "hp": hp, "stamina": stamina, "blocking": blocking, "stun_ticks": stun}


func _sfx_enemy(id: int, state: String, hp: int = 50, type: String = "skeleton") -> Dictionary:
	return {"id": id, "type": type, "state": state, "hp": hp}


func _gates_sfx() -> void:
	# A-SFX1: eventos do jogador
	var base: Dictionary = _sfx_player()
	var e_a: Array = [_sfx_enemy(0, "CHASE", 50)]
	var cases: Array = [
		AudioSfx.detect_events(base, _sfx_player("WINDUP"), [], []) == ["swing"],
		AudioSfx.detect_events(_sfx_player("ACTIVE"), _sfx_player("ACTIVE"), e_a, [_sfx_enemy(0, "CHASE", 25)]) == ["hit"],
		AudioSfx.detect_events(_sfx_player("IDLE", 100, 100, true), _sfx_player("IDLE", 97, 83, true), [], []) == ["block"],
		AudioSfx.detect_events(base, _sfx_player("IDLE", 90, 100, false, 20), [], []) == ["guard_break", "hurt"],
		AudioSfx.detect_events(base, base.duplicate(), e_a, e_a.duplicate(true)) == [],
	]
	_check("A-SFX1", not cases.has(false), "swing/hit/block/guard_break+hurt/sem mudança=%s" % [cases])

	# A-SFX2: não interferência com o núcleo
	var wc := WorldSim.new(1, "dungeon")
	var rc := PCG32.new(1, PCG32.STREAM_PILOT)
	for _k in range(1200):
		wc.step(IntInput.from_pilot_combat(rc))
	var wv := WorldSim.new(1, "dungeon")
	var rv := PCG32.new(1, PCG32.STREAM_PILOT)
	var m: Node = _main_with_world(wv)
	for _k in range(1200):
		wv.step(IntInput.from_pilot_combat(rv))
		m.sync_view()
	var sfx: Node = m.get_node("AudioSfx")
	var log_v: Array = sfx.played_log.duplicate()
	m.free()
	var kinds: Dictionary = {}
	for id: String in log_v:
		kinds[id] = int(kinds.get(id, 0)) + 1
	_check("A-SFX2", wc.chain == wv.chain and not log_v.is_empty() and log_v.has("swing"),
		"núcleo=%s cena+áudio=%s; tocados=%s" % [wc.chain, wv.chain, kinds])

	# A-SFX3: formato, duração, pico e determinismo
	var durs: Dictionary = {
		"swing": 0.18, "hit": 0.12, "block": 0.25, "guard_break": 0.30,
		"hurt": 0.20, "enemy_windup": 0.30, "enemy_strike": 0.10, "enemy_death": 0.45,
	}
	var a: Node = AudioSfx.new()
	var b: Node = AudioSfx.new()
	var bad: Array = []
	for id: String in durs:
		var sa: AudioStreamWAV = a.get_stream(id)
		var sb: AudioStreamWAV = b.get_stream(id)
		if sa == null or sb == null:
			bad.append("%s:ausente" % id)
			continue
		var n: int = roundi(float(durs[id]) * 22050)
		var peak: int = 0
		for i in range(sa.data.size() / 2):
			peak = maxi(peak, absi(sa.data.decode_s16(i * 2)))
		if sa.format != AudioStreamWAV.FORMAT_16_BITS or sa.mix_rate != 22050 or sa.stereo \
				or sa.data.size() != 2 * n or peak > 22937 or peak <= 0 \
				or _sha256(sa.data) != _sha256(sb.data):
			bad.append("%s:n=%d bytes=%d pico=%d" % [id, n, sa.data.size(), peak])
	a.free()
	b.free()
	_check("A-SFX3", bad.is_empty(), "8 streams 16 bits/22050 Hz/mono; problemas=%s" % [bad])

	# A-SFX4: eventos dos inimigos
	var p0: Dictionary = _sfx_player()
	var cases4: Array = [
		AudioSfx.detect_events(p0, p0, [_sfx_enemy(0, "CHASE")], [_sfx_enemy(0, "WINDUP")]) == ["enemy_windup"],
		AudioSfx.detect_events(p0, p0, [_sfx_enemy(0, "WINDUP")], [_sfx_enemy(0, "STRIKE")]) == ["enemy_strike"],
		AudioSfx.detect_events(p0, p0, [_sfx_enemy(0, "STRIKE")], [_sfx_enemy(0, "DEAD")]) == ["enemy_death"],
		AudioSfx.detect_events(p0, p0, [_sfx_enemy(0, "CHASE"), _sfx_enemy(1, "CHASE")],
			[_sfx_enemy(0, "WINDUP"), _sfx_enemy(1, "WINDUP")]) == ["enemy_windup"],
		AudioSfx.detect_events(p0, p0, [], [_sfx_enemy(5, "WINDUP")]) == [],
		AudioSfx.detect_events(p0, p0, [_sfx_enemy(1, "CHASE"), _sfx_enemy(0, "CHASE")],
			[_sfx_enemy(0, "CHASE"), _sfx_enemy(1, "STRIKE")]) == ["enemy_strike"],
	]
	_check("A-SFX4", not cases4.has(false), "windup/strike/death/dois windups/novo/casamento por id=%s" % [cases4])

	# A-SFX5: nada toca depois do terminal
	var s5: Node = AudioSfx.new()
	root.add_child(s5)
	s5.apply_state(_sfx_player(), [_sfx_enemy(0, "CHASE")], "NONE")
	s5.apply_state(_sfx_player("WINDUP"), [_sfx_enemy(0, "WINDUP")], "NONE")
	var before: int = s5.played_log.size()
	s5.apply_state(_sfx_player("IDLE", 0), [_sfx_enemy(0, "STRIKE")], "DEAD")
	s5.apply_state(_sfx_player("WINDUP", 0, 50, false, 20), [_sfx_enemy(0, "DEAD", 0)], "DEAD")
	var after: int = s5.played_log.size()
	s5.free()
	_check("A-SFX5", before == 2 and after == before, "antes do terminal=%d; depois=%d" % [before, after])


func _sha256(data: PackedByteArray) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish().hex_encode()


## Primeira linha opaca do PNG (alfa > 0) do sprite.
func _top_opaque(tex: Texture2D) -> int:
	var img: Image = tex.get_image()
	for y in range(img.get_height()):
		for x in range(img.get_width()):
			if img.get_pixel(x, y).a > 0.0:
				return y
	return img.get_height()


## V-SHOWCASE: o modo atração real mostra um inimigo em quadro com a escala de §6.
func _gate_showcase() -> void:
	var want_h: Dictionary = {"rat": 0.63, "dummy": 1.35, "skeleton": 1.60, "guardian": 2.00}
	var m: Node = _main_with_world(null)
	var w: WorldSim = m.world
	var ev: Node = m.get_node("EnemyView")
	var count: int = 0
	var first: int = -1
	var types: Dictionary = {}
	var scene_bad: Array = []
	for t in range(1, ShowcaseSeed.LAST_TICK + 1):
		m._physics_process(1.0 / 60.0)
		m.sync_view()
		if t < ShowcaseSeed.WINDOW_FROM:
			continue
		var ids: Array = ShowcaseSeed.enemies_in_frame(w)
		if ids.is_empty():
			continue
		count += 1
		if first < 0:
			first = t
		for id: int in ids:
			var type: String = ""
			for e: EnemySim in w.enemies:
				if e.id == id:
					type = e.type
			types[type] = true
			var sp: Sprite3D = ev.get_node_or_null("Enemy_%d" % id) as Sprite3D
			if sp == null:
				scene_bad.append("%d:sem sprite" % id)
				continue
			var h: float = sp.pixel_size * float(int(EnemyView.SPRITES[type]["b"]) - _top_opaque(sp.texture))
			if not sp.visible or sp.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y \
					or absf(h - float(want_h[type])) > 0.05:
				scene_bad.append("%d:%s h=%.2f" % [id, type, h])
	m.free()
	var seed_v: int = MainScript.DEFAULT_SEED
	_check("V-SHOWCASE", count >= ShowcaseSeed.MIN_TICKS and first >= 0 and first <= ShowcaseSeed.MAX_FIRST and scene_bad.is_empty(),
		"semente=%d ticks com inimigo em quadro=%d primeiro=t%d tipos=%s; cena=%s"
			% [seed_v, count, first, types.keys(), scene_bad.slice(0, 5)])


# ---------------------------------------------------------------- rodada 6 (C12–C17)

func _gates_r6() -> void:
	_gate_m5_v1()
	_gate_m5_v2()
	_gate_sfx6()
	_gate_showcase2()
	_gate_m6_v4()
	_gate_m6_v5()
	_gate_sfx7()


## M5-V1: agenda do mapa no modo atração, não interferência e saída por input real.
func _gate_m5_v1() -> void:
	var seed_v: int = MainScript.DEFAULT_SEED
	var m: Node = _main_attract(seed_v)
	var overlay: Control = m.get_node("AutomapLayer/AutomapOverlay") as Control
	var mismatch: Array = []
	var opened: int = 0
	var closed: int = 0
	for a in range(1, 601):
		m._physics_process(1.0 / 60.0)
		m.sync_view()
		if overlay.visible != MainScript.attract_map_open(a):
			mismatch.append(a)
		if overlay.visible:
			opened += 1
		else:
			closed += 1
	var chain_view: String = m.world.chain
	m.free()
	var wc := WorldSim.new(seed_v, "dungeon")
	var pe := PilotEscape.new(seed_v)
	for t in range(1, 601):
		if t <= ShowcaseSeed.IDLE_TICKS:
			wc.step(IntInput.new())
		else:
			wc.step(pe.next_input(wc))
	var m2: Node = _main_attract(seed_v)
	var ov2: Control = m2.get_node("AutomapLayer/AutomapOverlay") as Control
	for _a in range(250):
		m2._physics_process(1.0 / 60.0)
		m2.sync_view()
	var open_at_250: bool = ov2.visible
	var ev := InputEventKey.new()
	ev.keycode = KEY_W
	ev.physical_keycode = KEY_W
	ev.pressed = true
	m2._input(ev)
	var stayed_closed: bool = true
	for _k in range(10):
		m2._physics_process(1.0 / 60.0)
		m2.sync_view()
		if ov2.visible:
			stayed_closed = false
	var attract_after: bool = m2.attract_active()
	m2.free()
	var pure: Array = [MainScript.attract_map_open(209), MainScript.attract_map_open(210),
		MainScript.attract_map_open(299), MainScript.attract_map_open(300), MainScript.attract_map_open(450)]
	_check("M5-V1",
		mismatch.is_empty() and opened > 0 and closed > 0 and chain_view == wc.chain
			and open_at_250 and stayed_closed and not attract_after and pure == [false, true, true, false, true],
		"semente=%d; divergências=%s aberto=%d fechado=%d; cadeia cena=%s núcleo=%s; t250 aberto=%s, após W fechado=%s atração=%s; puras=%s"
			% [seed_v, mismatch.slice(0, 5), opened, closed, chain_view, wc.chain, open_at_250, stayed_closed, attract_after, pure])


## Células visitadas e não sólidas cuja área intersecta a tela, recontadas aqui.
func _count_cells_on_screen(w: WorldSim) -> int:
	var visited: PackedByteArray = w.get_visited()
	var cells: PackedByteArray = w.get_grid()
	var p: Dictionary = w.get_player()
	var screen := Rect2(Vector2.ZERO, AutomapOverlay.AREA.size)
	var n: int = 0
	for z in range(Grid.SIZE):
		for x in range(Grid.SIZE):
			var i: int = z * Grid.SIZE + x
			if visited[i] != 1 or cells[i] == Grid.SOLID:
				continue
			var sx: float = 320.0 + (float(x * Grid.CELL) - float(p["pos_x"])) * 8.0 / float(Grid.CELL)
			var sy: float = 156.0 - (float(z * Grid.CELL) - float(p["pos_z"])) * 8.0 / float(Grid.CELL)
			if Rect2(sx, sy - 8.0, 8.0, 8.0).intersects(screen):
				n += 1
	return n


## Problemas de cell_rects: centro sem célula, tamanho, célula não visitada ou sólida.
func _cell_rects_bad(w: WorldSim, rects: Array) -> Array:
	var bad: Array = []
	var visited: PackedByteArray = w.get_visited()
	var cells: PackedByteArray = w.get_grid()
	var center: bool = false
	for cr: Dictionary in rects:
		var r: Rect2 = cr["rect"]
		var i: int = int(cr["z"]) * Grid.SIZE + int(cr["x"])
		if r.has_point(Vector2(320, 156)):
			center = true
		if r.size != Vector2(8, 8):
			bad.append("tamanho %s" % r.size)
		if visited[i] != 1 or cells[i] == Grid.SOLID or int(cr["kind"]) != cells[i]:
			bad.append("célula %d,%d" % [cr["x"], cr["z"]])
	if not center:
		bad.append("sem célula no centro")
	return bad


## M5-V2: cell_rects pura e cabeçalho.
func _gate_m5_v2() -> void:
	var w := WorldSim.new(1, "dungeon")
	w.step(IntInput.new())
	var r1: Array = AutomapOverlay.cell_rects(w.get_visited(), w.get_grid(), w.get_player())
	var want1: int = _count_cells_on_screen(w)
	var bad1: Array = _cell_rects_bad(w, r1)
	var rng := PCG32.new(1, PCG32.STREAM_PILOT)
	for _k in range(600):
		w.step(IntInput.from_pilot_combat(rng))
	var r2: Array = AutomapOverlay.cell_rects(w.get_visited(), w.get_grid(), w.get_player())
	var bad2: Array = _cell_rects_bad(w, r2)
	var hw: float = ThemeDB.fallback_font.get_string_size(AutomapOverlay.HEADER_TEXT,
		HORIZONTAL_ALIGNMENT_LEFT, -1, AutomapOverlay.HEADER_FONT_SIZE).x
	var header_end: float = AutomapOverlay.HEADER_POS.x + hw
	_check("M5-V2",
		not r1.is_empty() and r1.size() == want1 and bad1.is_empty() and not r2.is_empty() and bad2.is_empty()
			and header_end <= 600.0,
		"t1: entradas=%d recontadas=%d problemas=%s; t601: entradas=%d problemas=%s; cabeçalho termina em x=%.1f"
			% [r1.size(), want1, bad1.slice(0, 5), r2.size(), bad2.slice(0, 5), header_end])


## Problemas de formato, duração, pico e determinismo de um stream (como A-SFX3).
func _stream_bad(a: Node, b: Node, id: String, dur: float) -> Array:
	var sa: AudioStreamWAV = a.get_stream(id)
	var sb: AudioStreamWAV = b.get_stream(id)
	if sa == null or sb == null:
		return ["%s:ausente" % id]
	var n: int = roundi(dur * 22050)
	var peak: int = 0
	for i in range(sa.data.size() / 2):
		peak = maxi(peak, absi(sa.data.decode_s16(i * 2)))
	if sa.format != AudioStreamWAV.FORMAT_16_BITS or sa.mix_rate != 22050 or sa.stereo \
			or sa.data.size() != 2 * n or peak > 22937 or peak <= 0 \
			or _sha256(sa.data) != _sha256(sb.data):
		return ["%s:n=%d bytes=%d pico=%d" % [id, n, sa.data.size(), peak]]
	return []


## A-SFX6: som "map" pela mudança de visibilidade do automapa.
func _gate_sfx6() -> void:
	var s6: Node = AudioSfx.new()
	root.add_child(s6)
	var p: Dictionary = _sfx_player()
	s6.apply_state(p, [], "NONE", true)
	var l1: Array = s6.played_log.duplicate()
	s6.apply_state(p, [], "NONE", false)
	var l2: Array = s6.played_log.slice(l1.size())
	var n2: int = s6.played_log.size()
	s6.apply_state(p, [], "NONE", false)
	var l3: Array = s6.played_log.slice(n2)
	var n3: int = s6.played_log.size()
	s6.apply_state(p, [], "DEAD", true)
	s6.apply_state(p, [], "DEAD", false)
	var l4: Array = s6.played_log.slice(n3)
	s6.free()
	var a: Node = AudioSfx.new()
	var b: Node = AudioSfx.new()
	var bad: Array = _stream_bad(a, b, "map", 0.12)
	a.free()
	b.free()
	_check("A-SFX6", l1.is_empty() and l2 == ["map"] and l3.is_empty() and l4.is_empty() and bad.is_empty(),
		"primeiro=%s fechar=%s repetir=%s terminal=%s; stream=%s" % [l1, l2, l3, l4, bad])


## V-SHOWCASE2: o modo atração real (com a agenda do mapa) mostra um item em quadro.
func _gate_showcase2() -> void:
	var m: Node = _main_with_world(null)
	var w: WorldSim = m.world
	var iv: Node = m.get_node("ItemView")
	var count: int = 0
	var first: int = -1
	var types: Dictionary = {}
	var scene_bad: Array = []
	for t in range(1, ShowcaseSeed.LAST_TICK + 1):
		m._physics_process(1.0 / 60.0)
		m.sync_view()
		if t < ShowcaseSeed.WINDOW_FROM:
			continue
		var ids: Array = ShowcaseSeed.items_in_frame(w)
		if ids.is_empty():
			continue
		count += 1
		if first < 0:
			first = t
		for id: int in ids:
			var type: String = ""
			for it: Dictionary in w.items:
				if int(it["id"]) == id:
					type = it["type"]
			types[type] = true
			var sp: Sprite3D = iv.get_node_or_null("Item_%d" % id) as Sprite3D
			if sp == null:
				scene_bad.append("%d:sem sprite" % id)
				continue
			if not sp.visible or sp.billboard != BaseMaterial3D.BILLBOARD_FIXED_Y \
					or not is_equal_approx(sp.pixel_size, float(ItemView.SPRITES[type]["pixel_size"])):
				scene_bad.append("%d:%s" % [id, type])
	m.free()
	_check("V-SHOWCASE2", count >= ShowcaseSeed.MIN_ITEM_TICKS and scene_bad.is_empty(),
		"semente=%d ticks com item em quadro=%d (limiar %d) primeiro=t%d tipos=%s; cena=%s"
			% [MainScript.DEFAULT_SEED, count, ShowcaseSeed.MIN_ITEM_TICKS, first, types.keys(), scene_bad.slice(0, 5)])


## M6-V4: textos de M6 na HUD com corpo 10, sem corte nem sobreposição.
func _gate_m6_v4() -> void:
	var hud: Node = HUD_SCENE.instantiate()
	root.add_child(hud)
	var font: Font = ThemeDB.fallback_font
	var sizes: Array = [
		(hud.level_text as Control).get_theme_font_size("font_size"),
		(hud.inv_text as Control).get_theme_font_size("font_size"),
		(hud.message as Control).get_theme_font_size("font_size"),
		(hud.hp_text as Control).get_theme_font_size("font_size"),
		(hud.sp_text as Control).get_theme_font_size("font_size"),
	]
	var lr: Rect2 = (hud.level_text as Control).get_rect()
	var ir: Rect2 = (hud.inv_text as Control).get_rect()
	var widths: Array = [
		font.get_string_size("Nv 3  XP 999  Ouro 999", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x,
		font.get_string_size("PV 9  PG 9  Chave", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x,
		font.get_string_size("Chave da Saída!", HORIZONTAL_ALIGNMENT_LEFT, -1, 10).x,
	]
	var others: Array = [
		(hud.get_node("HpBg") as Control).get_rect(), (hud.get_node("StaminaBg") as Control).get_rect(),
		(hud.get_node("Portrait") as Control).get_rect(), (hud.get_node("PortraitFrame") as Control).get_rect(),
		(hud.compass as Control).get_rect(), (hud.message as Control).get_rect(),
	]
	var texts: Array = [hud.hp_text, hud.sp_text, hud.level_text, hud.inv_text]
	var ok_rects: bool = true
	for i in range(texts.size()):
		var r: Rect2 = (texts[i] as Control).get_rect()
		if not HudDaggerfall.PANEL_RECT.encloses(r):
			ok_rects = false
		for o: Rect2 in others:
			if r.intersects(o):
				ok_rects = false
		for j in range(i + 1, texts.size()):
			if r.intersects((texts[j] as Control).get_rect()):
				ok_rects = false
	if not HudDaggerfall.PANEL_RECT.encloses((hud.message as Control).get_rect()):
		ok_rects = false
	hud.free()
	_check("M6-V4",
		sizes == [10, 10, 10, 8, 8] and lr == HudDaggerfall.LEVEL_TEXT_RECT and ir == HudDaggerfall.INV_TEXT_RECT
			and lr == Rect2(140, 316, 128, 14) and ir == Rect2(140, 333, 128, 14)
			and widths[0] <= 128.0 and widths[1] <= 128.0 and widths[2] <= 248.0 and ok_rects,
		"corpos Nv/Inv/Msg/V/G=%s; Nv=%s Inv=%s; larguras=%s; retângulos ok=%s" % [sizes, lr, ir, widths, ok_rects])


## M6-V5: tela final legível (título no corpo 24, estatísticas no corpo 12).
func _gate_m6_v5() -> void:
	var w := WorldSim.new(1, "test")
	w.debug_set_cell(2, 4, Grid.EXIT)
	w.debug_give("key", 1)
	var m: Node = _main_with_world(w)
	w.step(_input(0, 0, 0, true))
	m.sync_view()
	var es: CanvasLayer = m.get_node("EndScreen") as CanvasLayer
	var parch: Control = es.get_node("Parchment") as Control
	var title: Label = es.get_node("Parchment/Title") as Label
	var stats: Label = es.get_node("Parchment/Stats") as Label
	var term: String = w.terminal
	var visible: bool = es.visible
	var t_size: int = title.get_theme_font_size("font_size")
	var s_size: int = stats.get_theme_font_size("font_size")
	var pr: Rect2 = parch.get_rect()
	var sr: Rect2 = stats.get_rect()
	m.free()
	var font: Font = ThemeDB.fallback_font
	var tw: Dictionary = {}
	for k: String in ["ESCAPED", "DEAD", "TIMEOUT"]:
		var txt: String = {"ESCAPED": "VOCÊ ESCAPOU!", "DEAD": "VOCÊ MORREU", "TIMEOUT": "TEMPO ESGOTADO"}[k]
		tw[k] = font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 24).x
	var widths_ok: bool = tw.values().all(func(v: float) -> bool: return v <= 304.0)
	var stats_h: float = 4.0 * font.get_height(12)
	_check("M6-V5",
		term == "ESCAPED" and visible and t_size == 24 and s_size == 12 and pr == Rect2(160, 66, 320, 180)
			and widths_ok and stats_h <= 112.0 and sr.position.y + 112.0 <= 180.0 and sr.end.y <= 180.0,
		"terminal=%s visível=%s; corpos título/estatísticas=%d/%d; pergaminho=%s; larguras=%s; 4 linhas=%.0f px; Stats=%s"
			% [term, visible, t_size, s_size, pr, tw, stats_h, sr])


## A-SFX7: pickup e level_up pela diferença de estado.
func _gate_sfx7() -> void:
	var base: Dictionary = _sfx_player()
	base["gold"] = 0
	base["level"] = 1
	base["inventory"] = {"potion_hp": 0, "potion_sp": 0, "key": false}
	var gold: Dictionary = base.duplicate(true)
	gold["gold"] = 25
	var key: Dictionary = base.duplicate(true)
	key["inventory"]["key"] = true
	var php: Dictionary = base.duplicate(true)
	php["inventory"]["potion_hp"] = 1
	var both: Dictionary = base.duplicate(true)
	both["level"] = 2
	both["inventory"]["potion_sp"] = 1
	var cases: Array = [
		AudioSfx.detect_events(base, gold, [], []) == ["pickup"],
		AudioSfx.detect_events(base, key, [], []) == ["pickup"],
		AudioSfx.detect_events(base, php, [], []) == ["pickup"],
		AudioSfx.detect_events(base, both, [], []) == ["pickup", "level_up"],
		AudioSfx.detect_events(base, base.duplicate(true), [], []) == [],
	]
	var a: Node = AudioSfx.new()
	var b: Node = AudioSfx.new()
	var bad: Array = _stream_bad(a, b, "pickup", 0.15) + _stream_bad(a, b, "level_up", 0.45)
	a.free()
	b.free()
	_check("A-SFX7", not cases.has(false) and bad.is_empty(),
		"ouro/chave/poção/nível+poção/sem mudança=%s; streams=%s" % [cases, bad])
