extends Node3D
## Cena principal: monta o núcleo e as vistas; laço _physics_process -> sampler -> step -> vistas.
## Com external_drive = true (runner --with-view) o laço é conduzido de fora via advance().
## Argumentos: --seed=N --test-room [--dummy] [--enemies=tipo:cx:cz,...] [--fixture=automap]
##   [--replay=trilha.jsonl] [--show-map] [--demo]
## --demo = --test-room --enemies=skeleton:8:7,rat:19:4 --replay=demo_iter4.jsonl, com o automapa
##   aberto (só na view) nos ticks 520-600 da reprodução. Captura: godot --path game -- --demo
## Rodada 5: sem argumentos (fora do headless) abre o MODO VITRINE: semente 1 com o piloto jogando e o
##   automapa aberto nos ticks 300-420; a primeira entrada real do jogador devolve o controle.
##   --manual: controle do jogador desde o início. --pilot [--seed=N]: piloto sem devolver o controle.
##   Captura recomendada: godot --path game

@onready var player_view: CharacterBody3D = $Player
@onready var dungeon_view: Node3D = $DungeonView
@onready var enemy_view: Node3D = $Enemies
@onready var weapon_view: CanvasLayer = $WeaponView
@onready var hud: CanvasLayer = $HUD
@onready var automap: Control = $AutomapOverlay/Map
@onready var audio_view: Node = $AudioView
@onready var sampler: InputSampler = $InputSampler
@onready var item_view: Node3D = $Items
@onready var end_screen: CanvasLayer = $EndScreen

const DEMO_ENEMIES: String = "skeleton:8:7,rat:19:4"
const DEMO_TRACE: String = "res://tests/traces/demo_iter4.jsonl"
const DEMO_MAP_TICKS: Array = [520, 600]
const SHOWCASE_SEED: int = 1
const SHOWCASE_MAP_TICKS: Array = [300, 420]
const TAKEOVER_MOUSE_PX: float = 4.0

## Nova partida pedida na tela final (semente + 1); -1 = usar os argumentos.
static var restart_seed: int = -1
static var restart_pilot: bool = false

var world: WorldSim
var external_drive: bool = false
var _replay: Array = []
var _replay_on: bool = false
var _replay_k: int = 0
var _demo: bool = false
var force_showcase: bool = false   # testes: força o modo vitrine antes de _ready
var _pilot: Pilot = null
var _showcase: bool = false


func _ready() -> void:
	if world == null:
		var user_args: PackedStringArray = OS.get_cmdline_user_args()
		var args: Dictionary = parse_args(user_args)
		var headless: bool = DisplayServer.get_name() == "headless"
		var pilot_mode: bool = args.has("pilot")
		if restart_seed >= 0:
			args["seed"] = str(restart_seed)
			pilot_mode = pilot_mode or restart_pilot
			restart_seed = -1
		elif force_showcase or (user_args.is_empty() and not headless):
			_showcase = true
			pilot_mode = true
			args["seed"] = str(SHOWCASE_SEED)
		if args.has("demo"):
			_demo = true
			args["test-room"] = ""
			args["enemies"] = DEMO_ENEMIES
			args["replay"] = DEMO_TRACE
		AssetResolver.profile = args.get("art-profile", "free")
		world = WorldSim.create(int(args.get("seed", "1")), args.has("test-room"), args.get("fixture", ""))
		if args.has("dummy"):
			if args.has("test-room"):
				world.add_dummy(DungeonGen.cell_center_u(8), DungeonGen.cell_center_u(4))
			else:
				push_warning("--dummy exige --test-room; ignorado")
		if args.has("enemies"):
			if args.has("test-room"):
				var en: Array = parse_enemies(args["enemies"])
				if en.size() == 1 and en[0] is String:
					push_warning(en[0])
				else:
					add_enemies(world, en)
			else:
				push_warning("--enemies exige --test-room; ignorado")
		if args.has("replay"):
			var p: String = args["replay"]
			if not (p.begins_with("res://") or p.begins_with("user://") or p.is_absolute_path()):
				p = "res://" + p
			var tr: Dictionary = TraceIO.read(p)
			if tr["error"] != "":
				push_error(tr["error"])
			_replay = tr["inputs"]
			_replay_on = true
		automap.visible = args.has("show-map")
		if pilot_mode and not _replay_on and not args.has("manual"):
			_pilot = Pilot.create(world.seed_value)
		else:
			_showcase = false
	_setup_environment()
	dungeon_view.build(world)
	enemy_view.build(world)
	item_view.build(world)
	automap.toggled.connect(audio_view.on_map_toggled)
	end_screen.restart_requested.connect(_on_restart)
	_present([], null)
	if not external_drive and not _replay_on and _pilot == null and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


