extends Node3D
## Cena principal: cria a WorldSim, chama step() uma vez por tick físico e
## desenha o estado. A apresentação só lê snapshot(), grid e automap.visited.
## Modo vitrine (plano §8.7): sem tecla nem botão do mouse no 1º segundo, a
## entrada passa a vir do Pilot; a primeira tecla recarrega a cena para o jogador.

const DEFAULT_SEED: int = 1337
const ENEMY_SCENE: PackedScene = preload("res://view/enemy_view.tscn")
const ATTRACT_AFTER_TICKS: int = 60
const ATTRACT_MAP_PERIOD: int = 600
const ATTRACT_MAP_OPEN_AT: int = 300
const ATTRACT_MAP_TICKS: int = 90
const ATTRACT_RESTART_FRAMES: int = 300
const BLINK_FRAMES: int = 60
const ITEM_PICKUP_MSG: Array[String] = ["Pegou uma poção de vida", "Pegou uma poção de vigor", "Pegou a Chave da Saída", "+25 de ouro"]

## Sobrevive ao reload: a partida do jogador começa limpa, sem nova vitrine.
static var _player_took_over: bool = false
const WINDUP_SOUNDS: Array[String] = ["", "rat_windup", "skel_windup", "guard_windup"]

var sim: WorldSim
var external: bool = false
var _sampler: InputSampler = InputSampler.new()
var _prev: Dictionary = {}
var _cur: Dictionary = {}
var _last_use: bool = false
var _enemy_views: Array[EnemyView] = []
var _item_views: Array[ItemView] = []
var automap_toggle_count: int = 0
var _physics_ticks: int = 0
var _user_input: bool = false
var _attract_allowed: bool = true
var _attract: bool = false
var _attract_ticks: int = 0
var _attract_label: Label = null
var _frames: int = 0
var _end_frames: int = 0
var _pilot: Pilot = null

@onready var _env: WorldEnvironment = $WorldEnvironment
@onready var _dungeon_view: DungeonView = $DungeonView
@onready var _player_view: PlayerView = $PlayerView
@onready var _sfx: Sfx = $Sfx
@onready var _enemies_root: Node3D = $Enemies
@onready var _weapon_view: WeaponView = $WeaponView
@onready var _hud: HudDaggerfall = $Hud
@onready var _camera: Camera3D = $PlayerView/Camera3D
@onready var _torch: OmniLight3D = $PlayerView/Camera3D/OmniLight3D
@onready var _items_root: Node3D = $Items
@onready var _automap: AutomapOverlay = $Automap
@onready var _end_screen: EndScreen = $EndScreen


## Usado pelo runner (--with-view): a cena só desenha uma WorldSim externa.
func attach_sim(s: WorldSim) -> void:
	sim = s
	external = true


func _ready() -> void:
	_setup_environment()
	if sim == null:
		var seed_value: int = DEFAULT_SEED
		var room: String = "dungeon"
		for arg in OS.get_cmdline_user_args():
			if arg.begins_with("--seed="):
				seed_value = int(arg.trim_prefix("--seed="))
			elif arg.begins_with("--room="):
				room = arg.trim_prefix("--room=")
			elif arg.begins_with("--art-profile="):
				AssetResolver.profile = arg.trim_prefix("--art-profile=")
			elif arg == "--no-attract":
				_attract_allowed = false
		sim = WorldSim.create(seed_value, room)
	if external or _player_took_over:
		_attract_allowed = false
	_end_screen.interactive = not external
	_automap.toggled.connect(_on_automap_toggled)
	_dungeon_view.build(sim.grid)
	_cur = sim.snapshot()
	_prev = _cur
	_build_enemies()
	_build_items()
	_player_view.apply(_prev.player, _cur.player, 1.0)
	_weapon_view.apply(_cur.player, _cur.player, 1.0)
	_hud.apply(_cur.player)
	if not external and DisplayServer.get_name() != "headless":
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


## Detecta a primeira tecla/botão: antes da vitrine, cancela a vitrine; durante
## ela, recarrega a cena com a mesma semente sob controle do jogador.
func _input(event: InputEvent) -> void:
	if external:
		return
	var pressed: bool = (event is InputEventKey and (event as InputEventKey).pressed) \
		or (event is InputEventMouseButton and (event as InputEventMouseButton).pressed)
	if not pressed:
		return
	if _attract:
		_player_took_over = true
		get_viewport().set_input_as_handled()
		get_tree().reload_current_scene()
	else:
		_user_input = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not external:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_sampler.handle_event(event)


