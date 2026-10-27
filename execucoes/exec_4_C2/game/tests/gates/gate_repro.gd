class_name GateRepro
extends RefCounted
## R1 (intraprocesso), R3 e R3-combate (núcleo vs. cena), testes de cena,
## M4-A7 e preservação da grade de M2.

const TRACE: String = "r_seed1337_random.jsonl"
const COMBAT_TRACE: String = "r_seed1337_combat.jsonl"
## SHA-256 da concatenação de grid_sha256() das sementes 1..100 (gerador da rodada 1, 0eadf34).
const GRID_DIGEST_R1: String = "dc79b9c93d9b809f9e2ee07a2f37f798816ab20c7139d413b714434b76dd5e5a"
const SEED: int = 1337
const MAIN_SCENE: String = "res://view/main.tscn"


static func core_chain(inputs: Array) -> String:
	var sim: WorldSim = WorldSim.new(SEED, false)
	for inp: IntInput in inputs:
		sim.step(inp)
	return sim.chain


static func run(r: GateReport, tree: SceneTree) -> void:
	var inputs: Array = GateTraces.load_inputs(TRACE)
	var trace_ok: bool = inputs.size() == 600 and GateTraces.same_inputs(inputs, GateTraces.random_inputs(SEED, 600, true))
	r.check("R-trace", trace_ok, "trilha %s com 600 ticks" % TRACE)
	var a: String = core_chain(inputs)
	var b: String = core_chain(inputs)
	r.check("R1", a == b and a != "", "C_K=%s" % a)
	# R3: mesma trilha pela cena completa em headless.
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("configure", SEED, false, true)
	tree.root.add_child(main)
	for inp: IntInput in inputs:
		main.call("advance", inp)
	var sim: WorldSim = main.get("sim")
	r.check("R3", sim.chain == a and not sim.enemies.is_empty(),
		"cena C_K=%s com %d inimigos" % [sim.chain, sim.enemies.size()])
	_scene_checks(r, main)
	GateM4.scene_check(r, main)
	tree.root.remove_child(main)
	main.free()
	_combat(r, tree)
	_grid_preservation(r)


static func grid_digest() -> String:
	var gen: DungeonGen = DungeonGen.new()
	var all: String = ""
	for s: int in range(1, 101):
		all += gen.generate(s).grid_sha256()
	return StateHash.sha256_text(all)


static func _grid_preservation(r: GateReport) -> void:
	var d: String = grid_digest()
	r.check("PRES-grid", d == GRID_DIGEST_R1, "grid_sha256 das sementes 1..100 igual à rodada 1 (digest=%s)" % d)


## R3-combate: trilha aleatória com attack/block pela cena completa.
static func _combat(r: GateReport, tree: SceneTree) -> void:
	var inputs: Array = GateTraces.load_inputs(COMBAT_TRACE)
	var trace_ok: bool = inputs.size() == 600 \
		and GateTraces.same_inputs(inputs, GateTraces.random_inputs(SEED, 600, true, true))
	var a: String = core_chain(inputs)
	var main: Node = (load(MAIN_SCENE) as PackedScene).instantiate()
	main.call("configure", SEED, false, true)
	tree.root.add_child(main)
	for inp: IntInput in inputs:
		main.call("advance", inp)
	var sim: WorldSim = main.get("sim")
	r.check("R3-combate", trace_ok and sim.chain == a,
		"%s: núcleo C_K=%s, cena C_K=%s" % [COMBAT_TRACE, a, sim.chain])
	tree.root.remove_child(main)
	main.free()


static func _scene_checks(r: GateReport, main: Node) -> void:
	var player: Node = main.get_node_or_null("Player")
	var cam: Camera3D = null
	if player != null:
		cam = player.get_node_or_null("Camera3D") as Camera3D
	r.check("SCENE-player", player is CharacterBody3D and cam != null and is_equal_approx(cam.position.y, 1.5),
		"Player CharacterBody3D com Camera3D em Y=1,5")
	if cam != null:
		var sim: WorldSim = main.get("sim")
		var phi: float = TAU * float(sim.player.angle) / 4096.0
		var fwd: Vector3 = -cam.global_basis.z
		var expect: Vector3 = Vector3(cos(phi), 0.0, -sin(phi))
		var p3: Vector3 = (player as Node3D).global_position
		var pos_ok: bool = p3.distance_to(Vector3(sim.player.pos_x / 1024.0, 0.0, -sim.player.pos_z / 1024.0)) < 0.001
		r.check("SCENE-camera", fwd.distance_to(expect) < 0.001 and pos_ok,
			"frente da câmera=%s esperado=%s (angle=%d)" % [fwd, expect, sim.player.angle])
	# A apresentação não usa a física do motor.
	var offenders: Array = []
	for f: String in DirAccess.get_files_at("res://view"):
		if not f.ends_with(".gd"):
			continue
		var txt: String = FileAccess.get_file_as_string("res://view/" + f)
		for bad: String in ["move_and_slide", "move_and_collide", "queue_hit", "add_enemy"]:
			if txt.contains(bad):
				offenders.append("%s:%s" % [f, bad])
	r.check("SCENE-nophysics", offenders.is_empty(),
		"view/ sem move_and_slide/move_and_collide/queue_hit/add_enemy %s" % str(offenders))
	var hud: CanvasLayer = main.get_node_or_null("HUD") as CanvasLayer
	var weapon: CanvasLayer = main.get_node_or_null("Weapon") as CanvasLayer
	r.check("SCENE-hud", hud != null and hud.layer == 2 and weapon != null and weapon.layer == 1
		and weapon.get_node_or_null("Clip/Sword") is Sprite2D and weapon.get_node_or_null("Clip/Shield") is Sprite2D
		and hud.get_node_or_null("Vida/Fill") != null and hud.get_node_or_null("Vigor/Fill") != null
		and hud.get_node_or_null("Compass") != null and hud.get_node_or_null("Portrait") != null,
		"Main/HUD layer 2 (retrato, Vida, Vigor, bússola) e Main/Weapon layer 1 (espada, escudo)")
	var missing: Array = []
	for id: String in AssetResolver.asset_map().keys():
		var tex: Texture2D = AssetResolver.resolve(id)
		if tex == null or tex.get_width() != 32 or tex.get_height() != 32:
			missing.append(id)
	r.check("SCENE-assets", missing.is_empty() and AssetResolver.asset_map().size() == 23,
		"asset_map resolve %d texturas 32×32; falhas=%s" % [AssetResolver.asset_map().size(), str(missing)])
	var dv: Node = main.get_node_or_null("DungeonView")
	var sim2: WorldSim = main.get("sim")
	r.check("SCENE-dungeon", dv != null and dv.get_node_or_null("DungeonMesh") != null
		and int(dv.call("door_count")) == sim2.grid.doors().size() and dv.get_node_or_null("ExitPortal") != null,
		"malha, %d portas e portal instanciados" % sim2.grid.doors().size())
