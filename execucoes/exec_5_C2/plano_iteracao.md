# Plano de Iteração 5 — Condição C2 (HoH), Execução 5

- **Papel:** Planejador ($D_t$), iteração $t = 5$.
- **Entrada:** `GDD.md` (§1–5, §7), `relatorio_provas.json` da iteração 4 ($E_4$), código atual em `game/` (últimos commits de código: `9aa9351`, `6c85320`, `29badc5`).
- **Evidência $E_4$:** 68/68 gates PASS (`game/runs/gates_iter4.txt`). M1, M2, M3, M4 e M5 estão **aceitos** e sem regressão. Lacunas de $E_4$:
  1. **M6 não implementado.** Não existem `items_sim.gd`, `m6_gates.gd` nem o modo `--mode=pilot` (o runner devolve "não implementado"). `_step_quaff` (passo 4) e `_step_terminal` (passo 10) continuam *no-ops*.
  2. **Mídia não demonstrativa.** `frame_1.png` e `frame_2.png` são idênticos: a captura abre o jogo **sem argumentos** (masmorra da semente 1, jogador parado na sala inicial vazia). O `--demo` da rodada 4 existe, mas a captura não o usa.
  3. **Texto da HUD pequeno e com pouco contraste.** A fonte tem 10 px e o vermelho-escuro `#b02020` aparece sobre cinza-escuro.
  4. **Vazamento de ObjectDB** ao sair (1 instância na captura e 2 nos gates).

---

## 1. Marcos selecionados

| Marco | Motivo |
|---|---|
| **M6 — Itens, progressão e condição terminal de vitória/fuga** | É o único marco que falta. As dependências estão satisfeitas: `{M4, M5} → M6` e os dois foram aceitos em $E_4$. Com M6 aceito, $\sum_i g_{i,t} = 6$. |

**Só um marco.** Os outros cinco já foram aceitos. A segunda vaga da rodada vai para as **correções de lacunas** (§6): mídia demonstrativa, legibilidade da HUD e ObjectDB. Elas não são marcos, mas são achados de auditoria que se repetem desde $E_2$.

**Preservation Gate desta rodada (executado):** M1-A1…A6, M2-A1…A6, M3-A1…A7, M4-A1…A7 + M4-AUX-1…6 e M5-A1…A5. Também LINT, R1, R1-AI, R1-M5, R3-* (inclusive R3-enemies), DEMO-4, TYPES, SCENE e ASSETS. Nenhuma asserção nem trilha existente pode mudar: `m2_door.jsonl`, `m5_corridor.jsonl`, `demo_iter2.jsonl` e `demo_iter4.jsonl` **não podem ser regravadas**. Restrições:

- `DungeonGen.generate(s)`, `test_room()` e `automap_fixture()` **não mudam**. O SHA da grade de cada semente continua igual.
- `EnemySim.spawn` não muda e continua sendo chamado **antes** do posicionamento de itens. Assim, tipos e posições dos inimigos de cada semente ficam iguais aos de $E_4$.
- `test_room` e `automap_fixture` **não recebem itens**. Consequência verificável: a cadeia do gate `R1` (test_room + `m2_door.jsonl`, 600 ticks) tem de continuar **exatamente** `523fef79264724d26ba78e7b53b623a8f32de0157ef9eb7a95f50e058f8553d6`, e a de `R1-M5` continua `402d5674afe77462d8f310d349453dc9a1cda15a14afc92af1ddcfaac8485ff9`. As cadeias das masmorras geradas (R1-AI, R3-seed-*) e a de R3-enemies (o rato abatido agora dá XP) **mudam**, e isso é esperado: esses gates comparam execuções entre si, não valores fixos.

**Fora do escopo (não implementar):** classes novas, magia, meta-progressão, mais de uma fase, R5 (interplataforma), perfil de arte `daggerfall`, mudanças nas tabelas de M1–M4.

---

## 2. Arquivos a criar / alterar

```
game/
  sim/
    items_sim.gd             # NOVO     class_name ItemsSim: tabela, spawn de itens, coleta, poções, XP/nível, terminal
    pilot.gd                 # NOVO     class_name Pilot: piloto em malha fechada (só lê o mundo; fluxo PCG STREAM_PILOT)
    world_sim.gd             # ALTERAR  items[]; spawn de itens; passos 3, 4, 8 e 10; porta trancada; transitórios; getters
    combat.gd                # ALTERAR  registra abates do jogador em world.killed_now (passo 5) — sem mudar números
    state_hash.gd            # ALTERAR  "items": world.get_items() (era [])
  input/input_sampler.gd     # ALTERAR  quaff por borda de subida (hoje é por nível: segurar "1" beberia uma poção por tick)
  view/
    item_view.gd             # NOVO     Sprite3D billboard por item (Items/item_<id>)
    end_screen.tscn/.gd      # NOVO     tela final em pergaminho (CanvasLayer 4)
    hud_daggerfall.gd/.tscn  # ALTERAR  fonte maior/contraste; poções, chave, nível, XP, ouro; mensagens de M6
    audio_view.gd            # ALTERAR  sons de coleta, poção, nível, destranca, fuga, morte, timeout
    main.gd                  # ALTERAR  modo vitrine (padrão sem argumentos), --pilot, --manual, item_view, end_screen
  scripts/headless_runner.gd # ALTERAR  --mode=pilot, terminal_tick, --gates aceita M6
  tests/
    run_gates.gd             # ALTERAR  + M6Gates.run(self); R2, R4; SCENE/ASSETS estendidos; checagem fixa de R1
    gates/m6_gates.gd        # NOVO
```

