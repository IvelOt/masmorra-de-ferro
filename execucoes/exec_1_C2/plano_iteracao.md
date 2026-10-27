# Plano de Iteração 3 (Execução 1, Condição C2)

- **Papel:** Planejador ($D_t$), rodada 3.
- **Entrada:** `GDD.md` (§1 a §5 e §7), `relatorio_provas.json` da rodada 2, `media/iter_2/` e o código atual em `game/`.
- **Marcos desta rodada:** **M5** (automapa translúcido) e **M6** (itens, progressão, condição terminal e piloto do runner). Pelo grafo `M1 → M2 → {M3, M5}`, `M3 → M4`, `{M4, M5} → M6`, são os dois marcos que faltam. M5 vem primeiro porque M6 depende dele.
- **Correções herdadas da rodada 2 (só `view/`, não mudam nenhum hash):** HUD sem bússola e sem textos (§8.4), escudo em repouso que parece um objeto no chão (§8.3) e capturas estáticas idênticas (§8.7).
- **Fora do escopo:** perfil de arte `daggerfall`, quadros de 8 direções, tochas de parede, menus, salvamento, mais classes, qualquer mudança em constantes de M1 a M4.

---

## 0. Diagnóstico da rodada 2 (evidência)

| Fonte | Achado | Consequência para esta rodada |
|---|---|---|
| `relatorio_provas.json` → `verified` | `lint_sim.py` com 0 violações; PASS em M1-A1..A6, PCG32, M2-A1..A6, M2-PRES, R1, M3-A1..A7, M4-A1..A7, Spawn | M1 a M4 formam o **Preservation Gate** (§10) |
| `relatorio_provas.json` → `gap` | M5 e M6 não implementados | Escopo desta rodada |
| `media/iter_2/frame_1.png` e `frame_2.png` | Mesmo MD5 (`98fd990f…`) pela segunda rodada seguida. A captura abre `main.tscn` sem argumentos e sem entrada, então nada se mexe | Modo vitrine (*attract*) em §8.7 |
| `frame_1.png` | A iluminação melhorou: paredes e piso são legíveis e o teto ainda está escuro, mas é aceitável. A espada está boa. O **escudo** em repouso (canto inferior esquerdo em `(40, 344)`) aparece inteiro acima da HUD com a sombra do *tile*, e parece um item no piso | Nova pose de repouso em §8.3 |
| `frame_1.png` | A HUD tem só o retrato e duas barras finas, e ~85% da barra fica vazia. Não há bússola, valores, ouro, nível nem mensagens (o GDD §7.5 pede bússola e linha de mensagens) | Nova HUD em §8.4 (necessária também para M6) |
| Código | `IntInput.quaff` existe mas não tem efeito; a ação `toggle_map` (Tab) existe em `project.godot` e não é usada; `--mode=pilot` responde "não implementado" | Escopo de M5/M6 |

---

## 1. Regras gerais para o Desenvolvedor

As regras 1 a 9 da rodada 2 continuam valendo: núcleo inteiro e `RefCounted` em `game/sim/`, apresentação só leitura, `FixedMath.div_trunc/div_floor/mod_floor` em vez de `/`/`%` com negativos, tipagem estática, nenhum asset novo, a sala `"test"` intocada e sem entidades, `DungeonGen.generate(seed)` com a **mesma grade**, iteração por índice e `id`. Acrescentam-se:

10. `StateHash.SCHEMA_VERSION = 3`. Nenhum gate fixa valor literal de cadeia.
11. **Ordem do RNG da masmorra (fluxo 1):** `generate()` (grade) → `EnemySim.spawn_dungeon()` (inalterado) → `ItemsSim.place_dungeon()` (novo, §4.2). O posicionamento de itens só **continua** `d.rng` depois dos inimigos. Tipos e posições dos inimigos de todas as sementes ficam iguais aos da rodada 2. Antes de qualquer alteração, gravar em `game/tests/gates/m4_spawn_r2.json` a lista `[type, pos_x, pos_z]` dos inimigos das sementes 1 a 100; o gate `M6-PRES` compara com ela.
12. O piloto (`game/sim/pilot.gd`) é núcleo: inteiro, linted, só **lê** o `WorldSim` e devolve um `IntInput`. Usa apenas `RngPcg32.create(seed, STREAM_PILOT)`, nunca o fluxo da masmorra.
13. O estado "mapa aberto" é só de interface: não fica em `sim/`, não entra em `IntInput` nem no hash.
14. Constantes de M1 a M4 não mudam. O dano da espada no nível 1 continua 25.

---

## 2. Arquivos

### 2.1 Criar

| Arquivo | Marco | Conteúdo |
|---|---|---|
| `game/sim/automap_sim.gd` | M5 | Bitmap `visited`, mapa de salas por célula, marcação por tick, SHA |
| `game/sim/items_sim.gd` | M6 | Constantes de itens e progressão, lista de itens, posicionamento, coleta, poções, XP e nível |
| `game/sim/pilot.gd` | M6 | Piloto em malha fechada (§6) |
| `game/view/automap_overlay.tscn` + `.gd` | M5 | Sobreposição Tab (§7) |
| `game/view/item_view.gd` | M6 | `Sprite3D` *billboard* por item (§8.2) |
| `game/view/end_screen.tscn` + `.gd` | M6 | Tela final em pergaminho (§8.5) |
| `game/view/compass.gd` | correção | Bússola de faixa da HUD (§8.4) |
| `game/tests/gates/gate_m5.gd`, `gate_m6.gd` | M5/M6 | Asserções da §9 |
| `game/tests/gates/m4_spawn_r2.json` | M6 | Regra 11 |

### 2.2 Alterar

