# Plano de Iteração — Rodada 6 (Execução 3, Condição C2)

- **Papel:** Planejador ($D_t$). **Rodada:** 6. **Data:** 2026-10-09.
- **Fontes:** `GDD.md` (§1.3, §2, §4.5, §4.6, §5.1, §7.4, §7.5) e `relatorio_provas.json` (iterações 1 a 5).
- **Estado herdado (provas da iteração 5):** M1 a M6 entregues, `all_milestones_passed: true`. O comando `godot --headless --path game -s res://tests/run_gates.gd` dá **76 PASS / 0 FAIL**. `StateHash.SCHEMA_VERSION = 3`. Nenhuma falha mecânica. `DEFAULT_SEED = 223` (semente de vitrine da R5).
- **Lacunas abertas no relatório da iteração 5:**
  - (a) **Falha visual menor:** a HUD ocupa pouca área e o texto de status é pequeno em 640×360. Hoje esse texto usa corpo 8.
  - (b) Os quadros capturados **não mostram itens, automapa nem a tela final**, então esses elementos só foram conferidos pelos gates numéricos. A rodada 5 já tinha adiado essa lacuna para M5/M6.
  - (c) Os quadros também não mostram efeitos de combate. **Isso fica fora desta rodada**, porque é apresentação de M3 e já tem áudio desde a R5.

## 0. Marcos escolhidos

Todos os marcos já foram aceitos. Por isso esta rodada é de **acabamento da apresentação** em dois marcos (o máximo permitido), e são justamente os dois que a mídia ainda não mostrou:

| Marco | O que entra | Motivo |
|---|---|---|
| **M5**: automapa translúcido (camada de apresentação) | **C12:** o modo atração abre o automapa em janelas fixas de tempo. **C13:** geometria do automapa extraída para uma função pura testável, mais um cabeçalho legível. **C14:** som de abrir e fechar o mapa. | Fecha a lacuna (b) para o automapa. A aparência da overlay só pode ser avaliada pela captura (GDD §4.5), e hoje ela nunca aparece na captura. |
| **M6**: itens, progressão e tela final (camada de apresentação) | **C15:** a semente de vitrine passa a exigir também um item em quadro. **C16:** textos de M6 na HUD (nível, XP, ouro, inventário, mensagens) passam para corpo 10, e a tela final fica legível. **C17:** sons de coleta e de subida de nível. | Fecha a lacuna (a) nos textos que pertencem a M6 (GDD §4.6, "mensagens de coleta na HUD") e a lacuna (b) para os itens. |

**Ordem obrigatória:** primeiro M5 (C12 a C14, com os gates M5-V1, M5-V2 e A-SFX6), depois M6 (C15 a C17, com os gates V-SHOWCASE2, M6-V4, M6-V5 e A-SFX7).

**Fora do escopo (não implementar):**
- qualquer mudança em `game/sim/`: núcleo, constantes, hash, `SCHEMA_VERSION`, geração e IA. O piloto (`scripts/pilot_escape.gd`) e o runner (`scripts/headless_runner.gd`) também não mudam;
- mudanças em M1, M2, M3 e M4. Isso inclui **não mexer** em `HP_TEXT_RECT`, `SP_TEXT_RECT`, nas barras, no retrato, na bússola, na arma, nos inimigos nem nos 8 efeitos sonoros da R5;
- desenhar inimigos ou itens no automapa. O GDD §4.5 não prevê isso;
- forçar a tela final no modo atração, ou qualquer escrita no estado para mostrá-la. A tela final só é conferida por gate (M6-V5) e, fora do sandbox, por captura manual opcional;
- assets novos em `game/assets/`, mudanças em `asset_map.json` e `CREDITS.md`;
- perfil `daggerfall`, música e áudio ambiente contínuo.

**Regra do núcleo (GDD §5.1):** tudo desta rodada fica em `view/` (e nos testes) e **só lê** o estado: `get_player()`, `get_items()`, `get_visited()`, `get_grid()`, `get_terminal()`. O estado "mapa aberto" continua sendo só de interface (GDD §4.5). `view/` nunca chama `debug_*`.