As regras do núcleo valem para `items_sim.gd` **e** para `pilot.gd`, que ficam em `game/sim/` justamente para passar pelo linter. Os dois começam com `extends RefCounted` e passam em `python3 tools/lint_sim.py`: sem float, sem `Node`, sem `/` aplicado a valores que podem ser negativos (usar `FixedMath.div_trunc/div_floor`) e com iteração só por índice. O `Pilot` **nunca escreve** em `WorldSim`, só lê campos e getters, e nunca consome `rng_dungeon` nem `rng_ai`.

---

## 3. Especificação de código — M6 (núcleo)

### 3.1 Constantes (`ItemsSim`)

| Constante | Valor | Origem |
|---|---|---|
| `POTION_HP_HEAL` | 40 | GDD §4.6 |
| `POTION_SP_GAIN` | 50 | GDD §4.6 |
| `GOLD_PER_PILE` | 10 | decisão deste plano (o GDD não fixa o valor) |
| `LEVEL_XP` | `[0, 0, 100, 250]` (índice = nível) | GDD §4.6 |
| `LEVEL_MAX` | 3 | GDD §4.6 |
| `LEVEL_HP_BONUS` / `LEVEL_SP_BONUS` / dano | +20 / +10 / +5 por nível | GDD §4.6; o dano já sai de `Combat.sword_damage(level)` = `25 + 5·(level−1)` |
| `K_MAX` | 18000 | GDD §3.4 |
| XP por tipo | `EnemySim.TYPES[type]["xp"]` (rato 10, esqueleto 25, guardião 100); `dummy` = 0 | GDD §4.4 |

### 3.2 Item e estado novo em `WorldSim`

- Item = `Dictionary` com exatamente `{"id": int, "type": String, "cell_x": int, "cell_z": int, "taken": bool}`. `type ∈ {"potion_hp", "potion_sp", "key", "gold"}`.
- `var items: Array = []`, em ordem crescente de `id`. Entra no hash por `get_items()`, que devolve cópias.
- Transitórios **não hasheados**, zerados no início de cada `step()` (depois do `tick += 1`):
  - `killed_now: Array`: ids abatidos pelo jogador no passo 5 deste tick.
  - `exit_used: bool`: `use` sobre o `EXIT` com chave neste tick (passo 3).
  - `events: Array` de `String`, só para a view e os gates. Exemplos: `"pickup:<id>"`, `"quaff:1:<ganho>"`, `"quaff_empty:1"`, `"unlock:<door_id>"`, `"level:<n>"`, `"locked_no_key"`. O núcleo nunca lê `events`.
- `PlayerSim` já tem `level, xp, gold, potion_hp, potion_sp, key` e `inventory` no `to_canon()`. **Não mudar `to_canon()`.**
- `StateHash.canon`: `"items": world.get_items()`. Nenhuma outra chave muda.

### 3.3 Posicionamento de itens — `ItemsSim.spawn(world)` (só na masmorra gerada)

Chamado em `WorldSim.create(seed, false, "")` **logo depois** de `EnemySim.spawn(w)`. Consome **só** `rng_dungeon`, na ordem abaixo. Não altera a grade.

Célula livre para item: `grid.get_cell == FLOOR` (não pode ser porta nem `EXIT`), diferente da célula inicial do jogador, sem inimigo na célula (`div_floor(e.pos, 2048)`) e sem outro item. `free_cells(room)` = lista das células livres **dentro do retângulo da sala**, ordenada por `cz*64 + cx`. `pick(room)` = `free_cells(room)[rng_dungeon.bounded(n)]`.

```
1. Poção inicial: item potion_hp em pick(start_room).                      # a única exceção da sala inicial
2. Chave:
   reach = ItemsSim.bfs_no_locked(grid, cell do jogador)    # BFS-4 N,L,S,O; bloqueia SOLID e DOOR_LOCKED;
                                                            # DOOR_CLOSED e DOOR_OPEN passam
   cand  = salas r (ordem de id) com r.id != start_room, r.id != exit_room
           e pelo menos uma célula de free_cells(r) com reach >= 0
   room  = cand[rng_dungeon.bounded(cand.size())]
   cell  = sorteio entre as células de free_cells(room) com reach >= 0 (mesma regra de pick)
   (cand vazio => spawn falha: push_error e o gate M6-A1 reprova; não há fallback silencioso)
3. Para cada sala r em ordem de id, exceto start_room (inclui a sala da saída):
   t = rng_dungeon.bounded(3)      # 0 -> potion_hp, 1 -> potion_sp, 2 -> nenhuma poção
   se t < 2: item poção em pick(r)
   item gold em pick(r)
```

- Os ids seguem a ordem de criação: 0 é a poção inicial, 1 é a chave e depois vêm os itens das salas.
- "Ressortear de forma determinística" (GDD §4.6) é implementado como **filtrar e depois sortear**, que é equivalente e não precisa de laço.
- `test_room` e `automap_fixture` ficam **sem itens** (§1).
- Se `free_cells` de uma sala vier vazia (improvável, porque a sala tem no mínimo 4×4), aquele item é pulado **sem consumir RNG**. Isso precisa estar documentado num comentário.

### 3.4 Passo 3 — interação (`_step_use` + coleta)

Ordem fixa dentro do passo 3:

1. **Portas** (com `use`): vale a regra atual (Chebyshev ≤ 1, de frente, `along > 0 and side <= along`), na ordem de `dungeon.doors`, e só a primeira porta elegível é tratada. As portas elegíveis passam a ser:
   - `DOOR_CLOSED` → `DOOR_OPEN` (como hoje);
   - `DOOR_LOCKED` **com `player.key == true`** → `DOOR_OPEN`, `events += "unlock:<id>"`. A chave **não** é consumida.
   - `DOOR_LOCKED` sem chave: a porta não muda, `events += "locked_no_key"` e ela **não** conta como "tratada" (a busca continua para as portas seguintes).
   - Toda abertura faz `flow_dirty = true`.
2. **Saída** (com `use`): se a célula do jogador é o `EXIT` (`dungeon.exit_cell`) e `player.key`, então `exit_used = true`. Sem chave nada acontece, e a view mostra "Você precisa da Chave da Saída".
3. **Coleta automática** (sem `use`, em todo tick): para cada item com `taken == false` em ordem de id, se `(cell_x, cell_z) == (player.cell_x(), player.cell_z())`, então `taken = true` e:
   `potion_hp += 1` | `potion_sp += 1` | `key = true` | `gold += GOLD_PER_PILE`; `events += "pickup:<id>"`.
   Não há limite de inventário.

### 3.5 Passo 4 — poções (`_step_quaff`)

```
if input.quaff == 1:
    if potion_hp > 0: potion_hp -= 1; ganho = min(hp + 40, hp_max) - hp; hp += ganho; events += "quaff:1:<ganho>"
    else: events += "quaff_empty:1"
elif input.quaff == 2:
    if potion_sp > 0: potion_sp -= 1; idem com stamina/stamina_max/50; events += "quaff:2:<ganho>"
    else: events += "quaff_empty:2"
```

- Beber com a barra cheia é permitido e **consome** a poção (o ganho é 0). Isso é uma decisão explícita deste plano.
- Beber é permitido atordoado, golpeando ou bloqueando.
- O núcleo bebe uma poção **por tick** com `quaff != 0`. Quem garante "uma por toque de tecla" é o `InputSampler`, que passa a emitir `quaff` só na **borda de subida** de `quaff_hp`/`quaff_sp` (mesmo padrão de `_prev_use`).

### 3.6 Passo 5 — abates (`Combat.step_player_swing`)

Única mudança: na transição `e.state → "DEAD"` causada pelo golpe, fazer `world.killed_now.append(e.id)`. Números, ordem e `swing_hits` ficam como estão.

### 3.7 Passo 8 — vigor, XP e nível

Depois de `Combat.regen(self)`, chamar `ItemsSim.apply_xp(world)`:

```
for id in killed_now (ordem crescente):
    t = enemies[id].type
    xp += 0 if t == "dummy" else EnemySim.TYPES[t]["xp"]
while level < LEVEL_MAX and xp >= LEVEL_XP[level + 1]:
    level += 1; hp_max += 20; stamina_max += 10; hp = hp_max; events += "level:<level>"
```

- `stamina` **não** é restaurado na subida (o GDD só restaura a vida). Só o máximo sobe.
- Subir dois níveis no mesmo tick é possível (por exemplo, `xp` 240 + esqueleto 25 = 265 → nível 3, +40 `hp_max`).
- O dano maior vale a partir do próximo golpe, porque `sword_damage(level)` é lido no passo 5.

### 3.8 Passo 10 — condições terminais (`_step_terminal`)

Avaliadas nesta ordem de prioridade, e a primeira verdadeira vence:

1. `player.hp <= 0` → `terminal = "DEAD"`;
2. `exit_used` → `terminal = "ESCAPED"`;
3. `tick >= K_MAX` → `terminal = "TIMEOUT"`.

Depois disso, `step()` já congela tudo (o código atual só faz `tick += 1` e `_step_hash()` quando `terminal != "NONE"`). Isso não muda, mas os transitórios também precisam ficar vazios nos ticks congelados. A cadeia continua sendo emitida até K.

### 3.9 Getters novos (somente leitura)

- `get_items() -> Array` (cópias);
- `get_inventory() -> Dictionary` = `{potion_hp, potion_sp, key, gold, level, xp}`;
- `get_terminal() -> String`;
- `get_events() -> Array` (cópia);
- `get_exit_cell()` já existe;
- `get_player_status()` ganha `level` e `xp`. As chaves existentes não mudam.

### 3.10 Ordem final de `WorldSim.step()`

```
1  tick += 1; zera killed_now/exit_used/events; terminal -> só hash   7  Combat.resolve_incoming (inalterado)
2  player.pre_step + player.step                                    8  Combat.regen + ItemsSim.apply_xp   ← NOVO
3  _step_use (porta trancada, EXIT) + ItemsSim.collect   ← NOVO     9  automap.mark
4  _step_quaff                                          ← NOVO     10 _step_terminal                     ← NOVO
5  Combat.step_player_swing (+ killed_now)                          11 _step_hash
6  EnemySim.step_all
```

### 3.11 Piloto — `Pilot` (`game/sim/pilot.gd`; GDD §5.6)

`static func create(seed) -> Pilot` cria `rng = RngPcg32.create(seed, RngPcg32.STREAM_PILOT)`. `func next_input(world) -> IntInput` é chamado **antes** de cada `world.step()`. O piloto só lê o mundo e mantém um cache próprio (`flow: PackedInt32Array`, `flow_target`, `flow_key: bool`, `doors_sig: String`, contador de travamento).

**Alvo de navegação.** Se `player.key == false`, o alvo é a célula do item `key`. Senão, é `dungeon.exit_cell`.

