extends Node3D
## Cena principal: amostra o input, chama WorldSim.step() uma vez por tick físico
## e desenha o estado. A apresentação só lê o núcleo.
## Modo atração (plano R3 C3): sem evento de teclado/mouse nos primeiros 30 ticks
## (ou com o argumento de usuário --demo), o input vem do piloto de fuga (plano R4 C5)
## até o primeiro evento real; depois, do InputSampler para sempre.
## M5/M6: automapa (Tab, não pausa), itens no chão e tela final.
## R5: efeitos sonoros procedurais (AudioSfx) e semente de vitrine do modo atração.
## R6 (C12): o modo atração abre o automapa em janelas fixas de tempo (só `visible`).

const IntInput = preload("res://sim/int_input.gd")
const WorldSim = preload("res://sim/world_sim.gd")
const InputSampler = preload("res://input/input_sampler.gd")
const DungeonView = preload("res://view/dungeon_view.gd")
const EnemyView = preload("res://view/enemy_view.gd")
const ItemView = preload("res://view/item_view.gd")
const AutomapOverlay = preload("res://view/automap_overlay.gd")
const EndScreen = preload("res://view/end_screen.gd")
const AudioSfx = preload("res://view/audio_sfx.gd")
const PilotEscape = preload("res://scripts/pilot_escape.gd")
const PLAYER_VIEW_SCENE: PackedScene = preload("res://view/player_view.tscn")
const WEAPON_VIEW_SCENE: PackedScene = preload("res://view/weapon_view.tscn")
const HUD_SCENE: PackedScene = preload("res://view/hud_daggerfall.tscn")

const DEFAULT_SEED: int = 223  # semente de vitrine (plano R6 §5.1): 100 ticks com inimigo (primeiro em t=159), 41 ticks com item
const ATTRACT_IDLE_TICKS: int = 30
## Agenda do automapa no modo atração (plano R6 §2.1): aberto em [210, 299], [450, 539]…
const MAP_FIRST_TICK: int = 210
const MAP_PERIOD: int = 240
const MAP_OPEN_TICKS: int = 90
const AMBIENT_ENERGY: float = 0.35
const FOG_DENSITY: float = 0.04

var world: WorldSim
## Semente usada sem attach_world; os gates podem fixá-la antes de entrar na árvore.
var start_seed: int = DEFAULT_SEED
var _driven_externally: bool = false
var _sampler: InputSampler
var _dungeon_view: DungeonView
var _player_view: Node3D
var _enemy_view: EnemyView
var _item_view: ItemView
var _automap: AutomapOverlay
var _end: EndScreen
var _weapon_view: CanvasLayer
var _hud: CanvasLayer
var _sfx: AudioSfx
var _env: Environment
var _pilot: PilotEscape
var _phys_ticks: int = 0
var _real_input_seen: bool = false
var _demo: bool = false
var _attract_map: bool = false


## Usado pelo runner (--with-view): o runner avança o núcleo e chama sync_view().
func attach_world(w: WorldSim) -> void:
	world = w
	_driven_externally = true


func _ready() -> void:
	if world == null:
		world = WorldSim.new(start_seed, "dungeon")
	_sampler = InputSampler.new()
	_pilot = PilotEscape.new(start_seed)
	_demo = OS.get_cmdline_user_args().has("--demo")
	_build_environment()
	_dungeon_view = DungeonView.new()
	_dungeon_view.name = "DungeonView"
	add_child(_dungeon_view)
	_enemy_view = EnemyView.new()
	_enemy_view.name = "EnemyView"
	add_child(_enemy_view)
	_item_view = ItemView.new()
	_item_view.name = "ItemView"
	add_child(_item_view)
	_player_view = PLAYER_VIEW_SCENE.instantiate()
	add_child(_player_view)
	_weapon_view = WEAPON_VIEW_SCENE.instantiate()
	add_child(_weapon_view)
	_hud = HUD_SCENE.instantiate()
	add_child(_hud)
	var automap_layer := CanvasLayer.new()
	automap_layer.name = "AutomapLayer"
	automap_layer.layer = 3
	add_child(automap_layer)
	_automap = AutomapOverlay.new()
	_automap.name = "AutomapOverlay"
	automap_layer.add_child(_automap)
	_end = EndScreen.new()
	_end.name = "EndScreen"
	add_child(_end)
	_sfx = AudioSfx.new()
	_sfx.name = "AudioSfx"
	add_child(_sfx)
	if not _driven_externally:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	sync_view()


func _build_environment() -> void:
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0, 0, 0)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.35, 0.4, 0.55)
	_env.ambient_light_energy = AMBIENT_ENERGY
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.02, 0.02, 0.03)
	_env.fog_density = FOG_DENSITY
	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = _env
	add_child(we)


func get_environment() -> Environment:
	return _env


## Função pura da agenda; a = _phys_ticks.
static func attract_map_open(a: int) -> bool:
	return a >= MAP_FIRST_TICK and (a - MAP_FIRST_TICK) % MAP_PERIOD < MAP_OPEN_TICKS


func attract_active() -> bool:
	if _driven_externally or _real_input_seen:
		return false
	return _demo or _phys_ticks > ATTRACT_IDLE_TICKS


func _input(event: InputEvent) -> void:
	if event is InputEventKey or event is InputEventMouseButton:
		_real_input_seen = true
	elif event is InputEventMouseMotion and (event as InputEventMouseMotion).relative != Vector2.ZERO:
		_real_input_seen = true


func _unhandled_input(event: InputEvent) -> void:
	if _driven_externally:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_sampler.add_mouse_dx((event as InputEventMouseMotion).relative.x)


func _physics_process(_delta: float) -> void:
	if _driven_externally:
		return
	_phys_ticks += 1
	var inp: IntInput
	if attract_active():
		inp = _pilot.next_input(world)
	else:
		inp = _sampler.sample()
	world.step(inp)
	if attract_active():
		var open: bool = attract_map_open(_phys_ticks)
		if open != _automap.visible:
			_automap.toggle()
		_attract_map = true
	elif _attract_map:
		_automap.visible = false
		_attract_map = false


func _process(_delta: float) -> void:
	sync_view()


func sync_view() -> void:
	var p: Dictionary = world.get_player()
	_dungeon_view.refresh(world.get_grid(), world.get_grid_sha256())
	_player_view.apply_state(p)
	_enemy_view.apply_state(world.get_enemies(), p, world.get_tick())
	_item_view.apply_state(world.get_items(), world.get_tick())
	_weapon_view.apply_state(p)
	_hud.apply_state(p, world.get_tick())
	_automap.apply_state(world.get_visited(), world.get_grid(), p)
	_end.apply_state(world.get_terminal(), world.get_terminal_tick(), p)
	_sfx.apply_state(p, world.get_enemies(), world.get_terminal(), _automap.visible)