| Arquivo | Mudança |
|---|---|
| `game/sim/world_sim.gd` | Passos 1, 3, 4, 8, 9 e 10 de §2.2 do GDD; sala `"vault"`; `add_item`; `terminal_tick`; `snapshot()` v3 |
| `game/sim/combat.gd` | `swing_damage(level)`; `player_step` devolve a soma de XP dos inimigos mortos naquele tick |
| `game/sim/player_sim.gd` | Campos `level`, `xp`, `gold`, `potion_hp`, `potion_sp`, `has_key`; `to_state_dict()` v3 |
| `game/sim/state_hash.gd` | `SCHEMA_VERSION = 3` |
| `game/scripts/headless_runner.gd` | `--mode=pilot`; `--room=vault`; `--tab-every=N`; `terminal_tick` no relatório; invariantes novos (§9.4) |
| `game/tests/gates/run_gates.gd` | Executar também `gate_m5` e `gate_m6` |
| `game/view/main.tscn` / `main.gd` | Nós `Items`, `Automap`, `EndScreen`; sons novos; mensagens; modo vitrine (§8.7) |
| `game/view/hud_daggerfall.gd` | Nova HUD (§8.4) |
| `game/view/weapon_view.gd` | Pose de repouso do escudo (§8.3) |
| `game/view/dungeon_view.gd` | Base do portal no piso (§8.2) |
| `game/view/sfx.gd` | Sons novos (§8.6) |

### 2.3 Salas

| `room` | Grade | Entidades e itens | Jogador |
|---|---|---|---|
| `"test"`, `"combat"`, `"arena"` | como na rodada 2 | como na rodada 2, **sem itens** | `(5120, 15360)`, `angle = 0` |
| `"vault"` (nova) | cópia de `test_room()` com `(15, 4) → DOOR_LOCKED` e `(19, 7) → EXIT`; `exit_room = 1`, `exit_cell = [19, 7]` | sem inimigos; itens: id 0 `KEY` em `(4, 7)`, id 1 `POTION_HP` em `(6, 7)`, id 2 `POTION_SP` em `(6, 9)`, id 3 `GOLD` em `(8, 7)` | igual |
| `"dungeon"` | `generate(seed)` | inimigos (rodada 2) + itens (§4.2) | `start_pos` |

A sala `"vault"` cria uma **nova** instância de `DungeonGen.test_room()` e só então altera a própria grade; `test_room()` não muda. `doors` é recoletado depois da alteração (as posições continuam `(15, 4)` e `(15, 11)`).

---

## 3. Estado canônico v3 e ordem de `step()`

### 3.1 `s_k` (`SCHEMA_VERSION = 3`)

```
s_k = { "schema_version": 3, "tick", "terminal": "NONE"|"ESCAPED"|"DEAD"|"TIMEOUT",
        "player":  { ...campos v2...,
                     "level", "xp", "gold",
                     "inventory": { "potion_hp", "potion_sp", "key": bool } },
        "dungeon": { "grid_sha256", "doors": [...] },
        "enemies": [ ... v2 ... ],
        "items":   [ {"id","type","cell_x","cell_z","taken": bool} ... ],   # ordem por id
        "automap": { "visited_sha256" },
        "rng":     { "dungeon_state", "ai_state" } }
```

- `items` inclui os já coletados (`taken = true`), para manter o comprimento estável.
- `visited_sha256`: SHA-256 dos 4096 bytes de `visited` (valores 0/1), hexadecimal minúsculo, com o mesmo `HashingContext` de `Grid.sha256()`.
- `rng.dungeon_state = dungeon.rng.state_hex()` depois do posicionamento de itens (constante durante a partida). Nas salas sem gerador (`test`, `combat`, `arena`, `vault`) vale `""`. `rng.ai_state = RngPcg32.create(seed, STREAM_AI).state_hex()`: nenhum subsistema consome o fluxo de IA hoje, mas o campo fica no contrato do GDD.
- `terminal_tick` (−1 enquanto `NONE`) é um membro de `WorldSim` e vai no relatório do runner. Ele **não** entra em `s_k`.
- O piloto, o campo de fluxo e o estado "mapa aberto" não entram no hash.

### 3.2 Ordem de `WorldSim.step(inp)`

1. `tick += 1`. **Se `terminal != "NONE"`, pula direto para o passo 11** (estado congelado; só `tick` muda e o hash continua sendo emitido).
2. Jogador: como na rodada 2.
3. Interação, nesta ordem: (a) **coleta** dos itens não coletados na célula do jogador, em ordem de `id` (§4.3); (b) se `inp.use`: porta à frente (`DOOR_CLOSED` → `DOOR_OPEN` como antes; `DOOR_LOCKED` → `DOOR_OPEN` só com `has_key`, §4.4); (c) se `inp.use` e a célula do jogador é `EXIT` e `has_key`: `_escape_request = true`.
4. Poções (`quaff`, §4.5).
5. Combate do jogador (dano = `swing_damage(level)`); guarda o XP dos inimigos mortos neste tick em `_xp_gain`.
6. Inimigos: como na rodada 2.
7. Dano recebido: como na rodada 2 (`hp = max(hp, 0)`).
8. Regeneração de vigor (rodada 2), depois XP e nível (§4.6).
9. Automapa: `automap.mark(player.cell_x(), player.cell_z())` (§5).
10. Terminais, em ordem de prioridade: `hp <= 0` → `DEAD`; senão `_escape_request` → `ESCAPED`; senão `tick >= K_MAX` → `TIMEOUT`. Ao entrar num terminal, `terminal_tick = tick`. `_escape_request` volta a `false` no fim do passo.
11. Hash e cadeia.

Os terminais valem em todas as salas. Em `test/combat/arena` só `DEAD` e `TIMEOUT` podem ocorrer (não há `EXIT`).

### 3.3 API nova de `WorldSim`

```
static func create(seed: int, room: String = "dungeon") -> WorldSim   # room ∈ {"test","combat","arena","vault","dungeon"}
func add_item(type: int, cell_x: int, cell_z: int) -> int   # só antes do 1º step; devolve o id
var items: Array[Dictionary]                                # {id, type, cell_x, cell_z, taken}; a view lê
var automap: AutomapSim                                     # a view lê automap.visited
var terminal_tick: int = -1
const K_MAX: int = 18000
```

Como na rodada 2, os gates podem atribuir campos do jogador (`pos_*`, `angle`, `hp`, `stamina`, `level`, `xp`, `hp_max`, `stamina_max`, `potion_hp`, `potion_sp`, `has_key`), de inimigos, de itens, da grade e o próprio `tick` **antes** de um `step()`, para montar cenários. A `view/` nunca faz isso.

---

