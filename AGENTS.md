# Project agent memory

This file is the project's committed home for project-intrinsic agent knowledge: build, test, release, architecture, and sharp-edge notes that should travel with the code.

- Repositório de arquivo: `execucoes/exec_{1..5}_C2/` são saídas de experimentos do TCC (projetos Godot 4.7 independentes em `game/`). Trate código, `GDD.md`, `plano_iteracao.md` e `relatorio_provas.json` como artefatos congelados; mudanças de infraestrutura vão em `run.sh`, `export.sh` e `scripts/common.sh`.
- Os scripts usam `class_name` global: num checkout limpo (sem `game/.godot/`) importe antes de rodar (`./run.sh N --import` ou `godot --headless --path <game> --import`), senão falham com "Identifier ... not declared".
- Gates de cada execução: `./run.sh N --gates` (exit 0 = todos passam; as execuções 3–5 levam vários minutos).
- Exportar exige export templates da mesma versão do Godot (`./export.sh --install-templates`); `--export-pack Linux <x.pck>` valida o preset sem templates.
- `.avi` brutos ficaram fora do repositório de propósito (os `.mp4` são equivalentes); assets do perfil `daggerfall` nunca podem entrar.

## Maintaining this file

Keep this file for knowledge useful to almost every future agent session in this project.
Do not repeat what the codebase already shows; point to the authoritative file or command instead.
Prefer rewriting or pruning existing entries over appending new ones.
When updating this file, preserve this bar for all agents and keep entries concise.
