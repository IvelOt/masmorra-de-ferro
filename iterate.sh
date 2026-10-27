#!/usr/bin/env bash
# Cria e conduz execuções novas do experimento HoH (condição C2) a partir de template/.
#
# Uso:
#   ./iterate.sh                         menu interativo
#   ./iterate.sh new <nome>              cria execucoes/<nome>/ a partir do template limpo (repo git próprio)
#   ./iterate.sh list                    lista as execuções e a próxima fase de cada uma
#   ./iterate.sh status <nome>           rodadas, fases concluídas e próxima fase
#   ./iterate.sh next <nome> [--run]     executa (ou mostra) a próxima fase do ciclo
#   ./iterate.sh plan|dev|test <nome> [--iter N] [--run]
#                                        fase Planejador / Desenvolvedor / Testador: sem --run
#                                        mostra o prompt pronto; com --run chama o agente
#   ./iterate.sh capture <nome> [--iter N]  grava vídeo e quadros em media/iter_N/ para o Testador
#   ./iterate.sh loop <nome> [--max N]   roda o ciclo completo com o agente até o aceite ou N rodadas (padrão 6)
#   ./iterate.sh prompt <nome> <plan|dev|test> [--iter N]
#                                        imprime só o prompt (para colar ou redirecionar)
#   ./iterate.sh gates <nome>            roda game/tests/run_gates.gd headless
#   ./iterate.sh check <nome>            sintaxe GDScript, lint do núcleo e guarda de assets
#   ./iterate.sh validate <nome>         valida relatorio_provas.json contra o esquema
#   ./iterate.sh play|editor <nome> [-- <args>]  joga ou abre no editor
#
# Fases de uma rodada N, cada uma fechada por um commit no repositório da execução:
#   plan    -> 'docs: plano iteracao N'          (Planejador escreve plano_iteracao.md)
#   dev     -> 'feat: implementacao iteracao N'  (Desenvolvedor implementa game/)
#   capture -> 'chore: midia capturada para auditoria da iteracao N'
#   test    -> 'docs: provas iteracao N'         (Testador escreve relatorio_provas.json)
# A execução termina quando relatorio_provas.json traz "all_milestones_passed": true.
#
# Variáveis:
#   GODOT=/caminho/godot                 binário do Godot 4.7+
#   RUNS_DIR=<dir>                       onde ficam as execuções (padrão: ./execucoes)
#   HOH_AGENT_CMD='<comando>'            agente usado com --run; recebe o prompt na entrada padrão,
#                                        roda dentro da execução e vê HOH_ROLE e HOH_MODEL
#                                        (padrão: claude -p --model "$HOH_MODEL" --dangerously-skip-permissions)
#   HOH_MODEL_PLANNER / HOH_MODEL_DEVELOPER / HOH_MODEL_TESTER   (padrão: opus / opus / sonnet)
#   CAPTURE_SECONDS=6                    duração da gravação de cada rodada
set -euo pipefail

# shellcheck source=scripts/common.sh
. "$(dirname "$0")/scripts/common.sh"

usage() { sed -n '2,36p' "$0" | sed 's/^# \{0,1\}//'; }

TEMPLATE_DIR="$ROOT/template"
PROMPTS_DIR="$ROOT/experiment/prompts"
VALIDATOR="$ROOT/experiment/tools/validate_report.py"
RUNS_DIR="${RUNS_DIR:-$EXEC_DIR}"
DEFAULT_AGENT_CMD='claude -p --model "$HOH_MODEL" --dangerously-skip-permissions'
CAPTURE_SECONDS="${CAPTURE_SECONDS:-6}"
MAIN_SCENE="res://view/main.tscn"

# ---------------------------------------------------------------- execuções