## 4. M6: itens, progressão e terminais (`items_sim.gd`)

### 4.1 Constantes

| Constante | Valor |
|---|---|
| Tipos de item | `POTION_HP = 0`, `POTION_SP = 1`, `KEY = 2`, `GOLD = 3` |
| `POTION_HP_HEAL` / `POTION_SP_RESTORE` | 40 / 50 |
| `GOLD_VALUE` | 25 |
| `LEVEL_XP` (XP mínimo dos níveis 1, 2, 3) | `[0, 100, 250]` |
| `LEVEL_MAX` | 3 |
| Bônus por nível | `hp_max +20`, `stamina_max +10`, dano da espada +5 |
| `swing_damage(level)` | `25 + 5 × (level − 1)` → 25 / 30 / 35 |
| `K_MAX` | 18000 |

Estado inicial do jogador: `level = 1`, `xp = 0`, `gold = 0`, `potion_hp = 0`, `potion_sp = 0`, `has_key = false`.

### 4.2 Posicionamento na masmorra (`ItemsSim.place_dungeon(d, enemies)`)

Continua `d.rng` **depois** de `spawn_dungeon` (regra 11). "Célula livre" de uma sala = célula interior da sala com tipo `FLOOR`, que não é a célula de nenhum inimigo (`pos >> 11`), nem `exit_cell`, nem já tem item. A lista de células livres é percorrida em ordem de linha (`cz`, depois `cx`).

```
(s_cx, s_cz) = centro da sala inicial  (célula de start_pos)
id 0: POTION_HP em (s_cx + 1, s_cz)                         # sem RNG; visível na largada (angle 0 = +X)

# chave: sala que não é a inicial nem a da saída, alcançável sem porta trancada
reach = BFS a partir de (s_cx, s_cz) tratando DOOR_LOCKED como sólido (DOOR_CLOSED passa)
cands = ids das salas ≠ start_room e ≠ exit_room, em ordem crescente
k = d.rng.next_range(cands.size())
para j em 0 .. cands.size()-1:                               # ressorteio determinístico: varredura cíclica
    r = cands[(k + j) % cands.size()]
    se o centro de r é alcançável em reach e r tem célula livre: escolhida; parar
id 1: KEY na célula livre de índice d.rng.next_range(n_livres) da sala escolhida

# itens comuns: uma tiragem por sala, exceto a inicial (a sala da saída participa)
para cada sala r em ordem de id, r ≠ start_room:
    t = d.rng.next_range(100)
    0–34 → POTION_HP ; 35–54 → POTION_SP ; 55–84 → GOLD ; 85–99 → nada
    se há item e n_livres(r) > 0: célula = livres[d.rng.next_range(n_livres)]
    (se n_livres == 0, o item é descartado sem nova chamada ao RNG)
```

- Se nenhuma candidata servir para a chave, ela vai para a célula alcançável (em `reach`) mais distante da largada que não esteja na sala inicial nem na da saída, com desempate pelo menor índice. M6-A1 mostra se isso chega a acontecer nas sementes 1 a 100; o gate imprime quantas sementes usaram esse caminho.
- A grade não muda. Nenhum item fica na sala inicial além da poção de id 0.

### 4.3 Coleta (passo 3a)

Para cada item com `taken == false` e `(cell_x, cell_z) == (player.cell_x(), player.cell_z())`, em ordem de `id`: `taken = true` e
`POTION_HP` → `potion_hp += 1`; `POTION_SP` → `potion_sp += 1`; `KEY` → `has_key = true`; `GOLD` → `gold += 25`.
A coleta é automática, sem `use`, e acontece no primeiro tick em que a célula do jogador (`pos >> 11`) coincide com a do item.

### 4.4 Porta trancada (passo 3b)

Mesma regra de alcance e frente de `_use_door` (vizinha-4 na direção cardinal mais próxima, `|rel| ≤ 512`). Se a célula é `DOOR_LOCKED` e `has_key`: vira `DOOR_OPEN`, o cache do campo de fluxo é invalidado, e a chave **fica** no inventário (ela é exigida de novo no `EXIT`). Sem chave, nada muda; o som `door_bump` da rodada 2 continua.

### 4.5 Poções (passo 4)

```
quaff == 1 e potion_hp > 0: potion_hp -= 1; hp      = min(hp + 40, hp_max)
quaff == 2 e potion_sp > 0: potion_sp -= 1; stamina = min(stamina + 50, stamina_max)
```

A poção é consumida mesmo com a barra cheia (regra simples e determinística). Com o inventário vazio, `quaff` não tem efeito.

### 4.6 XP e nível (passo 8, depois da regeneração)

```
xp += _xp_gain ; _xp_gain = 0                          # XP da tabela de M4: DUMMY 0, RAT 10, SKELETON 25, GUARDIAN 100
enquanto level < 3 e xp >= LEVEL_XP[level]:            # LEVEL_XP[1] = 100, LEVEL_XP[2] = 250
    level += 1; hp_max += 20; stamina_max += 10; hp = hp_max
```

Um abate que cruza os dois limiares sobe dois níveis no mesmo tick. `stamina` não é restaurada na subida (só `hp`).

### 4.7 Terminais

Ver §3.2, passos 1 e 10. Depois do terminal, todo o `s_k` exceto `tick` fica constante (M6-A4).

---

## 5. M5: automapa no núcleo (`automap_sim.gd`)

- `visited: PackedByteArray` de 4096 posições, inicialmente 0.
- `room_of: PackedInt32Array` de 4096 posições, montado em `create()` a partir de `dungeon.rooms` (−1 fora de sala). Serve para `"dungeon"`, `"vault"` e as salas de teste (`test_room()` tem as salas 0 e 1).
- `mark(cx, cz)` (passo 9, em todo tick não terminal):
  - se `room_of[c] = r ≥ 0`: marca todas as células de `[r.x − 1, r.x + r.w] × [r.z − 1, r.z + r.h]` (sala e contorno), limitadas a `[0, 63]`;
  - senão (corredor ou porta): marca a célula e as 8 vizinhas, limitadas a `[0, 63]`.
