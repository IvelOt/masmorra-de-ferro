# Plano de Iteração 3 — Condição C2 (HoH Estático), Execução 2

- **Papel:** Planejador ($D_t$). Este documento não contém código GDScript; contém a especificação que o Desenvolvedor implementa.
- **Base:** `GDD.md` (§1 a §5, §7), o código aceito nas rodadas 1 e 2 (`game/sim/`, `game/view/`, `game/input/`, `game/tests/`) e `relatorio_provas.json` da rodada 2.
- **Situação herdada (relatório de provas):** M1, M2, M3 e M5 verificados (35/35 gates PASS). Lacunas apontadas:
  1. **M4 inexistente** (não há `enemy_sim.gd` nem gates M4; só `enemy_view.gd` visual);
  2. **M6 inexistente** (não há `items_sim.gd`, XP, níveis, chave, estados terminais `ESCAPED/DEAD`);
  3. **mídia de auditoria fraca**: `frame_1.png` e `frame_2.png` byte-idênticos, vista estática de corredor, sem inimigo, combate ou automapa;
  4. **HUD**: barras finas sem rótulo/valor; escudo cortado pela barra da HUD; bússola com rótulo "L" lido como incoerente.
- **Valores de referência medidos** pelo Planejador com o código atual (sonda headless sobre `dungeon_gen.generate`, sementes 1–100): toda sala ≥ 1 tem uma célula de saída (não sala, não sólida, 4-adjacente à sala) a ≤ 9 células BFS do centro; o número de salas candidatas à chave (≠ 0, ≠ Saída, alcançáveis sem porta trancada) é ≥ 4 em todas as sementes; a distância BFS até a sala vizinha mais próxima chega a 38 células (semente 10) e a da Saída a 104 células (semente 7).

---

## 1. Marcos selecionados nesta rodada

| Ordem | Marco | Motivo |
|---|---|---|
| 1 | **M4 — Entidades e inimigos em billboard 2.5D** | Sucessor direto de M3 (`M3 → M4`), já desbloqueado; é a lacuna nº 1 do relatório. A fila `incoming_hits` e o `enemy_view` da rodada 2 foram feitos como fronteira para ele. |
| 2 | **M6 — Itens, progressão e condição terminal** | `{M4, M5} → M6`: M5 já foi aceito, então M6 fica desbloqueado assim que M4 estiver pronto **na mesma rodada**. Fecha o jogo (objetivo, vitória/fuga, morte) e o piloto do runner, que também resolve a lacuna de mídia (§9). |

Ordem obrigatória de implementação: **M4 inteiro (gates PASS) antes de começar M6**. Se M6 não fechar, M4 deve continuar entregue e verde.

**Correções transversais (não são marcos, são exigências de auditoria):**
- **Modo de atração** (§9): ao abrir o jogo sem argumentos, o piloto joga uma arena de demonstração com inimigos, itens, porta trancada, automapa e fuga. A captura externa passa a mostrar movimento, combate, inimigos e automapa sem depender de teclado.
- **HUD e arma** (§8.3, §8.4): barras mais largas com valores numéricos, inventário, nível/XP; escudo inteiro acima da HUD; bússola com a rosa dos ventos internacional.

**Fora do escopo:** quadros de 8 direções e animação quadro a quadro de inimigos (o perfil `free` tem **um** sprite 32 × 32 por tipo; ver §8.1); perfil de arte `daggerfall`; R5 interplataforma; qualquer asset novo em `game/assets/`.

---

## 2. Arquivos a criar / alterar

```
game/
  sim/
    enemy_sim.gd         # NOVO (M4): tabela de tipos, percepção+LOS, campo de fluxo, movimento, ataque
    items_sim.gd         # NOVO (M6): posicionamento (populate), coleta, poções, XP/nível, terminais
    world_sim.gd         # ALTERAR: passos 3,4,6,8,10; populate em setup_seed; setup_test("arena"); schema 3
    player_sim.gd        # ALTERAR: level, xp, gold, inventory; colisão com entidades (bloqueadores)
    combat.gd            # ALTERAR: dano da espada = 25 + 5·(level−1); XP pendente por abate
    dungeon_gen.gd       # ALTERAR: só acrescentar test_arena() (generate/test_room/test_door_room intocados)
    int_input.gd         # ALTERAR: só o comentário (quaff passa a ter efeito)
  input/
    input_sampler.gd     # ALTERAR: quaff_hp/quaff_sp como borda (1/2)
    pilot.gd             # NOVO: piloto inteiro em malha fechada (lê o mundo, devolve IntInput)
  view/
    enemy_view.gd        # ALTERAR: textura/tamanho por tipo, efeitos por estado (§8.1)
    item_view.gd         # NOVO: Sprite3D billboard por item, some quando coletado
    hud_daggerfall.tscn/.gd   # ALTERAR: barras largas, valores, nível/XP, inventário, mensagens M4/M6
    weapon_view.gd       # ALTERAR: escudo em escala 3 e novas poses (§8.4)
    end_screen.tscn/.gd  # NOVO: pergaminho de fim de partida (CanvasLayer layer = 4)
    automap_overlay.gd   # ALTERAR: itens não coletados em células visitadas (§8.6)
    sfx_view.gd          # ALTERAR: sons de inimigos, itens, nível, fim (§10)
    main.tscn / main.gd  # ALTERAR: ItemView, EndScreen, modo de atração, --play, --arena
  scripts/
    headless_runner.gd   # ALTERAR: --mode=pilot, --record, --with-view, --arena; schema 3
  tests/
    run_gates.gd         # ALTERAR: executa M1, M2, M3, M5, M4, M6 (+ gates de cena)
    gates/gate_m4.gd     # NOVO
    gates/gate_m6.gd     # NOVO
tools/
  lint_sim.py            # ALTERAR: também verificar game/input/pilot.gd com as regras do núcleo (§7.1)
```

**Não reescrever** (preservados): `fixed_math.gd`, `trig_table.gd`, `rng_pcg32.gd`, `grid.gd`, `state_hash.gd`, o algoritmo de `dungeon_gen.generate()`, `test_room()`, `test_door_room()`, `automap_sim.gd`, a convenção núcleo→Godot `(pos_x/1024, y, −pos_z/1024)`, `gate_m1.gd`, `gate_m2.gd`, `gate_m3.gd`, `gate_m5.gd` (só ajustar se uma assinatura mudar, **sem** mudar asserções nem valores esperados).

