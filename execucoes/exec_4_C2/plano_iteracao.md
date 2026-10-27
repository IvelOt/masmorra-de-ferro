# Plano de Iteração 5 — Execução 4, Condição C2 (Rodada 5)

- **Papel:** Planejador ($D_t$), fluxo HoH.
- **Base:** `GDD.md` (§2.2, §4.5, §4.6, §5.3–§5.6, §7.5), código atual (`ec737fc` e `cb4d449`, commits `wip:` da rodada 4) e evidência $E_4$ em `relatorio_provas.json` (`f766d9a`).
- **Marcos escolhidos (fechamento):** **M5** (automapa translúcido) e **M6** (itens, progressão e condição terminal). O limite de 2 marcos por rodada é respeitado.
- **Justificativa:**
  - $E_4$ mostra que o **código** de M5/M6 agora existe (`automap_sim.gd`, `items_sim.gd`, `pilot_sim.gd`, `automap_overlay`, `item_view`, `end_screen`), mas **nenhuma asserção os verifica**: não há `M5-A*` nem `M6-A*` em `game/tests/`. Sem gate executado, o Verificador não pode aceitar os marcos (`all_milestones_passed: false`).
  - O Preservation Gate está vermelho: `SCENE-hud` falha (52 PASS, 1 FAIL). A causa foi conferida no código (§0): o gate procura `HUD/Vida/Fill` e `HUD/Vigor/Fill`, mas `hud_daggerfall.gd` cria os nós com os nomes `HpBar` e `SpBar`.
  - A mídia não mostra o jogo porque **a trilha da demonstração não existe**: `main.gd` aponta para `res://tests/traces/demo_iter4.jsonl`, mas o arquivo não está em `tests/traces/` e `GateTraces.fixed()` não o gera. O modo demonstração roda com input neutro, então a câmera fica parada diante de uma parede e só o roteiro de UI (abrir o mapa nos ticks 150–210) acontece. Isso explica o `frame_2` com o mapa vazio.
  - M1–M4 estão íntegros (gates PASS, R1/R3 iguais, `PRES-grid` PASS). Não há regressão de núcleo a corrigir.
- **Esta rodada é de verificação e acabamento, não de reescrita.** O núcleo de M5/M6 é mantido; só se corrige o que os gates novos revelarem.
- **Fora do escopo (não implementar):** perfil `daggerfall`; R5 interplataforma; quadros de 8 direções; classes, magia, meta-progressão; mudanças em constantes de M1–M4 (GDD §3.4); assets novos; mudança no formato de `s_k` (`schema_version` continua `1`).

---

## 0. Estado de partida (verificado no código)