**Campo de fluxo do piloto.** É uma BFS-4 a partir do alvo, na ordem N, L, S, O. `SOLID` bloqueia. `DOOR_LOCKED` bloqueia se `key == false` e passa se `key == true`. `DOOR_CLOSED`, `DOOR_OPEN`, `FLOOR` e `EXIT` passam. O campo é recalculado quando o alvo, `key` ou o estado de alguma porta muda. Próxima célula = o primeiro vizinho (N, L, S, O) com `flow == flow[atual] − 1`.

**Direção (sem float, sem atan2).** Para um ponto-alvo `(tx, tz)` em `u`:
```
dx = tx - p.pos_x; dz = tz - p.pos_z; fx = cos_q16(angle); fz = sin_q16(angle)
along = (dx*fx + dz*fz) >> 16
lat   = (dz*fx - dx*fz) >> 16          # > 0 => o alvo está no sentido de ângulo crescente (turn > 0)
if along <= 0: turn = 48 if lat >= 0 else -48
else:          turn = clamp_i(div_trunc(lat * 652, along), -48, 48)      # atan(x) ≈ x rad; 4096/2π ≈ 652
facing = along > 0 and abs_i(lat) * 1024 <= along * 859                  # dentro de ±40°
```
O sinal de `lat` precisa ser conferido pelo teste PILOT-AUX-1, com `turn` positivo levando `angle` na direção de `(−sin a, cos a)`.

**Prioridades de decisão em cada tick** (a primeira que se aplica produz o input):

1. **Terminal:** se `world.terminal != "NONE"`, devolve o input nulo.
2. **Poção:** se `hp < 30` e `potion_hp > 0` e o piloto não bebeu no tick anterior, `quaff = 1`. Se `stamina < 12`, `potion_sp > 0` e há inimigo engajado, `quaff = 2`. O restante do input do tick segue as regras abaixo.
3. **Fuga:** com `key == true` e a distância BFS do jogador ao `EXIT` ≤ 8 células, **não engaja** o Guardião: segue o fluxo e, sobre o `EXIT`, envia `use = 1`. A única exceção é bloquear quando o Guardião está em `WINDUP` no alcance (item 4a).
4. **Combate:** o alvo é o inimigo não-`DEAD`, `awake`, com a menor distância Chebyshev (em `u`) ≤ 4096 e com `EnemySim.los` verdadeira. Em empate, vence o menor id.
   - a. Se `e.state == "WINDUP"`, `cheb(e, p) <= reach + 384` e o golpe do jogador não está em `WINDUP`/`ACTIVE`: `block = 1`, `move = 0`, mira em `e`.
   - b. Senão, se `swing_state == "IDLE"`, `stamina >= 12`, `facing` e `along <= 1638 + half(e)`: `attack = 1`.
   - c. Senão: mira em `e` com `move = 1` se `cheb > 1400`, ou `move = 0` caso contrário.
5. **Navegação:** mira no centro da próxima célula do fluxo.
   - Se essa célula é `DOOR_CLOSED`, ou `DOOR_LOCKED` com chave, o jogador está a Chebyshev ≤ 1 dela e `facing` é verdadeiro, envia `use = 1` e `move = 0`.
   - Senão, `move = 1` se `facing` (ou se `along > 0 and abs(lat) <= along`), ou `move = 0` caso contrário.
   - **Exploração 1/16:** se `rng.bounded(16) == 0`, `strafe = rng.bounded(2) * 2 − 1` neste tick.
6. **Destravamento:** se `move == 1` por 45 ticks seguidos e a posição variar menos de 64 u, então durante 20 ticks: `move = −1` nos 10 primeiros, `strafe = ±1` (sorteado uma vez pelo `rng` do piloto) e mira mantida.

O piloto **nunca** chama `step()` e **nunca** muda campos do mundo. O PILOT-AUX-2 confere isso comparando `StateHash.canon(world)` antes e depois de `next_input`.

---

## 4. Apresentação, sprites, proporção visual e áudio

Viewport 640×360, `NEAREST`, *stretch* inteiro (`project.godot` não muda). Todos os sprites do perfil `free` medem **32×32 px**. Os identificadores `item.potion_hp`, `item.potion_sp`, `item.key`, `item.gold` e `exit.portal` **já existem** em `asset_map.json` e em `CREDITS.md`, então nenhum asset novo é necessário. A escala é sempre uniforme (só `flip_h` é permitido). Camadas: mundo 3D, `WeaponView` (CanvasLayer 1), `HUD` (2), automapa (3) e **`EndScreen` (4, nova)**.

### 4.1 Itens no mundo (`item_view.gd`, nós `Items/item_<id>`)

Os itens são `Sprite3D` com `billboard = BILLBOARD_FIXED_Y`, `shaded = false`, `alpha_cut = ALPHA_CUT_DISCARD` e `texture_filter = NEAREST`. Posição: `x = (cell_x*2048 + 1024)/1024`, `z = −(cell_z*2048 + 1024)/1024`, ou seja, o centro da célula, na mesma convenção dos inimigos.

| Tipo | Identificador | `pixel_size` | Altura no mundo | `position.y` (base) | Animação (só visual) |
|---|---|---|---|---|---|
| `potion_hp` | `item.potion_hp` | 0,0125 | 0,40 m | 0,20 | *bob* 0,03 m a 1 Hz |
| `potion_sp` | `item.potion_sp` | 0,0125 | 0,40 m | 0,20 | *bob* 0,03 m a 1 Hz |
| `gold` | `item.gold` | 0,0125 | 0,40 m | 0,20 | sem *bob*; brilho `modulate` 1,0↔1,2 a 2 Hz |
| `key` | `item.key` | 0,015625 | 0,50 m | 0,25 | *bob* 0,05 m a 1 Hz + pulso `modulate` 1,0↔1,4 (destaque do objetivo) |

