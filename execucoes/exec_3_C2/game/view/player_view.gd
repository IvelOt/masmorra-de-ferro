class_name PlayerView
extends CharacterBody3D
## Casca de apresentação: a posição vem do estado inteiro; sem move_and_slide.


func apply_state(p: Dictionary) -> void:
	position = Vector3(float(p["pos_x"]) / 1024.0, 0.0, -float(p["pos_z"]) / 1024.0)
	rotation.y = TAU * float(p["angle"]) / 4096.0 - PI / 2.0