**Regras C1 das rodadas 3 a 5 continuam valendo:** as classes do projeto entram só por `const X = preload("res://…")`, nunca pelo nome global de `class_name` (G0-NOCACHE).

**Preservation Gate:** as **76 asserções da rodada 5 continuam passando com os mesmos valores numéricos e as mesmas cadeias de hash**: M1-\*, M2-\*, M3-\*, M4-\*, M5-A\*, M6-A\*/B\*, M6-V1..V3, M3-V1..V4, V-LIGHT, V-CEIL, V-ATTRACT, V-ATTRACT2, A-SFX1..5, V-SHOWCASE, M3M4-R\*, M5M6-R\* e G0-NOCACHE. Há duas exceções permitidas, e os gates envolvidos **têm que continuar passando**:
1. Se `DEFAULT_SEED` mudar (C15), V-SHOWCASE e V-ATTRACT2 passam a rodar com a semente nova.
2. M6-V3 continua comparando os textos literais (`"V 75/100"`, `"PV 0  PG 0  -"`, com espaço duplo). Os formatos de texto **não mudam**: muda só o corpo da fonte e a altura dos retângulos.

---

## 1. Arquivos

```
game/
  view/
    main.gd               # ALTERAR (C12, C14, C15): agenda do mapa no modo atração; repassa map_open ao AudioSfx; DEFAULT_SEED
    automap_overlay.gd    # ALTERAR (C13): static func cell_rects(); cabeçalho "AUTOMAPA" e marcador de norte
    hud_daggerfall.gd     # ALTERAR (C16): corpo 10 em LevelText, InvText e Message; novos LEVEL_TEXT_RECT/INV_TEXT_RECT
    end_screen.gd         # ALTERAR (C16): título com corpo 24, estatísticas com corpo 12
    audio_sfx.gd          # ALTERAR (C14, C17): 3 novos ids (pickup, level_up, map); apply_state com map_open opcional
  tests/
    find_showcase_seed.gd # ALTERAR (C15): critério de item em quadro
    gates/run_gates.gd    # ALTERAR: _gates_r6() com M5-V1, M5-V2, A-SFX6, V-SHOWCASE2, M6-V4, M6-V5, A-SFX7
```

Nenhum arquivo é criado. Nenhum `.tscn` precisa mudar.

---

## 2. M5 / C12: automapa no modo atração (`view/main.gd`)

### 2.1 Agenda (função pura)

```
static func attract_map_open(a: int) -> bool   # a = _phys_ticks
    return a >= MAP_FIRST_TICK and (a - MAP_FIRST_TICK) % MAP_PERIOD < MAP_OPEN_TICKS
```

| Constante | Valor | Significado |
|---|---|---|
| `MAP_FIRST_TICK` | 210 | 3,5 s. A essa altura o piloto já saiu da sala inicial, e o mapa tem sala mais corredor para mostrar |
| `MAP_PERIOD` | 240 | 4 s por ciclo |
| `MAP_OPEN_TICKS` | 90 | 1,5 s aberto em cada ciclo, ou seja, 37,5% do tempo depois de 3,5 s |

Assim o mapa fica aberto em `[210, 299]`, `[450, 539]`, `[690, 779]`… e fechado no resto. Com `alpha = 0.6`, o mundo 3D, o inimigo e os itens continuam visíveis por trás (GDD §4.5). Por isso não há conflito com a vitrine de M4/M6.

### 2.2 Integração

- Novo campo `var _attract_map: bool = false`.
- Em `_physics_process`, **depois** de `world.step(inp)`:
  - se `attract_active()`: `_automap.visible = attract_map_open(_phys_ticks)` e `_attract_map = true`;
  - senão, se `_attract_map` for verdadeiro (o modo atração acabou de terminar por input real): `_automap.visible = false` e `_attract_map = false`. A partir daí, só Tab controla a overlay, como antes.