- Nunca desmarca. A marcação é idempotente: repetir a mesma célula não muda o bitmap.
- Valores de referência: na sala `"test"`, no tick 1, `visited` tem exatamente as 256 células de `[0, 15] × [0, 15]`. Na masmorra, no tick 1, tem exatamente `(w₀ + 2)(h₀ + 2)` células (sala 0 e contorno).

---

## 6. Piloto do runner (`pilot.gd`, M6-A6)

`Pilot.create(seed)` guarda `RngPcg32.create(seed, STREAM_PILOT)`. `Pilot.next_input(w: WorldSim) -> IntInput` lê o estado e devolve a entrada do tick. Tudo em inteiros. Algoritmo de referência (o Desenvolvedor pode ajustar os limiares, mas mantém a estrutura e registra os valores no topo do arquivo):

1. **Objetivo:** sem chave → célula da chave; com chave e alguma porta `DOOR_LOCKED` ainda fechada → a célula do corredor vizinha à porta trancada mais próxima por BFS, depois a própria porta; senão → `exit_cell`.
2. **Rota:** BFS a partir do objetivo sobre `FLOOR`, `DOOR_OPEN`, `DOOR_CLOSED`, `EXIT` e, com chave, `DOOR_LOCKED`. É recalculada quando a célula do jogador ou o objetivo muda. O alvo do tick é o centro da vizinha com `dist − 1` (ordem N, L, S, O, como no campo de fluxo de M4).
3. **Direção:** `d = alvo − pos`, `f = (cos_q16(angle), sin_q16(angle))`; `cross = (f.x·d.z − f.z·d.x) >> 16`, `dot = (f.x·d.x + f.z·d.z) >> 16`, `n = max(|d.x|, |d.z|, 1)`.
   `turn = clamp_i(div_trunc(cross · 128, n), −128, 128)`; `move = 1` se `dot > 0` e `2·|cross| ≤ dot`, senão 0 (gira no lugar).
4. **Portas:** se a próxima célula é `DOOR_CLOSED` (ou `DOOR_LOCKED` com chave), o jogador está na vizinha e de frente (`|rel| ≤ 512`), então `use = true`. No `EXIT` com chave, `use = true`.
5. **Combate:** alvo = inimigo vivo e acordado mais próximo (Chebyshev, desempate por `id`) a até `2048 + alcance`. O piloto vira para ele (item 3 com o centro do inimigo). Se o alvo está em `WINDUP` e de frente → `block = true`, `move = 0`. Senão, se `swing_state == IDLE`, `stamina ≥ 12` e o alvo está a `≤ 1638 + HALF` e dentro de ±30° → `attack = true`. Enquanto há alvo, o objetivo de rota fica suspenso.
6. **Poções:** `hp < 30` e `potion_hp > 0` → `quaff = 1`; senão `stamina < 15` e `potion_sp > 0` → `quaff = 2`.
7. **Exploração (1/16):** se `rng.next_range(16) == 0`, `turn += (rng.next_range(2)·2 − 1) · 24`, saturado em ±128. O fluxo do piloto é consumido **exatamente duas vezes por tick** (uma para o teste e uma para o sinal, mesmo quando não usado), para que a sequência dependa só do número de ticks.
8. **Destravamento:** se `move == 1` e a posição não mudou por 30 ticks, aplica `strafe = ±1` (sinal pelo bit `tick & 1`) e `move = −1` por 20 ticks.

Runner: `--mode=pilot` exige `--room=dungeon` e grava a trilha com `--record`. O piloto continua sendo chamado depois do terminal (a entrada é ignorada pelo núcleo congelado), para manter a cadeia com comprimento K.

---

## 7. M5: sobreposição do automapa (`automap_overlay.tscn`)

- Raiz `CanvasLayer` `AutomapOverlay`, `layer = 20` (acima da HUD, que é 10), `visible = false` no início, no grupo `"automap"`. Filho `Control` `Map` (`position (0, 0)`, `size (640, 320)`, sem tapar a HUD) com **`modulate = Color(1, 1, 1, 0.6)`**. Dentro de `Map`: `ColorRect` de pergaminho `(0.80, 0.70, 0.50)` ocupando tudo, e um `Control` `Canvas` que desenha com `_draw()`.
- `_unhandled_input(event)`: se `event.is_action_pressed("toggle_map")` e não é eco → `visible = not visible` e emite `toggled(visible)` (sinal de `view/`, usado por `main.gd` para o som). `main.gd` expõe `toggle_automap()`, que chama o mesmo caminho (usado por gates e pelo runner).
- O jogo **não pausa**: nenhum `get_tree().paused`, e nada muda no `_physics_process`.
- `apply(snapshot, visited: PackedByteArray, grid: Grid, frac)` é chamado por `main.gd` a cada quadro só quando `visible`. Sem estado (`apply` nunca chamado), `_draw()` não desenha nada e não falha (M5-A5 instancia a cena sozinha).
- **Projeção:** centrada no jogador (posição interpolada), norte fixo, zoom fixo de **8 px por célula** (±40 × ±20 células visíveis). Mapa = vista de cima do mundo 3D, **sem espelhamento**. Como a câmera usa `x = pos_x`, `z_godot = −pos_z` e frente `(cos a, sin a)` na simulação, o "para cima" do mapa é **+Z da simulação** (−Z do Godot):
  - `sx = 320 + (x − px) · 8 / 2048`, `sy = 160 − (z − pz) · 8 / 2048` (x, z em unidades de simulação);
  - seta do jogador na direção de tela `(cos a, −sin a)`.
  Para a apresentação, **Norte = +Z da simulação** (ângulo 1024), Leste = +X (ângulo 0). O rótulo "N" do campo de fluxo de M4 é interno e não muda.
- **O que desenhar** (só células com `visited = 1`):
  - piso visitado (`FLOOR`, `EXIT`, portas): quadrado de 8×8 em `(0.70, 0.60, 0.42)`;
  - borda entre célula visitada não sólida e vizinha-4 sólida: linha de 2 px `(0.25, 0.15, 0.08)`;
  - portas: barra de 8×3 px atravessando a passagem. Fechada `(0.55, 0.35, 0.15)`, aberta só contorno de 1 px na mesma cor, trancada vermelha `(0.80, 0.10, 0.10)`;
  - `EXIT` visitado: losango de 6 px roxo `(0.60, 0.20, 0.80)`;
  - jogador: triângulo vermelho `(0.85, 0.10, 0.10)` de 10 px de comprimento e 7 de base, no centro da tela;
  - "N" com a fonte padrão, tamanho 10, em `(316, 12)`.