Linter: as regras do núcleo valem para `enemy_sim.gd`, `items_sim.gd` e também para `input/pilot.gd` (ver §7.1). Em `sim/` não pode haver literal com ponto decimal, `float`, `floor(`, `round(`, `delta`, `signal`.

---

## 3. Constantes novas

### 3.1 Tipos de inimigo (`enemy_sim.gd`, `const TYPES: Dictionary` com chaves ordenadas no uso)

| `type` | `hp` | `speed` (u/tick) | `dmg` | `reach` (u) | `windup` | `cooldown` | `xp` | `half` (u) | Origem |
|---|---|---|---|---|---|---|---|---|---|
| `rat` | 20 | 100 | 5 | 1024 (1,0 m) | 8 | 30 | 10 | 256 | GDD §4.4; `half` do plano |
| `skeleton` | 50 | 68 | 12 | 1229 (1,2 m) | 18 | 45 | 25 | 384 | GDD §4.4 |
| `guardian` | 150 | 51 | 25 | 1434 (1,4 m) | 30 | 60 | 100 | 512 | GDD §4.4 |
| `dummy` | 100 | 0 | 0 | 0 | 0 | 0 | 0 | 384 | boneco de M3 (sem IA) |

Condição de projeto que o código deve **afirmar** num comentário: `reach > half + PLAYER_HALF` para os três tipos com IA (1024 > 640, 1229 > 768, 1434 > 896), para que um inimigo encostado no jogador esteja sempre no alcance.

| Constante | Valor | Arquivo |
|---|---|---|
| `SIGHT_CELLS_SQ` | 36 (raio de 6 células, distância euclidiana em células ao quadrado) | `enemy_sim.gd` |
| `LOS_MAX_STEPS` | 256 (limite de iterações do DDA) | `enemy_sim.gd` |
| `RAT_PERCENT` | 60 (sala comum: rato com 60%, esqueleto com 40%) | `items_sim.gd` (populate) |
| `POTION_HP_HEAL` / `POTION_SP_GAIN` | 40 / 50 | `items_sim.gd` |
| `LEVEL_XP` | `[0, 100, 250]` (nível 1, 2, 3; nível máximo 3) | `items_sim.gd` |
| `LEVEL_HP_BONUS` / `LEVEL_SP_BONUS` / `LEVEL_DMG_BONUS` | 20 / 10 / 5 por nível acima de 1 | `items_sim.gd` |
| `GOLD_MIN` / `GOLD_SPAN` | 10 / 21 (`amount = 10 + next_bounded(21)`, 10..30) | `items_sim.gd` |
| `GOLD_EXIT` | 50 (pilha fixa da Sala da Saída) | `items_sim.gd` |
| `SCHEMA_VERSION` | **3** | `world_sim.gd` |

Estados de inimigo como `String` no estado canônico: `"IDLE"`, `"CHASE"`, `"WINDUP"`, `"STRIKE"`, `"COOLDOWN"`, `"DEAD"`. Terminais: `"NONE"`, `"ESCAPED"`, `"DEAD"`, `"TIMEOUT"`.

---

## 4. Especificação do núcleo — M4 (`enemy_sim.gd`)

### 4.1 Entidade

Dicionário já existente, sempre em ordem crescente de `id`: `{id, type, pos_x, pos_z, half, hp, hp_max, state, state_ticks, awake}`. `spawn_enemy(type, pos_x, pos_z) -> int` em `world_sim.gd` cria com `hp = hp_max = TYPES[type].hp`, `half = TYPES[type].half`, `state = "IDLE"`, `state_ticks = 0`, `awake = false`, `id = enemies.size()`. `spawn_dummy()` passa a chamar `spawn_enemy("dummy", …)` (resultado idêntico ao da rodada 2).

### 4.2 Linha de visão (`los(grid, x0, z0, x1, z1) -> bool`) — DDA inteiro estilo Amanatides–Woo

Percorre as células cruzadas pelo segmento do centro do inimigo `(x0, z0)` ao centro do jogador `(x1, z1)`; só inteiros; `Grid.is_blocking` (sólido, porta fechada, porta trancada) bloqueia; a célula inicial não é testada.

```
cx, cz = cell_of(x0), cell_of(z0);   tx, tz = cell_of(x1), cell_of(z1)
dx = x1 − x0; dz = z1 − z0; sx = sign_i(dx); sz = sign_i(dz); adx = abs_i(dx); adz = abs_i(dz)
nx = (sx > 0) ? (cx+1)·CELL − x0 : x0 − cx·CELL      # distância até a 1ª fronteira em X
nz = (sz > 0) ? (cz+1)·CELL − z0 : z0 − cz·CELL
repetir até LOS_MAX_STEPS:
    se (cx, cz) == (tx, tz): devolver true
    se sx == 0:                passo Z
    senão se sz == 0:          passo X
    senão: comparar nx·adz com nz·adx       # nx/adx vs nz/adz sem divisão
        menor → passo X ; maior → passo Z
        igual (canto exato): se is_blocking(cx+sx, cz) ou is_blocking(cx, cz+sz): devolver false
                             passo X e passo Z juntos
    passo X: cx += sx; nx += CELL ;  passo Z: cz += sz; nz += CELL
    se is_blocking(cx, cz): devolver false
devolver false
```

### 4.3 Percepção (só em `IDLE`)

`dcx = cell_of(px) − cell_of(ex)`, `dcz = cell_of(pz) − cell_of(ez)`; acorda se `dcx² + dcz² ≤ 36` **e** `los(...)`. Ao acordar: `awake = true`, `state = "CHASE"`, `state_ticks = 0`, e executa a lógica de `CHASE` **no mesmo tick**. Inimigo acordado nunca volta a `IDLE`.

### 4.4 Campo de fluxo

- `flow: PackedInt32Array` (4096) em `world_sim.gd`, **fora do hash** (é função pura de `grid` e da célula do jogador). BFS a partir da célula do jogador, vizinhança-4 na ordem **N, L, S, O** = `DungeonGen.DIRS`, passável = `not Grid.is_blocking(t)`.
- Recalcular só quando a chave `(cell_of(px), cell_of(pz), grid.sha256())` mudar (abrir porta muda o `sha256`). Guardar a chave em `world.flow_key: String`.
- **Próxima célula** de um inimigo na célula `c` com `d = flow[c] > 1`: o primeiro vizinho, na ordem N, L, S, O, com `flow == d − 1`. Alvo = centro dessa célula. Se `d ≤ 1` (mesma célula ou vizinha do jogador): alvo = posição do jogador. Se `d < 0` (inalcançável): não se move neste tick.

### 4.5 Movimento e colisão de inimigos

