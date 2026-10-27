class_name GateUI
extends RefCounted
## UI-1..UI-7: layout da HUD, bússola, barras, arma, tela final, demonstração e
## áudio (plano da iteração 5 §5.3). Headless, sem GPU.

const MAIN_SCENE: String = "res://view/main.tscn"
const BAR_RECT: Rect2 = Rect2(0, 312, 640, 48)
const HUD_PARTS: Array = ["Portrait", "Vida", "Vigor", "Stats", "Inventory", "Message", "Compass"]
## angle BAM -> rumo da cardinal esperada no centro (0 = +x = leste).
const COMPASS_CASES: Dictionary = {0: 90, 1024: 0, 2048: 270, 3072: 180}
const FRONT_DEG: float = 35.0
const AUDIO_RATE: int = 22050
const AUDIO_MIN_S: float = 0.05
const AUDIO_MAX_S: float = 2.5
const AUDIO_PEAK: float = 0.9


static func run(r: GateReport, tree: SceneTree) -> void:
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("configure", 1, false, true)
	tree.root.add_child(main)
	var hud: HudDaggerfall = main.get_node("HUD") as HudDaggerfall
	var state: Dictionary = (main.get("sim") as WorldSim).get_state()
	_ui1(r, hud)
	_ui2(r, hud, state)
	_ui3(r, hud, state)
	_ui4(r, main.get_node("Weapon") as CanvasLayer)
	_ui5(r, main.get_node("EndScreen") as EndScreen, state)
	_ui7(r, main.get_node("AudioView"))
	tree.root.remove_child(main)
	main.free()
	_ui6(r)


static func _ui1(r: GateReport, hud: HudDaggerfall) -> void:
	var bar: Control = hud.get_node_or_null("Bar") as Control
	var errs: Array = []
	if bar == null or bar.get_global_rect() != BAR_RECT:
		errs.append("Bar=%s" % (bar.get_global_rect() if bar != null else "ausente"))
	var rects: Array = []
	for n: String in HUD_PARTS:
		var c: Control = hud.get_node_or_null(n) as Control
		if c == null:
			errs.append("%s ausente" % n)
			continue
		var rc: Rect2 = c.get_global_rect()
		if not BAR_RECT.encloses(rc):
			errs.append("%s fora da faixa %s" % [n, rc])
		rects.append([n, rc])
	for i: int in range(rects.size()):
		for j: int in range(i + 1, rects.size()):
			if (rects[i][1] as Rect2).intersects(rects[j][1] as Rect2):
				errs.append("%s × %s" % [rects[i][0], rects[j][0]])
	r.check("UI-1", errs.is_empty(), "faixa %s; 7 elementos dentro e sem sobreposição; erros=%s" % [BAR_RECT, str(errs)])


static func _with_player(state: Dictionary, fields: Dictionary) -> Dictionary:
	var s: Dictionary = state.duplicate(true)
	for k: String in fields.keys():
		s["player"][k] = fields[k]
	return s


static func _ui2(r: GateReport, hud: HudDaggerfall, state: Dictionary) -> void:
	var box: Control = hud.get_node("Compass") as Control
	var errs: Array = []
	if not box.clip_contents:
		errs.append("sem clip_contents")
	var mid: float = box.size.x / 2.0
	for a: int in COMPASS_CASES.keys():
		hud.on_tick(_with_player(state, {"angle": a}), {})
		for deg: int in [0, 90, 180, 270]:
			var l: Label = hud.compass_label(deg)
			if l.get_theme_font_size("font_size") < 14:
				errs.append("fonte %d < 14" % l.get_theme_font_size("font_size"))
			var cx: float = l.position.x + l.size.x / 2.0
			if deg == int(COMPASS_CASES[a]) and (not l.visible or absf(cx - mid) > 2.0):
				errs.append("angle %d: %s em x=%.1f visível=%s" % [a, l.text, cx, l.visible])
			if l.visible and (cx < 10.0 or cx > 100.0):
				errs.append("angle %d: %s visível em x=%.1f" % [a, l.text, cx])
	r.check("UI-2", errs.is_empty(), "bússola %s, cardinal esperada no centro %.0f±2 e letras em [10,100]; erros=%s" % [
		box.size, mid, str(errs)])


static func _fill_ok(hud: HudDaggerfall, bar: String, want: int) -> bool:
	var f: ColorRect = hud.get_node(bar + "/Fill") as ColorRect
	return int(f.size.y) == want and is_equal_approx(f.position.y + f.size.y, 40.0)