| Item | Situação |
|---|---|
| `tests/gates/run_gates.gd` | Roda `GateM1`, `GateM2`, `GateM3`, `GateM4` e `GateRepro`. **Não existe** `gate_m5.gd`, `gate_m6.gd` nem `gate_ui.gd`. |
| `gate_repro.gd:105` (`SCENE-hud`) | Exige `HUD/Vida/Fill`, `HUD/Vigor/Fill`, `HUD/Compass`, `HUD/Portrait`, `Weapon/Clip/Sword`, `Weapon/Clip/Shield`. |
| `view/hud_daggerfall.gd` | Barras criadas por `_bar("HpBar", Rect2(52, 316, 12, 42))` e `_bar("SpBar", Rect2(68, 316, 12, 42))`, com preenchimento `Fill` 10×40. `Compass` e `Portrait` existem como filhos diretos do `HUD`. Bússola: `COMPASS_RECT = (546, 316, 88, 40)`, janela de ±90° em 88 px (0,49 px/grau), letras com 14 px de largura e marcas "·" a cada 45°, ou seja, 22 px entre marcas. Por isso as letras ficam coladas e, com o rumo leste, "N" encosta na borda esquerda e "S" na direita. |
| `view/weapon_view.gd` | Espada ×5 em (452, 262) a −30°; escudo ×4 em (188, 284) a +8°; recorte `Clip` 640×312. No `frame_1` o cabo da espada fica **acima** do recorte (≈ y 300), sem mão, e há uma mancha escura de sombra junto ao escudo. A arte `weapon_sword.png` é diagonal (área opaca 2–30 × 2–30, ponta no canto superior direito, cabo no inferior esquerdo). |
| `view/main.gd` | Modo demonstração sem argumentos: `DEMO_SEED = 1`, `DEMO_TRACE = res://tests/traces/demo_iter4.jsonl` (**arquivo ausente**), mapa aberto nos ticks 150–210. O cabeçalho de pose da trilha é aplicado por `set_player_pose`. |
| `sim/pilot_sim.gd` | `goal_override: Array` já existe (objetivo fixo para a demonstração); `combat_target`, `aim`, `next_input(sim)`. |
| `scripts/headless_runner.gd` | `--mode=pilot`, `--record`, `--stop-at-terminal`, `--check-invariants` (com as invariantes de M5/M6) já implementados. |
| `sim/world_sim.gd` | Passos 1–11 implementados; `add_item(type, cx, cz)` é API de teste; `terminal_tick` fora do estado. |
| Mídia (`media/iter_4/gameplay_iter_4.mp4`) | **4,2 s** (≈ 252 ticks). Tudo o que a auditoria visual precisa ver tem de acontecer nos **primeiros 240 ticks**. |
| Checkout limpo | `game/.godot/` está no `.gitignore`; `run_gates.gd` só compila depois de `godot --headless --path game --import`. |

---

## 1. Arquivos desta rodada

```
game/
  tests/gates/
    gate_m5.gd         # NOVO — M5-A1..A6
    gate_m6.gd         # NOVO — M6-A1..A6, M6-A1b, R2, R4
    gate_ui.gd         # NOVO — UI-1..UI-7 (layout, arma, tela final, demonstração, áudio)
    gate_traces.gd     # ALTERAR — demo_iter4(), trilhas de M5/M6 em fixed()/headers()
    run_gates.gd       # ALTERAR — GateM5, GateM6, GateUI depois de GateM4 e antes de GateRepro;
                       #           comentário do topo com o comando --import (§5.7)
    gate_repro.gd      # NÃO ALTERAR as asserções de SCENE-hud (o defeito está na view)
  tests/traces/        # NOVAS: demo_iter4.jsonl, m5_a2_corridor_seed1.jsonl,
                       #        m6_a3_exit_seed1.jsonl, r4_pilot_seed1337.jsonl
  view/
    hud_daggerfall.gd  # ALTERAR — nomes Vida/Vigor, barras com rótulo, bússola nova, objetivo (§4.1)
    weapon_view.gd     # ALTERAR — poses, mão procedural, sem sombra (§4.2)
    main.gd            # ALTERAR — semente da demonstração lida do cabeçalho da trilha (§3.2)
  sim/                 # só correções apontadas pelos gates novos; nenhum campo novo em s_k
```

**Regra de preservação:** é proibido alterar valores esperados ou relaxar asserções dos gates de M1–M4 e de `gate_repro.gd`. O `SCENE-hud` deve passar **corrigindo a view**, não o gate.

---

## 2. Especificação de M5 e M6 a verificar (resumo normativo)

A especificação do plano da rodada 4 (§2 e §3, conferida contra o código em §0) continua valendo. Os pontos que os gates abaixo fixam:

