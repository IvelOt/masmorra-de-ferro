class_name EntitySim
extends RefCounted
## Entidade do mundo (M3: boneco de treino; M4: rato, esqueleto, guardião). Só int/String/bool.

## Meia-aresta da caixa por tipo (é o raio_alvo da hitbox).
## Números dos inimigos vêm de EnemySim.TYPES (fonte única); o boneco é só daqui.
const HALF: Dictionary = {
	"dummy": 384,
	"rat": EnemySim.TYPES["rat"]["half"],
	"skeleton": EnemySim.TYPES["skeleton"]["half"],
	"guardian": EnemySim.TYPES["guardian"]["half"],
}
const HP_BY_TYPE: Dictionary = {
	"dummy": 100,
	"rat": EnemySim.TYPES["rat"]["hp"],
	"skeleton": EnemySim.TYPES["skeleton"]["hp"],
	"guardian": EnemySim.TYPES["guardian"]["hp"],
}

var id: int = 0
var type: String = ""
var pos_x: int = 0
var pos_z: int = 0
var hp: int = 0
var state: String = "IDLE"
var state_ticks: int = 0
var awake: bool = false


static func make_dummy(p_id: int, p_pos_x: int, p_pos_z: int) -> EntitySim:
	var e := EntitySim.new()
	e.id = p_id
	e.type = "dummy"
	e.pos_x = p_pos_x
	e.pos_z = p_pos_z
	e.hp = HP_BY_TYPE["dummy"]
	e.state = "IDLE"
	return e


## Inimigo de M4 (ou boneco): hp do tipo, IDLE, adormecido.
static func make(p_id: int, p_type: String, p_pos_x: int, p_pos_z: int) -> EntitySim:
	var e := EntitySim.new()
	e.id = p_id
	e.type = p_type
	e.pos_x = p_pos_x
	e.pos_z = p_pos_z
	e.hp = HP_BY_TYPE[p_type]
	e.state = "IDLE"
	e.state_ticks = 0
	e.awake = false
	return e


func to_canon() -> Dictionary:
	return {
		"id": id, "type": type, "pos_x": pos_x, "pos_z": pos_z,
		"hp": hp, "state": state, "state_ticks": state_ticks, "awake": awake,
	}
