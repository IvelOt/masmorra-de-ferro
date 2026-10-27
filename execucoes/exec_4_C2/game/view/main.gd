extends Node3D
## Cena principal: WorldSim + views. _physics_process chama sim.step() uma vez
## por tick; as views só leem o estado. Args: --seed=N (padrão 1), --test-room,
## --dummy (boneco de treino na sala de teste) e --autoplay=res://…jsonl (a
## trilha substitui o InputSampler tick a tick; acabou, volta ao input neutro).
## Sem argumentos e fora de headless, inicia em modo demonstração (semente e pose
## do cabeçalho de demo_iter4.jsonl, automapa aberto nos ticks 150..210); o primeiro evento
## real de teclado/mouse a encerra e o InputSampler assume do estado corrente.
## --no-demo (ou --seed, --test-room, --autoplay) desliga a demonstração.

const DEMO_TRACE: String = "res://tests/traces/demo_iter4.jsonl"
const DEMO_SEED: int = 1
const DEMO_MAP_OPEN: int = 150
const DEMO_MAP_CLOSE: int = 210
const DEMO_MOUSE_PX: float = 4.0

## Semente da próxima partida pedida pela tela final (sobrevive ao reload da cena).
static var restart_seed: int = -1

@onready var dungeon_view: Node3D = $DungeonView
@onready var enemy_view: EnemyView = $Enemies
@onready var player_view: CharacterBody3D = $Player
@onready var audio_view: Node = $AudioView
@onready var weapon_view: CanvasLayer = $Weapon
@onready var hud: HudDaggerfall = $HUD
@onready var item_view: ItemView = $Items
@onready var automap: AutomapOverlay = $Automap
@onready var end_screen: EndScreen = $EndScreen

var sim: WorldSim = null
var sampler: InputSampler = InputSampler.new()
var seed_arg: int = 1
var test_room: bool = false
var dummy: bool = false
## false: masmorra sem inimigos (runner --no-enemies). Definido antes de _ready.
var spawn_enemies: bool = true
## true quando um driver externo (runner/gate) chama advance(); desliga o sampler.
var driven: bool = false
var autoplay_path: String = ""
## true enquanto a demonstração roda (sem argumentos, fora de headless).
var demo: bool = false
var _autoplay: Array = []
var _autoplay_header: Dictionary = {}
var _autoplay_pos: int = 0
var _configured: bool = false
var _state: Dictionary = {}


## Configura antes de entrar na árvore (usado pelo runner --with-view e pelos gates).
func configure(p_seed: int, p_test_room: bool, p_driven: bool, p_dummy: bool = false) -> void:
	seed_arg = p_seed
	test_room = p_test_room
	driven = p_driven
	dummy = p_dummy
	_configured = true


func _ready() -> void:
	if not _configured:
		var no_demo: bool = false
		for a: String in OS.get_cmdline_user_args() + OS.get_cmdline_args():
			if a.begins_with("--seed="):
				seed_arg = int(a.substr(7))
				no_demo = true
			elif a == "--test-room":
				test_room = true
				no_demo = true
			elif a == "--dummy":
				dummy = true
			elif a.begins_with("--autoplay="):
				autoplay_path = a.substr(11)
				no_demo = true
			elif a == "--no-demo":
				no_demo = true
		if restart_seed > 0:
			seed_arg = restart_seed
			restart_seed = -1
			no_demo = true
		if not no_demo and DisplayServer.get_name() != "headless":
			demo = true
			seed_arg = DEMO_SEED
			test_room = false
			autoplay_path = DEMO_TRACE
	if autoplay_path != "":
		_read_autoplay(autoplay_path)
	sim = WorldSim.new(seed_arg, test_room, spawn_enemies)
	if dummy and test_room:
		sim.add_training_dummy()
	if not _autoplay_header.is_empty():
		sim.set_player_pose(int(_autoplay_header["pos_x"]), int(_autoplay_header["pos_z"]),
			int(_autoplay_header["angle"]))
	_setup_environment()
	dungeon_view.build(sim.grid)
	_state = sim.get_state()
	player_view.push_state(_state["player"], true)
	enemy_view.build(_state["enemies"], audio_view)
	weapon_view.call("push_state", _state["player"])
	item_view.build(_state["items"])
	automap.audio = audio_view
	automap.push(sim.automap, sim.grid, _state)
	end_screen.driven = driven
	end_screen.on_restart = _restart
	end_screen.push_state(_state, seed_arg)
	hud.on_tick(_state, {})
	if not driven and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Lê a trilha antes de criar o WorldSim: na demonstração, a semente vem do