# Define RUN_NAME, RUN_DIR e GAME_DIR a partir de um nome (ou caminho).
resolve_run() {
	local arg="${1:-}"
	[ -n "$arg" ] || die "informe o nome da execução (veja ./iterate.sh list)"
	case "$arg" in
		*/*) RUN_DIR="$(cd "$arg" 2>/dev/null && pwd)" || die "diretório não encontrado: $arg" ;;
		*) RUN_DIR="$RUNS_DIR/$arg" ;;
	esac
	RUN_NAME="$(basename "$RUN_DIR")"
	GAME_DIR="$RUN_DIR/game"
	[ -f "$GAME_DIR/project.godot" ] || die "execução não encontrada: $RUN_DIR (crie com ./iterate.sh new $RUN_NAME)"
}

# As cinco execuções do TCC são artefatos congelados: só leitura.
is_archived() { [ "$RUN_DIR" = "$EXEC_DIR/$RUN_NAME" ] && [[ "$RUN_NAME" =~ ^exec_[1-5]_C2$ ]]; }

require_writable() {
	! is_archived || die "$RUN_NAME é uma execução arquivada do TCC (somente leitura); crie uma nova com ./iterate.sh new <nome>"
	git -C "$RUN_DIR" rev-parse --git-dir >/dev/null 2>&1 || die "$RUN_DIR não é um repositório git (as fases são marcadas por commits)"
}

phase_commit() {
	case "$1" in
		plan) echo "docs: plano iteracao $2" ;;
		dev) echo "feat: implementacao iteracao $2" ;;
		capture) echo "chore: midia capturada para auditoria da iteracao $2" ;;
		test) echo "docs: provas iteracao $2" ;;
	esac
}

phase_label() {
	case "$1" in
		plan) echo "Planejador" ;;
		dev) echo "Desenvolvedor" ;;
		capture) echo "Captura de mídia" ;;
		test) echo "Testador / Auditor Multimodal" ;;
		done) echo "concluída" ;;
	esac
}

# Assuntos de todos os commits da execução (vazio se não for repositório git).
run_log() { git -C "$RUN_DIR" log --format=%s 2>/dev/null || true; }

has_phase() { run_log | grep -Fxq "$(phase_commit "$1" "$2")"; }

milestones_passed() {
	[ -f "$RUN_DIR/relatorio_provas.json" ] || return 1
	python3 - "$RUN_DIR/relatorio_provas.json" <<-'EOF' 2>/dev/null
		import json, sys
		d = json.load(open(sys.argv[1], encoding="utf-8"))
		sys.exit(0 if isinstance(d, dict) and d.get("all_milestones_passed") is True else 1)
	EOF
}

# Imprime "<fase> <rodada>": a primeira fase sem commit, em ordem de rodada.
next_phase() {
	local n=1 p
	while :; do
		for p in plan dev capture test; do
			has_phase "$p" "$n" || { echo "$p $n"; return; }
		done
		# relatorio_provas.json reflete só a última rodada auditada.
		if ! has_phase plan $((n + 1)) && milestones_passed; then echo "done $n"; return; fi
		n=$((n + 1))
	done
}

ensure_git_identity() {
	if [ -z "$(git -C "$RUN_DIR" config user.email || true)" ]; then
		git -C "$RUN_DIR" config user.name "HoH Experiment"
		git -C "$RUN_DIR" config user.email "hoh@localhost"
	fi
}

# Godot precisa reimportar a cada fase: os agentes criam class_name novos.
import_project() {
	find_godot
	info "Importando o projeto (atualiza game/.godot/)..."
	"$GODOT" --headless --path "$GAME_DIR" --import >/dev/null 2>&1 || true
	[ -d "$GAME_DIR/.godot" ] || die "a importação falhou; rode manualmente: $GODOT --headless --path '$GAME_DIR' --import"
}

# ---------------------------------------------------------------- comandos

cmd_new() {
	local name="${1:-}"
	[ -n "$name" ] || die "uso: ./iterate.sh new <nome>"
	[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "nome inválido: '$name' (use letras, números, '.', '_' e '-')"
	[[ ! "$name" =~ ^exec_[1-5]_C2$ ]] || die "'$name' é reservado às execuções arquivadas do TCC"
	RUN_DIR="$RUNS_DIR/$name"
	[ ! -e "$RUN_DIR" ] || die "já existe: $RUN_DIR"
	mkdir -p "$RUNS_DIR"
	cp -r "$TEMPLATE_DIR/." "$RUN_DIR/"
	git -C "$RUN_DIR" init -q -b main
	ensure_git_identity
	git -C "$RUN_DIR" add -A
	git -C "$RUN_DIR" commit -q -m "chore: initial clean seed for HoH experiment execution $name"
	ok "execução criada em $RUN_DIR"
	printf '   GDD.md, game/project.godot, game/assets/free/ (%s arquivos) e tools/; nenhum código de jogo.\n' \
		"$(find "$RUN_DIR/game/assets/free" -name '*.png' | wc -l)"
	info "Próximo passo: ./iterate.sh next $name   (mostra o prompt do Planejador da rodada 1)"
}

cmd_list() {
	local d phase p n
	[ -d "$RUNS_DIR" ] || die "diretório de execuções não existe: $RUNS_DIR"
	for d in "$RUNS_DIR"/*/; do
		[ -f "$d/game/project.godot" ] || continue
		RUN_DIR="${d%/}"; RUN_NAME="$(basename "$RUN_DIR")"
		if is_archived; then
			phase="arquivada (TCC)"
		elif git -C "$RUN_DIR" rev-parse --git-dir >/dev/null 2>&1; then
			read -r p n <<<"$(next_phase)"
			if [ "$p" = done ]; then phase="concluída na rodada $n"; else phase="rodada $n · próxima fase: $p"; fi
		else
			phase="sem git"
		fi
		printf '%-24s %s%s%s\n' "$RUN_NAME" "$C_DIM" "$phase" "$C_RESET"
	done
}