- Ao ficar visível, a overlay precisa de `queue_redraw()`. Use `toggle()` ou chame `queue_redraw()` explicitamente; não basta mudar `visible` sem redesenhar.
- O caminho `attach_world` (runner e gates) **nunca** ativa a agenda, porque `attract_active()` já devolve `false` quando `_driven_externally`. Por isso M5-A4 e M5-A5 não mudam.
- O núcleo recebe exatamente os mesmos `IntInput` com ou sem a agenda: a agenda só mexe em `visible`.

### 2.3 Gate M5-V1 (headless, sem GPU)

1. Instancie `main.tscn` **sem** `attach_world`, com `start_seed = DEFAULT_SEED`, e chame `_physics_process(1.0/60)` e `sync_view()` 600 vezes. Em cada tick `a`, `overlay.visible == attract_map_open(a)`. Deve haver pelo menos um tick aberto e um fechado.
2. **Não interferência:** a cadeia `world.chain` depois dos 600 ticks é igual à de uma execução só de núcleo com a mesma semente: 30 ticks com `IntInput.new()` e depois `PilotEscape.new(seed).next_input(w)` até 600, como em `find_showcase_seed.gd`.
3. **Saída do modo atração:** numa segunda instância, rode até `a = 250` (mapa aberto). Chame `m._input(ev)` com um `InputEventKey` de `KEY_W` pressionado e rode mais 10 ticks. A overlay fica `visible == false` em todos eles, e `attract_active() == false`.
4. Funções puras: `attract_map_open(209) == false`, `(210) == true`, `(299) == true`, `(300) == false`, `(450) == true`.

---

## 3. M5 / C13: geometria testável e cabeçalho (`view/automap_overlay.gd`)

### 3.1 Função pura

Extraia o laço de `_draw_cells()` para:

```
static func cell_rects(visited: PackedByteArray, cells: PackedByteArray, p: Dictionary) -> Array
    # [{ "x": int, "z": int, "rect": Rect2, "kind": int }]  kind = valor de Grid na célula
```

- A função inclui só as células visitadas, que não são `SOLID` e cujo `rect` intersecta `Rect2(Vector2.ZERO, AREA.size)`.
- O `rect` segue a convenção atual: `Rect2(o.x, o.y − CELL_PX, CELL_PX, CELL_PX)`, com `o` vindo de `cell_origin`. Para isso, transforme `cell_origin` numa função estática `cell_origin_for(x, z, p)` e mantenha o método de instância chamando essa versão.
- `_draw_cells()` passa a desenhar **só** a lista devolvida por essa função. As cores, as linhas de parede, as portas e o Portal continuam como estão. O resultado visual não muda.

### 3.2 Cabeçalho e norte (proporção visual)

- Texto `"AUTOMAPA  [Tab]"` em `Vector2(8, 18)`, corpo **12**, cor `C_FRAME` (`#5a4020`), com `ThemeDB.fallback_font`.
- Marcador de norte: letra `"N"` em `Vector2(AREA.size.x − 20, 18)`, corpo 12, cor `C_FRAME`, e logo abaixo um triângulo de 6 px apontando para cima, centrado em x = 624.
- Os dois são desenhados **depois** das células e **antes** da moldura, então ficam por cima das células.
- A escala não muda: `CELL_PX = 8` (1 célula de 2 m = 8 px), a área é `Rect2(0, 0, 640, 312)`, `ALPHA = 0.6`, o norte (+z) fica para cima e o jogador fica no centro (320, 156).

### 3.3 Gate M5-V2 (headless)

1. Semente 1, `WorldSim.new(1, "dungeon")`, um `step(IntInput.new())`. Com `cell_rects(get_visited(), get_grid(), get_player())`:
   - a lista não fica vazia;
   - o número de entradas é igual ao número de células visitadas e não sólidas cuja área intersecta a tela (recontado no gate);
   - existe uma entrada cuja `rect` contém `Vector2(320, 156)`, ou seja, a célula do jogador fica no centro;
   - todas as `rect` têm tamanho `8×8`.
