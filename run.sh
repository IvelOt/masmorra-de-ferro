#!/usr/bin/env bash
# Roda uma execução da Masmorra de Ferro no Godot 4.
#
# Uso:
#   ./run.sh                     menu interativo
#   ./run.sh <1-5>               joga a execução escolhida (cena res://view/main.tscn)
#   ./run.sh <1-5> --editor      abre o projeto no editor do Godot
#   ./run.sh <1-5> --gates       roda a suíte de gates headless (tests/run_gates.gd)
#   ./run.sh <1-5> --import      só (re)importa o projeto, regenerando game/.godot/
#   ./run.sh <1-5> -- <args>     repassa argumentos ao jogo (ex.: -- --seed=7)
#   ./run.sh --list              lista as execuções
#
# Variáveis: GODOT=/caminho/godot escolhe o binário; FORCE_IMPORT=1 força reimportar.
set -euo pipefail

# shellcheck source=scripts/common.sh
. "$(dirname "$0")/scripts/common.sh"

usage() { sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; }

n=''
mode=play
game_args=()
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		--list)
			for i in "${EXECS[@]}"; do printf 'exec_%s_C2  %s\n' "$i" "$(exec_summary "$i")"; done
			exit 0 ;;
		--editor|-e) mode=editor ;;
		--gates|--test) mode=gates ;;
		--import) mode=import ;;
		--) shift; game_args=("$@"); break ;;
		[1-5]) n="$1" ;;
		*) usage >&2; die "argumento desconhecido: '$1'" ;;
	esac
	shift
done

[ -n "$n" ] || n="$(choose_exec)"
resolve_exec "$n"
find_godot
info "exec_${n}_C2 · $GODOT_VERSION"

case "$mode" in
	import)
		FORCE_IMPORT=1 ensure_imported
		ok "projeto importado"
		;;
	editor)
		exec "$GODOT" -e --path "$GAME_DIR"
		;;
	gates)
		ensure_imported
		info "Rodando gates headless (pode levar alguns minutos)..."
		exec "$GODOT" --headless --path "$GAME_DIR" -s res://tests/run_gates.gd
		;;
	play)
		if [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
			warn "nenhum DISPLAY/WAYLAND_DISPLAY detectado; a janela pode não abrir (use --gates para modo headless)."
		fi
		ensure_imported
		info "Sem tecla no início, o jogo entra em modo demonstração; aperte qualquer tecla para jogar."
		exec "$GODOT" --path "$GAME_DIR" res://view/main.tscn ${game_args[@]+-- "${game_args[@]}"}
		;;
esac