- Inimigos e itens **não** aparecem no automapa, como no Daggerfall.

---

## 8. Apresentação: sprites, proporção visual e áudio

Todos os PNG de `game/assets/free/` têm **32×32 px**. Filtro `NEAREST`, sem *mipmaps*, `alpha_cut = DISCARD`, `shaded = false` e `billboard = BILLBOARD_FIXED_Y` em todos os `Sprite3D`. Caixas de conteúdo opaco medidas (x0, y0, x1, y1 exclusivo):

| Identificador | Caixa opaca | Linhas vazias abaixo |
|---|---|---|
| `item.potion_hp` | (7, 2, 32, 29) | 3 |
| `item.potion_sp` | (8, 3, 30, 29) | 3 |
| `item.key` | (3, 10, 29, 21) | 11 |
| `item.gold` | (0, 1, 32, 31) | 1 |
| `exit.portal` | (3, 2, 29, 31) | 1 |
| `weapon.shield` | (5, 2, 32, 30) | — |

### 8.1 Regra de base

O pé do conteúdo opaco toca o piso: `position.y = (16 − linhas_vazias_abaixo) × pixel_size` (mesma regra da rodada 2). Posição horizontal: centro da célula, `x = (cell_x·2 + 1)`, `z = −(cell_z·2 + 1)` em metros.

### 8.2 Itens (`item_view.gd`) e portal

| Item | `pixel_size` | Altura do conteúdo | Largura | `position.y` base |
|---|---|---|---|---|
| `POTION_HP` | 0,016 | 27 px → 0,43 m | 25 px → 0,40 m | 0,208 |
| `POTION_SP` | 0,016 | 26 px → 0,42 m | 22 px → 0,35 m | 0,208 |
| `KEY` | 0,016 | 11 px → 0,18 m | 26 px → 0,42 m | 0,080 + 0,25 (flutua) = 0,330 |
| `GOLD` | 0,0125 | 30 px → 0,38 m | 32 px → 0,40 m | 0,1875 |

- Proporção: com os olhos a 1,5 m, poções e ouro ficam abaixo do joelho, como objetos no chão. A chave é pequena demais para ser vista no piso, por isso flutua a 0,25 m.
- Animação só visual: todos os itens oscilam `±0,04 m` em Y, com período de 1,5 s e fase `id × 0,7 rad`; a chave também gira (`rotation.y` +90°/s) apesar do *billboard*. Os nós ficam no grupo `"items"`, filhos de `Main/Items`. Quando `taken` vira `true`, o item sobe 0,3 m e some em 12 quadros, e então `visible = false`. O nó não é removido da árvore.
- **Portal (`dungeon_view.gd`):** `position.y` passa de 1,0 para **0,9375** (`(16 − 1) × 0,0625`). Hoje ele flutua 6 cm.

### 8.3 Escudo (correção, `weapon_view.gd`)

- Repouso: canto inferior esquerdo em **(−8, 372)**, com rotação de −8° e `modulate (0.85, 0.85, 0.85)`. Só os ~2/3 superiores aparecem acima da HUD (y = 320), cortados pela borda esquerda, e a leitura passa a ser "escudo na mão esquerda", não "objeto no chão".
- Bloqueio: sobe para o canto inferior esquerdo em (176, 300) e rotação 0° em 5 quadros (valores da rodada 2). Atordoamento: igual à rodada 2.
- A espada não muda.

### 8.4 HUD (correção + M6, `hud_daggerfall.gd`)

Barra 640×40 em y = 320…360, com a mesma pedra procedural da rodada 2. Textos com a fonte padrão do tema, `font_size = 10`, cor `(0.92, 0.86, 0.70)`, contorno de 1 px preto (`outline_size = 1`). Layout em px da tela interna:

| Elemento | Posição / tamanho | Conteúdo |
|---|---|---|
| Retrato | (8, 324), 32×32 | `ui.portrait` 1× (sem mudança) |
| Barra de Vida | x = 46, 10×32 | vermelho `(0.75, 0.10, 0.10)`, de baixo para cima, `div(32·hp, hp_max)` |
| Barra de Vigor | x = 60, 10×32 | verde `(0.15, 0.65, 0.20)`, `div(32·stamina, stamina_max)` |
| Valores | (76, 323) e (76, 339) | `PV 100/100` e `VG 100/100` |
| Nível e XP | (160, 323) | `Nv 1  XP 0/100` (no nível 3: `Nv 3  XP 255`) |
| Ouro | (160, 339) | `Ouro 0` |
| Chave | (262, 328), 16×16 | `item.key` em 0,5×; `modulate.a = 0.25` sem chave e 1 com chave |
| Poções | (284, 328) e (322, 328), 16×16 | `item.potion_hp` / `item.potion_sp` em 0,5× e `×N` à direita |
| Mensagens | (364, 322), 180×34, 2 linhas | as duas mensagens mais recentes; cada uma vive 180 quadros (3 s) |
| Bússola | (552, 324), 80×32 | `compass.gd` (abaixo) |

- Atordoamento: bordas das barras em amarelo `(0.9, 0.8, 0.2)` (sem mudança).
- **Mensagens** (geradas na `view/` por diferença entre *snapshots*): "Pegou a Chave da Saída", "Pegou uma poção de vida", "Pegou uma poção de vigor", "+25 de ouro", "Bebeu poção de vida (+N PV)", "Bebeu poção de vigor", "Porta trancada: falta a chave" (no `door_bump`), "A porta trancada se abriu", "Subiu para o nível N!", "Inimigo abatido (+N XP)".
- **Bússola de faixa (estilo Daggerfall):** fundo `(0.12, 0.11, 0.10)` com borda de 1 px `(0.45, 0.40, 0.33)` e recorte (`clip_contents`). A faixa tem 320 px para 4096 BAM (90° = 80 px, a largura visível). Uma direção `d` aparece em `x = 40 + (((angle − d + 2048) & 4095) − 2048) · 320 / 4096`, relativo à caixa. Letras `L` (d = 0), `N` (1024), `O` (2048), `S` (3072) em `font_size = 10`, marcas de 4 px a cada 512 BAM e um triângulo vermelho fixo no centro do topo. Conferência: virando à esquerda (`turn > 0`), o ângulo cresce e as letras correm para a direita, e de frente para o leste (`angle = 0`) o `N` fica 80 px à esquerda do centro, fora da janela.