2. Rode 600 ticks do piloto de combate (semente 1, como em M5-A4). `cell_rects` continua com uma entrada que contém `Vector2(320, 156)`, e todas as entradas continuam a vir de células visitadas e não sólidas. Células fora da tela podem sair da lista, porque o mapa é centrado no jogador.
3. A string do cabeçalho medida com `fallback_font.get_string_size(..., 12)` cabe em `x + w ≤ 600`, então não encosta no "N".

---

## 4. M5 e M6 / C14 e C17: efeitos sonoros novos (`view/audio_sfx.gd`)

### 4.1 Regras herdadas da R5 (não mudam)

Síntese procedural em código, sem arquivo de áudio. `AudioStreamWAV` com 16 bits, 22050 Hz, mono, sem loop. Ataque linear de 2 ms e decaimento exponencial. Pico ≤ 22937. Ruído com o `PCG32` local (`0xA0D10`, fluxo 7). Pool de 6 players. No máximo 1 instância de cada id por quadro. Nada toca no primeiro `apply_state` nem depois de um terminal.

**Os 3 ids novos entram no fim de `IDS`.** Assim, se o ruído for gerado em sequência num único `PCG32`, os bytes dos 8 streams antigos continuam idênticos.

### 4.2 Tabela

| id | Marco | Gatilho | Síntese | Duração | `volume_db` |
|---|---|---|---|---|---|
| `pickup` | M6 | `inventory.potion_hp` ou `inventory.potion_sp` subiu, ou `inventory.key` passou de `false` para `true`, ou `gold` subiu | seno de 988 Hz na primeira metade e de 1319 Hz na segunda (som de moeda), τ = 60 ms em cada metade | 0,15 s | −8 |
| `level_up` | M6 | `level` subiu | arpejo de três notas iguais (523, 659 e 784 Hz, 0,15 s cada), onda quadrada com amplitude 0,5 e τ = 120 ms por nota | 0,45 s | −6 |
| `map` | M5 | `map_open` mudou em relação ao quadro anterior (abrir ou fechar) | ruído com passa-baixa fixo em 2500 Hz (papel), τ = 50 ms | 0,12 s | −12 |

- Se `pickup` e `level_up` acontecerem no mesmo quadro, os dois tocam, nessa ordem (a ordem é a da tabela, depois dos 8 ids da R5).
- Em `detect_events`, leia os campos novos com `.get(chave, padrão)` (`inventory` com o padrão `{"potion_hp": 0, "potion_sp": 0, "key": false}`, `gold` com 0, `level` com 1). Assim os dicionários sintéticos de A-SFX1 e A-SFX4, que não têm esses campos, continuam dando os mesmos resultados.

### 4.3 API

```
static func detect_events(prev_p, p, prev_en, en) -> Array      # agora também devolve pickup/level_up (no fim)
func apply_state(p: Dictionary, enemies: Array, terminal: String, map_open: bool = false) -> void
```

- `map` é detectado em `apply_state`, e não em `detect_events`, porque não é estado do jogo. A regra é: se `_has_prev` e `map_open != _prev_map`, acrescente `"map"` no fim da lista do quadro. Guarde `_prev_map = map_open`. Também não toca nada depois de um terminal.
- Em `main.gd`, `sync_view()` passa `_automap.visible` como quarto argumento.

### 4.4 Gates