func _physics_process(_dt: float) -> void:
	if external:
		return
	_physics_ticks += 1
	if not _attract and _attract_allowed and not _user_input and _physics_ticks > ATTRACT_AFTER_TICKS:
		_start_attract()
	var inp: IntInput
	if _attract:
		inp = _pilot.next_input(sim)
		_attract_tick()
	else:
		inp = _sampler.sample()
	sim.step(inp)
	_last_use = inp.use
	refresh_from_sim()


func _process(_dt: float) -> void:
	if _cur.is_empty():
		return
	_frames += 1
	if _attract_label != null:
		_attract_label.visible = (_frames / BLINK_FRAMES) % 2 == 0
	if _attract and _end_screen.shown:
		_end_frames += 1
		if _end_frames >= ATTRACT_RESTART_FRAMES:
			get_tree().reload_current_scene()
			return
	var frac: float = 1.0 if external else Engine.get_physics_interpolation_fraction()
	if _automap.visible:
		_automap.apply(_prev.player, _cur.player, sim.automap.visited, sim.grid, frac)
	_player_view.apply(_prev.player, _cur.player, frac)
	_weapon_view.apply(_prev.player, _cur.player, frac)
	var cam: Vector3 = _camera.global_position
	for v in _enemy_views:
		v.apply(frac, cam)


## Um EnemyView por inimigo de sim.enemies, no grupo "enemies" (M4-A7).
func _build_enemies() -> void:
	for c in _enemies_root.get_children():
		c.queue_free()
	_enemy_views.clear()
	for d: Dictionary in _cur.enemies:
		var v: EnemyView = ENEMY_SCENE.instantiate()
		_enemies_root.add_child(v)
		v.add_to_group("enemies")
		v.setup(d)
		_enemy_views.append(v)


## Um ItemView por item de sim.items, no grupo "items".
func _build_items() -> void:
	for c in _items_root.get_children():
		c.queue_free()
	_item_views.clear()
	for d: Dictionary in _cur.items:
		var v: ItemView = ItemView.new()
		_items_root.add_child(v)
		v.add_to_group("items")
		v.setup(d)
		_item_views.append(v)


## Abre/fecha a sobreposição do automapa (gates, runner e vitrine).
func toggle_automap() -> void:
	_automap.toggle()


func _on_automap_toggled(_open: bool) -> void:
	automap_toggle_count += 1
	_sfx.play("automap_toggle")


func _start_attract() -> void:
	_attract = true
	_pilot = Pilot.create(sim.seed_value)
	_end_screen.interactive = false
	var layer: CanvasLayer = CanvasLayer.new()
	layer.name = "Attract"
	layer.layer = 25
	add_child(layer)
	var l: Label = Label.new()
	l.text = "DEMONSTRAÇÃO — pressione qualquer tecla"
	l.add_theme_font_size_override("font_size", 10)
	l.add_theme_color_override("font_color", Color(0.92, 0.86, 0.70))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	l.add_theme_constant_override("outline_size", 1)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.position = Vector2(0, 2)
	l.size = Vector2(640, 14)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(l)
	_attract_label = l


## Na vitrine, o automapa fica aberto por 90 ticks a cada 600 (só visual).
func _attract_tick() -> void:
	_attract_ticks += 1
	var ph: int = _attract_ticks % ATTRACT_MAP_PERIOD
	var want: bool = ph >= ATTRACT_MAP_OPEN_AT and ph < ATTRACT_MAP_OPEN_AT + ATTRACT_MAP_TICKS
	if want != _automap.visible:
		toggle_automap()


## Lê o estado após um step(): portas, itens, mensagens, sons e pose do jogador.
func refresh_from_sim() -> void:
	_prev = _cur
	_cur = sim.snapshot()
	var before: Dictionary = {}
	for d: Dictionary in _prev.dungeon.doors:
		before[d.id] = d.state
	for d: Dictionary in _cur.dungeon.doors:
		var b: int = int(before.get(d.id, d.state))
		if b == Grid.DOOR_CLOSED and d.state == Grid.DOOR_OPEN:
			_sfx.play("door_open")
		elif b == Grid.DOOR_LOCKED and d.state == Grid.DOOR_OPEN:
			_sfx.play("door_unlock")
			_hud.push_message("A porta trancada se abriu")
	if _last_use and _facing_cell_type() == Grid.DOOR_LOCKED:
		_sfx.play("door_bump")
		_hud.push_message("Porta trancada: falta a chave")
	_last_use = false
	for i in range(mini(_item_views.size(), _cur.items.size())):
		_item_views[i].push_state(_cur.items[i])
	_progress_feedback()
	_dungeon_view.sync_doors(_cur.dungeon.doors)
	_combat_sounds()
	for i in range(mini(_enemy_views.size(), _cur.enemies.size())):
		_enemy_views[i].push_state(_cur.enemies[i])
	_hud.apply(_cur.player)
	if external:
		_player_view.apply(_cur.player, _cur.player, 1.0)
		_weapon_view.apply(_cur.player, _cur.player, 1.0)