## cabeçalho. Sem trilha, a demonstração cai para o jogo interativo (nunca roda
## com input neutro).
func _read_autoplay(path: String) -> void:
	var tr: Variant = TraceIO.read(path)
	if tr == null:
		push_error("main: não leu a trilha %s" % path)
		if demo:
			demo = false
			autoplay_path = ""
		return
	_autoplay = tr["inputs"]
	_autoplay_header = tr["header"]
	if demo:
		seed_arg = int(_autoplay_header.get("seed", DEMO_SEED))


## Nova partida com a semente `p_seed` (Enter na tela final).
func _restart(p_seed: int) -> void:
	restart_seed = p_seed
	get_tree().reload_current_scene()


## Primeiro evento real de teclado ou mouse (movimento >= 4 px) encerra a demonstração.
func _end_demo_on(event: InputEvent) -> void:
	var real: bool = event is InputEventKey or event is InputEventMouseButton
	if event is InputEventMouseMotion:
		real = (event as InputEventMouseMotion).relative.length() >= DEMO_MOUSE_PX
	if real:
		demo = false
		autoplay_path = ""
		_autoplay = []


func _unhandled_input(event: InputEvent) -> void:
	if driven:
		return
	if demo:
		_end_demo_on(event)
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		sampler.add_mouse_motion((event as InputEventMouseMotion).relative.x)
	elif event is InputEventKey and (event as InputEventKey).pressed \
			and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(_dt: float) -> void:
	if driven or sim == null:
		return
	if autoplay_path != "":
		var inp: IntInput = IntInput.new()
		if _autoplay_pos < _autoplay.size():
			inp = _autoplay[_autoplay_pos]
			_autoplay_pos += 1
		advance(inp)
		return
	advance(sampler.sample())


## Um tick: núcleo avança, views leem. Única via de avanço da cena.
func advance(inp: IntInput) -> void:
	var use_on_locked: bool = false
	var exit_no_key: bool = false
	if inp.use and sim.terminal == "" and not sim.player.has_key:
		var t: Array = sim.use_target()
		use_on_locked = not t.is_empty() and sim.grid.get_cell(int(t[0]), int(t[1])) == Grid.DOOR_LOCKED
		exit_no_key = sim.on_exit_cell()
	sim.step(inp)
	var prev: Dictionary = _state
	var s: Dictionary = sim.get_state()
	_state = s
	var ev: Dictionary = HudDaggerfall.events(prev, s, inp)
	ev["locked_no_key"] = use_on_locked
	ev["exit_no_key"] = exit_no_key
	player_view.push_state(s["player"])
	var opened: Array = dungeon_view.update_doors(s["dungeon"]["doors"])
	audio_view.on_tick(s["player"], opened, use_on_locked)
	audio_view.call("on_combat", ev)
	audio_view.call("on_progress", ev)
	item_view.push_state(s["items"])
	if demo:
		# Roteiro de UI da demonstração (fora do núcleo).
		if sim.tick == DEMO_MAP_OPEN:
			automap.set_open(true)
		elif sim.tick == DEMO_MAP_CLOSE:
			automap.set_open(false)
	automap.push(sim.automap, sim.grid, s)
	end_screen.push_state(s, seed_arg)
	enemy_view.push_state(s["enemies"], PlayerView.sim_to_world(int(s["player"]["pos_x"]), int(s["player"]["pos_z"])))
	weapon_view.call("push_state", s["player"])
	hud.on_tick(s, ev)


func _setup_environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.29, 0.26)
	env.ambient_light_energy = 5.5
	env.fog_enabled = true
	env.fog_light_color = Color(0.05, 0.04, 0.035)
	env.fog_density = 0.045
	var we: WorldEnvironment = WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)