### 8.5 Tela final (`end_screen.tscn`, M6)

- `CanvasLayer` `EndScreen`, `layer = 30`, invisível até `snapshot.terminal != "NONE"`. Aparece com *fade* de 30 quadros.
- `Panel` de pergaminho procedural de 320×180 em (160, 70): fundo `(0.86, 0.78, 0.58)`, borda de 3 px `(0.40, 0.28, 0.14)`. Textos em `(0.25, 0.15, 0.08)`.
- Título com `font_size = 16`: `VOCÊ ESCAPOU!` / `VOCÊ MORREU` / `TEMPO ESGOTADO`. Linhas com `font_size = 10`: `Nível N`, `XP N`, `Ouro N`, `Tempo: T ticks (S s)` com `S = T/60` truncado, `Semente N`.
- Rodapé `Enter: nova partida` só no modo interativo. Enter recarrega a cena com a mesma semente (`get_tree().reload_current_scene()`). Com `external == true` (runner), não há rodapé nem recarga.

### 8.6 Áudio (`sfx.gd`; `AudioStreamWAV` gerados na inicialização, PCM 16 bits, 22050 Hz, mono)

| Id | Gatilho (diferença entre *snapshots*) | Síntese |
|---|---|---|
| `pickup_item` | `potion_hp` ou `potion_sp` aumentou | 0,12 s: seno 660 Hz por 50 ms e depois 990 Hz, decaimento linear |
| `pickup_key` | `key` false → true | 0,30 s: arpejo 523 / 659 / 784 Hz (100 ms cada), quadrada a 30% |
| `pickup_gold` | `gold` aumentou | 0,15 s: 1568 Hz + 2093 Hz, decaimento exponencial (τ = 25 ms) |
| `quaff` | uma poção diminuiu | 0,25 s: 3 pulsos de ruído de 60 ms com passa-baixa em 300 Hz ("gole") |
| `door_unlock` | porta `DOOR_LOCKED` → `DOOR_OPEN` | 20 ms de ruído (clique) + varredura 200 → 120 Hz por 0,3 s |
| `level_up` | `level` aumentou | 0,45 s: varredura quadrada 440 → 880 Hz com trêmolo de 12 Hz |
| `automap_toggle` | sinal `toggled` da sobreposição | 0,08 s de ruído com passa-alta em 2 kHz (papel) |
| `escape` | `terminal` → `ESCAPED` | fanfarra 523 / 659 / 784 / 1047 Hz, 120 ms cada |
| `death` | `terminal` → `DEAD` | 0,8 s: dente de serra 330 → 55 Hz + ruído decrescente |
| `timeout` | `terminal` → `TIMEOUT` | 3 bipes de 440 Hz, 100 ms com 100 ms de pausa |

Todos usam `AudioStreamPlayer` (2D). Os sons das rodadas 1 e 2 ficam como estão. Em `--headless` (driver *dummy*), nada pode falhar nem condicionar lógica ao áudio.

### 8.7 Modo vitrine da cena principal (correção das capturas)

As capturas de auditoria abrem `main.tscn` **sem argumentos e sem entrada**, e por isso as rodadas 1 e 2 produziram quadros idênticos. Para que a captura mostre o jogo funcionando:

- Se a cena é interativa (`external == false`), não recebeu `--no-attract` e **nenhum** `InputEventKey`/`InputEventMouseButton` chegou depois de 60 ticks físicos (1 s), a entrada passa a vir de `Pilot.next_input(sim)` em vez do `InputSampler`. Nos ticks antes disso a entrada é vazia, como hoje.
- Na vitrine, `main.gd` abre o automapa por 90 ticks a cada 600 ticks (só visual), e um rótulo `DEMONSTRAÇÃO — pressione qualquer tecla` (`font_size = 10`, centralizado em y = 8) pisca a cada 60 quadros.
- O primeiro evento de tecla ou de botão do mouse encerra a vitrine: a cena recarrega com a mesma semente sob controle do jogador. A partida do jogador sempre começa limpa, sem trilha misturada.
- O núcleo é o mesmo nos dois casos. A vitrine é só outra fonte de `IntInput`, e o *linter* continua valendo.
- Resultado esperado: com a semente padrão 1337, a largada mostra a poção de vida a 2 m (§4.2), o personagem anda, abre portas, combate e o automapa aparece. Dois quadros capturados em instantes diferentes têm MD5 diferente.

### 8.8 Árvore de `main.tscn` (acréscimos)

`Main` → `WorldEnvironment`, `DungeonView`, `Enemies`, `Items (Node3D)`, `PlayerView` → `Camera3D` → `OmniLight3D`, `WeaponView` (5), `Hud` (10), `Automap` (instância de `automap_overlay.tscn`, 20), `EndScreen` (30), `Sfx`.

---

## 9. Testes

### 9.1 Trilhas

| Arquivo | Sala | Conteúdo | Uso |
|---|---|---|---|
| `m1_forward_120.jsonl` (existente) | `vault` | 120 ticks `move=1` | M6-A3 (coleta ao longo da linha 7) |
| `m6_pilot_seed3.jsonl` | `dungeon`, semente 3 | gravada com `--mode=pilot --ticks=18000 --record=` | R4 (gravação/reprodução) |

### 9.2 Gate M5 (`gate_m5.gd`)

