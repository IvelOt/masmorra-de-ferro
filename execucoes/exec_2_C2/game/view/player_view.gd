extends CharacterBody3D
## Casca de apresentação do jogador (GDD §7.1): posição e yaw escritos a partir do snapshot.
## move_and_slide()/move_and_collide() nunca são chamados.
##
## Conversão núcleo -> Godot (plano §5.1; a view espelha Z):
##   posição:      godot.x = pos_x / 1024.0, godot.z = -pos_z / 1024.0, godot.y = 0 (pés)
##   célula:       x ∈ [2cx, 2cx+2], z ∈ [-2(cz+1), -2cz]
##   yaw:          rotation.y = TAU * angle / 4096.0 - PI / 2
## Com isso a=0 olha para +X, strafe=1 vai para a direita da câmera e turn > 0 gira à esquerda.

const UNITS_PER_M: float = 1024.0
const ANGLE_FULL: int = 4096


static func to_godot(pos_x: float, pos_z: float) -> Vector3:
	return Vector3(pos_x / UNITS_PER_M, 0.0, -pos_z / UNITS_PER_M)


static func yaw_of(angle: float) -> float:
	return TAU * angle / float(ANGLE_FULL) - PI / 2.0


## Interpola entre s_{k-1} e s_k; o ângulo segue o menor arco (wrap 4095 -> 0).
func apply(prev: Dictionary, cur: Dictionary, frac: float) -> void:
	var p0: Dictionary = prev.player
	var p1: Dictionary = cur.player
	var px: float = lerpf(float(p0.pos_x), float(p1.pos_x), frac)
	var pz: float = lerpf(float(p0.pos_z), float(p1.pos_z), frac)
	var a0: int = p0.angle
	var da: int = ((int(p1.angle) - a0 + 2048) & 4095) - 2048
	position = to_godot(px, pz)
	rotation = Vector3(0.0, yaw_of(a0 + da * frac), 0.0)