### 2.1 M5 — `AutomapSim`
- `visited: PackedByteArray` 64×64, índice `cz * 64 + cx`, só 0/1, monotônico; `rev` sobe quando um byte vai de 0 a 1; `sha256()` cacheado por `rev`.
- `mark(g, px, pz)` no passo 9 de todo tick não terminal: se a célula do jogador está na sala `r` (primeira em ordem de `id`), marca `[r.x−1, r.x+r.w] × [r.z−1, r.z+r.h]` recortado a `[0, 63]`; senão marca o 3×3 em volta da célula.
- Nenhum estado da overlay (aberta/fechada) entra em `s_k`. O Tab é tratado só em `automap_overlay.gd` (`_unhandled_input`, ação `toggle_map`).

### 2.2 M6 — itens, progressão e terminal
- Itens `{id, type, cell_x, cell_z, taken}`; tipos `POTION_HP=0`, `POTION_SP=1`, `KEY=2`, `GOLD=3`; id 0 é sempre a poção de vida da sala inicial em `room_center(sala 0) + (1, 0)`.
- Itens sorteados com o RNG da masmorra **depois** de `EnemySim.spawn_for_dungeon` (grade e inimigos idênticos aos da rodada 2).
- Chave: uma só, em sala ∉ {inicial, saída}, alcançável por `ItemsSim.bfs_lock` (BFS que trata `DOOR_LOCKED` como parede).
- `quaff=1`: +40 HP limitado a `hp_max`; `quaff=2`: +50 de vigor limitado a `stamina_max`. Com o inventário vazio, ou com a barra cheia, não faz nada e **não consome** a poção.
- XP por abate (`EnemySim.XP = [0, 10, 25, 100]`). Nível 2 com 100 XP, nível 3 com 250 XP. Cada nível dá +20 `hp_max`, +10 `stamina_max`, +5 de dano da espada e `hp = hp_max`. Um salto de vários níveis aplica todos os bônus.
- Terminais: `ESCAPED` (`use` no `EXIT` com a chave, no mesmo tick), `DEAD` (`hp ≤ 0`), `TIMEOUT` (`tick ≥ 18000`). Depois do terminal só `tick` muda.
- `DOOR_LOCKED` abre com `use` + chave, e a chave **não** é consumida.

Se algum gate da §5 revelar divergência entre o código e este resumo, o Desenvolvedor corrige o **código** para o resumo. Se a correção mudar `C_K` de R1/R3, os valores novos vão para o relatório. Valores esperados de M1–M4 não podem mudar.

---

## 3. Demonstração (causa da mídia vazia)

### 3.1 Restrição de tempo
O vídeo de auditoria tem ≈ 4,2 s e os quadros são extraídos dele. Por isso o roteiro abaixo põe **inimigo, golpe, item e coleta antes do tick 150** e o automapa aberto entre os ticks 150 e 210, com células já visitadas.

### 3.2 `GateTraces.demo_iter4() -> Dictionary` (`{"header": {...}, "inputs": [...]}`)
Determinística, só com o núcleo e sem tempo real:

1. **Escolha da semente e da pose.** Para `s` de 1 a 50, em ordem crescente: criar `WorldSim.new(s)`. Para cada inimigo `e` em ordem de `id`, com `type ∈ {RAT, SKELETON}`, achar a sala `r` que contém a célula de `e`. Exigir que exista um item não coletado com `type ≠ KEY` na **mesma** sala. Varrer as células `FLOOR` de `r` em ordem (`cz` crescente, depois `cx`) e aceitar a primeira célula `c` tal que:
   - a distância de Chebyshev de `c` até `e` está entre 4 e 5 células;
   - há linha de visão de `c` a `e` (`EnemySim.los`) e de `c` ao item;
   - o item está a ≤ 4 células de `c`, e o ângulo entre a direção do inimigo e a do item, visto de `c`, é ≤ 45°.

   A primeira combinação `(s, e, c)` que passa vence. O ângulo da pose é o múltiplo de 128 BAM que maximiza `dx·cos + dz·sin` em direção a `e` (inteiros, `TrigTable`). Cabeçalho: `{"seed": s, "pos_x": centro(c.x), "pos_z": centro(c.z), "angle": a}`. Se nenhuma semente servir, o gate UI-6 falha com a mensagem "sem cena de demonstração em 1..50".