| ID | Marco | Asserção |
|---|---|---|
| **A-SFX6** | M5 | Com um `AudioSfx` dentro da árvore: (1) o primeiro `apply_state(p, [], "NONE", true)` não registra nada; (2) a mesma chamada com `false` registra exatamente `["map"]`; (3) repetir `false` não registra nada; (4) com `terminal = "DEAD"`, alternar `map_open` não registra nada. O stream `map` tem 16 bits, 22050 Hz, mono, `data.size() == 2·round(0,12·22050)`, pico em `(0, 22937]` e SHA-256 idêntico entre duas instâncias |
| **A-SFX7** | M6 | `detect_events` com: `gold` 0→25 → `["pickup"]`; `inventory.key` false→true → `["pickup"]`; `potion_hp` 0→1 → `["pickup"]`; `level` 1→2 e `potion_sp` 0→1 no mesmo quadro → `["pickup", "level_up"]` (ordem da tabela). Estados iguais → `[]`. Os streams `pickup` (0,15 s) e `level_up` (0,45 s) passam pelas mesmas verificações de formato, pico e determinismo de A-SFX3. A-SFX1 a A-SFX5 continuam passando sem mudança |

---

## 5. M6 / C15: item em quadro no modo atração

### 5.1 Critério da semente de vitrine (estende o plano R5 §4.1)

A semente é aceita se valem **as duas** condições:
1. o critério de inimigo da R5, sem nenhuma mudança: ≥ 90 ticks com inimigo em quadro dentro de `[60, 420]`, com o primeiro desses ticks ≤ 300;
2. **novo:** ≥ **30** ticks (0,5 s) dentro de `[60, 420]` com algum **item em quadro**.

Um item está em quadro num tick quando estas condições valem ao mesmo tempo:
- `taken == false`;
- com centro do item `ix = cell_x·Grid.CELL + Grid.CELL/2` e `iz = cell_z·Grid.CELL + Grid.CELL/2`, a distância euclidiana ao jogador é ≤ **8192 u** (4 células);
- `|wrapi(bearing − angle, −2048, 2048)| ≤ 341 BAM` (±30°), com `bearing` calculado em float **no script de teste** e a mesma convenção de `enemies_in_frame`;
- `EnemySim.line_of_sight(grid, ix, iz, p.pos_x, p.pos_z) == true`.

Implemente isso como `static func items_in_frame(w) -> Array` (ids) em `tests/find_showcase_seed.gd`, ao lado de `enemies_in_frame`. `evaluate(s)` passa a devolver `[count_enemy, first_enemy, count_item]`, e `accepted` testa as duas condições.

**Busca:** `s = 1 .. 2000` em ordem crescente. A **primeira** semente aceita vira `DEFAULT_SEED`. O comentário ao lado da constante passa a ser `# semente de vitrine (plano R6 §5.1): N ticks com inimigo (primeiro em t=T), M ticks com item`.

**Escada de fallback, determinística e registrada no comentário:**
1. Se nenhuma semente passar com 30 ticks de item, repita a busca com **15**.
2. Se ainda nenhuma passar, mantenha `DEFAULT_SEED = 223`, não crie V-SHOWCASE2 como PASS forçado e relate com `blocked`.

Não mexa no piloto, na geração nem no núcleo para forçar o resultado.

### 5.2 Gate V-SHOWCASE2 (headless, sem GPU)

Instancie `main.tscn` sem `attach_world`, com a semente `DEFAULT_SEED`, e chame `_physics_process` mais `sync_view()` 420 vezes, porque é o modo atração real (com a agenda de C12 ativa). Em cada tick avalie `items_in_frame(main.world)`. O gate passa se:
- a contagem dentro de `[60, 420]` é ≥ o limiar usado (30, ou 15 pela escada de fallback);
- em todo tick com item em quadro, o `Sprite3D` `ItemView/Item_<id>` tem `visible == true`, `billboard == BILLBOARD_FIXED_Y` e `pixel_size` igual ao de `ItemView.SPRITES` para o tipo;
- V-SHOWCASE (inimigo, R5) continua passando com a mesma semente. Isso é verificado pelo próprio gate da R5.

Na saída do gate, informe a semente, a contagem, o primeiro tick e os tipos de item vistos.

---

## 6. M6 / C16: textos legíveis (HUD de M6 e tela final)

### 6.1 HUD (`view/hud_daggerfall.gd`)

