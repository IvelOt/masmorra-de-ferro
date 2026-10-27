extends Node3D
## Cena principal: cria o WorldSim, chama step() uma vez por tick físico e repassa o snapshot
## às views. Nenhuma decisão de jogo acontece aqui.
## Argumentos de usuário (após `--`):
##   (nenhum)      modo de atração: arena de demonstração jogada pelo piloto, em laço;
##                 qualquer tecla ou botão do mouse inicia uma partida com a semente 1
##   --play        partida com setup_seed(seed) e teclado; --seed=N (padrão 1) implica --play
##   --arena       arena jogável; --test-room, --combat-room: salas de teste
##   --demo        trilha res://tests/traces/demo_iter2.jsonl no lugar do teclado (semente)
##   --art-profile=<perfil>
## Enter na tela final (fora da atração) reinicia a mesma partida.

const WorldSim = preload("res://sim/world_sim.gd")
const IntInput = preload("res://sim/int_input.gd")
const InputSampler = preload("res://input/input_sampler.gd")
const TraceIO = preload("res://input/trace_io.gd")
const Pilot = preload("res://input/pilot.gd")
const AssetResolver = preload("res://view/asset_resolver.gd")

const DEMO_TRACE: String = "res://tests/traces/demo_iter2.jsonl"
## Agenda de UI do --demo (só view; Tab não é input da simulação).
const DEMO_MAP_OPEN_TICK: int = 300
const DEMO_MAP_CLOSE_TICK: int = 390
## Agenda de UI do modo de atração (só view, fora do hash).
const ATTRACT_MAP_OPEN_TICK: int = 420
const ATTRACT_MAP_CLOSE_TICK: int = 540
const ATTRACT_END_SECONDS: float = 4.0
const ATTRACT_PILOT_SEED: int = 1
const ATTRACT_MESSAGE: String = "DEMONSTRAÇÃO — tecle algo para jogar"

@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _dungeon_view: Node3D = $DungeonView
@onready var _enemy_view: Node3D = $EnemyView
@onready var _item_view: Node3D = $ItemView
@onready var _player_view: CharacterBody3D = $PlayerView
@onready var _sfx_view: Node3D = $SfxView
@onready var _weapon_view: CanvasLayer = $WeaponView
@onready var _hud: Control = $Hud/Bar
@onready var _automap: Control = $Automap/Overlay
@onready var _end_screen: CanvasLayer = $EndScreen

## Gancho dos testes de cena: "combat", "room", "arena", "attract" ou "seed:N" substituem os
## argumentos de usuário.
var start_override: String = ""
## Quando verdadeiro, _physics_process não faz nada; o teste chama tick_once().
var driven_externally: bool = false
var world: WorldSim = null
var _sampler: InputSampler = null
var _resolver: AssetResolver = null
var _demo: Array = []
var _pilot: Pilot = null
var _attract: bool = false
## Configuração da partida atual: "seed:N", "room", "combat", "arena" (para o reinício).
var _setup: String = ""
var _end_left: float = 0.0
var _prev: Dictionary = {}
var _cur: Dictionary = {}


func _ready() -> void:
	var seed_arg: int = 1
	var room: String = ""
	var demo: bool = false
	var play: bool = false
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--seed="):
			seed_arg = arg.get_slice("=", 1).to_int()
			play = true
		elif arg == "--play":
			play = true
		elif arg == "--test-room":
			room = "room"
		elif arg == "--combat-room":
			room = "combat"
		elif arg == "--arena":
			room = "arena"
		elif arg == "--demo":
			demo = true
	var setup: String = ""
	if start_override.begins_with("seed:"):
		setup = start_override
		demo = false
	elif start_override == "attract":
		setup = "attract"
		demo = false
	elif start_override != "":
		setup = start_override
		demo = false
	elif room != "":
		setup = room
	elif play or demo:
		setup = "seed:%d" % seed_arg
	else:
		setup = "attract"
	if demo:
		_demo = TraceIO.read_trace(DEMO_TRACE)
	_sampler = InputSampler.new()
	_sampler.interactive = DisplayServer.get_name() != "headless" and setup != "attract"
	add_child(_sampler)
	_resolver = AssetResolver.new()
	_setup_environment()
	_automap.toggled.connect(_sfx_view.play_map_toggle)
	_start(setup)