2. **Inputs** (600 ticks, gravados pelo núcleo a partir do estado com a pose aplicada):
   - ticks 1–20: neutro (o inimigo percebe o jogador; o mundo aparece com o inimigo e o item na tela);
   - ticks 21–140: `PilotSim.new(s)` com `goal_override = célula do item`. O piloto combate sozinho quando há alvo (`combat_target`) e depois segue até o item;
   - ticks 141–210: giro de +16 por tick durante 64 ticks e 6 ticks neutros (o mapa está aberto entre 150 e 210 pelo roteiro de UI; o giro mostra a seta do jogador e a bússola girando);
   - ticks 211–600: piloto sem `goal_override` (vai para a chave).
3. Em `fixed()`/`headers()` a trilha entra como `"demo_iter4.jsonl"` e é gravada por `run_gates.gd -- --record-traces`. **O arquivo gravado é commitado.**

### 3.3 `main.gd`
- No modo demonstração, ler o cabeçalho de `DEMO_TRACE` **antes** de criar o `WorldSim` e usar `header.seed` como semente (se ausente, `DEMO_SEED`). Depois aplicar a pose como hoje.
- Se a trilha não puder ser lida, `push_error` e sair do modo demonstração (`demo = false`) para o jogo interativo. Nunca rodar a demonstração com input neutro.
- Roteiro de UI inalterado (`DEMO_MAP_OPEN = 150`, `DEMO_MAP_CLOSE = 210`).

---

## 4. Correções de apresentação (pendências de $E_2$–$E_4$)

Coordenadas no viewport 640×360; HUD em `y = 312..360`; filtro `NEAREST`; escalas inteiras.

### 4.1 HUD (`hud_daggerfall.gd`)
| Elemento | Nome do nó (filho direto de `HUD`) | Retângulo | Detalhes |
|---|---|---|---|
| Faixa | `Bar` | (0, 312, 640, 48) | sem mudança |
| Retrato | `Portrait` | (6, 316, 40, 40) | moldura de 2 px `#a08a60`; `Face` 32×32 ×1 centrado |
| Barra de Vida | **`Vida`** (antes `HpBar`) | (52, 315, 16, 42) | moldura de 2 px `#a08a60`, fundo `#000`; `Fill` 12×38 (`#b02020`); rótulo "V" (fonte 8, `#f0e0a0`) centrado no topo **dentro** da moldura, por cima do preenchimento |
| Barra de Vigor | **`Vigor`** (antes `SpBar`) | (72, 315, 16, 42) | igual, `Fill` `#20a040`, rótulo "G" |
| Atributos | `Stats` | (94, 315, 108, 42) | 3 linhas, fonte 10 (sem mudança no texto) |
| Inventário | `Inventory` | (206, 316, 120, 40) | ícones 16×16 + contadores, sem mudança |
| Mensagens | `Message` | (332, 316, 186, 40) | sem mensagem ativa, mostra o **objetivo** em `#a09070`: "Objetivo: ache a Chave" sem chave; "Objetivo: Portal de Fuga" com chave |
| Bússola | `Compass` | (524, 316, 110, 40) | ver abaixo |

- A altura do preenchimento é `round(38·v/vmax)`, alinhado à base. Os nomes `Vida/Fill` e `Vigor/Fill` fazem o `SCENE-hud` voltar a passar **sem mexer no gate**.
- **Bússola:** janela de ±60° em 110 px (`110/120 ≈ 0,917 px/grau`). Só as cardinais N, L, S, O, em fonte 14 (N em `#f2cc66`). Entre as cardinais há traços verticais de 1×6 px a cada 15° (`#857a66`), em vez de "·". Uma letra só fica visível quando seu centro está em `x ∈ [10, 100]` dentro da caixa, nunca encostada na borda. Há uma linha central vermelha de 1×8 px no topo (marcador). Com isso, cardinais vizinhas ficam a 82 px uma da outra e no máximo duas aparecem ao mesmo tempo.