| ID | Montagem | Asserção |
|---|---|---|
| M5-A1 | (a) `test`, 1 tick vazio. (b) `dungeon`, sementes 1 a 100, 1 tick vazio | (a) `visited` = exatamente `[0, 15] × [0, 15]` (256 células). (b) exatamente as `(w₀+2)(h₀+2)` células da sala 0 com contorno |
| M5-A2 | `dungeon`, sementes 1 a 5: todas as portas `DOOR_CLOSED/LOCKED` → `DOOR_OPEN` e todos os inimigos `DEAD` antes do tick 1. Caminho = BFS (`DungeonGen.bfs`) do centro da sala 0 até o centro da sala vizinha mais próxima por distância BFS. Para cada célula do caminho, em ordem: teleportar o jogador para o centro dela e dar 1 `step` vazio | (i) toda célula de corredor do caminho (`room_of = −1`) está marcada; (ii) a sala de destino só tem células marcadas a partir do tick em que o jogador entra nela (antes disso, só as células a Chebyshev ≤ 1 de uma célula de corredor já visitada); (iii) toda sala fora do caminho tem 0 células interiores marcadas, exceto as que ficam a Chebyshev ≤ 1 de uma célula de corredor do caminho |
| M5-A3 | `test` com os 600 ticks aleatórios de M1-A4; `dungeon` sementes 1 a 5 com os 600 ticks aleatórios (semente 1, seq 3) | invariante por tick: nenhuma célula marcada volta a 0, e a contagem nunca diminui |
| M5-A4 | `dungeon` semente 7, 600 ticks aleatórios (semente 1, seq 3). Mundo A: só o núcleo. Mundo B: mesma semente e trilha, com `view/main.tscn` instanciada (`attach_sim`), `refresh_from_sim()` depois de cada `step` e `toggle_automap()` nos ticks múltiplos de 37 | `A.chain() == B.chain()` e B abriu e fechou o mapa ao menos 8 vezes |
| M5-A5 | instanciar `view/automap_overlay.tscn` sozinha, adicionar à raiz e chamar `_unhandled_input` com um `InputEventKey` (`keycode = physical_keycode = KEY_TAB`, `pressed = true`) duas vezes | `visible` vai de `false` → `true` → `false`; `0 < get_node("Map").modulate.a < 1`; `_draw` sem estado não gera erro |

### 9.3 Gate M6 (`gate_m6.gd`)

| ID | Montagem | Asserção |
|---|---|---|
| M6-A1 | `dungeon`, sementes 1 a 100 | exatamente um `KEY`, fora da sala inicial e da sala da saída, com célula alcançável a partir da largada por BFS que trata `DOOR_LOCKED` como sólido. Também: a sala inicial tem um único item (`POTION_HP` em `(s_cx+1, s_cz)`); nenhum item na célula de inimigo ou no `EXIT`; nenhum par de itens na mesma célula; o gate imprime quantas sementes usaram o *fallback* da chave |
| M6-PRES | `dungeon`, sementes 1 a 100 | `[type, pos_x, pos_z]` dos inimigos igual a `m4_spawn_r2.json`, e `grid_sha256` igual a `m2_grid_sha_r1.json` |
| M6-A2 | `vault`. (a) `hp = 50`, `potion_hp = 1`, `quaff = 1` no tick 1. (b) `hp = 80`, `potion_hp = 1`. (c) inventário vazio, `quaff = 1` e depois `quaff = 2`. (d) `stamina = 10`, `potion_sp = 1`, `quaff = 2` | (a) `hp = 90`, `potion_hp = 0`. (b) `hp = 100` (não 120). (c) `hp`, `stamina` e o inventário não mudam. (d) `stamina = 60` (tick 1 não regenera) |
| M6-A3 | (a) `vault` + `m1_forward_120.jsonl`. (b) `vault`, jogador no centro de `(14, 4)`, `angle = 0`, `use` no tick 1 sem chave; novo mundo igual com `has_key = true`. (c) `vault`, jogador no centro de `(19, 7)`, `use` sem chave; depois `has_key = true` e `use` | (a) `pos_x` final = **20644** (igual a M1-A1); itens 0, 1 e 3 `taken`, item 2 não; `key = true`, `potion_hp = 1`, `gold = 25`; o item 0 é coletado exatamente no primeiro tick com `pos_x ≥ 8192`. (b) sem chave `(15, 4)` continua `DOOR_LOCKED`; com chave vira `DOOR_OPEN` no tick 1. (c) sem chave `terminal = "NONE"`; com chave `ESCAPED` no mesmo tick, com `terminal_tick == tick` |
| M6-A4 | (a) `vault`, `inject_hit(5120+1500, 15360, 200)` no tick 1, depois 100 ticks aleatórios (semente 1, seq 3). (b) `vault`, `tick = K_MAX − 2` antes de 2 `step`s vazios. (c) `vault`, jogador em `(19, 7)` com chave, `use` e `inject_hit` de 200 no mesmo tick | (a) `hp = 0`, `DEAD`, `terminal_tick = 1`; nos ticks 2 a 101, `canon(s_k)` sem `tick` é igual ao do tick 1, e a cadeia continua a avançar. (b) `TIMEOUT` com `terminal_tick = 18000`. (c) `DEAD` (prioridade sobre `ESCAPED`) |
| M6-A5 | (a) `test` + rato em `(6349, 15360)`, `hp = 20`, `awake`/`CHASE`, `player.xp = 95`, golpe no tick 1 (montagem de M4-A6). (b) `combat`, `player.level = 2`, golpe no tick 1. (c) como (a) com `level = 2`, `hp_max = 120`, `stamina_max = 110`, `xp = 245`. (d) como (a) com `xp = 240` e nível 1. (e) como (a) com `level = 3`, `xp = 300` | (a) no tick 7: `xp = 105`, `level = 2`, `hp_max = 120`, `hp = 120`, `stamina_max = 110`. (b) boneco `hp` 100 → 70 no tick 7. (c) `level = 3`, `hp_max = 140`, `stamina_max = 120`, `hp = 140`. (d) dois níveis no mesmo tick: `level = 3`, `hp_max = 140`, `stamina_max = 120`. (e) `level` continua 3 e `hp_max` não muda |
| M6-A6 | piloto, `dungeon`, sementes 1 a 50, até o terminal ou `K_MAX` (o gate pode parar no terminal) | `ESCAPED` em **≥ 40 de 50** (80%, limiar do GDD). O gate imprime, por semente, o terminal, `terminal_tick`, nível e ouro, e confere que `rng.dungeon_state` no fim é igual ao do tick 1 |

