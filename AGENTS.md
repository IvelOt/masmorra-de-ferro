# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Repositório de arquivo: `execucoes/exec_{1..5}_C2/` são saídas de experimentos do TCC (projetos Godot 4.7 independentes em `game/`). Trate código, `GDD.md`, `plano_iteracao.md` e `relatorio_provas.json` como artefatos congelados; mudanças de infraestrutura vão em `run.sh`, `export.sh` e `scripts/common.sh`.
- Os scripts usam `class_name` global: num checkout limpo (sem `game/.godot/`) importe antes de rodar (`./run.sh N --import` ou `godot --headless --path <game> --import`), senão falham com "Identifier ... not declared".
- Execuções novas: `./iterate.sh new <nome>` copia `template/` (semente byte a byte igual à da coleta, mais o esqueleto `game/tests/run_gates.gd` e `export_presets.cfg`) para `execucoes/<nome>/`, um repo git próprio e ignorado aqui. A fase seguinte é deduzida das mensagens de commit fixas de cada fase; não as renomeie. Os prompts em `experiment/prompts/` são o texto exato do TCC: altere-os só sabendo que isso muda o estímulo experimental. `--run` chama um agente de verdade (`HOH_AGENT_CMD`); para testar o script, aponte `HOH_AGENT_CMD` para um agente falso e `RUNS_DIR` para um diretório temporário.
- Gates de cada execução: `./run.sh N --gates` (exit 0 = todos passam; as execuções 3–5 levam vários minutos).
- Exportar exige export templates da mesma versão do Godot (`./export.sh --install-templates`); `--export-pack Linux <x.pck>` valida o preset sem templates.
- `.avi` brutos ficaram fora do repositório de propósito (os `.mp4` são equivalentes); assets do perfil `daggerfall` nunca podem entrar.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
