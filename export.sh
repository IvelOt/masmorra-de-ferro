#!/usr/bin/env bash
# Exporta binários standalone (Linux x86_64) das execuções com o CLI do Godot 4.
#
# Uso:
#   ./export.sh <1-5>             exporta uma execução (release)
#   ./export.sh all               exporta as cinco
#   ./export.sh <1-5|all> --debug exporta em modo debug (console e asserts)
#   ./export.sh <1-5|all> --out DIR   diretório de saída (padrão: ./build)
#   ./export.sh --install-templates   baixa e instala os export templates
#                                     da versão do Godot instalada
#
# Saída: <out>/exec_N_C2/masmorra-de-ferro-execN.x86_64 (PCK embutido, um só arquivo).
# Cada game/ já traz export_presets.cfg com o preset "Linux".
# Variáveis: GODOT=/caminho/godot escolhe o binário.
set -euo pipefail

# shellcheck source=scripts/common.sh
. "$(dirname "$0")/scripts/common.sh"

usage() { sed -n '2,15p' "$0" | sed 's/^# \{0,1\}//'; }

PRESET="Linux"
target=''
build_mode=release
out_dir="$ROOT/build"
install_templates=0
while [ $# -gt 0 ]; do
	case "$1" in
		-h|--help) usage; exit 0 ;;
		--debug) build_mode=debug ;;
		--release) build_mode=release ;;
		--out) [ $# -ge 2 ] || die "--out exige um diretório"; out_dir="$2"; shift ;;
		--install-templates) install_templates=1 ;;
		all|[1-5]) target="$1" ;;
		*) usage >&2; die "argumento desconhecido: '$1'" ;;
	esac
	shift
done

find_godot

# "4.7.2.stable.arch_linux.ed1daf0bf" -> "4.7.2.stable" (nome da pasta de templates).
TEMPLATE_VERSION="$(printf '%s' "$GODOT_VERSION" | grep -oE '^[0-9]+(\.[0-9]+)+\.[a-z]+[0-9]*')" ||
	die "não foi possível extrair a versão de '$GODOT_VERSION'"
TEMPLATE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/godot/export_templates/$TEMPLATE_VERSION"

install_export_templates() {
	local release tag url tmp
	release="${TEMPLATE_VERSION%.*}"         # 4.7.2
	tag="${release}-${TEMPLATE_VERSION##*.}" # 4.7.2-stable
	url="https://github.com/godotengine/godot/releases/download/${tag}/Godot_v${tag}_export_templates.tpz"
	command -v curl >/dev/null 2>&1 || die "curl é necessário para baixar os templates"
	command -v unzip >/dev/null 2>&1 || die "unzip é necessário para extrair os templates"
	tmp="$(mktemp -d)"
	trap 'rm -rf "$tmp"' EXIT
	info "Baixando $url (arquivo grande, ~1 GB)..."
	curl -fL --progress-bar -o "$tmp/templates.tpz" "$url" || die "falha no download de $url"
	info "Extraindo para $TEMPLATE_DIR"
	unzip -q "$tmp/templates.tpz" -d "$tmp"
	mkdir -p "$TEMPLATE_DIR"
	cp -r "$tmp/templates/." "$TEMPLATE_DIR/"
	ok "templates instalados em $TEMPLATE_DIR"
}

if [ "$install_templates" = 1 ]; then
	install_export_templates
	[ -n "$target" ] || exit 0
fi

[ -n "$target" ] || { usage >&2; die "informe a execução (1-5) ou 'all'"; }

template_file="$TEMPLATE_DIR/linux_${build_mode}.x86_64"
if [ ! -f "$template_file" ]; then
	die "export template ausente: $template_file
  Instale com:  ./export.sh --install-templates
  ou pelo editor: Editor > Gerenciar Templates de Exportação > Baixar e Instalar."
fi

export_one() {
	local n="$1" dest log
	resolve_exec "$n"
	[ -f "$GAME_DIR/export_presets.cfg" ] || die "export_presets.cfg ausente em $GAME_DIR"
	ensure_imported
	mkdir -p "$out_dir/exec_${n}_C2"
	dest="$(cd "$out_dir/exec_${n}_C2" && pwd)/masmorra-de-ferro-exec${n}.x86_64"
	log="$(dirname "$dest")/export.log"
	info "exec_${n}_C2 -> $dest ($build_mode)"
	if ! "$GODOT" --headless --path "$GAME_DIR" "--export-${build_mode}" "$PRESET" "$dest" >"$log" 2>&1 || [ ! -s "$dest" ]; then
		tail -n 20 "$log" >&2
		die "exportação da exec_${n}_C2 falhou (log completo: $log)"
	fi
	chmod +x "$dest"
	ok "$(du -h "$dest" | cut -f1)  $dest"
}

if [ "$target" = all ]; then
	for n in "${EXECS[@]}"; do export_one "$n"; done
else
	export_one "$target"
fi

info "Pronto. Execute o binário diretamente, ex.: $out_dir/exec_1_C2/masmorra-de-ferro-exec1.x86_64"