cmd_status() {
	resolve_run "$1"
	local p n i ph mark
	info "$RUN_NAME · $RUN_DIR"
	if is_archived; then
		ok "execução arquivada do TCC: $(exec_summary "${RUN_NAME:5:1}")"
		return
	fi
	read -r p n <<<"$(next_phase)"
	for ((i = 1; i <= n; i++)); do
		printf '  rodada %s:' "$i"
		for ph in plan dev capture test; do
			if has_phase "$ph" "$i"; then mark="${C_GREEN}✓${C_RESET}"; else mark="${C_DIM}·${C_RESET}"; fi
			printf '  %s %s' "$mark" "$ph"
		done
		printf '\n'
	done
	if [ -f "$RUN_DIR/relatorio_provas.json" ]; then
		python3 "$VALIDATOR" "$RUN_DIR/relatorio_provas.json" || true
	fi
	if [ "$p" = done ]; then
		ok "todos os marcos aceitos pelo Testador na rodada $n"
	else
		info "próxima fase: $p (rodada $n, $(phase_label "$p")) -> ./iterate.sh next $RUN_NAME"
	fi
}

render_prompt() {
	local role="$1" iter="$2" file text
	case "$role" in
		plan) file=planner ;;
		dev) file=developer ;;
		test) file=tester ;;
		*) die "fase sem prompt: '$role' (use plan, dev ou test)" ;;
	esac
	text="$(<"$PROMPTS_DIR/$file.md")"
	text="${text//'{{EXEC}}'/$RUN_NAME}"
	text="${text//'{{ITER}}'/$iter}"
	printf '%s\n' "$text"
}

role_model() {
	case "$1" in
		plan) echo "${HOH_MODEL_PLANNER:-opus}" ;;
		dev) echo "${HOH_MODEL_DEVELOPER:-opus}" ;;
		test) echo "${HOH_MODEL_TESTER:-sonnet}" ;;
	esac
}