### 4.2 Arma (`weapon_view.gd`)
- **Espada ×4** (128 px de lado; antes ×5). Em `IDLE`: centro em (452, 280), rotação **0°**. A arte já é diagonal, então a lâmina aponta para o centro-alto da tela e o cabo (canto inferior esquerdo da textura, pixel (4, 28)) fica **abaixo** de `y = 312` e é cortado pelo recorte.
- **Mão procedural:** `Polygon2D` `Hand`, filho de `Sword` (herda posição, rotação e escala). É uma manopla de metal: polígono de 6 vértices em coordenadas de textura em volta do punho (≈ 7×6 texels a partir de (2, 22)), cor `#7d828c` com contorno `Line2D` `#25262b` de 1 texel. O pomo continua visível acima da mão. Fica visível em todas as poses.
- **Escudo ×4** em `IDLE`: centro em (204, 300), rotação +6°. Assim só os ≈ 2/3 superiores aparecem e a borda inferior é cortada pelo recorte. Os centros ficam simétricos em relação a `x = 328 ± 8` e a ≈ 248 px um do outro.
- Poses de golpe, bloqueio e atordoamento com os mesmos deslocamentos relativos de hoje em relação à nova base (WINDUP = base + (48, −22), −30°; ACTIVE de base + (28, −60) a base + (−172, +10), −30° → +75°; bloqueio: escudo em (268, 250) ×5, 0°).
- **Sem sombra projetada** (remover qualquer nó de sombra ou cópia escurecida).

### 4.3 Proporções no mundo 3D (sem mudança; os gates conferem)
Parede de 3 m, olho a 1,5 m, célula de 2 m. Altura visível a partir da área opaca da textura 32×32 (`pixel_size = alvo / altura_opaca`), com a base no piso:

| Sprite | Altura visível | Base | Fonte |
|---|---|---|---|
| Boneco / Rato / Esqueleto / Guardião | 1,60 / 0,50 / 1,75 / 2,30 m | 0 | `enemy_view.gd` `TARGET_M` |
| Poção de vida / vigor | 0,40 m | 0 | `item_view.gd` |
| Chave | 0,25 m (flutua 0,35 m ± 0,05 m) | 0,35 m | `item_view.gd` |
| Ouro | 0,30 m | 0 | `item_view.gd` |
| Portal de Fuga | 2,20 m | 0 | `dungeon_view.gd` |

### 4.4 Áudio (procedural, fora do hash; já em `audio_view.gd`)
Nenhum som novo. A rodada só **verifica** (UI-7) que cada evento de M5/M6 tem stream (nomes de `AudioView.PROGRESS_SOUNDS`): `pick_potion`, `pick_gold`, `pick_key`, `quaff`, `unlock`, `level_up`, `paper` (abrir/fechar o automapa), `end_ESCAPED`, `end_DEAD`, `end_TIMEOUT`. Cada stream é `AudioStreamWAV` de 22 050 Hz, mono, 16 bits, com duração entre 0,05 s e 2,5 s e pico ≤ 0,9 (sem saturar). Volume no barramento `SFX`.

---

## 5. Gates (o Verificador de C2 executa `run_gates.gd`)

Todos imprimem `PASS|FAIL <ID> <detalhe>` via `GateReport`. Cenas instanciadas são liberadas antes do `quit` (sem `ObjectDB instances were leaked`).

