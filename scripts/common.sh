# shellcheck shell=bash
# Funções compartilhadas por run.sh e export.sh. Não execute diretamente.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EXEC_DIR="$ROOT/execucoes"
EXECS=(1 2 3 4 5)

if [ -t 1 ]; then
	C_RESET=$'\e[0m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'
	C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_CYAN=$'\e[36m'
else
	C_RESET=''; C_BOLD=''; C_DIM=''; C_RED=''; C_GREEN=''; C_YELLOW=''; C_CYAN=''
fi

info() { printf '%s==>%s %s\n' "$C_CYAN" "$C_RESET" "$*"; }
ok()   { printf '%s ok%s %s\n' "$C_GREEN" "$C_RESET" "$*"; }
warn() { printf '%s !!%s %s\n' "$C_YELLOW" "$C_RESET" "$*" >&2; }
die()  { printf '%serro:%s %s\n' "$C_RED" "$C_RESET" "$*" >&2; exit 1; }

# Resumo de uma linha por execução (usado no menu).
exec_summary() {
	case "$1" in
		1) echo "M1-M6 completos · 43 gates · 3 iterações" ;;
		2) echo "M1-M6 completos · 60 gates · 3 iterações" ;;
		3) echo "M1-M6 completos · 83 gates · 6 iterações" ;;
		4) echo "M1-M6 completos · 75 gates · 5 iterações" ;;
		5) echo "M1-M6 completos · 89 gates · 5 iterações" ;;
	esac
}

# Localiza o binário do Godot 4: $GODOT, depois godot, godot4.
find_godot() {
	local cand
	for cand in "${GODOT:-}" godot godot4; do
		[ -n "$cand" ] || continue
		if command -v "$cand" >/dev/null 2>&1; then
			GODOT="$(command -v "$cand")"
			break
		fi
		GODOT=''
	done
	if [ -z "${GODOT:-}" ]; then
		die "Godot 4 não encontrado no PATH.
  Instale o Godot 4.7+ (https://godotengine.org/download/linux) e garanta que
  'godot' esteja no PATH, ou aponte para o binário:  GODOT=/caminho/godot $0 ..."
	fi
	GODOT_VERSION="$("$GODOT" --version 2>/dev/null | head -n1)"
	case "$GODOT_VERSION" in
		4.*) ;;
		*) die "Godot 4.x requerido; '$GODOT' informou versão '${GODOT_VERSION:-desconhecida}'." ;;
	esac
}

# Valida o número da execução e define GAME_DIR.
resolve_exec() {
	local n="$1"
	case "$n" in
		[1-5]) ;;
		*) die "execução inválida: '$n' (use 1 a 5)" ;;
	esac
	GAME_DIR="$EXEC_DIR/exec_${n}_C2/game"
	[ -f "$GAME_DIR/project.godot" ] || die "projeto não encontrado: $GAME_DIR/project.godot"
}

# Num checkout limpo não existe game/.godot/, e os scripts com class_name
# global falham ao rodar. Importar uma vez gera o cache.
ensure_imported() {
	if [ ! -d "$GAME_DIR/.godot" ] || [ "${FORCE_IMPORT:-0}" = 1 ]; then
		info "Importando o projeto (primeira execução, gera game/.godot/)..."
		"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true
		[ -d "$GAME_DIR/.godot" ] || die "a importação falhou; rode manualmente: $GODOT --headless --path '$GAME_DIR' --import"
	fi
}

# Menu interativo; imprime o número escolhido em stdout.
choose_exec() {
	local n
	{
		printf '\n%sMasmorra de Ferro%s · escolha uma execução (condição C2)\n\n' "$C_BOLD" "$C_RESET"
		for n in "${EXECS[@]}"; do
			printf '  %s[%s]%s exec_%s_C2  %s%s%s\n' "$C_BOLD" "$n" "$C_RESET" "$n" "$C_DIM" "$(exec_summary "$n")" "$C_RESET"
		done
		printf '\n'
	} >&2
	while :; do
		read -r -p "Execução [1-5, q para sair]: " n </dev/tty || exit 1
		case "$n" in
			[1-5]) echo "$n"; return ;;
			q|Q) exit 0 ;;
			*) warn "opção inválida: '$n'" ;;
		esac
	done
}
