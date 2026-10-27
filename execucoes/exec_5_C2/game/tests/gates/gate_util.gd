class_name GateUtil
extends RefCounted
## Utilitários comuns dos gates: resultado, repetição de input e invariante M1-A4.


static func res(id: String, ok: bool, detail: String = "") -> Dictionary:
	return {"id": id, "pass": ok, "detail": detail}


static func repeat(n: int, move: int, strafe: int, turn: int, use: bool = false) -> Array:
	var out: Array = []
	for _k in range(n):
		out.append(IntInput.make(move, strafe, turn, use))
	return out


static func player_collides(world: WorldSim) -> bool:
	return world.player.box_hits(world.dungeon.grid)


## Executa as entradas; devolve o primeiro tick em que a caixa do jogador intersecta célula sólida (-1 = nunca).
static func run_checked(world: WorldSim, inputs: Array) -> int:
	for i: IntInput in inputs:
		world.step(i)
		if player_collides(world):
			return world.tick
	return -1


static func run(world: WorldSim, inputs: Array) -> void:
	for i: IntInput in inputs:
		world.step(i)


static func print_results(results: Array) -> int:
	var fails: int = 0
	for r: Dictionary in results:
		print("%s %s %s" % ["PASS" if r["pass"] else "FAIL", r["id"], r["detail"]])
		if not r["pass"]:
			fails += 1
	print("[gates] %d/%d PASS" % [results.size() - fails, results.size()])
	return fails


## Trilha que anda, gira e tenta abrir portas (R3 e M5 com masmorras geradas).
static func walker_inputs(n: int) -> Array:
	var rng := RngPcg32.create(11, 77)
	var out: Array = []
	for k in range(n):
		var t: int = rng.bounded(97) - 48 if k % 40 < 8 else 0
		out.append(IntInput.make(1, rng.bounded(3) - 1, t, k % 15 == 0))
	return out