# Rodada padrão de uma fase: a da próxima fase pendente.
default_iter() {
	local p n
	read -r p n <<<"$(next_phase)"
	if [ "$p" = done ]; then echo $((n + 1)); else echo "$n"; fi
}

cmd_role() {
	local role="$1" iter="$2" run="$3" prev model expected agent_cmd prompt changed
	expected="$(phase_commit "$role" "$iter")"
	model="$(role_model "$role")"
	case "$role" in
		dev) prev=plan ;;
		test) prev=capture ;;
		*) prev='' ;;
	esac
	[ -z "$prev" ] || has_phase "$prev" "$iter" || warn "a fase '$prev' da rodada $iter ainda não tem commit ('$(phase_commit "$prev" "$iter")')"
	prompt="$(render_prompt "$role" "$iter")"

	if [ "$run" = 0 ]; then
		printf '\n%s%s · rodada %s%s  (modelo sugerido: %s)\n' "$C_BOLD" "$(phase_label "$role")" "$iter" "$C_RESET" "$model"
		printf '%s────────────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
		printf '%s\n' "$prompt"
		printf '%s────────────────────────────────────────────────────────────%s\n' "$C_DIM" "$C_RESET"
		printf 'Rode o agente dentro de %s com o prompt acima, por exemplo:\n' "$RUN_DIR"
		printf '  cd %q && claude --model %s   (e cole o prompt)\n' "$RUN_DIR" "$model"
		printf '  ./iterate.sh %s %s --iter %s --run   (chama o agente sozinho)\n' "$role" "$RUN_NAME" "$iter"
		printf 'A fase termina com o commit: %s\n' "'$expected'"
		return
	fi

	if has_phase "$role" "$iter"; then
		ok "commit '$expected' já existe; fase pulada"
		return
	fi
	agent_cmd="${HOH_AGENT_CMD:-$DEFAULT_AGENT_CMD}"
	if [ -z "${HOH_AGENT_CMD:-}" ] && ! command -v claude >/dev/null 2>&1; then
		die "Claude Code ('claude') não está no PATH; instale-o ou defina HOH_AGENT_CMD"
	fi
	[ -z "$(git -C "$RUN_DIR" status --porcelain)" ] || warn "a árvore de trabalho de $RUN_NAME tem mudanças não commitadas"
	info "$(phase_label "$role") · rodada $iter · modelo $model"
	info "agente: $agent_cmd"
	(cd "$RUN_DIR" && HOH_ROLE="$role" HOH_ITER="$iter" HOH_MODEL="$model" bash -c "$agent_cmd" <<<"$prompt") ||
		warn "o agente terminou com erro"
	has_phase "$role" "$iter" || die "o agente terminou sem o commit esperado '$expected'; rode a fase de novo"
	ok "commit '$expected' registrado"
	[ -z "$(git -C "$RUN_DIR" status --porcelain)" ] || warn "o agente deixou mudanças não commitadas em $RUN_NAME"
	if [ "$role" = test ]; then
		changed="$(git -C "$RUN_DIR" log -1 --format= --name-only --grep="^${expected}\$" | grep -vx 'relatorio_provas.json' || true)"
		[ -z "$changed" ] || warn "o commit do Testador alterou arquivos além de relatorio_provas.json: $(echo "$changed" | tr '\n' ' ')"
		python3 "$VALIDATOR" "$RUN_DIR/relatorio_provas.json" || warn "relatorio_provas.json fora do esquema (experiment/schemas/)"
	fi
}

