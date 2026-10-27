# Protocolo HoH (condição C2): papéis, prompts e evidência

Esta pasta guarda o que os agentes recebem em cada rodada do experimento do TCC e o formato da evidência que devolvem. O [`../iterate.sh`](../iterate.sh) usa estes arquivos; nada aqui precisa ser editado para replicar o experimento.

```
experiment/
├── prompts/
│   ├── planner.md      # Planejador
│   ├── developer.md    # Desenvolvedor
│   └── tester.md       # Testador / Auditor Multimodal
├── schemas/
│   └── relatorio_provas.schema.json   # JSON Schema da evidência do Testador
└── tools/
    └── validate_report.py             # valida um relatorio_provas.json (só biblioteca padrão)
```

## O ciclo de uma rodada

```
          GDD.md + relatorio_provas.json da rodada anterior + media/iter_{N-1}/
                                   │
                    ┌──────────────▼──────────────┐
  1. plan           │ Planejador (opus)           │ escreve plano_iteracao.md (≤ 2 marcos)
                    └──────────────┬──────────────┘   commit 'docs: plano iteracao N'
                    ┌──────────────▼──────────────┐
  2. dev            │ Desenvolvedor (opus)        │ implementa game/ (sim/, view/, tests/run_gates.gd)
                    └──────────────┬──────────────┘   commit 'feat: implementacao iteracao N'
                    ┌──────────────▼──────────────┐
  3. capture        │ iterate.sh (sem agente)     │ --check-only + 6 s de --write-movie → media/iter_N/
                    └──────────────┬──────────────┘   commit 'chore: midia capturada para auditoria da iteracao N'
                    ┌──────────────▼──────────────┐
  4. test           │ Testador multimodal (sonnet)│ olha os quadros, roda os gates, escreve relatorio_provas.json
                    └──────────────┬──────────────┘   commit 'docs: provas iteracao N'
                                   │
              all_milestones_passed = true ? ── sim ──► execução concluída
                                   │ não
                                   └──► rodada N+1 (máximo de 6 no experimento)
```

Cada fase termina com um commit de mensagem fixa no repositório git da execução. O `iterate.sh` descobre a próxima fase lendo esses commits, então uma execução pode ser interrompida e retomada a qualquer momento.

## Papéis

| Papel | Prompt | Modelo no TCC | Lê | Escreve | Não pode |
|---|---|---|---|---|---|
| **Planejador** | [`prompts/planner.md`](prompts/planner.md) | Opus 5.5 | `GDD.md`, `relatorio_provas.json` anterior, `game/assets/` | `plano_iteracao.md`: marcos da rodada (no máximo 2, respeitando `M1 → M2 → {M3, M5}`, `M3 → M4`, `{M4, M5} → M6`), especificação de código, sprites, proporção visual, áudio e testes; o *Preservation Gate* dos marcos já aceitos | escrever GDScript |
| **Desenvolvedor** | [`prompts/developer.md`](prompts/developer.md) | Opus 5.5 | `GDD.md`, `plano_iteracao.md` | código em `game/`: núcleo inteiro em `game/sim/`, apresentação em `game/view/` (cena `view/main.tscn`), gates em `game/tests/run_gates.gd` | alterar `GDD.md` ou os assets |
| **Testador / Auditor Multimodal** | [`prompts/tester.md`](prompts/tester.md) | Sonnet 5.5 | `media/iter_N/` (quadros e vídeo), `game/` | `relatorio_provas.json` | alterar o código do jogo (o `iterate.sh` avisa se o commit dele tocar outro arquivo) |

Os prompts são o texto exato que o orquestrador do TCC enviou em cada rodada, com dois marcadores trocados na hora de usar: `{{EXEC}}` (nome da execução) e `{{ITER}}` (número da rodada). O rótulo "HoH Estático" dentro deles também é do original e foi mantido para não mudar o estímulo; no texto do TCC a condição se chama C2, HoH completo. Para ver um prompt pronto:

```bash
./iterate.sh prompt exec_custom plan --iter 1
```