```
mx = clamp_i(alvo_x − ex, −speed, speed);  mz = clamp_i(alvo_z − ez, −speed, speed)
eixo X: nx = ex + mx; se bloqueado(nx, ez) e não bloqueado_antes(ex, ez): cancela X (ex fica)
eixo Z: idem com nz, usando o ex já resolvido
bloqueado(x, z) = grid.box_hits_solid(x−h, z−h, x+h, z+h)
                  or sobrepõe(x, z, h, outra entidade viva qualquer, inclusive dummy)
                  or sobrepõe(x, z, h, jogador com PLAYER_HALF)
sobrepõe = abs_i(x − ox) < h + oh and abs_i(z − oz) < h + oh        # semiaberto: encostar não colide
```

- "Cancelar" = não aplicar o deslocamento do eixo (sem empurrão, sem prender à face). A regra "só cancela se **não** sobrepunha antes" evita travar entidades que testes colocam sobrepostas de propósito (M3-A3); no jogo normal nada nasce sobreposto.
- Diagonal não normalizada (cada eixo limitado a `±speed`), coerente com o estilo DOOM do jogador. Comentar no código.
- Entidades `DEAD` não colidem com nada.

### 4.6 Colisão jogador × entidade (`player_sim.step`)

`step(inp, grid, blocking, blockers: Array = [])`, `blockers` = `[[x, z, half], …]` das entidades vivas, em ordem de `id`, montado por `world_sim`. Por eixo, **depois** da resolução contra a grade: se a caixa do jogador sobrepõe algum bloqueador e **não** sobrepunha antes do movimento daquele eixo, então `pos = pos_antes_do_eixo` e `vel` daquele eixo `= 0`. Com `blockers = []` o caminho é bit a bit o da rodada 1/2 (M1-A*, M3-X2 não podem mudar).

### 4.7 Máquina de estados (passo 6, inimigos em ordem crescente de `id`, pula `DEAD` e `dummy`)

```
no_alcance(e) = max_i(abs_i(px − ex), abs_i(pz − ez)) <= reach  and  los(grid, ex, ez, px, pz)
IDLE:     percepção (§4.3); se acordou, cai em CHASE no mesmo tick
CHASE:    se no_alcance: state = WINDUP, state_ticks = 1 (não se move)   senão: mover (§4.5)
WINDUP:   state_ticks += 1; se state_ticks > windup:
              state = STRIKE, state_ticks = 1
              se no_alcance(e): world.inject_hit(dmg, ex, ez)   # resolvido no passo 7 do MESMO tick
STRIKE:   state = COOLDOWN, state_ticks = 1
COOLDOWN: state_ticks += 1; se state_ticks > cooldown: state = CHASE, state_ticks = 0 e executa CHASE no mesmo tick
```

Consequências que os gates verificam (golpe aceito em `WINDUP` no tick `T`): `STRIKE` no tick `T + windup`; próximo `WINDUP` no mínimo em `T + windup + cooldown + 1`; intervalo entre dois `STRIKE` = `windup + cooldown + 1` (esqueleto **64**, rato **39**, guardião **91**) ≥ `windup + cooldown` (GDD M4-A4).

**Morte (M4-A6):** no passo 5, quando a espada leva `hp ≤ 0`: `hp = 0`, `state = "DEAD"`, `state_ticks = 0` no mesmo tick, e `world.pending_xp += TYPES[type].xp` (consumido no passo 8, §5.4). Entidade `DEAD` não percebe, não se move, não ataca, não colide.

### 4.8 Posicionamento (`items_sim.populate`, parte inimigos)

Chamado por `setup_seed(s)` **depois** de `generate(s)`, continuando o **mesmo** `gen.rng` (fluxo `STREAM_DUNGEON`); `generate()` não muda, logo o `grid_sha256` de M2-A5 não muda. Para `rid = 1 .. N−1` em ordem crescente:
- `rid == exit_room`: `guardian` no centro da célula `(r.cx − 1, r.cz)` (o centro `(r.cx, r.cz)` é a célula `EXIT`; `r.cx − 1 ≥ r.x + 1` porque a sala tem largura ≥ 4);
- senão: `t = rng.next_bounded(100)`; `rat` se `t < 60`, senão `skeleton`; no centro da célula `(r.cx, r.cz)`.

Sala 0 nunca recebe inimigo. `ids` na ordem de criação. `rng.dungeon_state` no hash passa a ser o estado **depois** do populate completo (inimigos + itens).

### 4.9 Arena de demonstração (`dungeon_gen.test_arena()` + `world_sim.setup_test("arena")`)

Usada pelo modo de atração (§9), pelos gates M6-X1 e M6-V1. Grade:

| Elemento | Células |
|---|---|
| Sala 0 | `_fill_rect(2, 2, 12, 10, FLOOR, 0)` → `x ∈ [2, 13]`, `z ∈ [2, 11]`; `rooms[0] = {id 0, x 2, z 2, w 12, h 10, cx 8, cz 7}` |
| Corredor | `(14, 6)` e `(16, 6)` `FLOOR` (sala −1); `(15, 6)` **`DOOR_LOCKED`** (padrão de porta válido: N/S sólidos, L/O livres) |
| Sala 1 (Saída) | `_fill_rect(17, 4, 5, 5, FLOOR, 1)` → `x ∈ [17, 21]`, `z ∈ [4, 8]`; `rooms[1] = {id 1, x 17, z 4, w 5, h 5, cx 19, cz 6}`; **`EXIT` em `(19, 6)`**; `exit_room = 1` |
| Spawn | centro de `(3, 6)` = `(7168, 13312)`, `angle = 0` (olhando para L) |

Entidades e itens fixos (`setup_test("arena")`, sem RNG):

| id | Entidade/item | Célula | Observação |
|---|---|---|---|
| E0 | `rat` | `(9, 6)` | `dcx = 6` → acorda no tick 1 (36 ≤ 36, visão livre) |
| E1 | `skeleton` | `(12, 9)` | acorda quando o jogador se aproxima |
| E2 | `guardian` | `(20, 7)` | atrás da porta trancada; acorda quando ela abre e o jogador entra |
| I0 | `potion_hp` | `(6, 9)` | |
| I1 | `gold` (`amount 25`) | `(8, 3)` | |
| I2 | `key` | `(11, 3)` | |
| I3 | `potion_sp` | `(4, 10)` | |

`setup_test("room"|"door"|"combat")` continuam sem itens; `"combat"` mantém só o boneco.

---

## 5. Especificação do núcleo — M6 (`items_sim.gd`)

### 5.1 Estado novo do jogador (`player_sim.gd`, inicializado em `place()`)