static func parse_args(argv: PackedStringArray) -> Dictionary:
	var out: Dictionary = {}
	for a: String in argv:
		if not a.begins_with("--"):
			continue
		var kv: PackedStringArray = a.substr(2).split("=", true, 1)
		out[kv[0]] = kv[1] if kv.size() > 1 else ""
	return out


## "tipo:cx:cz,..." -> [[tipo, cx, cz], ...]; em erro devolve [mensagem]. Usado também pelo runner.
static func parse_enemies(spec: String) -> Array:
	var out: Array = []
	if spec.strip_edges() == "":
		return out
	for item: String in spec.split(","):
		var p: PackedStringArray = item.strip_edges().split(":")
		if p.size() != 3 or not EnemySim.TYPES.has(p[0]) or not p[1].is_valid_int() or not p[2].is_valid_int():
			return ["--enemies inválido: %s" % item]
		out.append([p[0], p[1].to_int(), p[2].to_int()])
	return out


static func add_enemies(w: WorldSim, enemies: Array) -> void:
	for en: Array in enemies:
		w.add_enemy(en[0], DungeonGen.cell_center_u(en[1]), DungeonGen.cell_center_u(en[2]))


## Usado pelo runner antes de entrar na árvore.
func attach_world(w: WorldSim) -> void:
	world = w
	external_drive = true


func _setup_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1.0, 0.85, 0.65)
	env.ambient_light_energy = 0.15
	env.fog_enabled = true
	env.fog_light_color = Color(0.02, 0.015, 0.01)
	env.fog_density = 0.08
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)


## Vitrine: a primeira entrada real (tecla, botão ou mouse > 4 px) desliga o piloto e devolve o controle.
func _input(event: InputEvent) -> void:
	if not _showcase or _pilot == null or world == null or world.get_terminal() != "NONE":
		return
	var real: bool = (event is InputEventKey and event.pressed) or (event is InputEventMouseButton and event.pressed) \
		or (event is InputEventMouseMotion and (event as InputEventMouseMotion).relative.length() > TAKEOVER_MOUSE_PX)
	if not real:
		return
	_pilot = null
	_showcase = false
	if automap.visible:
		automap.visible = false
		automap.toggled.emit(false)
	hud.show_message("Controle manual")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _on_restart() -> void:
	restart_seed = world.seed_value + 1
	restart_pilot = _pilot != null
	get_tree().reload_current_scene()


func _physics_process(_delta: float) -> void:
	if external_drive or world == null:
		return
	if _pilot != null:
		if _showcase:
			var show_map: bool = world.get_tick() >= SHOWCASE_MAP_TICKS[0] and world.get_tick() < SHOWCASE_MAP_TICKS[1]
			if show_map != automap.visible:
				automap.visible = show_map
				automap.toggled.emit(show_map)
		advance(_pilot.next_input(world))
	elif _replay_on:
		var inp: IntInput = _replay[_replay_k] if _replay_k < _replay.size() else IntInput.new()
		_replay_k += 1
		if _demo:
			var show: bool = _replay_k >= DEMO_MAP_TICKS[0] and _replay_k <= DEMO_MAP_TICKS[1]
			if show != automap.visible:
				automap.visible = show
				automap.toggled.emit(show)
		advance(inp)
	else:
		advance(sampler.sample())


func advance(input: IntInput) -> void:
	world.step(input)
	_present(dungeon_view.refresh(world), input)


func _present(opened: Array, input: IntInput) -> void:
	player_view.apply_state(world.get_player_pos(), world.get_angle())
	enemy_view.refresh(world)
	item_view.refresh(world)
	dungeon_view.set_exit_ready(world.get_inventory()["key"])
	weapon_view.refresh(world)
	hud.refresh(world, input)
	automap.refresh(world)
	audio_view.on_tick(world.get_player_pos(), world.get_player_vel(), opened.size())
	audio_view.on_combat(world.get_player_status(), world.get_enemies(), input)
	audio_view.on_items(world.get_events(), world.get_items(), world.get_terminal())
	end_screen.refresh(world)