- Proporção: todo item fica **abaixo** do joelho de um esqueleto (1,6 m) e menor que o rato (1,0 m). Com a câmera a 1,5 m e FOV vertical de 75°, uma poção a 3 m ocupa ≈ 31 px de altura e a chave ≈ 39 px. O item nunca pode ser maior que um inimigo.
- Item com `taken == true` → `visible = false` no mesmo quadro. Os nós não são destruídos, o que mantém a contagem estável para o teste de cena.
- O portal do `EXIT` já é construído por `dungeon_view._build_exit`. Enquanto `key == false`, ele fica com `modulate` 0,5 (apagado); com a chave, vai a 1,0 com pulso, indicando que a saída está disponível.

### 4.2 HUD (`hud_daggerfall`): legibilidade e dados de M6

A geometria do `Frame` (640×48 em y = 312), o retrato (8–40) e as barras `HpBack` (x 48) e `SpBack` (x 60) **não mudam**. Todos os textos passam a ter **fonte 12** e contorno de 3 px `#141210`.

| Nó (relativo ao `Frame`) | x | y | Texto / formato | Cor |
|---|---|---|---|---|
| `HpText` (existe) | 74–176 | 4–22 | `Vida 100/100` | **`#ff6a5a`** (antes `#b02020`) |
| `SpText` (existe) | 74–176 | 24–42 | `Vigor 100/100` | **`#5ae07a`** (antes `#20a040`) |
| `PotText` (novo) | 180–266 | 4–22 | `PV 1  PF 0` (poções de Vida/Vigor) | `#e0d0a0` |
| `KeyText` (novo) | 180–266 | 24–42 | `Chave: não` / `Chave: SIM` | `#e0d0a0` / `#ffd84a` com chave |
| `Compass` (existe) | 270–370 | **4–22** (antes 12–36) | `L 0°` | `#e0d0a0` |
| `LvlText` (novo) | 270–370 | 24–42 | `Nível 1`, centralizado | `#e0d0a0` |
| `Message` (existe) | 400–632 | **4–22** (antes 12–36) | mensagens | `#f0e4c0` |
| `StatText` (novo) | 400–632 | 24–42 | `Ouro 0 · XP 0/100` (no nível 3: `XP 250 (máx)`) | `#e0d0a0` |

- Nenhum nó pode invadir a área 3D (y < 312 em coordenadas de tela) nem se sobrepor a outro. O gate SCENE confere os retângulos.
- **Mensagens novas** (2 s; prioridade: terminal > nível > chave/destranca > coleta > poção > M4 existentes). São derivadas de `get_events()` e do diff de `get_inventory()`:
  - `pickup` → "Pegou Poção de Vida", "Pegou Poção de Vigor", "Pegou a Chave da Saída!" ou "+10 de ouro";
  - `quaff:1:N` → "Bebeu Poção de Vida (+N)"; `quaff:2:N` → "Bebeu Poção de Vigor (+N)"; `quaff_empty` → "Sem poções";
  - `level:n` → "Nível n! Vida restaurada";
  - `unlock` → "A porta da saída se abre";
  - `locked_no_key` → "Trancada. Encontre a chave";
  - `use` sobre o `EXIT` sem chave (detectado pela view) → "Você precisa da Chave da Saída".

### 4.3 Tela final (`end_screen.tscn/.gd`; GDD §4.6)

- `CanvasLayer` com `layer = 4`, oculta enquanto `terminal == "NONE"`. Contém:
  - fundo `ColorRect` 640×360 preto com `modulate.a = 0.55`;
  - `Panel` de pergaminho com **320×200 px em (160, 80)**, cor `#d8c8a0` e borda de 4 px `#5a4630` (`StyleBoxFlat`).
- Conteúdo (fonte 20 no título e 12 nas linhas, cor `#2a1e10`, centralizado):

| Terminal | Título | Cor do título |
|---|---|---|
| `ESCAPED` | "VOCÊ ESCAPOU!" | `#205020` |
| `DEAD` | "VOCÊ MORREU" | `#801818` |
| `TIMEOUT` | "O TEMPO ACABOU" | `#604010` |

  Linhas: `Nível N`, `Ouro G`, `Inimigos abatidos K` (contagem de `DEAD` na view, sem o boneco), `Tempo T ticks (mm:ss)` (a partir do tick terminal) e, por fim, `Enter: nova partida (semente+1) · Esc: sair`.
- Enter recarrega `main.tscn` com `seed + 1`, porque cria um mundo novo e não mexe no anterior. Esc fecha o jogo. Em `--headless`, nada é lido do teclado.

### 4.4 Áudio (procedural, só apresentação; sem arquivos novos)

Mesmo motor da rodada 2: `AudioStreamGenerator` mono a 22 050 Hz, RNG próprio da view e geração pulada em silêncio no headless. Os eventos vêm de `get_events()` e da borda de `get_terminal()`.