### 5.1 `gate_m5.gd`
| ID | Cenário | Asserção |
|---|---|---|
| M5-A1 | sementes 1..20, um `step` neutro | `visited` = retângulo da sala inicial expandido em 1 (recortado), célula a célula; contagem = `(w+2)·(h+2)` |
| M5-A2 | semente 1, `m5_a2_corridor_seed1.jsonl`: pose de `GateM2.a6_setup`, `use` na porta, anda pelo corredor (caminho BFS até a sala vizinha, parando 1 célula antes dela) | toda célula de corredor pisada e suas vizinhas-8 estão marcadas; nenhuma célula de outra sala além da inicial está marcada |
| M5-A3 | sementes 1..20, 1200 ticks de `GateTraces.random_inputs(s, 1200, true)` | em nenhum tick uma célula volta a 0; a contagem nunca decresce |
| M5-A4 | semente 1337, `r_seed1337_random.jsonl`: (a) núcleo puro; (b) `main.tscn` com `driven = true` e `InputEventKey` Tab (pressionado e solto) enviado a `Main/Automap` a cada 37 ticks; (c) `main.tscn` sem Tab | `C_K(a) == C_K(b) == C_K(c)`; `Map.visible` alternou ≥ 10 vezes em (b) |
| M5-A5 | `automap_overlay.tscn` sozinho na árvore | começa com `Map.visible == false`; Tab pressionado → `true`; Tab solto → continua `true`; outro Tab → `false`; eco não alterna; `0 < Map.modulate.a < 1`; `layer == 3`; `Map.size == (640, 312)` |
| M5-A6 | `main.tscn` semente 1, mapa aberto, 30 ticks | contador de desenhos da overlay > 0; `automap_overlay.gd` não contém chamadas `mark(`, `step(`, `set_cell(` |

### 5.2 `gate_m6.gd`
| ID | Cenário | Asserção |
|---|---|---|
| M6-A1 | sementes 1..100 | exatamente 1 `KEY`; sala ∉ {start, exit}; `bfs_lock` do spawn alcança a chave; todos os itens em `FLOOR` dentro de salas, sem dois na mesma célula; na sala 0 só o item id 0 (`POTION_HP`) |
| M6-A1b | sementes 1..100, duas instâncias; e `WorldSim` com vs. sem itens | listas de itens idênticas entre instâncias; posições e tipos dos inimigos idênticos aos de `EnemySim.spawn_for_dungeon` sozinho (os itens não mudam o sorteio dos inimigos); `PRES-grid` continua PASS |
| M6-A2 | sala de teste + `add_item` | (a) `quaff=1` sem poção: jogador inalterado; (b) `hp = 100`: não consome; (c) `hp = 30` → 70 e `potion_hp − 1`; (d) `hp = 90` → 100; (e) vigor com +50 nos mesmos casos; (f) a coleta incrementa o inventário no tick em que o jogador entra na célula |
| M6-A3 | semente 1, pose no centro do `EXIT` | (a) `use` sem chave: `terminal == ""`; (b) chave coletada (item 1 movido para a célula do jogador, 1 `step`) e `use` → `terminal == "ESCAPED"` e `terminal_tick == tick` no mesmo tick; (c) `use` diante de `DOOR_LOCKED` sem chave não abre; com chave abre e `grid_version` sobe |
| M6-A4 | sala de teste, `queue_hit(…, 100)` pelas costas | `terminal == "DEAD"` no tick do golpe; nos 300 ticks seguintes de input aleatório com `attack/use/quaff`, o JSON canônico de `get_state()` sem `tick` fica constante e `tick` sobe de 1 em 1; `TIMEOUT` com 18000 ticks neutros na sala de teste, com `terminal_tick == 18000` |
| M6-A5 | sala de teste; abates à espada | 4 esqueletos → `xp 100`, `level 2`, `hp_max 120`, `stamina_max 110`, `hp 120`, dano 30; + Guardião → `xp 200`, ainda `level 2`; + 2 esqueletos → `xp 250`, `level 3`, `hp_max 140`, `stamina_max 120`, dano 35; salto 1 → 3 num tick (`xp = 240`, abate de rato) aplica os dois bônus |
| M6-A6 | piloto, sementes 1..50, `--stop-at-terminal` (no próprio processo do gate, via `PilotSim` + `WorldSim`) | `ESCAPED` em **≥ 40 de 50**. Imprimir uma linha por semente (`seed terminal terminal_tick level gold`) e o total. O limiar **não** pode ser baixado |
| R4 | semente 1337, piloto por 3000 ticks gravado em `r4_pilot_seed1337.jsonl`, depois replay | `C_K` iguais |
| R2 | dois processos do runner (`OS.execute` do binário corrente) em replay de `r_seed1337_combat.jsonl` e em `--mode=pilot --seed=7 --ticks=3000` | `chain_final` iguais em cada par |