cmd_capture() {
	local iter="$1" media chk_out chk_rc=0 raw frame1 frame2 mp4 captured=false display=() frames=$((CAPTURE_SECONDS * 30))
	media="$RUN_DIR/media/iter_$iter"
	mkdir -p "$media"
	import_project
	info "Checagem de sintaxe (godot --check-only)..."
	chk_out="$(timeout 120 "$GODOT" --headless --path "$GAME_DIR" --check-only --quit 2>&1)" || chk_rc=$?

	raw="$media/capture.avi"
	frame1="$media/frame_1.png"; frame2="$media/frame_2.png"; mp4="$media/gameplay_iter_$iter.mp4"
	if [ ! -f "$GAME_DIR/view/main.tscn" ]; then
		warn "$MAIN_SCENE ainda não existe; nada para gravar nesta rodada"
	else
		if command -v xvfb-run >/dev/null 2>&1; then
			display=(xvfb-run -a)
		elif [ -z "${DISPLAY:-}" ] && [ -z "${WAYLAND_DISPLAY:-}" ]; then
			warn "sem DISPLAY e sem xvfb-run: a gravação deve falhar (instale xvfb)"
		fi
		info "Gravando ${CAPTURE_SECONDS}s da cena principal (--write-movie, 30 fps)..."
		if command -v ffmpeg >/dev/null 2>&1; then
			rm -f "$raw"
			timeout 120 ${display[@]+"${display[@]}"} "$GODOT" --path "$GAME_DIR" "$MAIN_SCENE" \
				--write-movie "$raw" --fixed-fps 30 --quit-after "$frames" >/dev/null 2>&1 || true
			if [ -s "$raw" ]; then
				ffmpeg -loglevel error -y -i "$raw" -c:v libx264 -pix_fmt yuv420p -r 30 "$mp4" || warn "falha ao gerar $mp4"
				ffmpeg -loglevel error -y -ss 00:00:01 -i "$raw" -vframes 1 "$frame1" || true
				ffmpeg -loglevel error -y -ss 00:00:03 -i "$raw" -vframes 1 "$frame2" || true
				rm -f "$raw"
			fi
		else
			# Sem ffmpeg: grava PNG por quadro e guarda os quadros de 1 s e 3 s (sem vídeo).
			warn "ffmpeg ausente: só os quadros serão salvos, sem vídeo"
			local tmp; tmp="$(mktemp -d)"
			timeout 120 ${display[@]+"${display[@]}"} "$GODOT" --path "$GAME_DIR" "$MAIN_SCENE" \
				--write-movie "$tmp/f.png" --fixed-fps 30 --quit-after "$frames" >/dev/null 2>&1 || true
			[ ! -f "$tmp/f00000030.png" ] || cp "$tmp/f00000030.png" "$frame1"
			[ ! -f "$tmp/f00000090.png" ] || cp "$tmp/f00000090.png" "$frame2"
			rm -rf "$tmp"
		fi
		[ -f "$frame1" ] && captured=true
		if [ "$captured" = true ]; then ok "quadros salvos em media/iter_$iter/"; else warn "a gravação não produziu quadros"; fi
	fi

	python3 - "$media/resumo_midia.json" "$iter" "$chk_rc" "$captured" "$chk_out" <<-'EOF'
		import json, sys
		from datetime import datetime
		from pathlib import Path
		out, it, rc, cap, chk = sys.argv[1:]
		media = Path(out).parent
		frames = [f"media/{media.name}/{f}" for f in ("frame_1.png", "frame_2.png") if (media / f).exists()]
		json.dump({
		    "iteration": int(it),
		    "syntax_check_ok": rc == "0",
		    "syntax_output": chk,
		    "frames_captured": cap == "true",
		    "frame_files": frames,
		    "timestamp": datetime.now().isoformat(),
		}, open(out, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
	EOF
	[ "$chk_rc" = 0 ] || warn "godot --check-only terminou com código $chk_rc (veja resumo_midia.json)"

	ensure_git_identity
	git -C "$RUN_DIR" add "media/iter_$iter/"
	git -C "$RUN_DIR" commit -q --allow-empty -m "$(phase_commit capture "$iter")"
	ok "commit '$(phase_commit capture "$iter")' registrado"
}

cmd_gates() {
	import_project
	info "Rodando gates headless: godot --headless --path game -s res://tests/run_gates.gd"
	[ -f "$GAME_DIR/tests/run_gates.gd" ] || die "game/tests/run_gates.gd não existe"
	"$GODOT" --headless --path "$GAME_DIR" -s res://tests/run_gates.gd
}

cmd_check() {
	local f out rc=0 fails=0 n=0 png name
	import_project
	info "Sintaxe GDScript (--check-only por script)..."
	while IFS= read -r f; do
		n=$((n + 1))
		if ! out="$(timeout 60 "$GODOT" --headless --path "$GAME_DIR" --check-only -s "res://${f#"$GAME_DIR"/}" 2>&1)" ||
			grep -q 'SCRIPT ERROR\|Parse Error' <<<"$out"; then
			fails=$((fails + 1))
			warn "${f#"$RUN_DIR"/}"
			grep -E 'ERROR|Error' <<<"$out" | head -n 5 >&2 || true
		fi
	done < <(find "$GAME_DIR" -name '*.gd' -not -path '*/.godot/*' | sort)
	if [ "$fails" = 0 ]; then ok "$n script(s) sem erro de sintaxe"; else rc=1; warn "$fails de $n script(s) com erro"; fi

	if [ -f "$RUN_DIR/tools/lint_sim.py" ]; then
		info "Lint do núcleo determinístico (tools/lint_sim.py)..."
		python3 "$RUN_DIR/tools/lint_sim.py" || rc=1
	fi

	info "Guarda de assets (GDD §7.4.4): todo PNG de assets/free/ precisa constar em CREDITS.md..."
	fails=0
	for png in "$GAME_DIR"/assets/free/*.png; do
		[ -e "$png" ] || continue
		name="$(basename "$png")"
		grep -Fq "\`$name\`" "$GAME_DIR/assets/CREDITS.md" || { warn "sem entrada em CREDITS.md: $name"; fails=1; }
	done
	if [ -n "$(git -C "$RUN_DIR" ls-files game/assets/daggerfall 2>/dev/null)" ]; then
		warn "game/assets/daggerfall/ está versionado: o perfil daggerfall nunca pode entrar no repositório"
		fails=1
	fi
	if [ "$fails" = 0 ]; then ok "assets conferidos"; else rc=1; fi
	return "$rc"
}

cmd_validate() {
	[ -f "$RUN_DIR/relatorio_provas.json" ] || die "$RUN_NAME ainda não tem relatorio_provas.json"
	python3 "$VALIDATOR" "$RUN_DIR/relatorio_provas.json"
}

# Executa uma fase pendente; devolve 1 quando a execução já terminou.
step() {
	local run="$1" p n
	read -r p n <<<"$(next_phase)"
	case "$p" in
		done) ok "$RUN_NAME concluída: o Testador aceitou M1-M6 na rodada $n"; return 1 ;;
		capture) cmd_capture "$n" ;;
		*) cmd_role "$p" "$n" "$run" ;;
	esac
}

cmd_loop() {
	local max="$1" p n
	while :; do
		read -r p n <<<"$(next_phase)"
		if [ "$p" = plan ] && [ "$n" -gt "$max" ]; then
			warn "limite de $max rodada(s) atingido sem o aceite de todos os marcos"
			return 1
		fi
		step 1 || return 0
	done
}

cmd_menu() {
	local runs=() d choice action
	for d in "$RUNS_DIR"/*/; do
		[ -f "$d/game/project.godot" ] && runs+=("$(basename "$d")")
	done
	{
		printf '\n%sMasmorra de Ferro · iterações HoH%s\n\n' "$C_BOLD" "$C_RESET"
		printf '  %s[0]%s criar uma execução nova a partir do template\n' "$C_BOLD" "$C_RESET"
		for d in "${!runs[@]}"; do printf '  %s[%s]%s %s\n' "$C_BOLD" "$((d + 1))" "$C_RESET" "${runs[$d]}"; done
		printf '\n'
	} >&2
	read -r -p "Escolha [0-${#runs[@]}, q para sair]: " choice </dev/tty || exit 1
	case "$choice" in
		q|Q) exit 0 ;;
		0)
			read -r -p "Nome da execução nova (ex.: exec_custom): " d </dev/tty || exit 1
			cmd_new "$d"
			exit 0 ;;
		*)
			[[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#runs[@]}" ] || die "opção inválida: '$choice'"
			resolve_run "${runs[$((choice - 1))]}" ;;
	esac
	cmd_status "$RUN_NAME"
	printf '\nAções: next · run (próxima fase com o agente) · capture · gates · check · validate · play · q\n' >&2
	read -r -p "Ação: " action </dev/tty || exit 1
	case "$action" in
		next) require_writable; step 0 || true ;;
		run) require_writable; step 1 || true ;;
		capture) require_writable; cmd_capture "$(default_iter)" ;;
		gates) cmd_gates ;;
		check) cmd_check ;;
		validate) cmd_validate ;;
		play) import_project; exec "$GODOT" --path "$GAME_DIR" "$MAIN_SCENE" ;;
		q|Q|'') exit 0 ;;
		*) die "ação desconhecida: '$action'" ;;
	esac
}