| Evento | Som |
|---|---|
| coleta de poção | dois senos curtos 880→1320 Hz, 60 ms cada |
| coleta de ouro | "tlim": senos 2000 + 3000 Hz, 40 ms, decaimento exponencial |
| coleta da chave | arpejo Dó-Mi-Sol (523/659/784 Hz), 90 ms por nota |
| beber poção | "glup": 3 rajadas de ruído passa-baixa de 300 Hz, 50 ms cada, 40 ms de intervalo |
| `quaff_empty` / trancada sem chave | clique seco de ruído de 20 ms + seno de 120 Hz por 60 ms |
| subida de nível | arpejo ascendente de 4 notas (523/659/784/1047 Hz), a última com 300 ms |
| destrancar | clangor metálico: ruído passa-banda de 1,5 kHz por 120 ms + baque de 200 Hz |
| `ESCAPED` | acorde maior (262+330+392 Hz), 1,2 s com *fade-out* |
| `DEAD` | dente-de-serra descendo de 220 a 55 Hz em 1,0 s |
| `TIMEOUT` | dois toques de gongo de 110 Hz, 600 ms cada |

Os sons das rodadas 2 e 4 continuam valendo.

### 4.5 `main.gd`: modo vitrine (corrige a mídia estática) e controle

- **Sem argumentos de usuário e fora do headless**, o jogo abre em **modo vitrine**: masmorra da semente 1, com o **piloto** (`Pilot.create(1)`) gerando os inputs. O automapa aparece (só na view) nos ticks 300–420. Na primeira entrada real do jogador (tecla, botão do mouse ou movimento do mouse acima de 4 px), o piloto é desligado e o `InputSampler` assume, com a mensagem "Controle manual" por 2 s.
  - Consequência: qualquer captura feita com `godot --path game` mostra movimento, portas, inimigos, combate, coleta de itens, automapa e, se a captura for longa, a tela final.
- `--manual`: abre direto no controle do jogador, como o comportamento atual sem argumentos.
- `--pilot`: força o piloto, aceita `--seed=N` e não devolve o controle.
- `--demo` (rodada 4) **continua igual**.
- Item, tela final e portal são construídos/atualizados em `_present()` a partir de getters. Nada escreve no núcleo.

### 4.6 Runner (`headless_runner.gd`)

- `--mode=pilot`: `Pilot.create(seed)`, depois `input = pilot.next_input(world)` e `world.step(input)` a cada tick, até `--ticks`. O padrão de `--ticks` no modo pilot é 18000. Com `--record`, grava a trilha usada.
- Relatório: `terminal` e **`terminal_tick`** (o primeiro tick em que `terminal != "NONE"`, ou −1). As demais chaves continuam iguais.
- `--gates=M6` (isolado) e `--gates=M1,M2,M3,M4,M5,M6`.

---

## 5. Testes

### 5.1 Gates de M6 (`tests/gates/m6_gates.gd`)

Os gates podem ajustar campos do mundo antes ou entre ticks (fixture), como nas rodadas anteriores. "Teleportar" = definir `pos_x/pos_z` para o centro de uma célula e zerar `vel`.

| ID | Cenário | Asserção exata |
|---|---|---|
| M6-A1 | sementes 1…100, `create(s, false)` | exatamente 1 item `key`; a sala dele não é `start_room` nem `exit_room`; `bfs_no_locked` a partir da célula inicial alcança a célula da chave; nenhum item fica em `SOLID`, porta, `EXIT`, célula inicial ou célula de inimigo, e não há dois itens na mesma célula; a sala inicial tem exatamente 1 item, e ele é `potion_hp`; mesma semente → mesma lista de itens |
| M6-A2 | test_room; o fixture põe `potion_hp = 2`, `potion_sp = 1`, `hp = 80`, `stamina = 30` | tick 1 `quaff=1` → `hp == 100` (sem passar de 100), `potion_hp == 1`; tick 2 `quaff=1` com hp cheio → `hp == 100`, `potion_hp == 0`; tick 3 `quaff=1` com o inventário vazio → `hp`, `potion_hp` e todo o `canon` exceto `tick`/regeneração idênticos ao de um mundo gêmeo com `quaff=0`; tick 4 `quaff=2` → `stamina == min(30+regen+50, 100)` e `potion_sp == 0`; **invariante** em 600 ticks com `quaff` aleatório: `hp <= hp_max` e `stamina <= stamina_max` |
| M6-A3 | `create(1, false)`, com todos os inimigos forçados a `DEAD` (fixture) para isolar | (a) jogador teleportado para o `EXIT` com `key = false`, `use=1` → `terminal == "NONE"` após o tick; (b) `key = true`, `use=1` no tick t → `terminal == "ESCAPED"` **após o step do tick t**; (c) porta trancada: jogador na célula do lado de fora de uma porta `DOOR_LOCKED`, olhando para ela; `use` sem chave → continua `DOOR_LOCKED`; com `key = true`, `use` → `DOOR_OPEN` no mesmo tick e `key` continua `true` |
| M6-A4 | test_room; `inject_hit(px+1000, pz, 100)` antes do tick 1; depois 120 ticks de input aleatório (semente fixa) com `move`, `turn`, `attack`, `use` e `quaff` | após o tick 1: `hp == 0`, `terminal == "DEAD"`; para k = 2…121, `canon(s_k)` sem a chave `tick` é **idêntico** a `canon(s_1)` sem `tick`; `tick` cresce de 1 em 1; a cadeia continua avançando (`chain` muda a cada tick) |
| M6-A5 | test_room + rato à frente (`add_enemy("rat", 6020, 15360)`) e boneco em (8,4); o fixture põe `xp = 95` | o tick em que o rato vai a `DEAD` termina com `level == 2`, `xp == 105`, `hp_max == 120`, `hp == 120`, `stamina_max == 110`, `stamina` **não** restaurado; o golpe seguinte no boneco tira exatamente **30**. Caso B: `xp = 240` + esqueleto abatido (+25) → `level == 3`, `hp_max == 140`, `stamina_max == 120`, dano 35. Caso C: `level == 3`, `xp = 1000` + abate → continua `level == 3`. Caso D: o boneco abatido dá 0 XP |
| M6-A6 | **fim a fim:** `--mode=pilot`, sementes 1…50, até `terminal != "NONE"` ou K = 18000 | `ESCAPED` em **≥ 40 de 50** (80%). Informar a contagem por terminal (`ESCAPED`/`DEAD`/`TIMEOUT`), a média de `terminal_tick` e as sementes que falharam. O gate pode parar a simulação no tick terminal (o estado fica congelado depois dele). **Se o limiar não for atingido, ajustar só a estratégia do piloto (§3.11), nunca as regras do jogo nem as tabelas** |