**Atenção a M6-A3 (a):** os itens não afetam o movimento, então `pos_x` tem que bater com M1-A1. Se não bater, a coleta está mexendo no jogador.

**Atenção a M6-A5 (a):** os números de M4-A6 continuam (rato `DEAD` no tick 7, `hp` do jogador 100 até ali). O XP entra no passo 8 do tick 7, e a subida de nível acontece nesse mesmo tick.

### 9.4 Runner: opções e invariantes novos (saída 2 no primeiro tick violado)

- `--room` aceita `test|combat|arena|vault|dungeon`. `--mode=pilot` (só `dungeon`) funciona e grava com `--record`. `--tab-every=N` (só com `--with-view`) chama `toggle_automap()` a cada N ticks.
- Relatório: `terminal` e `terminal_tick` reais.
- Invariantes novos: `visited` monotônico; `level ∈ [1, 3]` e `hp_max == 100 + 20·(level−1)`, `stamina_max == 100 + 10·(level−1)`; `potion_hp, potion_sp, gold ≥ 0`; `items` com tamanho constante e `taken` nunca volta a `false`; depois do terminal, `canon(s_k)` sem `tick` constante.

### 9.5 Comando único do Verificador

```
python3 tools/lint_sim.py && \
godot --headless --path game --import && \
godot --headless --path game -s res://scripts/headless_runner.gd -- --gates --output=runs/tmp/gates.json
```

- **R1:** duas `WorldSim` semente 7, `dungeon`, `idle`, 600 ticks → `chain()` iguais (já existe).
- **R2:** `--seed=11 --mode=pilot --ticks=18000` em dois processos → `chain_final` iguais.
- **R3 (obrigatório em C2):** com e sem `--with-view`, cadeias iguais em `--seed=7 --mode=idle --ticks=600`, `--room=arena --mode=replay --trace=res://tests/traces/m4_arena_fight.jsonl` e `--seed=3 --mode=replay --trace=res://tests/traces/m6_pilot_seed3.jsonl --ticks=18000`, este último também com `--tab-every=37` (M5-A4 em nível de processo).
- **R4:** `--seed=3 --mode=pilot --ticks=18000 --record=runs/tmp/p3.jsonl`, depois `--mode=replay --trace=runs/tmp/p3.jsonl` → `chain_final` iguais.

### 9.6 Captura para auditoria visual (fora do sandbox, insumo do Verificador)

Com o modo vitrine (§8.7), a captura padrão (`main.tscn` sem argumentos) já mostra movimento. O que conferir em `media/iter_3/`: quadros com MD5 diferentes; poção e ouro com a base no piso e abaixo do joelho; chave flutuando; automapa translúcido com o mundo visível por trás, sem tapar a HUD e com a seta coerente com a direção da câmera; HUD com bússola, valores, ouro, nível e mensagens sem sobreposição de textos; escudo em repouso lido como "na mão"; tela final legível, se aparecer.

---

## 10. Preservation Gate desta rodada

- **M1-A1 a M1-A6**, **PCG32**, **R1**: mesmos números das rodadas anteriores. A sala `"test"` não ganha itens.
- **M2-A1 a M2-A6** e **M2-PRES**: mesmos `grid_sha256` das sementes 1 a 100.
- **M3-A1 a M3-A7**: com `level = 1` o dano continua 25. M3-A7 pode levar o jogador a `DEAD` (os golpes injetados somam mais que 100 de dano); a partir daí o estado congela, e o invariante continua valendo. O gate não pode tratar isso como falha.
- **M4-A1 a M4-A7** e **Spawn**: números da rodada 2 e, além disso, **M6-PRES** (inimigos idênticos aos da rodada 2).
- Qualquer falha de M1 a M4 bloqueia o aceite de M5/M6 nesta rodada.

---

## 11. Critério de pronto da rodada 3

1. `tools/lint_sim.py` com 0 violações (inclui `automap_sim.gd`, `items_sim.gd` e `pilot.gd`).
2. `godot --headless --path game --import` e `--quit` sem erro de *parse*.
3. `PASS` em todo o Preservation Gate (§10), em M5-A1..A5, M6-A1..A6 e M6-PRES.
4. R2, R3 e R4 com cadeias iguais (§9.5).
5. Modo vitrine funcionando: dois quadros da cena padrão, separados por pelo menos 2 s, com MD5 diferentes.
6. Commits separados: `feat(sim): M5 automapa`, `feat(sim): M6 itens, progressao e terminais`, `feat(sim): piloto do runner`, `feat(view): automapa, itens, HUD, tela final e vitrine`, `test: gates M5/M6`.

## 12. Riscos e observações para o Verificador

- **Espelhamento do automapa:** usar `sy = 160 + (z − pz)…` (+Z para baixo) deixa o mapa espelhado em relação ao que a câmera mostra. Para conferir, vire à esquerda: a seta tem que girar no sentido anti-horário na tela.
- **RNG da masmorra:** se o posicionamento de itens rodar antes de `spawn_dungeon`, os tipos dos inimigos mudam e `M6-PRES` falha. É a regressão mais provável desta rodada.
- **Congelamento:** o passo 1 tem que pular os passos 2 a 10 inteiros. Se só o movimento parar, a regeneração de vigor ou o automapa continuam mudando o estado e M6-A4 falha.
- **Nível e regeneração:** a subida restaura `hp`, mas não `stamina`. M6-A5 confere `hp_max` e `stamina_max`, não o valor corrente do vigor.
- **Piloto e tempo de gate:** M6-A6 roda até 50 × 18000 passos com hash. Parar no terminal reduz bastante o custo. Se o limiar de 80% não for atingido, o Desenvolvedor relata a taxa obtida, as sementes que falharam e o motivo (preso, morto, tempo), sem relaxar o limiar.
- **Vitrine e não interferência:** a vitrine só troca a fonte de `IntInput`. Os testes R3/R4 com o piloto garantem que a cena com o piloto produz a mesma cadeia que o núcleo puro.
- **Apresentação:** a proporção dos itens, a legibilidade do automapa, a bússola e a tela final não são verificáveis em headless. Elas são conferidas pela captura da §9.6 e não entram em $R_{\text{mec}}$.