| Campo | Inicial |
|---|---|
| `level` | 1 |
| `xp` | 0 |
| `gold` | 0 |
| `inventory` | `{"potion_hp": 0, "potion_sp": 0, "key": 0}` (dicionário só com `int`) |

`sword_damage()` = `Combat.SWORD_DAMAGE + LEVEL_DMG_BONUS · (level − 1)`; `combat.swing_step` passa a usá-lo (com `level = 1` dá 25: M3 não muda).

### 5.2 Itens

`world.items: Array` de `{id, type, cell_x, cell_z, amount, taken}` em ordem crescente de `id`; `type ∈ {"potion_hp", "potion_sp", "key", "gold"}`; `amount` = ouro da pilha (0 para os outros tipos).

**`populate`, parte itens** (mesmo `rng`, logo depois dos inimigos; esta ordem de sorteios é normativa):

```
livres(rid) = células da sala rid em ordem (cz crescente, depois cx crescente) com cell == FLOOR,
              room_id == rid, fora do centro (r.cx, r.cz), fora da célula do guardião, fora de EXIT,
              e sem item já posto.  escolher(rid) = livres(rid)[rng.next_bounded(tamanho)]
1. potion_hp na sala 0: escolher(0) (o centro da sala 0 é o spawn e já está excluído)
2. chave: K = [rid ≠ 0, ≠ exit_room, cujo centro é alcançável do centro da sala 0 por BFS
          com DOOR_LOCKED tratado como bloqueio], em ordem crescente
          rid_k = K[rng.next_bounded(|K|)];  célula = escolher(rid_k)
          (filtrar antes de sortear é o "ressorteio determinístico" do GDD; |K| ≥ 4 nas sementes 1–100)
3. para rid = 1 .. N−1 crescente, rid ≠ exit_room:
     a. se rng.next_bounded(2) == 0: tipo = potion_hp se rng.next_bounded(3) < 2 senão potion_sp; escolher(rid)
     b. gold com amount = 10 + rng.next_bounded(21); escolher(rid)
4. sala da Saída: gold com amount = 50; escolher(exit_room)
```

### 5.3 Passos 3 e 4 (interação e poções)

```
3a. use: portas (código atual) + DOOR_LOCKED de frente com inventory.key > 0 → DOOR_OPEN
         (a chave NÃO é consumida: a Sala da Saída pode ter várias portas trancadas)
3b. coleta automática: para cada item não coletado, em ordem de id, com (cell_x, cell_z) ==
         (cell_of(pos_x), cell_of(pos_z)): taken = true; potion_* e key → inventory += 1; gold → gold += amount
3c. use com a célula do jogador == EXIT e inventory.key > 0 → world.escape_pending = true
4.  quaff == 1 e potion_hp > 0: potion_hp −= 1; hp = min_i(hp + 40, hp_max)
    quaff == 2 e potion_sp > 0: potion_sp −= 1; stamina = min_i(stamina + 50, stamina_max)
    inventário vazio: nada muda
```

`escape_pending` e `pending_xp` são zerados no passo 10/8 e valem sempre 0/false no instante do hash; **não** entram em `s_k` (comentar no código, como `incoming_hits`).

### 5.4 Passo 8 (XP e nível), depois do vigor de M3

```
xp += pending_xp; pending_xp = 0
enquanto level < 3 e xp >= LEVEL_XP[level]:          # LEVEL_XP = [0, 100, 250]
    level += 1; hp_max += 20; stamina_max += 10; hp = hp_max
```

O bônus de dano (+5 por nível) sai de `sword_damage()`. Vários níveis no mesmo tick aplicam os bônus várias vezes.

### 5.5 Passo 10 (terminais), em ordem de prioridade

```
se hp <= 0:            terminal = "DEAD"
senão se escape_pending: terminal = "ESCAPED"
senão se tick >= K_MAX:  terminal = "TIMEOUT"
se terminal != "NONE": terminal_tick = tick
escape_pending = false
```

Depois do terminal, `step()` só incrementa `tick` e emite hash (já implementado no passo 1). `get_snapshot()` continua funcionando.

### 5.6 `step()` completo (GDD §2.2)

```
1.  tick += 1; last_input; se terminal: só hash
    was_stunned = stun_ticks > 0
2.  blocking efetivo; player.step(inp, grid, blocking, blockers_vivos)
3.  use (portas/trancadas) → coleta → pedido de fuga             (§5.3)
4.  poções                                                       (§5.3)
5.  golpe do jogador (dano = sword_damage(); abate → pending_xp) (M3 + §4.7)
6.  inimigos em ordem de id (percepção → movimento → ataque)     (§4.7)
7.  dano recebido (fila; agora alimentada pelos STRIKE do passo 6)
8.  atordoamento/vigor (M3) → XP e nível                         (§5.4)
9.  automapa
10. terminais                                                    (§5.5)
11. hash
```

### 5.7 Estado canônico, schema 3 (GDD §5.3)

```
s_k = { schema_version: 3, tick, terminal,
        player:  {pos_x, pos_z, vel_x, vel_z, angle, hp, hp_max, stamina, stamina_max,
                  swing_state, swing_ticks, swing_hits[], blocking, stun_ticks, regen_ticks,
                  level, xp, gold, inventory{potion_hp, potion_sp, key}},
        dungeon: {grid_sha256, doors[]},
        enemies: [{id, type, pos_x, pos_z, half, hp, hp_max, state, state_ticks, awake}],
        items:   [{id, type, cell_x, cell_z, amount, taken}],
        automap: {visited_sha256},
        rng:     {dungeon_state, ai_state} }
```

`ai_state` = estado de um `Pcg32(seed, STREAM_AI)` criado no `setup_*` e **não consumido** nesta versão (a IA é determinística sem sorteio); fica no hash para cumprir o contrato do GDD. `get_snapshot()` acrescenta `items` (cópia), `terminal_tick` e os campos novos do jogador.

---

## 6. Piloto (`game/input/pilot.gd`)

`RefCounted`, só inteiros (o linter aplica as regras do núcleo a este arquivo), **só lê** o `WorldSim` e devolve um `IntInput` por tick: `pilot.next_input(world) -> IntInput`. RNG próprio `Pcg32(seed, STREAM_PILOT)`; nunca toca o RNG da masmorra. Algoritmo de referência (o Desenvolvedor pode ajustar **apenas** parâmetros marcados *[ajustável]*, nunca constantes do núcleo):