## (Re)inicia a partida e reconstrói as views a partir do primeiro snapshot.
func _start(setup: String) -> void:
	_attract = setup == "attract"
	world = WorldSim.new()
	if _attract:
		_setup = "arena"
		world.setup_test("arena")
		_pilot = Pilot.new(ATTRACT_PILOT_SEED)
	elif setup.begins_with("seed:"):
		_setup = setup
		world.setup_seed(setup.get_slice(":", 1).to_int())
		_pilot = null
	else:
		_setup = setup
		world.setup_test(setup)
		_pilot = null
	_end_left = 0.0
	_cur = world.get_snapshot()
	_prev = _cur
	_dungeon_view.build(_cur, _resolver)
	_enemy_view.setup(_resolver, _cur)
	_item_view.setup(_resolver, _cur)
	_player_view.apply(_prev, _cur, 1.0)
	_weapon_view.update(_prev, _cur)
	_hud.update(_prev, _cur)
	_hud.set_fixed_message(ATTRACT_MESSAGE if _attract else "")
	_automap.set_open(false)
	_automap.set_snapshot(_cur)
	_end_screen.show_footer = not _attract
	_end_screen.update(_cur)


func _setup_environment() -> void:
	var env: Environment = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color.BLACK
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#202028")
	env.ambient_light_energy = 0.35
	env.fog_enabled = true
	env.fog_light_color = Color("#05050a")
	env.fog_density = 0.06
	_env.environment = env


func _unhandled_input(event: InputEvent) -> void:
	if driven_externally:
		return
	if _attract:
		var pressed: bool = (event is InputEventKey and (event as InputEventKey).pressed) \
			or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
		if pressed:
			get_viewport().set_input_as_handled()
			_sampler.interactive = DisplayServer.get_name() != "headless"
			_sampler.call("_ready")
			_start("seed:1")
	elif world.terminal != "NONE" and event is InputEventKey and (event as InputEventKey).pressed \
			and ((event as InputEventKey).keycode == KEY_ENTER or (event as InputEventKey).keycode == KEY_KP_ENTER):
		get_viewport().set_input_as_handled()
		_start(_setup)


func _physics_process(_delta: float) -> void:
	if driven_externally:
		return
	var k: int = world.tick
	var inp: IntInput = null
	if _attract:
		if world.terminal != "NONE":
			# tela final por 4 s e a arena recomeça (laço, como a demo do DOOM)
			_end_left -= 1.0 / float(Engine.physics_ticks_per_second)
			if _end_left <= 0.0:
				_start("attract")
			return
		inp = _pilot.next_input(world)
		_sampler.sample()  # descarta bordas pendentes
		if k + 1 == ATTRACT_MAP_OPEN_TICK:
			_automap.set_open(true)
		elif k + 1 == ATTRACT_MAP_CLOSE_TICK:
			_automap.set_open(false)
	elif k < _demo.size():
		inp = _demo[k]
		_sampler.sample()  # descarta bordas pendentes do teclado durante a demonstração
		if k + 1 == DEMO_MAP_OPEN_TICK:
			_automap.set_open(true)
		elif k + 1 == DEMO_MAP_CLOSE_TICK:
			_automap.set_open(false)
	else:
		inp = _sampler.sample()
	tick_once(inp)
	if _attract and world.terminal != "NONE":
		_end_left = ATTRACT_END_SECONDS


## Um tick: step() no núcleo -> snapshot -> update(prev, cur) de cada view.
func tick_once(inp: IntInput) -> void:
	world.step(inp)
	_prev = _cur
	_cur = world.get_snapshot()
	_dungeon_view.update_doors(_cur)
	_enemy_view.update(_prev, _cur)
	_item_view.update(_cur)
	_weapon_view.update(_prev, _cur)
	_hud.update(_prev, _cur)
	_automap.set_snapshot(_cur)
	_end_screen.update(_cur)
	_sfx_view.on_tick(_prev, _cur, inp)


func _process(_delta: float) -> void:
	_player_view.apply(_prev, _cur, Engine.get_physics_interpolation_fraction())