## Sons de combate a partir da diferença entre snapshots (plano §7.5).
func _combat_sounds() -> void:
	var p0: Dictionary = _prev.player
	var p1: Dictionary = _cur.player
	var swing_started: bool = int(p1.swing_state) == Combat.S_WINDUP and int(p1.swing_ticks) == 1
	if swing_started:
		_sfx.play("swing")
	var blocked: bool = bool(p1.blocking) and int(p1.stamina) < int(p0.stamina) and not swing_started
	if blocked:
		_sfx.play("block")
	if int(p1.stun_ticks) == Combat.GUARD_BREAK_STUN and int(p0.stun_ticks) != Combat.GUARD_BREAK_STUN:
		_sfx.play("guard_break")
	elif int(p1.hp) < int(p0.hp) and not blocked:
		_sfx.play("player_hurt")
	var n: int = mini(_prev.enemies.size(), _cur.enemies.size())
	for i in range(mini(n, _enemy_views.size())):
		var e0: Dictionary = _prev.enemies[i]
		var e1: Dictionary = _cur.enemies[i]
		var v: EnemyView = _enemy_views[i]
		if int(e1.state) == EnemySim.DEAD and int(e0.state) != EnemySim.DEAD:
			v.play_stream(_sfx.stream("enemy_death"))
			_hud.push_message("Inimigo abatido (+%d XP)" % EnemySim.XP[int(e1.type)])
		elif int(e1.hp) < int(e0.hp):
			v.play_stream(_sfx.stream("hit_flesh"))
		elif int(e1.state) == EnemySim.WINDUP and int(e0.state) != EnemySim.WINDUP:
			v.play_stream(_sfx.stream(WINDUP_SOUNDS[int(e1.type)]))


## Itens, poções, nível e terminal a partir da diferença entre snapshots.
func _progress_feedback() -> void:
	var p0: Dictionary = _prev.player
	var p1: Dictionary = _cur.player
	var i0: Dictionary = p0.inventory
	var i1: Dictionary = p1.inventory
	for k in range(mini(_prev.items.size(), _cur.items.size())):
		var it: Dictionary = _cur.items[k]
		if bool(it.taken) and not bool(_prev.items[k].taken):
			_hud.push_message(ITEM_PICKUP_MSG[int(it.type)])
	if bool(i1.key) and not bool(i0.key):
		_sfx.play("pickup_key")
	if int(i1.potion_hp) > int(i0.potion_hp) or int(i1.potion_sp) > int(i0.potion_sp):
		_sfx.play("pickup_item")
	if int(p1.gold) > int(p0.gold):
		_sfx.play("pickup_gold")
	if int(i1.potion_hp) < int(i0.potion_hp):
		_sfx.play("quaff")
		_hud.push_message("Bebeu poção de vida (+%d PV)" % maxi(int(p1.hp) - int(p0.hp), 0))
	if int(i1.potion_sp) < int(i0.potion_sp):
		_sfx.play("quaff")
		_hud.push_message("Bebeu poção de vigor")
	if int(p1.level) > int(p0.level):
		_sfx.play("level_up")
		_hud.push_message("Subiu para o nível %d!" % int(p1.level))
	if str(_cur.terminal) != "NONE" and str(_prev.terminal) == "NONE":
		match str(_cur.terminal):
			"ESCAPED":
				_sfx.play("escape")
			"DEAD":
				_sfx.play("death")
			"TIMEOUT":
				_sfx.play("timeout")
		_end_screen.show_result(_cur, sim.seed_value)


func _facing_cell_type() -> int:
	var p: Dictionary = _cur.player
	var dir: int = ((int(p.angle) + 512) & 4095) >> 10
	var dxs: Array[int] = [1, 0, -1, 0]
	var dzs: Array[int] = [0, 1, 0, -1]
	return sim.grid.get_cell((int(p.pos_x) >> 11) + dxs[dir], (int(p.pos_z) >> 11) + dzs[dir])


func _setup_environment() -> void:
	var e: Environment = Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0, 0, 0)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.35, 0.31, 0.27)
	e.ambient_light_energy = 1.0
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_DEPTH
	e.fog_light_color = Color(0.02, 0.02, 0.02)
	e.fog_depth_begin = 8.0
	e.fog_depth_end = 24.0
	_env.environment = e
	# tocha (correção de iluminação da rodada 2, plano §7.1)
	_torch.light_energy = 2.2
	_torch.omni_range = 12.0
	_torch.omni_attenuation = 0.7