1. **Objetivo:** se `inventory.key == 0` → célula do item `key`; senão → célula `EXIT`.
2. **Navegação:** BFS a partir da célula-objetivo (N, L, S, O), passável = não `SOLID`; `DOOR_LOCKED` só é passável com chave. Recalcular quando a célula do jogador ou o `grid.sha256()` mudar. Próxima célula = primeiro vizinho com distância − 1; alvo = centro dela.
3. **Direção sem trigonometria inversa:** com `f = (cos, sin)` do ângulo e `d` = alvo − posição: `cross = (fx·dz − fz·dx) >> 16`, `dot = (fx·dx + fz·dz) >> 16`. `turn = ±48` (sinal de `cross`) se `dot ≤ 0`; senão `turn = clamp_i(div_trunc(cross·652, max_i(dot, 1)), −48, 48)` (652 ≈ 4096/2π). `move = 1` se `dot > 0` e `2·|cross| < dot` *[ajustável]*, senão 0.
4. **Portas:** se a próxima célula é `DOOR_CLOSED` (ou `DOOR_LOCKED` com chave), o jogador está a Chebyshev 1 célula dela e de frente (`dot > 0`, `|cross| ≤ dot`) → `use = true` (em ticks alternados, para gerar borda).
5. **Fuga:** com chave e célula atual `EXIT` → `use = true`. Com chave e distância BFS ao `EXIT` ≤ 4 células *[ajustável]* → ignora inimigos (foge passando pelo Guardião, estratégia válida no GDD).
6. **Combate:** alvo = inimigo vivo e `awake` mais próximo (Chebyshev em u) com `los` e a ≤ 8192 u (4 células) *[ajustável]*. Encara o alvo (passo 3 com `d` = alvo). Se o alvo está em `WINDUP` e a ≤ `reach + 512` → `block = true` e `move = 0`. Senão, se `swing_state == IDLE`, `stamina ≥ 12`, `along ≤ SWORD_REACH + half` e `2·|cross| < dot` → `attack = true` (borda: nunca em dois ticks seguidos). Senão aproxima-se (`move = 1`) até `along ≤ SWORD_REACH`.
7. **Poções:** `hp < 30` e `potion_hp > 0` → `quaff = 1`; senão `stamina < 20` e `potion_sp > 0` → `quaff = 2` (um tick; nunca em dois ticks seguidos).
8. **Exploração e desatolamento:** a cada tick, `rng.next_bounded(16) == 0` → `strafe = ±1` aleatório naquele tick. Se a posição não mudou por 30 ticks com `move = 1` → 20 ticks de `strafe` num sentido sorteado *[ajustável]*.

Saída exigida (M6-A6): `ESCAPED` em ≥ 80% das sementes 1–50 em até `K_MAX = 18000` ticks. O Desenvolvedor registra no comentário do gate a taxa obtida e a distribuição de terminais.

---

## 7. Runner, linter e entradas

### 7.1 `tools/lint_sim.py`

Aplicar a lista `FORBIDDEN` também a `game/input/pilot.gd` (exceto a regra `extends RefCounted` que ele já cumpre) e continuar aplicando a regra "apresentação não escreve no núcleo" a `view/` e `input/`. Esperado: 0 violações.

### 7.2 `headless_runner.gd`

```
godot --headless --path game -s res://scripts/headless_runner.gd -- \
      --seed=N --ticks=K --mode=zero|replay|pilot [--trace=in.jsonl] [--record=out.jsonl] \
      [--test-room|--combat-room|--arena] [--with-view] --output=report.json
```

- `pilot`: `pilot.gd` gera o input; `--record` grava a trilha (`trace_io.gd`, uma linha por tick).
- Para ao atingir terminal **ou** `--ticks` (a cadeia continua com o comprimento `K` pedido: depois do terminal o `step()` só conta ticks).
- `--with-view`: instancia `main.tscn` (`driven_externally = true`, mesmo `start_override`) e alimenta `tick_once` com o mesmo input; relatório ganha `chain_view` e o código de saída é 2 se `chain_view != chain_final` (R3). Para isso o runner passa a rodar em `_initialize()` (não `_init()`) e espera um `process_frame`.
- Relatório: `{schema_version: 3, godot_version, seed, ticks, terminal, terminal_tick, grid, hashes[], chain_final, final_state, [chain_view]}`.

### 7.3 `InputSampler`

`quaff_hp` (tecla 1) e `quaff_sp` (tecla 2) viram **borda** (`_quaff_pending`, mesmo padrão de `attack`/`use`): `quaff = 1` ou `2` só no tick seguinte ao pressionamento.

---

## 8. Apresentação (somente leitura do snapshot)

### 8.1 Inimigos (`enemy_view.gd`)

Cada nó continua `Sprite3D` `Enemy_<id>`, `billboard = BILLBOARD_FIXED_Y`, `texture_filter = NEAREST`, `shaded = false`, `alpha_cut = ALPHA_CUT_DISCARD`. Sprites de 32 × 32 px; **altura do quadro = 32 · pixel_size**, base no piso (`y_centro = 16 · pixel_size`):

| `type` | Textura | `pixel_size` | Altura | `y` do centro |
|---|---|---|---|---|
| `rat` | `enemy.rat` | 0.03 | 0,96 m | 0.48 |
| `skeleton` | `enemy.skeleton` | 0.05 | 1,60 m | 0.80 |
| `guardian` | `enemy.guardian` | 0.065 | 2,08 m | 1.04 |
| `dummy` | `enemy.dummy` | 0.05 | 1,60 m | 0.80 (M3-V1 exige 0.05) |

Só existe **um quadro por tipo** no perfil `free`: as 8 direções do GDD usam o mesmo quadro, com `flip_h = true` quando a componente lateral (em relação à câmera) do último deslocamento é negativa. Efeitos por estado (só visuais, `_process`):

| Estado / evento | Efeito |
|---|---|
| `CHASE` andando (posição mudou) | balanço vertical ±0,04 m a 3 Hz |
| `WINDUP` | `modulate` interpola branco → `#ffd060` e escala 1,00 → 1,12 ao longo de `state_ticks / windup` (o "aviso" que dá sentido ao bloqueio) |
| `STRIKE` | avanço de 0,35 m na direção da câmera por 8 quadros |
| HP caiu | `#ff6060` por 6 quadros (já existe) |
| vira `DEAD` | `#606060`, afunda 0,6 m em 30 quadros e some (o núcleo mantém a entidade) |

### 8.2 Itens (`item_view.gd`, nó `ItemView` em `main.tscn`)