Medidas da `ThemeDB.fallback_font` (Godot 4.7.2), conferidas pelo planejador: no corpo 10, a altura da linha é **14 px**. `"Nv 3  XP 999  Ouro 999"` mede 109 px, `"PV 9  PG 9  Chave"` cerca de 82 px, e `"Chave da Saída!"` 76 px.

| Elemento | Antes | Depois |
|---|---|---|
| `LEVEL_TEXT_RECT` | `Rect2(140, 318, 128, 12)`, corpo 8 | `Rect2(140, 316, 128, 14)`, corpo **10** |
| `INV_TEXT_RECT` | `Rect2(140, 334, 128, 12)`, corpo 8 | `Rect2(140, 333, 128, 14)`, corpo **10** |
| `Message` | `(384, 318)` com 248×36, corpo 8 | mesmo retângulo, corpo **10**: 2 linhas de 14 px cabem em 36 |
| `HpText` / `SpText` | corpo 8 | **sem mudança** (são de M3) |

- `_make_text` passa a receber o corpo da fonte como parâmetro: `_make_text(name, rect, font_size := 8)`. As chamadas de `HpText` e `SpText` continuam com 8.
- Os formatos dos textos **não mudam** (M6-V3 compara strings literais).
- Os retângulos novos ficam dentro de `PANEL_RECT` (312 a 360) e não intersectam a bússola `Rect2(272, 322, 96, 22)`, porque terminam em x = 268. Também não intersectam `HP_TEXT_RECT`, `SP_TEXT_RECT` (que terminam em x = 136) nem um ao outro (o primeiro vai de 316 a 330 e o segundo de 333 a 347).

### 6.2 Tela final (`view/end_screen.gd`)

| Elemento | Antes | Depois |
|---|---|---|
| Pergaminho | `Rect2(160, 66, 320, 180)` | **sem mudança** |
| `Title` | posição (0, 16), 320×24, corpo 16 | posição (0, 14), 320×32, corpo **24** |
| `Stats` | posição (0, 60), 320×100, corpo 8 | posição (0, 56), 320×112, corpo **12** (4 linhas de 17 px = 68 px) |

Os textos (`TITLES` e `"Nível %d\nOuro %d\nXP %d\nTicks %d"`) **não mudam** (M6-V1).

### 6.3 Gates

| ID | Marco | Asserção |
|---|---|---|
| **M6-V4** | M6 | Instanciar `hud_daggerfall.tscn`. `level_text` e `inv_text` têm corpo 10 (`get_theme_font_size("font_size") == 10`) e `get_rect()` igual aos novos `LEVEL_TEXT_RECT` e `INV_TEXT_RECT`. `message` tem corpo 10. `HpText` e `SpText` continuam com corpo 8. As strings de pior caso `"Nv 3  XP 999  Ouro 999"` e `"PV 9  PG 9  Chave"` medidas no corpo 10 têm largura ≤ 128 px, e `"Chave da Saída!"` tem largura ≤ 248 px. Todos os retângulos de texto ficam dentro de `PANEL_RECT` e não se intersectam, nem intersectam bússola, barras ou retrato (mesma checagem de M6-V3) |
| **M6-V5** | M6 | Com o mesmo cenário de M6-V1 (`ESCAPED` no tick 1): `Title` tem corpo 24, `Stats` tem corpo 12, e o pergaminho continua em `Rect2(160, 66, 320, 180)`. Para cada um dos 3 títulos, a largura no corpo 24 é ≤ 304 px (320 menos 2×8 de margem). A altura de `Stats` com 4 linhas no corpo 12 cabe em 112 px, e `Stats` termina dentro do pergaminho (56 + 112 ≤ 180) |

---

## 7. Testes: `_gates_r6()` em `tests/gates/run_gates.gd`

Chame `_gates_r6()` depois de `_gates_r5()` em `_init`. Cada gate imprime uma linha `PASS`/`FAIL` no formato atual. Atualize o comentário de cabeçalho (linha 3) para listar os gates da rodada 6.