static func _ui3(r: GateReport, hud: HudDaggerfall, state: Dictionary) -> void:
	var errs: Array = []
	hud.on_tick(_with_player(state, {"hp": 50, "hp_max": 100, "stamina": 50, "stamina_max": 100}), {})
	if not _fill_ok(hud, "Vida", 19) or not _fill_ok(hud, "Vigor", 19):
		errs.append("50/100 != 19 px na base")
	hud.on_tick(_with_player(state, {"hp": 140, "hp_max": 140, "stamina": 120, "stamina_max": 120}), {})
	if not _fill_ok(hud, "Vida", 38) or not _fill_ok(hud, "Vigor", 38):
		errs.append("cheia != 38 px")
	for pair: Array in [["Vida", "V"], ["Vigor", "G"]]:
		var frame: Control = hud.get_node(String(pair[0])) as Control
		var l: Label = frame.get_node_or_null("Label") as Label
		if l == null or l.text != String(pair[1]) or not Rect2(Vector2.ZERO, frame.size).encloses(Rect2(l.position, l.size)):
			errs.append("rótulo %s" % pair[1])
	hud.on_tick(state, {})
	r.check("UI-3", errs.is_empty(), "Vida/Vigor: 19 px com 50/100, 38 px cheias (140/140), rótulos V e G na moldura; erros=%s" % str(errs))


static func _shadow_nodes(n: Node, out: Array) -> void:
	var low: String = String(n.name).to_lower()
	if low.contains("shadow") or low.contains("sombra"):
		out.append(String(n.name))
	for c: Node in n.get_children():
		_shadow_nodes(c, out)


static func _ui4(r: GateReport, weapon: CanvasLayer) -> void:
	var sword: Sprite2D = weapon.get_node("Clip/Sword") as Sprite2D
	var shield: Sprite2D = weapon.get_node("Clip/Shield") as Sprite2D
	var half: Vector2 = sword.texture.get_size() / 2.0
	var grip: Vector2 = sword.get_global_transform() * (Vector2(4, 28) - half)
	var st: Transform2D = shield.get_global_transform()
	var sh: Vector2 = shield.texture.get_size() / 2.0
	var bottom: float = -INF
	for c: Vector2 in [Vector2(-sh.x, -sh.y), Vector2(sh.x, -sh.y), Vector2(sh.x, sh.y), Vector2(-sh.x, sh.y)]:
		bottom = maxf(bottom, (st * c).y)
	var hand: Polygon2D = sword.get_node_or_null("Hand") as Polygon2D
	var shadows: Array = []
	_shadow_nodes(weapon, shadows)
	var dist: float = sword.global_position.x - shield.global_position.x
	var ok: bool = grip.y >= 318.0 and bottom - 312.0 >= 24.0 and hand != null and hand.visible \
		and shadows.is_empty() and dist >= 220.0 and dist <= 280.0
	r.check("UI-4", ok, "cabo (4,28) em y=%.1f; escudo passa do recorte em %.1f px; Hand=%s; sombras=%s; distância dos centros=%.1f" % [
		grip.y, bottom - 312.0, hand != null and hand.visible, str(shadows), dist])


static func _ui5(r: GateReport, end: EndScreen, state: Dictionary) -> void:
	var errs: Array = []
	for pair: Array in [["ESCAPED", "ESCAPOU"], ["DEAD", "MORREU"], ["TIMEOUT", "TEMPO"]]:
		var s: Dictionary = state.duplicate(true)
		s["terminal"] = ""
		end.push_state(s, 1)
		s["terminal"] = String(pair[0])
		end.push_state(s, 1)
		var pr: Rect2 = Rect2(end.panel().position, end.panel().size)
		if not end.visible or pr.size != Vector2(360, 200) or not Rect2(0, 0, 640, 360).encloses(pr) \
				or not end.title().contains(String(pair[1])):
			errs.append("%s: visível=%s painel=%s título='%s'" % [pair[0], end.visible, pr, end.title()])
	end.push_state(state, 1)
	r.check("UI-5", errs.is_empty(), "tela final ESCAPOU/MORREU/TEMPO em painel 360×200; erros=%s" % str(errs))


static func _front(sim: WorldSim, x: int, z: int, max_cells: int) -> bool:
	var p: PlayerSim = sim.player
	var dx: float = float(x - p.pos_x)
	var dz: float = float(z - p.pos_z)
	var cheb: int = maxi(absi(PilotSim.cell_of(x) - PilotSim.cell_of(p.pos_x)), absi(PilotSim.cell_of(z) - PilotSim.cell_of(p.pos_z)))
	if cheb > max_cells or (dx == 0.0 and dz == 0.0):
		return false
	var phi: float = TAU * float(p.angle) / 4096.0
	var d: Vector2 = Vector2(dx, dz).normalized()
	return rad_to_deg(acos(clampf(d.dot(Vector2(cos(phi), sin(phi))), -1.0, 1.0))) <= FRONT_DEG \
		and EnemySim.los(sim.grid, p.pos_x, p.pos_z, x, z)