`Sprite3D` `Item_<id>` por item, mesmas flags de billboard dos inimigos, `pixel_size = 0.016` (0,51 m), centro em `y = 0.26`, balanço ±0,04 m a 1 Hz; texturas `item.potion_hp`, `item.potion_sp`, `item.key`, `item.gold`; `visible = false` quando `taken`. Posição: centro da célula `((cell_x·2048 + 1024)/1024, y, −(cell_z·2048 + 1024)/1024)`.

### 8.3 HUD (`hud_daggerfall`) — corrige "barras finas sem rótulo"

Barra 640 × 48 em y = 312 (inalterada). Coordenadas locais da barra:

| Elemento | Posição / tamanho | Especificação |
|---|---|---|
| Retrato | (8, 8), 32 × 32 | inalterado |
| Barra de Vida | (46, 4), **12 × 40** (interior 10 × 38) | `#c02020`, de baixo para cima |
| Barra de Vigor | (62, 4), **12 × 40** | `#20a040`; amarelo piscante no atordoamento (inalterado) |
| Texto de Vida | (80, 4), fonte 10 | `"Vida %d/%d"`, cor `#e06060` |
| Texto de Vigor | (80, 17), fonte 10 | `"Vigor %d/%d"`, cor `#60d080` |
| Nível / XP | (80, 30), fonte 10 | `"Nv %d  XP %d/%d"` (no nível 3: `"Nv 3  XP %d"`), cor `#f0e0b0` |
| Bússola | centro (320, 24), 96 × 20 | rótulos **N, NE, E, SE, S, SW, W, NW** (rosa internacional: elimina o "L" apontado e a confusão "O"/"0"); `angle = 0` → **E**, 1024 → N, 2048 → W, 3072 → S |
| Inventário | ícones 16 × 16 (`TextureRect`, `expand_mode` ajustado, `NEAREST`) em y = 4: poção de vida x = 384, poção de vigor x = 424, chave x = 464, ouro x = 504; contador `"×%d"` (fonte 10) 18 px à direita de cada ícone | chave: `modulate.a = 0.25` sem chave, 1 com chave; ouro mostra o total |
| Mensagens | (384, 26), largura 248, fonte 10 | uma por vez, 2 s |

Mensagens novas (detecção por comparação de snapshots): `"Rato abatido (+10 XP)"`, `"Esqueleto abatido (+25 XP)"`, `"Guardião abatido (+100 XP)"`, `"Poção de Vida"`, `"Poção de Vigor"`, `"Chave da Saída!"`, `"+%d de ouro"`, `"Porta trancada: falta a chave"` (`last_input.use` diante de `DOOR_LOCKED` sem chave e a porta não mudou), `"Porta destrancada"`, `"Nível %d!"`, e no modo de atração, fixa: `"DEMONSTRAÇÃO — tecle algo para jogar"`.

### 8.4 Arma (`weapon_view`) — corrige "escudo cortado pela HUD"

- Espada: inalterada (escala 4, pose `IDLE` em (500, 286)).
- Escudo: **escala 3** (96 × 96 px); `SHIELD_IDLE = (100, 258)` (ocupa y 210..306, inteiro acima de y = 312); `SHIELD_UP = (220, 226)`. Tremor e interpolação inalterados.

### 8.5 Tela final (`end_screen.tscn/.gd`, `CanvasLayer layer = 4`)

Painel pergaminho `#d8c8a0` com borda de 3 px `#3a2a18`, retângulo (120, 50) a (520, 290) — **não cobre a HUD**. `visible = false` até `terminal != "NONE"`. Título (fonte 20, `#3a2a18`, centralizado): `"VOCÊ ESCAPOU!"`, `"VOCÊ MORREU"` ou `"TEMPO ESGOTADO"`. Linhas (fonte 12): `Nível`, `XP`, `Ouro`, `Inimigos abatidos` (contagem de `DEAD` exceto `dummy`), `Tempo mm:ss` (`terminal_tick / 60`). Rodapé: `"Tecle Enter para nova partida"` (fora do modo de atração).

### 8.6 Automapa

Acrescentar só: itens **não coletados** em células visitadas como pontos de 3 × 3 px (chave `#e0c020`, poção de vida `#c02020`, poção de vigor `#20a040`, ouro `#c0a040`). Inimigos não aparecem no mapa (como no Daggerfall). O resto inalterado (M5-A5 continua valendo).

### 8.7 Cena principal (`main.gd`)

- Nós novos: `ItemView (Node3D)` e `EndScreen (CanvasLayer)`; `tick_once` passa o snapshot a eles.
- Argumentos: sem argumentos → **modo de atração** (§9); `--play` → partida com `setup_seed(seed)` e teclado; `--seed=N` implica `--play`; `--arena` → arena jogável; `--test-room`, `--combat-room`, `--demo` inalterados. `start_override` ganha `"arena"` e `"attract"`.
- Enter na tela final (fora da atração) reinicia com a mesma semente.

---

## 9. Mídia de auditoria: modo de atração

Corrige a lacuna nº 3 (quadros idênticos) sem depender de teclado na captura:

- Sem argumentos de usuário, `main.gd` usa `setup_test("arena")` e o `pilot.gd` (semente 1) como fonte de input. Mensagem fixa na HUD (§8.3).
- Agenda de UI (só view, fora do hash): automapa aberto do tick 420 ao 540.
- No terminal, a tela final fica 4 s visível e a arena recomeça (laço infinito, como a demo do DOOM).
- Qualquer tecla ou botão do mouse sai da atração e inicia `setup_seed(1)` com teclado.
- Resultado esperado na tela, em ordem: rato acordando e avançando com aviso amarelo de preparação; escudo erguido e golpes; mensagens de abate/XP; coleta da chave; esqueleto; automapa translúcido sobre o mundo em movimento; porta trancada abrindo; Guardião (2 m) na Sala da Saída; tela "VOCÊ ESCAPOU!".

---

## 10. Áudio (procedural em `sfx_view.gd`, fora do hash)

Continua sem arquivos de áudio. Buffers `AudioStreamWAV` 16 bits mono 22050 Hz gerados no `_ready()`. Sons de inimigos com volume atenuado pela distância ao jogador: `vol_db = base − 20·log10(max(1, dist_m / 2))`.