**Custo de M6-A6:** se 50 partidas com SHA por tick passarem de 300 s, o gate pode criar o `WorldSim` com uma flag `emit_hash := false` (atributo fora de `s_k`, padrão `true`, que só pula o passo 11). O resultado (`terminal`) não pode depender da flag. Isso é conferido em 3 sementes, com e sem a flag, comparando `terminal` e `terminal_tick`.

### 5.3 `gate_ui.gd` (headless, sem GPU)
| ID | Asserção |
|---|---|
| UI-1 | `HUD/Bar` = (0, 312, 640, 48); `Portrait`, `Vida`, `Vigor`, `Stats`, `Inventory`, `Message`, `Compass` dentro da faixa e sem sobreposição dois a dois (`get_global_rect()`) |
| UI-2 | bússola: `clip_contents`; fonte das cardinais ≥ 14; com `angle` = 0, 1024, 2048 e 3072, a cardinal esperada está no centro (± 2 px) e toda letra visível tem o centro em `x ∈ [10, 100]` da caixa |
| UI-3 | `hp = 50/100` → `Vida/Fill` com 19 px (`round(38·0,5)`) alinhado à base; `hp_max = 140, hp = 140` → 38 px; idem `Vigor`; os rótulos "V" e "G" existem e ficam dentro da moldura |
| UI-4 | arma em `IDLE`: o pixel de textura (4, 28) da espada, transformado para a tela, fica com `y ≥ 318` (cabo cortado); o retângulo transformado do escudo passa de `y = 312` em ≥ 24 px; `Sword/Hand` existe e está visível; nenhum nó de sombra sob `Weapon`; distância horizontal entre os centros em [220, 280] |
| UI-5 | tela final: estado com `terminal = "ESCAPED"` → `Main/EndScreen` visível, painel 360×200 dentro de 640×360, título contém "ESCAPOU"; `DEAD` → título contém "MORREU"; `TIMEOUT` → "TEMPO" |
| UI-6 | demonstração: `demo_iter4.jsonl` existe, tem 600 ticks e o cabeçalho com `seed`, `pos_x`, `pos_z`, `angle`, e é igual à saída de `GateTraces.demo_iter4()`. Rodada pelo núcleo: (a) nos ticks 1–100, um inimigo vivo fica na frente (±35°), com LOS e a ≤ 6 células por ≥ 45 ticks; (b) há um golpe iniciado antes do tick 140; (c) um item não coletado fica na frente a ≤ 4 células em algum tick ≤ 60, e algum item é coletado até o tick 150; (d) no tick 150, `automap.count() ≥ 40`; (e) o `angle` varia ≥ 1024 entre os ticks 141 e 210 |
| UI-7 | áudio: `AudioView.get_stream(n)` não nulo para cada nome de §4.4, com formato, duração e pico dentro dos limites |

### 5.4 Preservação
- M1-A1..A6, M2-A1..A6 (+INV), M3-A1..A8, M4-A1..A7, `PRES-grid`, R1, R3, R3-combate e todos os `SCENE-*` passam **sem alteração de asserções**.
- Os `C_K` de R1/R3 só podem mudar se uma correção de núcleo de §2 for necessária. Nesse caso, os valores antigos e os novos vão para o relatório.