# ---------------------------------------------------------------- argumentos

[ $# -gt 0 ] || { cmd_menu; exit 0; }
cmd="$1"; shift
case "$cmd" in
	-h|--help|help) usage; exit 0 ;;
	new) cmd_new "${1:-}"; exit 0 ;;
	list|ls) cmd_list; exit 0 ;;
	status) cmd_status "${1:-}"; exit 0 ;;
esac

target="${1:-}"; [ $# -eq 0 ] || shift
iter='' run="${HOH_RUN:-0}" max=6 role='' game_args=()
if [ "$cmd" = prompt ]; then role="${1:-}"; [ $# -eq 0 ] || shift; fi
while [ $# -gt 0 ]; do
	case "$1" in
		--iter) [ $# -ge 2 ] || die "--iter exige um número"; iter="$2"; shift ;;
		--run) run=1 ;;
		--max) [ $# -ge 2 ] || die "--max exige um número"; max="$2"; shift ;;
		--) shift; game_args=("$@"); break ;;
		*) usage >&2; die "argumento desconhecido: '$1'" ;;
	esac
	shift
done
[ -z "$iter" ] || [[ "$iter" =~ ^[1-9][0-9]*$ ]] || die "--iter inválido: '$iter'"
[[ "$max" =~ ^[1-9][0-9]*$ ]] || die "--max inválido: '$max'"
resolve_run "$target"

