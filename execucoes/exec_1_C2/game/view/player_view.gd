class_name PlayerView
extends CharacterBody3D
## Casca de apresentação do jogador: posição e giro escritos a partir do
## estado inteiro. Nunca chama move_and_slide()/move_and_collide().


## Interpola entre dois estados do jogador (dicionários do snapshot).
func apply(prev: Dictionary, cur: Dictionary, frac: float) -> void:
	var px: float = lerpf(float(prev.pos_x), float(cur.pos_x), frac) / 1024.0
	var pz: float = lerpf(float(prev.pos_z), float(cur.pos_z), frac) / 1024.0
	position = Vector3(px, 0.0, -pz)
	var a0: float = TAU * float(prev.angle) / 4096.0
	var a1: float = TAU * float(cur.angle) / 4096.0
	rotation.y = lerp_angle(a0, a1, frac) - PI / 2.0