### 5.5 Checagens estáticas
- `python3 tools/lint_sim.py` → 0 violações.
- `python3 tools/gen_trig_table.py` não altera `sim/trig_table.gd`.
- grep em `view/`: nenhuma chamada a `queue_hit`, `add_enemy`, `add_item`, `mark(`, `move_and_slide`, `move_and_collide`.

### 5.6 Trilhas
As trilhas novas (§1) são geradas por `GateTraces.fixed()`/`headers()` e gravadas com `-- --record-traces`. Cada gate confere que o arquivo gravado é igual à geração (`same_inputs`), como `R-trace` já faz.

### 5.7 Comando de verificação (checkout limpo)
```
godot --headless --path game --import
python3 tools/lint_sim.py
godot --headless --path game -s res://tests/run_gates.gd
```
Esse bloco vai no comentário do topo de `tests/gates/run_gates.gd`.

---

## 6. Critérios de conclusão (Definition of Done do Desenvolvedor)
1. `lint_sim.py` limpo; `trig_table.gd` inalterado.
2. `run_gates.gd` com **0 FAIL**: preservação (§5.4), M5-A1..A6, M6-A1..A6, M6-A1b, R2, R4, UI-1..UI-7. Se M6-A6 ficar abaixo de 40/50, todo o resto ainda deve passar e o relatório traz a tabela por semente com o motivo de cada falha.
3. `demo_iter4.jsonl` commitado. Abrir o jogo sem argumentos mostra, nos primeiros 4 s: inimigo, golpe, item coletado (mensagem na HUD) e o automapa com a sala e o corredor visitados.
4. Nenhum asset novo; nada em `game/assets/daggerfall/`.
5. Código commitado em commits **`feat:`/`fix:`/`test:`** (não `wip:`), na ordem da §7, ou num único commit `feat: implementacao iteracao 5`.
6. Relatório do Desenvolvedor com o trecho final da saída de `run_gates.gd` (contagem PASS/FAIL, sem `ObjectDB instances were leaked`), os `C_K` e a tabela de M6-A6.

## 7. Ordem de implementação (fatias com commit)
| Fatia | Conteúdo | Gates verdes ao fim |
|---|---|---|
| 1 | HUD: `Vida`/`Vigor`, rótulos, bússola, objetivo | SCENE-hud, UI-1..UI-3 |
| 2 | `gate_m5.gd` + correções de núcleo/overlay que ele apontar | M5-A1..A6 |
| 3 | `gate_m6.gd` (A1..A5, A1b) + correções | M6-A1..A5, A1b, preservação |
| 4 | M6-A6, R2 e R4 (calibração do piloto **sem** baixar o limiar) | M6-A6, R2, R4 |
| 5 | Arma (§4.2) | UI-4 |
| 6 | `demo_iter4()`, trilha gravada, `main.gd` (§3) | UI-6 |
| 7 | UI-5, UI-7 e revisão final | tudo |

## 8. Riscos
| Risco | Mitigação |
|---|---|
| Piloto abaixo de 80% | fatia 4 dedicada; ajustes só em `pilot_sim.gd` (destravamento, Guardião ignorado com a chave, poção abaixo de 30 HP); a tabela por semente vai ao relatório |
| M6-A6 lento | flag `emit_hash` (§5.2), com equivalência conferida |
| Nenhuma semente atender à cena de demonstração | critérios graduais da §3.2 (4–5 células, ±45°); UI-6 falha com mensagem explícita, em vez de gravar uma trilha vazia |
| Renomear as barras quebrar o código que as referencia | `_hp_fill`/`_sp_fill` continuam sendo as referências internas; só o `name` muda |
| Correção de núcleo mudar `C_K` | registrar os valores; os valores esperados de M1–M4 não mudam |
| Gates não compilarem num checkout limpo | `--import` antes (§5.7) |