## Evidência do Testador: `relatorio_provas.json`

Esquema: [`schemas/relatorio_provas.schema.json`](schemas/relatorio_provas.schema.json). Campos obrigatórios (os quatro que o prompt pede):

| Campo | Tipo | Conteúdo |
|---|---|---|
| `verified` | lista de texto | o que foi verificado com sucesso: gates que passaram, comandos rodados, marcos cobertos |
| `visual_findings` | lista de texto | o que se vê nos quadros: escala e proporção de sprites, arma, portas, HUD (Vida, Vigor, bússola, textos) |
| `gap` | lista de texto | falhas reais, visuais ou mecânicas; viram entrada do Planejador na rodada seguinte |
| `all_milestones_passed` | booleano | `true` só com M1 a M6 completos e funcionais; é o único campo que o orquestrador lê, e encerra a execução |

`iteration` (inteiro) é opcional e outros campos são aceitos. Exemplo mínimo:

```json
{
  "iteration": 1,
  "verified": ["godot --headless --path game -s res://tests/run_gates.gd: exit 0, 17 PASS, 0 FAIL (M1-A1..A6, M2-A1..A7)"],
  "visual_findings": ["frame_1: corredor de pedra com perspectiva correta; espada no canto inferior direito sem distorção"],
  "gap": ["M3 a M6 não implementados", "HUD sem bússola"],
  "all_milestones_passed": false
}
```

Validação:

```bash
./iterate.sh validate exec_custom
python3 experiment/tools/validate_report.py execucoes/exec_custom/relatorio_provas.json
```

Das cinco execuções arquivadas, a `exec_3_C2` acumulou os relatórios numa lista JSON em vez de um objeto e não passa no esquema; as outras quatro passam (a `exec_5_C2` grava a rodada como `iteracao`).

## A captura de mídia

A fase `capture` não usa agente. Ela reproduz o que o orquestrador do TCC fazia antes de chamar o Testador:

1. importa o projeto (`godot --headless --import`) e roda `godot --headless --check-only --quit`;
2. se `game/view/main.tscn` existir, grava `CAPTURE_SECONDS` (padrão 6) segundos da cena com `--write-movie` a 30 fps, sob `xvfb-run` quando disponível;
3. com `ffmpeg`, gera `gameplay_iter_N.mp4` e extrai `frame_1.png` (1 s) e `frame_2.png` (3 s); sem `ffmpeg`, salva só os dois quadros;
4. escreve `media/iter_N/resumo_midia.json` (`syntax_check_ok`, `frames_captured`, `frame_files`) e faz o commit.

Sem entrada do teclado, o que aparece nos quadros é o que a cena principal faz sozinha. Nas execuções do TCC os Desenvolvedores acabaram criando um modo demonstração com piloto automático para que os quadros mostrassem movimento; antes disso, as duas fotos podiam sair idênticas (na `exec_1_C2` isso aconteceu nas rodadas 1 e 2, e o Planejador da rodada 3 tratou o problema).

## Diferenças em relação ao orquestrador original

O orquestrador do TCC (`hoh_orchestrator.py`, fora deste repositório) disparava cada papel numa sessão isolada do Claude Code em *worktree* próprio, fazia o *merge* local e só seguia quando encontrava o commit esperado. O `iterate.sh` mantém os prompts, os modelos, as mensagens de commit, a captura e o critério de parada, e simplifica o resto:

- o agente roda direto no diretório da execução (`HOH_AGENT_CMD`, padrão `claude -p --model <modelo> --dangerously-skip-permissions`);
- o `iterate.sh` não roda `git clean` entre fases; só avisa se o agente deixar arquivos sem commit;
- os quadros em `resumo_midia.json` usam caminhos relativos à execução, e o `.avi` bruto é apagado depois da conversão;
- o repositório-semente ganhou um esqueleto vazio de `game/tests/run_gates.gd` e um `export_presets.cfg`; o resto do `template/` é idêntico ao da coleta (mesmo `GDD.md`, `project.godot`, assets e `tools/`).