| Evento (comparando snapshots) | Som | Base |
|---|---|---|
| Rato acorda (`awake` false → true) | guincho: seno 1800 → 2600 Hz, 80 ms | −10 dB |
| Esqueleto acorda | chocalho de ossos: 5 cliques de ruído de 15 ms a cada 30 ms | −10 dB |
| Guardião acorda | rugido: serra 80 Hz + ruído, 400 ms | −6 dB |
| Inimigo entra em `WINDUP` | sopro crescente: ruído passa-banda 300 → 900 Hz, 250 ms (aviso para bloquear) | −12 dB |
| Inimigo abatido | rato: guincho descendente 2000 → 600 Hz; esqueleto: chocalho longo 8 cliques; guardião: rugido grave 60 Hz, 600 ms | −8 dB |
| Coleta de poção / ouro | tilintar 880 + 1320 Hz, 100 ms / 3 cliques 2000–3000 Hz | −10 dB |
| Coleta da chave | arpejo 660/880/1320 Hz, 3 × 60 ms | −8 dB |
| Beber poção | 3 bolhas: seno 200 Hz, 40 ms cada | −10 dB |
| Porta destrancada | clique metálico 1500 Hz 20 ms + som de porta já existente | −8 dB |
| Subida de nível | arpejo 523/659/784 Hz, 3 × 100 ms | −6 dB |
| `ESCAPED` | fanfarra ascendente 5 notas (C-E-G-C-E), 120 ms cada | −4 dB |
| `DEAD` | tom descendente 400 → 80 Hz, 800 ms | −4 dB |

Sons das rodadas 1–2 continuam (o "jogador ferido" agora dispara com golpes reais de inimigos).

---

## 11. Testes necessários

### 11.1 Execução

```
python3 tools/lint_sim.py                                   # 0 violação(ões)
godot --headless --path game --import --quit
godot --headless --path game -s res://tests/run_gates.gd    # 0 = tudo passa; 2 = asserção falhou; 1 = erro
```

`run_gates.gd`: M1, M2, M3, M5, **M4, M6** (núcleo), depois os gates de cena (M3-V1, M5-A4, M5-A5, **M4-A7, M6-V1, M6-V2**). **M6-A6 roda por último** (é o mais longo). Formato de saída inalterado.

### 11.2 Gate M4 (`gate_m4.gd`) — salvo indicação, `setup_test("room")`, jogador no spawn `(7168, 15360)`, `angle = 0`, input zero

| ID | Cenário | Asserção exata |
|---|---|---|
| M4-A1 | `spawn_enemy("skeleton", centro de (6, 7))`; parede: `set_cell(5, z, SOLID)` para `z ∈ [2, 13]`; 120 ticks | `state == "IDLE"` e `awake == false` em todo tick (3 células, sem visão). Controle sem a parede: `CHASE` (ou `WINDUP`) e `awake` no tick 1 |
| M4-A2 | sementes 1–20; para cada sala `r ≥ 1`: mundo novo, `enemies = [inimigo da sala r]` (o que o populate pôs), todas as portas → `DOOR_OPEN`, inimigo `awake = true`, `state = "CHASE"`; jogador parado no centro da **primeira célula** (índice crescente) não sólida, fora de sala e 4-adjacente à sala `r` | o inimigo entra em `WINDUP` em **≤ 1200 ticks** em todos os pares (o gate imprime o máximo observado; referência: essas células ficam a ≤ 9 células BFS do centro) |
| M4-A3 | `skeleton` em `(8368, 15360)` (1200 u à frente, `awake`, `CHASE`). (a) jogador parado; (b) `move = −1` nos ticks 1–18 | `WINDUP` no tick 1, `STRIKE` no tick **19**; (a) `hp` 100 nos ticks 1–18 e **88** no tick 19; (b) `hp == 100` no tick 19 (fora do alcance no `STRIKE`) |
| M4-A4 | (a) o esqueleto de A3 com jogador parado, 400 ticks; (b) `rat` em `(8068, 15360)`, 200 ticks | ticks com queda de `hp`: (a) **19, 83, 147, 211, 275, 339**, `hp` final 28; (b) **9, 48, 87, 126, 165**, quedas de 5. Diferença entre quedas consecutivas ≥ `windup + cooldown` (63 / 38) |
| M4-A5 | sementes 1–10, trilha de M3-A7 (`GateM3.a7_trace(4242)`, sem `inject_hit`), 600 ticks | **por tick:** nenhuma entidade viva com caixa em célula bloqueante; nenhum par de entidades vivas sobreposto; nenhuma entidade viva sobreposta ao jogador; e M1-A4 |
| M4-A6 | `rat` em `(8068, 15360)`; `attack` no tick 1; ticks 2–30 zero; depois 60 ticks `move = 1` | rato `DEAD` com `hp == 0` no tick **7** (`ACTIVE`); `player.hp == 100` (o `STRIKE` do tick 9 não acontece); `player.xp == 10` ao fim do tick 7; o jogador atravessa: `pos_x > 8068 + 640` ao final |
| M4-A7 | cena: `main.tscn`, `start_override = "seed:1"`, `driven_externally` | todo filho de `EnemyView` é `Sprite3D` com `billboard == BILLBOARD_FIXED_Y`; quantidade == `world.enemies.size()` (= salas − 1); `pixel_size` conforme §8.1 por tipo |
| M4-X1 | `los` em `test_room()` | centro (3,7) → centro (10,7): true; com `(6,7)` sólida: false; canto exato centro (3,3) → centro (5,5) com `(4,3)` sólida: false; sem ela: true |
| M4-X2 | campo de fluxo em `test_door_room()`, jogador no centro de `(12, 4)` | porta aberta: `flow(4,4) == 8`, `flow(8,4) == 4`, `flow(2,2) == 12`; porta fechada: `flow(4,4) == −1` |
| M4-X3 | perseguição longa: sementes 1–20, `rat` acordado no centro da Sala da Saída (guardião removido), portas abertas, jogador parado no spawn | `WINDUP` em ≤ `div_trunc(D·2048·5, 4·100) + 120` ticks, `D` = distância BFS em células entre as duas células |
| M4-X4 | raio de percepção (`rat`, 1 tick) | `(9,7)` acorda; `(10,7)` não; `(8,10)` acorda (25 + 9); `(8,11)` não (25 + 16) |
| M4-X5 | populate, sementes 1–100 | `enemies.size() == salas − 1`; nenhum na sala 0; exatamente um `guardian`, na Sala da Saída; os demais `rat`/`skeleton`; nenhuma caixa em célula bloqueante nem sobreposta |
| M4-X6 | bloqueio pelo corpo | `dummy` em `(9216, 15360)`; 120 ticks `move = 1`: `pos_x ≤ 8448` em todo tick e `pos_x ≥ 8448 − 149` ao final |
| M4-X7 | repetição R1 | sementes 1–5, trilha de M3-A7: duas instâncias → `chain` iguais e não vazias |