| ID | Marco | Seção |
|---|---|---|
| **M5-V1** | M5 | §2.3: agenda do mapa no modo atração, não interferência e saída por input real |
| **M5-V2** | M5 | §3.3: `cell_rects` pura e cabeçalho |
| **A-SFX6** | M5 | §4.4: som `map` |
| **V-SHOWCASE2** | M6 | §5.2: item em quadro no modo atração |
| **M6-V4** | M6 | §6.3: textos de M6 na HUD com corpo 10 |
| **M6-V5** | M6 | §6.3: tela final legível |
| **A-SFX7** | M6 | §4.4: sons `pickup` e `level_up` |

**Total esperado:** 76 + 7 = **83 PASS, 0 FAIL**, com código de saída 0.

---

## 8. Proporção visual: resumo consolidado (sem sprites novos)

- Viewport interno de 640×360, `NEAREST`, *stretch* inteiro, câmera com `fov = 60` (vertical) a 1,6 m. Nada muda.
- **Todos os sprites são 32×32 px** (perfil free, DCSS CC0). Nenhum é criado, trocado ou redimensionado nesta rodada.
- Itens (`item_view.gd`, valores atuais que V-SHOWCASE2 confere): poções e chave com `pixel_size` 0,016, e ouro com 0,012. Ou seja, no máximo 0,51 m e 0,38 m de lado, com o pé em y = 0 (via `foot_y`) e oscilação de ±0,03 m. A 4 m da câmera, uma poção ocupa cerca de 40 px dos 360 px da tela. Isso é pequeno, mas legível, e coerente com paredes de 2 m (cerca de 156 px à mesma distância).
- Inimigos: sem mudança (rato 0,035, boneco 0,05, esqueleto 0,05, guardião 0,0625).
- Automapa: área de 640×312 acima da HUD, 8 px por célula, alpha 0,6, cabeçalho e "N" no corpo 12.
- HUD: faixa de 640×48 em y = 312. Os textos de M6 passam a corpo 10 (14 px de altura). Barras, retrato, Vida/Vigor (corpo 8) e bússola não mudam.
- Tela final: pergaminho de 320×180 centrado na área de jogo, título no corpo 24 e estatísticas no corpo 12.

## 9. Áudio: resumo

Ficam 11 efeitos procedurais: os 8 da R5 sem mudança, mais `pickup`, `level_up` e `map`. Todos são mono, 16 bits, 22050 Hz, sem arquivo, sem música e sem ambiente. Os de jogo são disparados pela diferença entre estados lidos; o `map`, pela mudança de visibilidade da overlay. Tudo toca pelo mesmo pool de 6 `AudioStreamPlayer` no bus Master. A ausência de áudio no núcleo continua verificada pelo `lint_sim.py` e pela igualdade de cadeias (A-SFX2 e M5-V1).

## 10. Critério de conclusão da rodada

1. `python3 tools/lint_sim.py` → 0 violações. `game/sim/`, `game/scripts/` e `game/assets/` ficam **sem diff** nesta rodada (`git diff --stat main -- game/sim game/scripts game/assets` vazio).
2. Todos os scripts passam em `--check-only`.
3. Em clone limpo, sem `--import`, `godot --headless --path game -s res://tests/run_gates.gd` → **83 PASS / 0 FAIL**, com código de saída 0.
4. `main.gd` expõe `attract_map_open()` e `DEFAULT_SEED` com o comentário da §5.1. `automap_overlay.gd` expõe `cell_rects()`. `audio_sfx.gd` tem os 11 ids.
5. Captura (fora do sandbox): em pelo menos um quadro dos primeiros ~7 s aparece o automapa translúcido, com o mundo 3D visível por trás. Em pelo menos um quadro aparece um item em *billboard* apoiado no piso. Os textos da HUD estão legíveis. A trilha de áudio não fica em silêncio quando o mapa abre ou quando há coleta.
6. `asset_map.json`, `CREDITS.md` e `game/assets/free/` intocados.