**Auxiliares obrigatórios (M6-AUX):**
1. **Coleta:** o jogador passa por cima de cada tipo de item (fixture com 4 itens na test_room, ids 0…3) → `taken`, inventário e `gold += 10`. Parado em cima de um item já coletado, nada muda nos ticks seguintes.
2. **Isolamento de RNG:** `create(s, false)` para s = 1…20 → os inimigos (`to_canon()`) são iguais aos de um `EnemySim.spawn` executado sem `ItemsSim.spawn`, e a grade tem o mesmo SHA de `DungeonGen.generate(s)`. Em 900 ticks de `walker_inputs`, `rng_dungeon.state_hex()` não muda depois do `create`, e o piloto nunca altera `rng_dungeon` nem `rng_ai`.
3. **Sem itens nas fixtures:** `create(s, true)` e `create(s, false, "automap")` → `items == []`; a cadeia de `R1` é igual a `523fef79…53d6` (valor fixo de $E_4$).
4. **TIMEOUT:** test_room com o fixture `tick = 17995`; 10 ticks nulos → `terminal == "TIMEOUT"` após o tick que atinge 18000, e não antes.
5. **Prioridade terminal:** no mesmo tick, `exit_used` e `hp <= 0` → `DEAD`.
6. **Tipos:** `StateHash.assert_types` aceita `items[]` com os 4 tipos, `taken` verdadeiro e falso, e `terminal` nos 4 valores.
7. **Sampler:** com `Input.action_press("quaff_hp")` mantido por 3 amostras, `quaff == 1` só na primeira.

**Piloto (PILOT-AUX):**
1. Direção: com o jogador em (5,7), `angle = 0` e o alvo em (5,3) (z menor), o sinal de `turn` leva `|lat|` a diminuir. Em ≤ 40 ticks, `facing` fica verdadeiro.
2. Somente leitura: `StateHash.canon(world)` é idêntico antes e depois de 1000 chamadas de `next_input` sem `step()`.
3. Determinismo: duas instâncias do piloto na mesma semente produzem trilhas idênticas por 3000 ticks.

### 5.2 Testes de contrato (rodada 5)

1. `python3 tools/lint_sim.py` → exit 0, agora cobrindo `items_sim.gd` e `pilot.gd`.
2. `tools/run_gates.sh` num checkout limpo → todos PASS, exit 0.
3. **Preservation:** todas as 68 linhas PASS de $E_4$ continuam PASS, com as mesmas asserções e trilhas. As cadeias fixas de R1 e R1-M5 continuam idênticas (§1).
4. **R1-pilot:** duas instâncias no mesmo processo, semente 1, piloto, 3000 ticks → `chain` iguais.
5. **R2 (novo gate):** duas execuções independentes do runner via `OS.execute(OS.get_executable_path(), ["--headless", "--path", <game>, "-s", "res://scripts/headless_runner.gd", "--", "--seed=1", "--mode=pilot", "--ticks=3000", "--output=…"])` → `chain_final` iguais.
6. **R3-pilot:** semente 2, piloto, 3000 ticks, com e sem `main.tscn` → `chain` iguais. A cena não pode alterar o resultado mesmo com `item_view` e `end_screen` ativos.
7. **R4 (novo gate):** sementes 1…3, `--mode=pilot --ticks=6000 --record` → trilha; `--mode=replay` da trilha → `chain_final` igual.
8. **SCENE (estendido):** `Items/item_<id>` é `Sprite3D` com `BILLBOARD_FIXED_Y` e `pixel_size` conforme §4.1; o número de nós é igual a `items.size()`; `EndScreen` existe, `layer == 4` e começa invisível; depois de forçar `terminal = "ESCAPED"` num mundo de teste e chamar `_present`, ele fica visível e o título é "VOCÊ ESCAPOU!"; `PotText`, `KeyText`, `LvlText` e `StatText` existem com o texto inicial do §4.2; os rótulos da HUD têm `font_size == 12` e retângulos dentro do `Frame`, sem sobreposição entre si.
9. **ASSETS:** acrescentar `item.potion_hp`, `item.potion_sp`, `item.key` e `item.gold` → **23** identificadores, cada um uma textura 32×32 no perfil `free`.
10. **VITRINE (novo, cena em headless):** instanciar `main.tscn` com `showcase` forçado (por exemplo, a propriedade `force_showcase = true` antes de `_ready`) e fazer 600 `_physics_process` simulados → o jogador saiu da célula inicial e o mundo avançou 600 ticks com `terminal` válido.
11. Runner: `--gates=M6` isolado e `--gates=M1,M2,M3,M4,M5,M6` → exit 0.

### 5.3 Evidência que o Desenvolvedor deve deixar no commit

