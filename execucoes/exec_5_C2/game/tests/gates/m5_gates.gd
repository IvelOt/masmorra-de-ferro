class_name M5Gates
extends RefCounted
## Acceptance Gate de M5 (plano 2 §6.2): automapa sobre automap_fixture() e generate(s).

const CORRIDOR_TRACE: String = "res://tests/traces/m5_corridor.jsonl"
const MAIN_SCENE: String = "res://view/main.tscn"
const OVERLAY_PATH: String = "AutomapOverlay/Map"


static func run(tree: SceneTree) -> Array:
	var out: Array = []
	out.append(_a1())
	out.append(_a2())
	out.append(_a3())
	out.append(_a4(tree))
	out.append(_a5(tree))
	return out


## Conjunto esperado: retângulo inclusivo recortado a 0..63.
static func rect_bytes(x0: int, z0: int, x1: int, z1: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(Grid.W * Grid.H)
	b.fill(0)
	for cz in range(maxi(z0, 0), mini(z1, Grid.H - 1) + 1):
		for cx in range(maxi(x0, 0), mini(x1, Grid.W - 1) + 1):
			b[cz * Grid.W + cx] = 1
	return b


static func _a1() -> Dictionary:
	var w := WorldSim.create(1, false, "automap")
	w.step(IntInput.new())
	if w.get_visited() != rect_bytes(1, 1, 8, 8):
		return GateUtil.res("M5-A1", false, "fixture: count=%d" % w.automap.count())
	for s in range(1, 21):
		var g := WorldSim.create(s, false)
		g.step(IntInput.new())
		var r: Dictionary = g.dungeon.rooms[0]
		var want: PackedByteArray = rect_bytes(r["x"] - 1, r["z"] - 1, r["x"] + r["w"], r["z"] + r["h"])
		if g.get_visited() != want:
			return GateUtil.res("M5-A1", false, "semente %d: count=%d esperado=%d" % [s, g.automap.count(), (r["w"] + 2) * (r["h"] + 2)])
	return GateUtil.res("M5-A1", true, "fixture 64 células; sementes 1-20 = sala 0 + contorno")


static func _a2() -> Dictionary:
	var tr: Dictionary = TraceIO.read(CORRIDOR_TRACE)
	if tr["error"] != "":
		return GateUtil.res("M5-A2", false, tr["error"])
	var ins: Array = tr["inputs"]
	if ins.size() != 421:
		return GateUtil.res("M5-A2", false, "trilha com %d ticks" % ins.size())
	var w := WorldSim.create(1, false, "automap")
	var p := w.player
	# marcos de referência da trilha: tick -> [pos_x, vel_x]
	var refs: Dictionary = {120: [16000, 0], 321: [30336, 0], 382: [37520, 139], 421: [38676, 0]}
	var z_ok: bool = true
	var marks: Array = []
	for k in range(ins.size()):
		w.step(ins[k])
		z_ok = z_ok and p.pos_z == 11264
		if w.tick == 1 and w.automap.count() != 64:
			marks.append("t1 count=%d" % w.automap.count())
		if w.tick == 121 and w.get_cell(8, 5) != Grid.DOOR_OPEN:
			marks.append("t121 porta (8,5)=%d" % w.get_cell(8, 5))
		if w.tick == 322 and w.get_cell(15, 5) != Grid.DOOR_OPEN:
			marks.append("t322 porta (15,5)=%d" % w.get_cell(15, 5))
		if refs.has(w.tick):
			var ref: Array = refs[w.tick]
			if p.pos_x != ref[0] or p.vel_x != ref[1]:
				marks.append("t%d pos_x=%d vel_x=%d" % [w.tick, p.pos_x, p.vel_x])
	var am: AutomapSim = w.automap
	var ok: bool = marks.is_empty() and z_ok
	for x in range(8, 16):
		ok = ok and am.is_visited(x, 5)
	for z in range(1, 9):
		for x in range(15, 23):
			ok = ok and am.is_visited(x, z)
	for z in range(14, 20):
		for x in range(2, 8):
			ok = ok and not am.is_visited(x, z)
	ok = ok and not am.is_visited(5, 10) and am.count() == 146
	return GateUtil.res("M5-A2", ok, "count=%d pos_z fixo=%s %s" % [am.count(), z_ok, "; ".join(marks)])


## Primeiro tick em que o bitmap regride (-1 = nunca).
static func monotonic_violation(w: WorldSim, inputs: Array) -> int:
	var prev: PackedByteArray = w.get_visited()
	var prev_n: int = w.automap.count()
	for i: IntInput in inputs:
		w.step(i)
		var cur: PackedByteArray = w.get_visited()
		var n: int = w.automap.count()
		if n < prev_n:
			return w.tick
		for idx in range(cur.size()):
			if prev[idx] == 1 and cur[idx] == 0:
				return w.tick
		prev = cur
		prev_n = n
	return -1


static func _a3() -> Dictionary:
	var walk: Array = GateUtil.walker_inputs(900)
	var details: Array = []
	for s in range(1, 6):
		var w := WorldSim.create(s, false)
		var bad: int = monotonic_violation(w, walk)
		if bad >= 0:
			return GateUtil.res("M5-A3", false, "semente %d: regressão no tick %d" % [s, bad])
		details.append("s%d=%d" % [s, w.automap.count()])
	var wt := WorldSim.create(1, false, "automap")
	var bad_t: int = monotonic_violation(wt, TraceIO.read(CORRIDOR_TRACE)["inputs"])
	if bad_t >= 0:
		return GateUtil.res("M5-A3", false, "trilha: regressão no tick %d" % bad_t)
	return GateUtil.res("M5-A3", true, "monotônico; %s trilha=%d" % [" ".join(details), wt.automap.count()])


static func tab_event(pressed: bool) -> InputEventKey:
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_TAB
	ev.pressed = pressed
	return ev


## Entrega Tab (pressionar + soltar) à árvore; se o headless não rotear, chama o handler direto.
static func send_tab(tree: SceneTree, overlay: Control) -> void:
	var before: bool = overlay.visible
	tree.root.push_input(tab_event(true))
	tree.root.push_input(tab_event(false))
	if overlay.visible == before:
		overlay._unhandled_input(tab_event(true))
		overlay._unhandled_input(tab_event(false))


static func _a4(tree: SceneTree) -> Dictionary:
	var walk: Array = GateUtil.walker_inputs(900)
	var details: Array = []
	var ok: bool = true
	for s in range(1, 6):
		var core := WorldSim.create(s, false)
		GateUtil.run(core, walk)
		var w := WorldSim.create(s, false)
		var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
		main.attach_world(w)
		tree.root.add_child(main)
		var overlay: Control = main.get_node(OVERLAY_PATH)
		var toggles: int = 0
		for k in range(walk.size()):
			if k % 50 == 0:
				var was: bool = overlay.visible
				send_tab(tree, overlay)
				if overlay.visible != was:
					toggles += 1
			main.advance(walk[k])
		tree.root.remove_child(main)
		main.free()
		var same: bool = core.chain == w.chain
		ok = ok and same and toggles >= 2
		details.append("s%d=%s/%d" % [s, "=" if same else "!=", toggles])
	return GateUtil.res("M5-A4", ok, "cadeia com/sem Tab, alternâncias: %s" % " ".join(details))


static func _a5(tree: SceneTree) -> Dictionary:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.attach_world(WorldSim.create(1, true))
	tree.root.add_child(main)
	var overlay: Control = main.get_node_or_null(OVERLAY_PATH)
	var ok: bool = overlay != null
	var detail: String = "overlay=%s" % ("ok" if ok else "null")
	if ok:
		var v0: bool = overlay.visible
		send_tab(tree, overlay)
		var v1: bool = overlay.visible
		send_tab(tree, overlay)
		var v2: bool = overlay.visible
		var a: float = overlay.modulate.a
		ok = not v0 and v1 and not v2 and a > 0.0 and a < 1.0
		detail += " visible %s->%s->%s alpha=%.2f" % [v0, v1, v2, a]
	tree.root.remove_child(main)
	main.free()
	return GateUtil.res("M5-A5", ok, detail)
