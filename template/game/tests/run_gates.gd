extends SceneTree
## Suíte de gates headless (Acceptance + Preservation Gates, GDD §4 e §6.3).
## Uso: godot --headless --path game -s res://tests/run_gates.gd
##
## Esqueleto do repositório-semente: ainda não há gates. O Desenvolvedor
## registra cada asserção dos marcos em _gates() e o Testador roda este
## arquivo a cada iteração. Os gates dos marcos já aceitos continuam aqui
## (Preservation Gate) e são reexecutados em toda rodada.
##
## Contrato de saída (lido pelo iterate.sh e pelo Testador):
##   uma linha "PASS <id>" ou "FAIL <id>: <motivo>" por gate, depois
##   "[gates] <n> PASS, <m> FAIL"; código 0 só se houver ao menos um gate
##   e todos passarem.


## Cada gate é [id, Callable]; o Callable devolve "" quando passa ou a
## descrição da falha. Exemplo:
##   ["M1-A3", func() -> String: return "" if angle_back_to_start() else "ângulo não voltou"],
func _gates() -> Array:
	return []


func _initialize() -> void:
	var gates: Array = _gates()
	var failed: int = 0
	for g: Array in gates:
		var why: String = (g[1] as Callable).call()
		if why.is_empty():
			print("PASS %s" % g[0])
		else:
			failed += 1
			print("FAIL %s: %s" % [g[0], why])
	print("[gates] %d PASS, %d FAIL" % [gates.size() - failed, failed])
	if gates.is_empty():
		printerr("[gates] nenhum gate registrado ainda (esqueleto do repositório-semente)")
		quit(1)
		return
	quit(0 if failed == 0 else 1)