- A saída completa de `tools/run_gates.sh` em `game/runs/gates_iter5.txt` (versionado), com `N PASS / 0 FAIL`.
- A linha de M6-A6 com a contagem por terminal e a lista das sementes que falharam.
- Os nomes M6-A1…A6, M6-AUX-1…7, PILOT-AUX-1…3, R1-pilot, R2, R3-pilot, R4 e VITRINE presentes na saída.

---

## 6. Correções de lacunas de $E_4$ (não são marcos)

### 6.1 Mídia demonstrativa
Resolvida pelo modo vitrine (§4.5), que é o comportamento padrão sem argumentos e que o gate VITRINE verifica. Com isso, os dois quadros capturados pelo auditor diferem, porque o piloto anda e gira desde o tick 1, e mostram inimigos, portas e itens da masmorra gerada. Comando de captura recomendado: `godot --path game` (sem argumentos). O `--demo` da rodada 4 continua disponível.

### 6.2 HUD legível
§4.2: fonte 12, contorno 3 px, vermelho `#ff6a5a` e verde `#5ae07a`. É verificado em SCENE (§5.2-8).

### 6.3 Vazamento de ObjectDB (higiene, não é gate)
Rodar `godot --headless --verbose --path game -s res://tests/run_gates.gd` e identificar os objetos vazados. Candidatos: `AudioStreamGenerator`/*playback* em `AudioView`, o cache estático de texturas em `AssetResolver` e instâncias de `main.tscn` nos testes de cena sem `free()`. Corrigir se for trivial, sem alterar hash nenhum. Se não for trivial, registrar a causa num comentário.

---

## 7. Ordem de entrega e critério de pronto (Definition of Done para o Desenvolvedor)

Entrega incremental, **um commit por prioridade**. Cada commit deixa `tools/run_gates.sh` com exit 0.

| Prioridade | Conteúdo | Commit |
|---|---|---|
| **P0 (obrigatório)** | `items_sim.gd`; `world_sim.gd` (passos 3, 4, 8 e 10, porta trancada, transitórios, getters); `combat.gd` (`killed_now`); `state_hash.gd` (`items`); `m6_gates.gd` com M6-A1…A5 e M6-AUX-1…7; `input_sampler.gd` (borda do `quaff`) | `feat: implementacao iteracao 5 (M6 nucleo)` |
| **P1 (obrigatório)** | `pilot.gd`; `--mode=pilot` e `terminal_tick` no runner; M6-A6; PILOT-AUX-1…3; R1-pilot, R2, R3-pilot e R4 | `feat: implementacao iteracao 5 (M6 piloto)` |
| **P2** | `item_view.gd`, `end_screen`, HUD (§4.2), áudio (§4.4), modo vitrine (§4.5); SCENE, ASSETS (23) e VITRINE; ObjectDB (§6.3); `game/runs/gates_iter5.txt` | `feat: implementacao iteracao 5 (apresentacao, HUD e vitrine)` |

Critério de pronto da rodada:

1. Todos os arquivos de §2 criados ou alterados; `lint_sim.py` limpo; nenhum erro de parse num checkout limpo.
2. `tools/run_gates.sh` → todas as linhas PASS (Preservation M1–M5, M6-A1…A6, auxiliares, contrato) e exit 0.
3. R1, R2, R3 e R4 com `chain` iguais; R1 da test_room igual a `523fef79…53d6`.
4. Interativo: abrir o jogo sem argumentos mostra o piloto jogando. Uma tecla devolve o controle. Itens aparecem no chão e são coletados ao passar por cima. A chave abre a porta da saída, e `use` sobre o portal termina em "VOCÊ ESCAPOU!". A HUD mostra poções, chave, nível, XP e ouro em fonte legível.
5. Se o orçamento acabar, o que já estiver verde **tem de estar commitado**, P0 antes de tudo.

---

## 8. Riscos específicos desta rodada

| Risco | Mitigação no plano |
|---|---|
| Posicionamento de itens mudar inimigos ou grade (regressão de M2/M4) | itens só depois de `EnemySim.spawn`, consumindo só `rng_dungeon`; M6-AUX-2 compara com o spawn isolado e com o SHA da grade |
| Cadeias fixas de test_room mudarem | test_room e automap_fixture sem itens; XP do boneco = 0; M6-AUX-3 confere `523fef79…` |
| Piloto abaixo de 80% (M6-A6) | ajustar só a estratégia (prioridades, raio de engajamento, fuga do Guardião, destravamento); informar a taxa real; nunca mexer nas regras |
| Piloto escrever no mundo | ele só lê; PILOT-AUX-2 compara o `canon` antes e depois |
| Tempo de execução dos gates (50 × até 18000 ticks com hash) | M6-A6 para no tick terminal; R2/R3/R4 com 3000 a 6000 ticks |
| `atan2` ou float entrando pelo piloto | direção por `lat/along` inteiros (§3.11); o linter cobre `pilot.gd` |
| Segurar a tecla "1" esvaziar o inventário | `quaff` por borda de subida no sampler (M6-AUX-7) |
| Morte do jogador congelar gates de M4 | os gates de M4 já usam `hp_max = 100000` nos cenários de acúmulo; os demais não chegam a 0 (DEMO-4 termina com hp 97) |
| Vitrine afetar o núcleo | o piloto na view só gera `IntInput`, como o replay; VITRINE e R3-pilot verificam |
| Chave inalcançável sem atravessar a sala da saída | filtro `bfs_no_locked` antes do sorteio (§3.3); M6-A1 em 100 sementes |