static func _ui6(r: GateReport) -> void:
	var gen: Dictionary = GateTraces.demo_iter4()
	if gen.is_empty():
		r.check("UI-6", false, "sem cena de demonstração em 1..%d" % GateTraces.DEMO4_MAX_SEED)
		return
	var tr: Variant = GateTraces.load_trace(GateTraces.DEMO4)
	var h: Dictionary = tr["header"] if tr != null else {}
	var file_ok: bool = tr != null and (tr["inputs"] as Array).size() == GateTraces.DEMO4_TICKS \
		and h.has("seed") and h.has("pos_x") and h.has("pos_z") and h.has("angle") \
		and h == gen["header"] and GateTraces.same_inputs(tr["inputs"], gen["inputs"])
	if not file_ok:
		r.check("UI-6", false, "%s ausente ou diferente de GateTraces.demo_iter4()" % GateTraces.DEMO4)
		return
	var sim: WorldSim = WorldSim.new(int(h["seed"]))
	sim.set_player_pose(int(h["pos_x"]), int(h["pos_z"]), int(h["angle"]))
	var enemy_front: int = 0
	var swing_tick: int = -1
	var item_front_tick: int = -1
	var pick_tick: int = -1
	var count150: int = -1
	var turned: int = 0
	var prev_angle: int = sim.player.angle
	var inputs: Array = tr["inputs"]
	for k: int in range(inputs.size()):
		sim.step(inputs[k])
		var t: int = sim.tick
		if t <= 100:
			for e: EnemySim.Enemy in sim.enemies:
				if e.state != EnemySim.DEAD and _front(sim, e.pos_x, e.pos_z, 6):
					enemy_front += 1
					break
		if swing_tick < 0 and sim.player.swing_state == Combat.WINDUP and sim.player.swing_ticks == 1:
			swing_tick = t
		if item_front_tick < 0 and t <= 60:
			for it: ItemsSim.Item in sim.items:
				if not it.taken and _front(sim, PilotSim.center(it.cell_x), PilotSim.center(it.cell_z), 4):
					item_front_tick = t
					break
		if pick_tick < 0:
			for it: ItemsSim.Item in sim.items:
				if it.taken:
					pick_tick = t
		if t == 150:
			count150 = sim.automap.count()
		if t > 140 and t <= 210:
			var d: int = (sim.player.angle - prev_angle) & 4095
			turned += mini(d, 4096 - d)
		prev_angle = sim.player.angle
	var ok: bool = enemy_front >= 45 and swing_tick > 0 and swing_tick < 140 and item_front_tick > 0 \
		and pick_tick > 0 and pick_tick <= 150 and count150 >= 40 and turned >= 1024
	r.check("UI-6", ok, "semente %d pose (%d,%d,%d): inimigo à frente em %d ticks (1–100); golpe no tick %d; item à frente no tick %d, coleta no tick %d; automapa=%d no tick 150; giro %d BAM (141–210)" % [
		int(h["seed"]), int(h["pos_x"]), int(h["pos_z"]), int(h["angle"]), enemy_front, swing_tick,
		item_front_tick, pick_tick, count150, turned])


static func _ui7(r: GateReport, audio: Node) -> void:
	var errs: Array = []
	for n: String in AudioView.PROGRESS_SOUNDS:
		var w: AudioStreamWAV = audio.call("get_stream", n) as AudioStreamWAV
		if w == null:
			errs.append("%s ausente" % n)
			continue
		var frames: int = w.data.size() / 2
		var secs: float = float(frames) / float(w.mix_rate)
		var peak: int = 0
		for i: int in range(frames):
			peak = maxi(peak, absi(w.data.decode_s16(i * 2)))
		var pk: float = float(peak) / 32767.0
		if w.format != AudioStreamWAV.FORMAT_16_BITS or w.mix_rate != AUDIO_RATE or w.stereo \
				or secs < AUDIO_MIN_S or secs > AUDIO_MAX_S or pk > AUDIO_PEAK:
			errs.append("%s: %.2f s pico %.2f" % [n, secs, pk])
	r.check("UI-7", errs.is_empty(), "%d sons de M5/M6: 16 bits mono 22050 Hz, 0,05–2,5 s, pico <= 0,9; erros=%s" % [
		AudioView.PROGRESS_SOUNDS.size(), str(errs)])