### 11.3 Gate M6 (`gate_m6.gd`)

| ID | Cenário | Asserção exata |
|---|---|---|
| M6-A1 | populate, sementes 1–100 | exatamente um item `key`; não está na sala 0 nem na Sala da Saída; sua célula é alcançável do spawn por BFS com `DOOR_LOCKED` bloqueando; exatamente uma `potion_hp` na sala 0 e nenhum outro item lá; nenhum item em célula não `FLOOR`, no `EXIT` ou na célula de um inimigo; ids crescentes |
| M6-A2 | `room`: `hp = 90`, `potion_hp = 1`; `quaff = 1`; depois `quaff = 1` de novo; idem vigor (`stamina = 70`, `potion_sp = 1`, `quaff = 2` ×2) | `hp == 100`, `potion_hp == 0`; 2º `quaff`: nada muda; `stamina == 100` (limitado), `potion_sp == 0`; 2º: nada muda |
| M6-A3 | `arena`: jogador posto no centro de `EXIT (19, 6)`; `use` sem chave; depois `key = 1` e `use` | sem chave: `terminal == "NONE"`; com chave: `"ESCAPED"` e `terminal_tick == tick` do `use`. Porta: jogador no centro de `(14, 6)`, `angle = 0`, `use` sem chave → `(15,6)` continua `DOOR_LOCKED`; com chave → `DOOR_OPEN` |
| M6-A4 | `room`: `inject_hit(200, 8397, 15360)`; tick 1; depois 100 ticks da trilha de M3-A7 | `terminal == "DEAD"`, `terminal_tick == 1`; `canonical_state()` sem `tick` idêntico em todos os ticks seguintes |
| M6-A5 | `room`: `pending_xp = 100` → 1 tick; depois `pending_xp = 150` → 1 tick | após o 1º: `level 2`, `hp_max 120`, `hp 120`, `stamina_max 110`, `sword_damage() 30`; após o 2º: `xp 250`, `level 3`, `140`, `120`, `35`. Teste extra: `pending_xp = 300` de uma vez → `level 3` com os dois bônus |
| M6-A6 | **fim a fim:** runner/piloto, sementes 1–50, até 18000 ticks | `ESCAPED` em **≥ 40 de 50** sementes; nenhum `hash_error`; nenhuma violação de invariante (M1-A4 e M4-A5 por tick) |
| M6-X1 | arena com piloto | `ESCAPED` em ≤ 3600 ticks (garante a demonstração) |
| M6-X2 | R4 gravação/reprodução | semente 1, piloto, 3000 ticks com `--record`; reprodução da trilha sem piloto → `chain` igual |
| M6-X3 | coleta e ouro | `arena`: jogador posto no centro de `(8, 3)` e 1 tick → `gold == 25`, item `taken`; posto em `(11, 3)` → `key == 1` |
| M6-V1 | cena `main.tscn`, `start_override = "arena"`, `driven_externally`, `tick_once` com o piloto até o terminal | `EndScreen` invisível antes e **visível** depois de `ESCAPED`; `ItemView` tem 4 `Sprite3D` e o da chave fica `visible == false` após a coleta; R3: `chain` da cena == `chain` de um núcleo puro com a mesma trilha |
| M6-V2 | HUD e arma em cena | rótulos `"Vida 100/100"` e `"Vigor 100/100"` no início; barras com largura 12; escudo em `IDLE`: `position.y + 16·scale.y ≤ 312`; `hud_daggerfall.heading_label(angle)` (função estática nova, usada pelo `_draw` da bússola) devolve `"E"` para 0, `"N"` para 1024, `"W"` para 2048, `"S"` para 3072 e `"NE"` para 512 |

### 11.4 Preservation Gate

- **M1-A1..A6, M1-X*, M2-A1..A6, M2-X*, M3-A1..A7, M3-X1..X4, M3-V1, M5-A1..A5, M5-X1** passam **sem mudar asserções**.
- Riscos conhecidos e o que fazer:
  - `blockers = []` nas salas de teste sem entidades: física idêntica (M1, M3-X2).
  - M3-A7/M3-X4 têm o boneco à frente: agora ele bloqueia o corpo; as asserções são invariantes/igualdade, continuam válidas.
  - M3-A7 injeta até 30 de dano a cada 37 ticks: o jogador pode morrer e o estado congelar (`DEAD`); invariantes continuam válidos.
  - M5-A3/A4 usam `setup_seed`: agora há inimigos e itens; monotonicidade e igualdade de cadeias continuam válidas.
  - `SCHEMA_VERSION` 2 → 3 muda `C_0` e todos os `H_k`; nenhum gate compara hash com constante.
- `python3 tools/lint_sim.py` → 0 violações (inclui `enemy_sim.gd`, `items_sim.gd`, `input/pilot.gd`).

---

## 12. Ordem de implementação sugerida

1. `enemy_sim.gd` (tipos, `los`, fluxo, máquina), `spawn_enemy`, colisões (§4.5–4.6), passo 6, `pending_xp` no abate → `gate_m4.gd` núcleo (A1–A6, X1–X7) + preservação verde. **Parar aqui e confirmar M4 verde.**
2. `test_arena()`, `items_sim.gd` (populate, coleta, poções, XP/nível, terminais), schema 3 → `gate_m6.gd` A1–A5, X3.
3. `pilot.gd`, runner (`pilot`, `--record`, `--with-view`, `--arena`) → M6-X1, X2, A6.
4. Views: `enemy_view`, `item_view`, HUD, arma, `end_screen`, automapa, `sfx_view`, `main` (atração, `--play`, `--arena`), `input_sampler` (quaff).
5. Gates de cena M4-A7, M6-V1, M6-V2.
6. `lint_sim.py`, `--import --quit`, `run_gates.gd` → tudo PASS antes do commit.

## 13. Critérios de pronto da rodada 3

1. `python3 tools/lint_sim.py` → 0 violações.
2. `run_gates.gd` → todas as asserções de §11.2, §11.3 e o Preservation Gate (§11.4) passam; saída 0.
3. `godot --path game` (sem argumentos) mostra o modo de atração: inimigos em billboard proporcionais (rato < esqueleto < guardião), aviso de preparação, bloqueio e golpes, itens no chão, HUD com valores e inventário, escudo inteiro acima da HUD, automapa translúcido entre os ticks 420 e 540, tela "VOCÊ ESCAPOU!".
4. `godot --path game -- --play --seed=1` é jogável do início à fuga ou morte, com tela final.
5. Nenhum arquivo novo em `game/assets/`.
6. Commits no branch da rodada; sem push.