case "$cmd" in
	prompt)
		[ -n "$role" ] || die "uso: ./iterate.sh prompt <nome> <plan|dev|test> [--iter N]"
		render_prompt "$role" "${iter:-$(default_iter)}" ;;
	plan|dev|test)
		[ "$run" = 0 ] || require_writable
		if [ "$run" = 1 ] && [ -z "$iter" ] && [ "$(next_phase | cut -d' ' -f1)" = done ]; then
			die "$RUN_NAME já foi concluída; para abrir outra rodada mesmo assim, passe --iter N"
		fi
		cmd_role "$cmd" "${iter:-$(default_iter)}" "$run" ;;
	capture)
		require_writable
		cmd_capture "${iter:-$(default_iter)}" ;;
	next)
		require_writable
		step "$run" || true ;;
	loop)
		require_writable
		cmd_loop "$max" ;;
	gates) cmd_gates ;;
	check) cmd_check ;;
	validate) cmd_validate ;;
	play)
		import_project
		exec "$GODOT" --path "$GAME_DIR" "$MAIN_SCENE" ${game_args[@]+-- "${game_args[@]}"} ;;
	editor)
		import_project
		exec "$GODOT" -e --path "$GAME_DIR" ;;
	*) usage >&2; die "comando desconhecido: '$cmd'" ;;
esac
