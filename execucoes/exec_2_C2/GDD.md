# Plano do Experimento S4: Benchmark Action RPG Roguelike em Primeira Pessoa (Godot 4.7)

- **Estágio:** S4 (implementação do jogo de referência e do runner headless)
- **Data:** 2026-10-07
- **Status:** proposta de plano. As seções 5 e 6 dependem de congelamento formal antes da primeira coleta (ver §8).
- **Substitui:** o benchmark 2D de visão superior com cinco mecânicas descrito em `secoes/03_metodologia.tex` (§ "Desenho Experimental e Benchmark de Jogo") e implementado em `game/scripts/*.gd` (commit `16c1a39`).
- **Decisão registrada:** `DECISIONS.md`, entrada de 2026-10-07. **Proveniência:** `PROVENANCE.jsonl`, evento `pivot_benchmark_arpg`.

---

## Sumário

1. [Visão geral do jogo](#1-visão-geral-do-jogo)
2. [Arquitetura: núcleo de simulação vs. camada de apresentação](#2-arquitetura-núcleo-de-simulação-vs-camada-de-apresentação)
3. [Unidades, aritmética e constantes canônicas](#3-unidades-aritmética-e-constantes-canônicas)
4. [Marcos incrementais HoH (M1 a M6)](#4-marcos-incrementais-hoh-m1-a-m6)
5. [Contrato de simulação estável e verificação headless](#5-contrato-de-simulação-estável-e-verificação-headless)
6. [Protocolo experimental: condições C0, C1, C2 e métricas](#6-protocolo-experimental-condições-c0-c1-c2-e-métricas)
7. [Observações de engenharia e riscos](#7-observações-de-engenharia-e-riscos)
8. [Cronograma do estágio S4 e itens a congelar](#8-cronograma-do-estágio-s4-e-itens-a-congelar)
9. [Impacto sobre o manuscrito e o código existente](#9-impacto-sobre-o-manuscrito-e-o-código-existente)

---

## 1. Visão geral do jogo

### 1.1 Conceito

Action RPG roguelike em primeira pessoa, 2.5D/3D, construído em **Godot 4.7**. Une duas referências:

| Referência | O que tomamos | O que não tomamos |
|---|---|---|
| **DOOM (1993)** | Movimentação rápida com momento e atrito, *strafe*, giro só no eixo horizontal (sem olhar para cima/baixo), inimigos em *sprites* 2D sempre voltados para a câmera, automapa que não pausa o jogo, simulação em *ticks* fixos e aritmética de ponto fixo. | Armas de fogo, *hitscan*, alturas variáveis de piso. |
| **The Elder Scrolls II: Daggerfall (1996)** | Ambientação de masmorra medieval, classe Guerreiro, atributos de Vida e Vigor (*fatigue*), barra de HUD inferior com três barras verticais e bússola, molduras de pedra/pergaminho, automapa como planta translúcida. | Mundo aberto, sistema de magia, criação de personagem completa, masmorras gigantes com labirintos verticais. |

A versão do Daggerfall é **modernizada e leve**: resolução interna baixa (640×360, filtro *nearest*) ampliada para a janela, HUD em `CanvasLayer` sem *shaders* pesados, fonte *pixel* legível.

### 1.2 Escopo da primeira versão (benchmark)

- **Uma classe:** Guerreiro (espada + escudo). Outras classes ficam fora do escopo do benchmark.
- **Uma fase:** masmorra gerada por semente com 6 a 9 salas conectadas por corredores e portas.
- **Roguelike:** morte permanente (fim da partida), layout, inimigos e itens determinados pela semente. Não há meta-progressão entre partidas.
- **Objetivo:** encontrar a Chave da Saída e alcançar o Portal de Fuga, sobrevivendo aos inimigos.

### 1.3 Controles

| Ação | Teclado/mouse | Campo do input inteiro (§5.2) |
|---|---|---|
| Avançar / recuar | W / S | `move ∈ {-1, 0, 1}` |
| *Strafe* esquerda / direita | A / D | `strafe ∈ {-1, 0, 1}` |
| Girar (teclado) | ← / → | `turn` em unidades angulares |
| Girar (mouse, só horizontal) | movimento X do mouse | `turn` (quantizado, §5.2) |
| Ataque de espada | botão esquerdo / Ctrl | `attack: bool` (borda de subida) |
| Bloqueio com escudo | botão direito / Shift | `block: bool` (nível) |
| Usar (portas, portal, itens) | E / Espaço | `use: bool` (borda de subida) |
| Beber poção de vida / vigor | 1 / 2 | `quaff ∈ {0, 1, 2}` |
| Automapa | **Tab** (alterna) | não entra na simulação (§4.5, §5.4) |

Não há eixo vertical de visão, pulo ou agachamento, como no DOOM original. Isso elimina uma dimensão inteira de estado contínuo e mantém a lógica no plano XZ.

---

## 2. Arquitetura: núcleo de simulação vs. camada de apresentação

A regra arquitetural central do benchmark é: **toda decisão de jogo acontece num núcleo de simulação puro, inteiro e sem nós de cena; a camada 3D apenas lê esse estado e desenha.** A camada 3D nunca escreve no núcleo.

```
            input do jogador (teclado/mouse)       trilha gravada / piloto do runner
                         │                                    │
                 ┌───────▼────────┐                           │
                 │ InputSampler   │  quantiza para IntInput   │
                 └───────┬────────┘                           │
                         └──────────────┬─────────────────────┘
                                        ▼
                         ┌──────────────────────────────┐
                         │  Sim (RefCounted, inteiro)   │   step(IntInput) -> estado s_k
                         │  ordem fixa de subsistemas   │   hash H_k = SHA256(canon(s_k))
                         └──────────────┬───────────────┘
                                        │ somente leitura
              ┌─────────────────────────┼─────────────────────────┐
              ▼                         ▼                         ▼
      Mundo 3D (Node3D)        Inimigos (Sprite3D)        HUD / Automapa / Espada
      malha da masmorra        billboard Y                (CanvasLayer)
```

### 2.1 Estrutura de diretórios proposta

```
game/
  project.godot              # atualizado para 3D (§7.6)
  sim/                       # núcleo: só RefCounted, sem Node, sem float
    fixed_math.gd            # multiplicação/divisão Q16, divisão com truncamento explícito
    trig_table.gd            # tabela seno/cosseno Q16 com 4096 entradas (gerada, §3.3)
    rng_pcg32.gd             # PCG32 próprio (não depende do RandomNumberGenerator do motor)
    int_input.gd             # struct de entrada por tick
    grid.gd                  # grade de células (sólido/piso/porta) e colisão AABB x grade
    dungeon_gen.gd           # M2
    player_sim.gd            # M1 + M3
    combat.gd                # M3: ataque, bloqueio, vigor
    enemy_sim.gd             # M4: estados, campo de fluxo BFS, ataques
    automap_sim.gd           # M5: bitmap de células visitadas
    items_sim.gd             # M6: itens, XP, níveis, condição terminal
    world_sim.gd             # orquestra step() em ordem fixa
    state_hash.gd            # serialização canônica + SHA-256 + guarda de tipos
  view/                      # apresentação: Node3D/Control, pode usar float
    player_view.tscn/.gd     # CharacterBody3D + Camera3D (casca, §7.1)
    dungeon_view.gd          # malha gerada a partir de grid.gd
    enemy_view.tscn/.gd      # Sprite3D billboard
    weapon_view.tscn/.gd     # espada/escudo em 1ª pessoa (2D sobre a câmera)
    hud_daggerfall.tscn/.gd  # barras de Vida/Vigor, bússola, mensagens
    automap_overlay.tscn/.gd # M5
  input/
    input_sampler.gd         # teclado/mouse -> IntInput
    trace_io.gd              # gravação/leitura de trilhas de input (JSON Lines)
  scripts/
    headless_runner.gd       # reescrito para o ARPG (§5.6)
  tests/
    traces/                  # trilhas douradas por marco (visíveis ao verificador)
    gates/                   # asserções do Acceptance/Preservation Gate
  assets/
    asset_map.json           # identificadores lógicos -> caminho por perfil (§7.4.2)
    CREDITS.md               # manifesto de licenças do perfil free (§7.4)
    free/                    # perfil A: CC0/CC-BY, versionado
    daggerfall/              # perfil B: extraído da cópia local, NO .gitignore
tools/
  gen_trig_table.py          # gera sim/trig_table.gd de forma reprodutível
  df_extract.py              # perfil B: extrai PNG da cópia DOS local do Daggerfall (§7.4.3)
```

### 2.2 Ordem fixa de atualização por tick

`WorldSim.step(input)` executa, sempre nesta ordem:

1. `tick += 1`; se o estado é terminal, congela (só o contador avança, §4.6).
2. Jogador: giro → empuxo/momento → colisão com a grade (eixo X, depois Z).
3. Interação (`use`): portas, portal, coleta de itens sob o jogador.
4. Poções (`quaff`).
5. Combate do jogador: máquina de estados do golpe, teste da hitbox na janela ativa, bloqueio.
6. Inimigos, em ordem crescente de `id`: percepção → movimento → ataque.
7. Resolução de dano recebido pelo jogador (com bloqueio) e mortes.
8. Regeneração de vigor, XP e subida de nível.
9. Automapa: marcação de células visitadas.
10. Teste das condições terminais.
11. Serialização canônica e cálculo de `H_k`.

Nenhum subsistema itera sobre `Dictionary` sem ordenar as chaves, e nenhum usa sinais (`signal`) do motor para lógica, porque a ordem de entrega de sinais não faz parte do contrato.

---

## 3. Unidades, aritmética e constantes canônicas

### 3.1 Unidades

| Grandeza | Unidade de simulação | Conversão para a apresentação |
|---|---|---|
| Distância | `u` (inteiro), **1 m = 1024 u** | `float(u) / 1024.0` |
| Célula da grade | **2048 u = 2 m** | — |
| Ângulo | BAM de 12 bits: **1 volta = 4096** | `TAU * a / 4096.0` |
| Tempo | tick; **60 ticks = 1 s** (`physics_ticks_per_second=60`) | — |
| Seno/cosseno | Q16 (65536 = 1,0) | — |

O inteiro do GDScript é de 64 bits; com coordenadas máximas de 64 células × 2048 u = 131072 u e produtos Q16, o maior produto intermediário fica abaixo de 2^40, sem risco de *overflow*.

### 3.2 Divisão e arredondamento

A semântica de divisão inteira é fixada por função própria em `fixed_math.gd`: `div_trunc(a, b)` trunca em direção a zero e `div_floor(a, b)` arredonda para baixo. O código da simulação não usa o operador `/` diretamente sobre valores que possam ser negativos; usa sempre uma das duas funções, o que torna a escolha explícita e testável. O atrito depende disso: com `div_trunc`, uma velocidade de 1 u/tick decai para 0 (`58/64 → 0`), enquanto um arredondamento para baixo deixaria velocidades negativas presas em −1 para sempre. O deslocamento `>> 16` usado nos produtos Q16 é aritmético (arredonda para baixo) e é aceito como está, por ser determinístico e aplicado de forma uniforme.

### 3.3 Tabela trigonométrica

`sim/trig_table.gd` contém `const SIN_Q16: PackedInt32Array` com 4096 entradas, gerada por `tools/gen_trig_table.py` (`round(sin(2πi/4096) * 65536)`, arredondamento do Python 3). O cosseno é `SIN_Q16[(a + 1024) & 4095]`. O teste de integridade compara o SHA-256 da tabela com o valor registrado no gate de M1. **Nenhuma chamada a `sin()`, `cos()`, `atan2()` ou `sqrt()` em float é permitida no núcleo.**

### 3.4 Constantes canônicas (valores iniciais, ajustáveis até o congelamento)

| Constante | Valor | Observação |
|---|---|---|
| `PLAYER_HALF` | 384 u (0,375 m) | caixa quadrada no plano XZ, estilo DOOM |
| `THRUST_FORWARD` | 14 u/tick² | |
| `THRUST_STRAFE` | 12 u/tick² | *strafe* um pouco mais lento, como no DOOM |
| `FRICTION_NUM / DEN` | 58 / 64 | `v ← div_trunc(v·58, 64) + empuxo` |
| Velocidade terminal | ≈ 149 u/tick (≈ 8,7 m/s) frente; ≈ 128 u/tick lateral | |
| Diagonal | **não normalizada** | homenagem intencional ao *straferunning* do DOOM; documentada para que o verificador não a trate como defeito |
| `TURN_KEY` | 48 BAM/tick (≈ 253°/s) | |
| `HP_MAX` / `STAMINA_MAX` | 100 / 100 | |
| Golpe: preparação / ativo / recuperação | 6 / 6 / 12 ticks (0,4 s total) | |
| Golpe: custo de vigor / dano / alcance / arco | 12 / 25 / 1638 u (1,6 m) / ±40° | |
| Bloqueio: arco frontal / redução / custo | ±60° / 75% / `dano/2 + 5` de vigor | |
| Regeneração de vigor | +1 a cada 3 ticks fora de ataque e bloqueio | |
| Atordoamento por quebra de guarda | 20 ticks | |
| `K_MAX` (orçamento de ticks por partida) | 18000 ticks (5 min) | |

---

## 4. Marcos incrementais HoH (M1 a M6)

Cada marco é um incremento que o Planejador ($D_t$) pode selecionar. Para cada um definimos: **escopo**, **especificação técnica**, **Acceptance Gate** (critérios verificáveis em headless) e **Preservation Gate** (o que ele não pode quebrar). Os gates de todos os marcos já aceitos são reexecutados em toda iteração (§6.4).

Dependências: `M1 → M2 → {M3, M5}`, `M3 → M4`, `{M4, M5} → M6`. M3 e M5 podem ser feitos em qualquer ordem depois de M2.

### 4.1 M1: Controlador em primeira pessoa estilo DOOM

**Escopo.** Movimento rápido com momento, *strafe*, giro horizontal e colisão com paredes numa sala de teste fixa (sem gerador ainda).

**Especificação técnica.**

- Nó de cena: `CharacterBody3D` com `Camera3D` na altura dos olhos (1,5 m) e `CollisionShape3D` cilíndrica (raio 0,375 m, altura 1,7 m). **O nó é apenas casca de apresentação**: sua `position` é escrita a cada quadro a partir do estado inteiro; `move_and_slide()` não é usado para lógica (justificativa em §7.1).
- Estado inteiro: `pos_x, pos_z, vel_x, vel_z, angle`.
- Giro: `angle ← (angle + turn) & 4095`.
- Empuxo: `f = (cos a, sin a)`, `r = (cos(a − 1024), sin(a − 1024))` (vetor à direita); `thrust = (move·THRUST_FORWARD·f + strafe·THRUST_STRAFE·r) >> 16`.
- Momento: `vel ← div_trunc(vel·58, 64) + thrust`, por eixo.
- Colisão "cilindro como AABB inteira": o cilindro é aproximado por um quadrado de meia-aresta `PLAYER_HALF` no plano XZ, como os *things* do DOOM. Resolução separada por eixo (X, depois Z): aplica-se o deslocamento do eixo, e se a caixa intersecta alguma célula sólida a posição é presa à face da célula (`face − PLAYER_HALF` ou `face + PLAYER_HALF`) e a velocidade daquele eixo é zerada. Como o deslocamento por tick (≤ ~280 u) é muito menor que a célula (2048 u), não há tunelamento.
- Intervalos semiabertos `[x, x + w)`, herdados de `fixed_aabb.gd`: caixas que só se tocam pela face não colidem.

**Acceptance Gate (headless).**

| ID | Cenário (trilha de input) | Asserção |
|---|---|---|
| M1-A1 | 120 ticks de `move=1` numa sala aberta, `angle=0` | `pos_x` final igual ao valor de referência; `vel_x` converge para a terminal |
| M1-A2 | `strafe=1` por 60 ticks | deslocamento só no eixo perpendicular ao ângulo |
| M1-A3 | 64 ticks de `turn=+64` (64 × 64 = 4096); depois 64 ticks de `turn=-64` | ângulo volta exatamente ao inicial nas duas sequências |
| M1-A4 | 600 ticks de input aleatório semeado contra paredes | **invariante por tick:** caixa do jogador ∩ células sólidas = ∅ |
| M1-A5 | soltar todos os comandos após velocidade máxima | velocidade chega a 0 em número fixo de ticks |
| M1-A6 | integridade | SHA-256 de `SIN_Q16` igual ao registrado |

**Preservation Gate.** Nenhum (marco base).

### 4.2 M2: Gerador de masmorra e salas conectadas

**Escopo.** Masmorra 3D de uma fase com múltiplas salas, paredes, corredores e portas, gerada por semente.

**Especificação técnica.**

- Grade de 64 × 64 células; tipos: `SOLID`, `FLOOR`, `DOOR_CLOSED`, `DOOR_OPEN`, `DOOR_LOCKED`, `EXIT`.
- Algoritmo (só inteiros, `rng_pcg32` semeado com `seed`):
  1. Sortear `N ∈ [6, 9]` salas retangulares de 4×4 a 9×9 células, por tentativa e rejeição (no máximo 200 tentativas), com margem mínima de 2 células entre salas.
  2. Conectar centros por **árvore geradora mínima de Prim** com distância Manhattan e desempate pelo menor `id`.
  3. Acrescentar arestas extras (laços) com probabilidade 15% por par vizinho, para evitar masmorra puramente em árvore.
  4. Escavar corredores em "L" de 1 célula de largura (primeiro horizontal, depois vertical; a ordem vem de um bit do RNG).
  5. Porta em cada célula onde um corredor entra numa sala.
  6. Sala inicial = sala 0; Sala da Saída = sala de maior distância BFS a partir da inicial, com porta `DOOR_LOCKED` e célula `EXIT`.
- Portas: `use` a até 1 célula de distância, de frente (|ângulo relativo| ≤ 45°), abre `DOOR_CLOSED`; `DOOR_LOCKED` exige a chave (M6). Porta aberta permanece aberta (sem temporizador, para simplificar o estado).
- Apresentação: `dungeon_view.gd` constrói um `ArrayMesh` (ou `GridMap`) a partir da grade, com texturas de pedra de baixa resolução, iluminação ambiente fraca e `OmniLight3D` de tocha presa à câmera. Não participa da lógica.

**Acceptance Gate (headless), avaliado para as sementes 1 a 100.**

| ID | Asserção |
|---|---|
| M2-A1 | número de salas em [6, 9] e salas sem sobreposição |
| M2-A2 | todas as células `FLOOR` alcançáveis a partir da sala inicial (BFS, portas consideradas abertas) |
| M2-A3 | a Sala da Saída é diferente da inicial e a distância BFS entre elas ≥ 20 células |
| M2-A4 | toda porta tem piso nos dois lados opostos e sólido nos outros dois |
| M2-A5 | mesma semente → mesmo SHA-256 da grade; sementes diferentes → grades diferentes em ≥ 99 de 100 pares |
| M2-A6 | o jogador consegue atravessar uma porta aberta e é bloqueado por uma porta fechada (trilha dourada) |

**Preservation Gate.** M1-A1 a M1-A6 (a sala de teste de M1 continua disponível como `dungeon_gen.test_room()`).

### 4.3 M3: Sistema de combate do Guerreiro

**Escopo.** Espada em primeira pessoa com *slash* rápido, hitbox 3D, escudo/bloqueio e consumo de vigor.

**Especificação técnica.**

- Máquina de estados do golpe: `IDLE → WINDUP(6) → ACTIVE(6) → RECOVERY(12) → IDLE`. `attack` só inicia o golpe em `IDLE`, sem bloqueio ativo e com `stamina ≥ 12`; o custo é debitado na entrada de `WINDUP`.
- **Hitbox 3D:** setor cilíndrico à frente do jogador, avaliado em todos os 6 ticks de `ACTIVE`. Para o vetor `d` do jogador ao centro do alvo:
  - `along = (d · f) >> 16`, `side = |d × f| >> 16`;
  - acerto se `0 < along ≤ 1638 + raio_alvo` **e** `side · 1024 ≤ along · 859` (tan 40° ≈ 859/1024), **ou** se as caixas já se sobrepõem;
  - faixa vertical [0,2 m; 1,8 m] contra a faixa do alvo. Hoje todos estão no chão e o teste sempre passa, mas ele fica no contrato para extensões.
- Um acerto por alvo por golpe (`swing_hits`, como no protótipo 2D).
- Bloqueio (`block` em nível): só fora de `WINDUP/ACTIVE`; reduz o empuxo pela metade. Um ataque inimigo cuja origem está a ±60° do `angle` do jogador tem dano reduzido para `dano − div_trunc(dano·3, 4)` e consome `div_trunc(dano, 2) + 5` de vigor. Se o vigor não basta, a guarda quebra: dano integral e 20 ticks de atordoamento (sem atacar nem bloquear).
- Regeneração: +1 de vigor a cada 3 ticks, fora de ataque e bloqueio.
- Apresentação: `weapon_view` desenha espada e escudo em 2D sobre a câmera (sprites em `CanvasLayer`, como as armas do DOOM), com quadros sincronizados ao estado do golpe; balanço da arma (*bob*) proporcional à velocidade, só visual. A HUD estilo Daggerfall mostra Vida (vermelho) e Vigor (verde) como barras verticais na moldura inferior.
- Para M3 existe um **boneco de treino** estático (`training_dummy`, 100 HP, sem IA) na sala de teste, para isolar o combate da IA de M4.

**Acceptance Gate (headless).**

| ID | Asserção |
|---|---|
| M3-A1 | golpe leva exatamente 24 ticks de `IDLE` a `IDLE`; janela ativa nos ticks 7 a 12 |
| M3-A2 | boneco a 1,2 m de frente recebe exatamente 25 de dano por golpe; a 1,2 m e 60° de lado recebe 0 |
| M3-A3 | um golpe nunca aplica dano duas vezes ao mesmo alvo |
| M3-A4 | com `stamina < 12`, `attack` é ignorado e o vigor não muda |
| M3-A5 | dano frontal bloqueado = 25% (truncado); dano pelas costas com bloqueio = 100% |
| M3-A6 | quebra de guarda gera 20 ticks de atordoamento |
| M3-A7 | vigor nunca sai de [0, `STAMINA_MAX`] (invariante por tick) |

**Preservation Gate.** M1-A* e M2-A*.

### 4.4 M4: Entidades e inimigos em billboard 2.5D

**Escopo.** Inimigos desenhados como `Sprite3D` sempre voltados para a câmera, com IA de percepção, perseguição e ataque.

**Especificação técnica.**

- Tipos (dados em tabela constante):

| Tipo | HP | Velocidade | Dano | Alcance | Preparação | Recarga | XP |
|---|---|---|---|---|---|---|---|
| Rato gigante | 20 | 100 u/tick (≈ 5,9 m/s) | 5 | 1,0 m | 8 ticks | 30 ticks | 10 |
| Esqueleto | 50 | 68 u/tick (≈ 4 m/s) | 12 | 1,2 m | 18 ticks | 45 ticks | 25 |
| Guardião da Saída | 150 | 51 u/tick (≈ 3 m/s) | 25 | 1,4 m | 30 ticks | 60 ticks | 100 |

- Máquina de estados: `IDLE → CHASE → WINDUP → STRIKE → COOLDOWN → CHASE`, e `DEAD`. A preparação (*windup*) é longa de propósito: ela abre a janela de leitura que dá sentido ao bloqueio de M3.
- Percepção: acorda quando o jogador está a ≤ 6 células **e** há linha de visão, calculada por DDA inteiro na grade (estilo Amanatides–Woo, só inteiros). Inimigos acordados não voltam a dormir.
- Perseguição: campo de fluxo por **BFS a partir da célula do jogador**, vizinhança-4 em ordem fixa N, L, S, O, recalculado só quando o jogador muda de célula. O inimigo anda em linha reta em direção ao centro da próxima célula (passo inteiro, sem momento) e entra em `WINDUP` quando a distância Chebyshev é ≤ alcance.
- Colisão inimigo-inimigo: em ordem crescente de `id`, um movimento que faria a caixa intersectar outra entidade é cancelado naquele eixo. Não há empurrão.
- O ataque é resolvido no tick de `STRIKE` contra a posição corrente do jogador (o jogador pode sair do alcance durante a preparação).
- Posicionamento (com M2): 1 inimigo por sala exceto a inicial, tipo sorteado pelo RNG da masmorra; o Guardião é posto na Sala da Saída.
- Apresentação (`enemy_view`): `Sprite3D` com `billboard = BILLBOARD_FIXED_Y` (gira só em torno de Y, como no DOOM), `texture_filter = NEAREST`, `shaded = false`, `alpha_cut = DISCARD`, `pixel_size` ajustado para ~1,6 m de altura. Quadros de 8 direções escolhidos pelo ângulo entre a orientação do inimigo e a câmera (só visual); quadros de andar, preparar, golpear, dor e morte.

**Acceptance Gate (headless).**

| ID | Asserção |
|---|---|
| M4-A1 | inimigo sem linha de visão permanece `IDLE` mesmo a 3 células |
| M4-A2 | inimigo acordado alcança o jogador parado em qualquer sala conexa das sementes 1 a 20 em ≤ 1200 ticks |
| M4-A3 | um ataque só causa dano se o jogador estiver no alcance no tick de `STRIKE` |
| M4-A4 | a recarga impede dois ataques do mesmo inimigo em menos de `preparação + recarga` ticks |
| M4-A5 | inimigos nunca ficam dentro de células sólidas nem uns dentro dos outros (invariante) |
| M4-A6 | inimigo com HP ≤ 0 vai a `DEAD` no mesmo tick e deixa de colidir e atacar |
| M4-A7 | cena: todo nó de inimigo é `Sprite3D` com `billboard == BILLBOARD_FIXED_Y` (inspeção da árvore em headless) |

**Preservation Gate.** M1-A*, M2-A*, M3-A*.

### 4.5 M5: Automapa translúcido

**Escopo.** Sobreposição 2D alternada pela tecla Tab, mostrando a planta das áreas já visitadas.

**Especificação técnica.**

- Modelo (na simulação): `visited: PackedByteArray` de 64 × 64. Ao entrar numa célula de sala, todas as células daquela sala e suas paredes de contorno são marcadas; em corredores, marca-se a célula atual e as vizinhas-8. Esse bitmap faz parte do estado hasheado.
- Visão (fora da simulação): `automap_overlay` é um `Control` em `CanvasLayer` acima da HUD que desenha com `_draw()` as bordas entre células visitadas e sólidas (linhas), portas (cor própria; trancada em vermelho), Portal de Fuga após visto, e o jogador como seta orientada por `angle`. Fundo pergaminho com `modulate.a = 0.6`; o mundo 3D continua visível por trás.
- **Tab** alterna `automap_overlay.visible`. Como no DOOM, o jogo **não pausa** com o mapa aberto. O estado "mapa aberto" é de interface e **não entra no estado hasheado**: duas partidas idênticas em que só uma abre o mapa devem ter a mesma cadeia de hashes (esse é o próprio teste M5-A4).
- Centralizado no jogador e com orientação norte fixa; zoom fixo.

**Acceptance Gate (headless).**

| ID | Asserção |
|---|---|
| M5-A1 | no tick 1, `visited` contém exatamente a sala inicial e seu contorno |
| M5-A2 | após a trilha dourada que atravessa um corredor, as células do corredor estão marcadas e as salas não visitadas não estão |
| M5-A3 | `visited` é monotônico: nenhuma célula marcada volta a 0 (invariante) |
| M5-A4 | **não interferência:** mesma semente e trilha, com e sem pressões de Tab → cadeias de hash idênticas |
| M5-A5 | teste de cena em headless: instanciar a overlay, enviar `InputEventKey(Tab)` → `visible` alterna; `0 < modulate.a < 1` |

A aparência final da overlay (legibilidade, cores) não tem verificação automática sem GPU; ela é avaliada qualitativamente por captura de tela fora do sandbox e registrada como observação, sem entrar em $R_{\text{mec}}$.

**Preservation Gate.** M1-A*, M2-A* (e M3/M4 se já aceitos).

### 4.6 M6: Itens, progressão e condição terminal de vitória/fuga

**Escopo.** Itens coletáveis, progressão do Guerreiro e estados terminais da partida.

**Especificação técnica.**

- Itens (posição sorteada pelo RNG da masmorra, em células de piso livres, nunca na sala inicial exceto 1 poção):
  - Poção de Vida (+40 HP, limitado ao máximo) e Poção de Vigor (+50): vão ao inventário ao passar por cima; consumidas com `quaff`.
  - **Chave da Saída:** exatamente uma, numa sala que não é a inicial nem a da Saída; o caminho da sala inicial até ela não pode exigir passar pela porta trancada (verificado na geração; se falhar, a sala é ressorteada de forma determinística).
  - Ouro: pontuação (relatada, não é condição de vitória).
- Progressão: XP por abate (tabela de M4). Nível 2 com 100 XP e nível 3 com 250 XP; cada nível dá +20 `HP_MAX`, +10 `STAMINA_MAX`, +5 de dano da espada, e restaura a vida ao máximo.
- Estados terminais (avaliados no passo 10 de §2.2):
  - `ESCAPED` (vitória/fuga): `use` sobre a célula `EXIT` com a chave no inventário. A porta trancada da Sala da Saída é aberta com `use` + chave. O Guardião **não** precisa estar morto: fugir passando por ele é uma estratégia válida e coerente com o gênero.
  - `DEAD`: HP ≤ 0. Morte permanente.
  - `TIMEOUT`: `tick ≥ K_MAX`.
- Depois do estado terminal, `step()` só incrementa `tick`; o restante do estado fica congelado, e o hash continua a ser emitido (a cadeia tem comprimento K fixo).
- Apresentação: tela final no estilo Daggerfall (pergaminho com o resultado, nível, ouro, ticks); mensagens de coleta na HUD.

**Acceptance Gate (headless).**

| ID | Asserção |
|---|---|
| M6-A1 | para as sementes 1 a 100 existe exatamente uma chave, alcançável sem passar pela porta trancada |
| M6-A2 | poção de vida nunca leva HP acima do máximo; inventário vazio torna `quaff` sem efeito |
| M6-A3 | `use` no `EXIT` sem chave não termina a partida; com chave produz `ESCAPED` no mesmo tick |
| M6-A4 | HP ≤ 0 produz `DEAD`; após o terminal o estado (exceto `tick`) é constante |
| M6-A5 | subida de nível aplica exatamente os bônus da tabela |
| M6-A6 | **fim a fim:** o piloto do runner (§5.6) termina em `ESCAPED` em ≥ 80% das sementes de 1 a 50 (limiar a calibrar com a implementação de referência e congelar antes da coleta) |

**Preservation Gate.** Todos os gates de M1 a M5.

---

## 5. Contrato de simulação estável e verificação headless

Este contrato atualiza para 3D o que `secoes/03_metodologia.tex` já define (laço síncrono, colisão inteira, isolamento estocástico, hash canônico por tick). O que muda é que agora existe uma câmera em perspectiva, rotação contínua e malha 3D, e todos esses elementos precisam ficar **fora** do caminho de decisão.

### 5.1 Regras do núcleo (verificáveis por análise estática)

1. **Sem float no núcleo.** Arquivos em `game/sim/` não podem conter literais float, `float(`, `Vector2`, `Vector3`, `Transform3D`, `Basis`, `sin(`, `cos(`, `atan2(`, `sqrt(`, `lerp(`, `randf`, `randi(` (do motor), `Time.`, `OS.get_ticks`, `delta`. Um *linter* (`grep` com lista de proibição, rodado pelo verificador) rejeita o commit.
2. **Sem nós no núcleo.** `game/sim/*.gd` estende só `RefCounted`; não usa `Node`, `get_tree()`, `signal`, `await` nem `PhysicsServer3D`.
3. **RNG próprio.** Só `rng_pcg32.gd`, semeado pela semente da partida, com fluxos separados (`stream` diferente) para geração da masmorra, IA e piloto do runner. O piloto nunca consome o fluxo da masmorra.
4. **Ordem fixa** conforme §2.2; iteração sobre coleções sempre por índice ou chave ordenada.
5. **Avanço explícito.** O tick só avança por `WorldSim.step()`. No jogo interativo, `_physics_process` chama `step()` uma vez por tick físico com o `IntInput` amostrado; em headless, o runner chama `step()` num laço sem tempo real.
6. **Apresentação somente leitura.** A camada `view/` recebe o estado por cópia ou por *getters*; o *linter* rejeita atribuições a campos de `sim` a partir de `view/`.

### 5.2 Fronteira de entrada (IntInput)

```
IntInput = { move: int∈{-1,0,1}, strafe: int∈{-1,0,1}, turn: int∈[-128,128],
             attack: bool, block: bool, use: bool, quaff: int∈{0,1,2} }
```

- O `InputSampler` converte o mouse em `turn`: acumula o deslocamento X em pixels, converte por sensibilidade fixa e **carrega o resto fracionário** para o tick seguinte. Essa quantização acontece fora da simulação. Portanto o float do mouse nunca entra no núcleo, e a trilha gravada de `IntInput` reproduz a partida exatamente.
- Uma partida é definida por `(seed, schema_version, trilha de IntInput)`. Trilhas são gravadas em JSON Lines (uma linha por tick) por `trace_io.gd`.

### 5.3 Estado canônico e hash

```
s_k = { schema_version, tick, terminal,
        player:  {pos_x, pos_z, vel_x, vel_z, angle, hp, hp_max, stamina, stamina_max,
                  swing_state, swing_ticks, swing_hits[], blocking, stun_ticks,
                  level, xp, gold, inventory{potion_hp, potion_sp, key}},
        dungeon: {grid_sha256, doors[] (id ordenado)},
        enemies: [{id, type, pos_x, pos_z, hp, state, state_ticks, awake}],   # ordem por id
        items:   [{id, type, cell_x, cell_z, taken}],                         # ordem por id
        automap: {visited_sha256},
        rng:     {dungeon_state, ai_state} }
```

- Serialização: `JSON.stringify(s_k, "", true)` com `sort_keys = true`, sem indentação. **Guarda de tipos** recursiva antes de serializar: só `int`, `bool`, `String`, `Array`, `Dictionary`; qualquer `float` aborta a execução com erro. Isso impede que um float entre no hash e gere representações diferentes entre plataformas.
- A grade (64×64) e o bitmap do automapa entram como SHA-256 próprio, para manter `s_k` pequeno; a grade completa vai uma única vez no cabeçalho do relatório.
- Hash por tick: `H_k = SHA256(JSON_canon(s_k))` (definição do manuscrito).
- **Cadeia** (acréscimo): `C_k = SHA256(C_{k−1} ‖ H_k)`, com `C_0 = SHA256(seed ‖ schema_version)`. `C_K` resume a partida inteira num só valor e facilita comparar muitas execuções. A igualdade da cadeia implica a igualdade de todos os `H_k`; mesmo assim, o relatório guarda os `H_k` para localizar o **primeiro tick divergente**, que é o diagnóstico mais útil para o Desenvolvedor.

### 5.4 Por que a lógica 3D se repete sem GPU

- O Godot em `--headless` usa o *driver* de renderização *dummy*: nada é desenhado, mas a árvore de cena, `Sprite3D`, `Control` e scripts funcionam. Como nenhuma decisão de jogo depende da renderização, da física 3D do motor ou do tempo real, o núcleo produz o mesmo resultado com ou sem GPU.
- A câmera, a malha, a interpolação visual entre `s_{k−1}` e `s_k`, o *bob* da arma e o automapa só **leem** o estado.
- **Teste de não interferência da apresentação** (obrigatório em C2): a mesma semente e trilha rodam (a) só com o núcleo e (b) com a cena completa instanciada em headless; as cadeias `C_K` devem ser iguais. Se forem diferentes, a apresentação está escrevendo no núcleo.

### 5.5 Níveis de repetição verificados

| Nível | Procedimento | Esperado |
|---|---|---|
| R1 intraprocesso | duas instâncias de `WorldSim` no mesmo processo, mesma semente e trilha | `C_K` iguais |
| R2 interprocesso | duas execuções independentes do runner | `C_K` iguais |
| R3 núcleo vs. cena | §5.4 | `C_K` iguais |
| R4 gravação/reprodução | gravar a trilha do piloto e reproduzi-la sem piloto | `C_K` iguais |
| R5 interplataforma (opcional) | x86-64 vs. ARM64, mesma build do Godot | `C_K` iguais; divergência é relatada, não oculta |

### 5.6 Runner headless

```
godot --headless --path game -s res://scripts/headless_runner.gd -- \
      --seed=1337 --ticks=18000 --mode=pilot|replay --trace=in.jsonl \
      --record=out.jsonl --output=runs/report_1337.json [--with-view]
```

- `pilot`: piloto em malha fechada sobre o estado inteiro (como o atual), agora em 3D: segue o campo de fluxo até a chave, depois até a porta da saída e o `EXIT`; combate o inimigo acordado mais próximo usando a janela de preparação para bloquear e contra-atacar; bebe poção abaixo de 30 HP. Usa seu próprio fluxo PCG para variação controlada (passos de exploração 1/16).
- `replay`: lê uma trilha gravada e ignora o piloto.
- Relatório: `{schema_version, godot_version, seed, ticks, terminal, terminal_tick, grid, hashes[], chain_final, final_state, gates?}`.
- Código de saída: 0 em sucesso; 1 em erro de execução ou violação da guarda de tipos; 2 em violação de invariante (a execução para no primeiro tick violado, e o tick é registrado).

---

## 6. Protocolo experimental: condições C0, C1, C2 e métricas

### 6.1 Objeto comum às três condições

- **Entrada:** o mesmo *Game Design Document* (GDD), derivado das seções 1, 3 e 4 deste plano **sem** as tabelas de Acceptance Gate. O GDD é congelado com SHA-256 registrado no `PROVENANCE.jsonl` antes da primeira execução.
- **Ponto de partida:** repositório-semente idêntico (projeto Godot 4.7 vazio, `project.godot` 3D, assets livres do perfil `free` em `game/assets/free/` (§7.4.2; o perfil `daggerfall` nunca entra no repositório-semente), runner esqueleto sem lógica de jogo). Os assets são dados fixos e **não** são produzidos pelos agentes.
- **Modelo, temperatura e ferramentas** idênticos entre condições; o que muda é só a arquitetura do harness. O modelo desenvolvedor do experimento é um item a congelar (§8). Ele é distinto do papel `lead_game_developer`, que constrói a implementação de referência e as suítes.
- **Orçamentos:** no máximo $T_{\max} = 12$ iterações e teto de tokens por execução (valor a congelar). Execução que atinge o teto encerra com o estado corrente.
- **Isolamento:** cada execução começa num *worktree* limpo, sem acesso à implementação de referência, à suíte oculta nem a execuções anteriores.

### 6.2 Condições

| | **C0 Monolítico** | **C1 HoH estático** | **C2 HoH completo** |
|---|---|---|---|
| Papéis | 1 agente faz tudo | Planejador + Desenvolvedor | Planejador + Desenvolvedor + Verificador |
| Divisão em marcos | livre (recebe a lista M1 a M6) | Planejador escolhe ≤ 2 marcos por iteração | idem |
| Validação disponível | o que o agente decidir rodar | só `godot --headless --check-only` | `--check-only` + runner headless em sandbox *ro* + gates visíveis + teste de não interferência |
| Preservation Gate | inexistente | declarado pelo Planejador, sem execução | declarado e **executado** a cada iteração |
| Evidência que volta ao agente | nenhuma estruturada | erros de compilação | $E_t^{\text{ver}}$ / $E_t^{\text{gap}}$ com o primeiro tick divergente e as asserções violadas |

### 6.3 Suítes de avaliação

- **Suíte visível** (`game/tests/gates/`): os gates da §4 com as trilhas douradas e as sementes 1 a 100. Só o Verificador de C2 a executa durante o desenvolvimento.
- **Suíte oculta** (*held-out*): as mesmas asserções com **sementes e trilhas diferentes** (sementes 10001 a 10100, trilhas regravadas) e cenários adicionais equivalentes. Fica fora do alcance de todos os agentes e é aplicada **igualmente às três condições, depois do fim de cada execução**. Ela é a fonte de $R_{\text{mec}}$. Isso evita que C2 seja favorecida por ter acesso direto ao instrumento de medida.
- As duas suítes são construídas e validadas contra a implementação de referência em S4, que precisa passar 100% delas.

### 6.4 Métricas

Seja $\mathcal{M} = \{M_1, \dots, M_6\}$ e $g_{i,t} \in \{0,1\}$ o resultado da suíte oculta do marco $M_i$ aplicada ao commit da iteração $t$ (avaliação *post hoc* de todos os commits; o Acceptance Gate visível é só o instrumento de C2).

1. **Taxa de conclusão de mecânicas**
   $$R_{\text{mec}} = \frac{1}{6}\sum_{i=1}^{6} g_{i,T_{\text{fim}}}$$
   Um marco conta só se **todas** as suas asserções ocultas passam no commit final.

2. **Taxa de regressão estrutural**
   $$R_{\text{reg}} = \frac{\big|\{(i,t) : g_{i,t}=0 \land \exists\, t' < t,\ g_{i,t'}=1\}\big|}{\big|\{(i,t) : \exists\, t' < t,\ g_{i,t'}=1\}\big|}$$
   É a fração das avaliações de marcos já aceitos anteriormente que voltaram a falhar. Indefinida (relatada como "n/a") se nenhum marco chegou a passar.

3. **Taxa de repetição exata**
   $$R_{\text{rep}} = \frac{1}{|S|}\sum_{s \in S} \mathbb{1}\left[C_K^{(s,A)} = C_K^{(s,B)}\right]$$
   com $S$ = 20 sementes ocultas, $K = 18000$, A e B processos independentes (nível R2), aplicada ao commit final. Se o build final não executa, $R_{\text{rep}} = 0$. Relatamos também R3 (não interferência) separadamente.

4. **Iterações até convergência** $N_{\text{iter}}$: primeira iteração $t$ em que $\sum_i g_{i,t} = 6$; se nunca ocorre, $N_{\text{iter}} = T_{\max}$ e a execução é marcada como censurada (tratada como tal na análise).

5. **Custo em tokens:** soma de tokens de entrada, saída e cache de todos os agentes da execução, extraída dos *logs* do harness; relatados total e por marco aceito ($\text{tokens}/(6 \cdot R_{\text{mec}})$).

### 6.5 Replicação e análise estatística

- $n = 10$ execuções independentes por condição (30 no total), com ordem de execução das condições aleatorizada por semente registrada.
- Comparações par a par C0×C1, C1×C2, C0×C2 com Mann–Whitney $U$ (conforme o manuscrito), $\delta$ de Cliff e IC 95% por *bootstrap* com 10.000 reamostragens. **Proposta a confirmar no congelamento:** correção de Holm–Bonferroni para as três comparações, e Kruskal–Wallis como teste omnibus prévio.
- Limitação declarada: com $n = 10$ por grupo o poder estatístico é baixo para efeitos médios. Os tamanhos de efeito e intervalos são o resultado principal, e os valores-p são secundários.

### 6.6 Registro e proveniência de cada execução

Cada execução gera `runs/<condição>/<run_id>/` com: commits por iteração, evidências $E_t$ (C2), relatórios headless, *log* de tokens e `manifest.json` (modelo, versão do Godot com *hash* do binário, hash do GDD, hash do repositório-semente, sementes). Um evento `experiment_run` é acrescentado ao `PROVENANCE.jsonl` por execução.

---

## 7. Observações de engenharia e riscos

### 7.1 `CharacterBody3D` versus contrato de determinismo

A intenção do capitão pede `CharacterBody3D`, e o contrato (`DECISIONS.md`, 2026-10-06) proíbe a física de floats do motor na lógica. As duas coisas se conciliam assim: `CharacterBody3D` é o **tipo do nó de apresentação** do jogador (dá hierarquia de cena natural para a câmera e permite, no futuro, usar a física só para efeitos visuais), mas a posição dele é **escrita** a partir do estado inteiro a cada quadro, e `move_and_slide()`/`move_and_collide()` não participam da lógica. O *linter* de §5.1 garante isso. O formato de colisão "cilindro" da especificação é honrado como cilindro na cena e como quadrado inteiro (o mesmo modelo do DOOM) na simulação.

### 7.2 Rotação contínua e o problema da trigonometria

Rotação em float é a fonte de divergência mais provável num jogo 3D. A combinação de ângulo BAM de 12 bits com tabela Q16 gerada fora do motor e versionada torna o giro exato: 4096 passos voltam exatamente ao início. O custo é a granularidade de 0,088° por unidade, imperceptível em jogo.

### 7.3 Billboards e headless

`Sprite3D` com `BILLBOARD_FIXED_Y` é orientado pelo *shader*, então não há transformação a calcular por script e nada a divergir. Em headless o nó existe e pode ser inspecionado (M4-A7), mas não é desenhado. Escolher o quadro de 8 direções é função pura do estado e da câmera, só na apresentação.

### 7.4 Assets e sprites: perfis de arte e parecer sobre o Daggerfall Workshop

O Capitão sugeriu usar os assets originais do Daggerfall distribuídos pelo ecossistema do Daggerfall Workshop (<https://www.dfworkshop.net/downloads/>), ou seja, armas em 1ª pessoa, monstros em billboard, texturas de masmorra e UI. Abaixo está o parecer e a forma de incorporação que resulta dele.

#### 7.4.1 Parecer de licenciamento (2026-10-07)

| Item | Situação verificada | Fonte |
|---|---|---|
| Código do Daggerfall Unity (DFU) | Licença **MIT** | `github.com/Interkarma/daggerfall-unity` (API de licença do GitHub) |
| Assets do DFU | O DFU **não** traz assets. O README diz: "Daggerfall Unity requires a free copy of DOS Daggerfall to run. This provides all necessary game assets such as textures, 3D models, and sound effects." | README do repositório |
| Assets originais (texturas, sprites, UI) | Propriedade da Bethesda. Distribuídos como *freeware* desde 2009 (`DFInstall.zip`) e hoje gratuitos no Steam, sob os "Terms Of Use For DAGGERFALL" | texto dos termos (cópia mantida no pacote AUR `daggerfall`, arquivo `license`) |

Trechos relevantes dos termos de uso:

> 1. You have a non-exclusive, non-transferable license and right to use this Product for your own personal use and enjoyment. This Product is not provided for any non-personal, commercial purpose. All rights not expressly granted to you herein are hereby reserved by Bethesda Softworks.
>
> 5. You acknowledge that Bethesda Softworks owns any and all trademark, copyright and other proprietary rights to this Product.

**Conclusão:** "gratuito" não quer dizer "livre". A licença é **pessoal e intransferível** e não concede direito de redistribuir nem de criar obras derivadas. A página de downloads do Daggerfall Workshop não pôde ser lida diretamente (proteção Cloudflare retornou 403), mas o próprio projeto declara que os assets vêm da cópia DOS do usuário. Ou seja, o Workshop não relicencia a arte. Para este TCC:

| Uso | Avaliação |
|---|---|
| Extrair os assets da **própria cópia** do Capitão e usá-los localmente, num protótipo jogado por ele | Compatível com o uso pessoal; risco baixo |
| Versionar os PNG extraídos no git (mesmo no repositório privado `IvelOt/tcc`), compartilhar com o orientador ou com a banca, ou incluí-los no repositório-semente dos agentes | **Redistribuição sem autorização: não coberta pelos termos** |
| Capturas de tela com arte do Daggerfall no artigo ou em *preprint* público | Exige permissão ou o enquadramento como citação (Lei 9.610/98, art. 46, III) com justificativa crítica. Não recomendado para figuras de resultado |
| Usar os assets como dados fixos do benchmark (C0 a C2) | Desnecessário: a arte não é medida (§6.1); e torna o experimento **não replicável** por terceiros, que não poderiam receber o pacote |

Parecer: **tecnicamente viável e simples; juridicamente tranquilo só no uso pessoal e local.** Por isso a arte do Daggerfall entra como **perfil opcional, local e não versionado**. O perfil padrão, versionado e usado no experimento, continua sendo de assets livres. Adotar o perfil local é escolha do Capitão. Pedir permissão à Bethesda (ZeniMax/Microsoft) fica registrado como opção, não como pré-requisito.

#### 7.4.2 Dois perfis de arte, um só código

| | **Perfil A: `free` (padrão, versionado)** | **Perfil B: `daggerfall` (opcional, só local)** |
|---|---|---|
| Fonte | CC0/CC-BY. Candidatos a verificar: pacotes CC0 da Kenney (texturas, UI) e *tiles* CC0 do Dungeon Crawl Stone Soup no OpenGameArt (monstros, itens) | Extraídos da cópia DOS do Daggerfall do próprio usuário (Steam ou `DFInstall.zip`) |
| Onde fica | `game/assets/free/` (no git) | `game/assets/daggerfall/` (**no `.gitignore`**) |
| Manifesto | `game/assets/CREDITS.md`: URL, autor, licença, SHA-256 de cada arquivo | `game/assets/daggerfall/LOCAL_MANIFEST.json` gerado pela extração (arquivo de origem, registro, quadro, SHA-256). Também ignorado pelo git |
| Usado no experimento C0 a C2 e nas suítes | **Sim** | **Não** |
| Usado em figuras do artigo | Sim | Não, salvo permissão |

Os dois perfis expõem os **mesmos identificadores lógicos** num `game/assets/asset_map.json` versionado, por exemplo `enemy.skeleton.walk.dir0..4`, `weapon.sword.idle|windup|slash1..3`, `weapon.shield.raise`, `wall.dungeon.stone01`, `floor.dungeon.01`, `ui.hud.frame`, `ui.compass`, `ui.automap.parchment`. Cada identificador aponta para um caminho em cada perfil. A camada `view/` resolve o identificador pelo perfil ativo (`--art-profile=free|daggerfall` ou configuração do projeto). Se um arquivo do perfil B faltar, o identificador cai no perfil A e um aviso é emitido. O núcleo `sim/` nunca carrega textura. Por isso o perfil de arte **não altera nenhum hash**, e o teste de não interferência (R3, §5.5) roda com os dois perfis e deve dar a mesma cadeia `C_K`.

#### 7.4.3 Pipeline de extração e importação (perfil B)

1. **Fonte:** a pasta `ARENA2/` da instalação DOS do usuário. O caminho é passado à ferramenta e nunca entra no repositório.
2. **Extração para PNG.** Opções, em ordem de preferência:
   - ferramenta própria `tools/df_extract.py`, a escrever em S4.3, que lê os formatos documentados na UESP (`Daggerfall:Files`): arquivos `TEXTURE.###` (texturas e sprites de billboard, paleta de 8 bits), `.CIF`/`.RCI` (sprites de arma em 1ª pessoa) e `.IMG` (telas e UI), aplicando a paleta correta (`PAL.PAL`/`ART_PAL.COL`) e convertendo o índice de transparência em alfa 0;
   - alternativa: exportar PNG com as ferramentas do ecossistema do Daggerfall Workshop (o Daggerfall Imaging 2, ou a API DaggerfallConnect do DFU, em C# e licença MIT), seguido do mesmo passo de renomeação e manifesto.

   A ferramenta só **lê** a cópia local, grava em `game/assets/daggerfall/` e gera `LOCAL_MANIFEST.json`. Nenhum asset é baixado de terceiros.
3. **Resolução e formato:** arte de origem em baixa resolução (paleta VGA, tela nativa de 320×200). Os PNG são mantidos no tamanho original, sem *upscale*, o que combina com o `SubViewport` 640×360 e o filtro `NEAREST` da §7.5. Os quadros de monstro do Daggerfall vêm em poucas orientações espelhadas, e não em 8 independentes. O mapeamento para os quadros de 8 direções de M4 usa espelhamento horizontal (`flip_h`) e é registrado no `asset_map.json`. O número exato de orientações por tipo é conferido na extração.
4. **Importação no Godot 4.7:** `.import` com `compress/mode=Lossless`, `mipmaps/generate=false`, filtro `NEAREST` (global em `textures/canvas_textures/default_texture_filter=0`, já no `project.godot`, e por material em 3D).
   - Monstros: `Sprite3D`/`AnimatedSprite3D` com `billboard=BILLBOARD_FIXED_Y`, `shaded=false`, `alpha_cut=DISCARD`, `SpriteFrames` montados a partir do `asset_map.json`.
   - Paredes e piso: `StandardMaterial3D` *unshaded* ou com luz de tocha, `texture_filter=NEAREST`, UV em múltiplos da célula de 2 m.
   - Arma e escudo: `TextureRect` em `CanvasLayer`, ancorados embaixo, com quadros sincronizados a `swing_state`.
   - HUD e automapa: `NinePatchRect` com moldura e pergaminho.
5. **Verificação:** `tools/df_extract.py --verify` confere o SHA-256 de cada PNG contra o `LOCAL_MANIFEST.json`. Em headless, um teste de cena carrega cada identificador do `asset_map.json` nos dois perfis e falha se algum não resolver.

#### 7.4.4 Regras gerais de assets

- Todo asset versionado tem entrada em `game/assets/CREDITS.md`. Asset sem entrada não entra no repositório.
- `game/assets/daggerfall/` é ignorado pelo git. Um guardião de *pre-commit* (ou o próprio Verificador) rejeita qualquer arquivo de `assets/` sem entrada no `CREDITS.md`.
- *Fallback*: sem sprite adequado, um script gera um *placeholder* procedural (silhueta colorida). O benchmark não depende da qualidade da arte, e a arte não é produzida nem avaliada nas condições C0 a C2.

### 7.5 Interface estilo Daggerfall, leve

- `SubViewport` 640×360 com `NEAREST` e *stretch* inteiro para a janela; HUD em `CanvasLayer` com `NinePatchRect` de moldura de pedra.
- Barra inferior: retrato do Guerreiro, barras verticais de Vida (vermelho) e Vigor (verde), bússola com o `angle` atual, linha de mensagens. A barra de Magia do Daggerfall fica fora, por não fazer sentido para a classe.
- Sem pós-processamento caro; neblina de distância (`Environment.fog`) curta para o clima e para baratear a renderização.

### 7.6 Ajustes em `project.godot`

- Descrição: "Projeto 3D em primeira pessoa…", seções de física 3D (`3d/physics_engine` padrão, gravidade 0, porque não é usada na lógica), `rendering_method="gl_compatibility"` mantido (leve e funciona no *dummy*).
- `input_map` com as ações de §1.3; captura de mouse (`Input.MOUSE_MODE_CAPTURED`) só no modo interativo.
- `physics_ticks_per_second=60`, `max_physics_steps_per_frame=8` e `physics_interpolation=false` mantidos. A interpolação visual é feita manualmente na `view/`.

### 7.7 Riscos e mitigação

| Risco | Efeito | Mitigação |
|---|---|---|
| Godot 4.7 muda a saída de `JSON.stringify` entre *patches* | hashes diferentes entre máquinas | versão e hash do binário fixados no `manifest.json`; teste R5 opcional; guarda de tipos |
| Escopo 3D grande demais para $T_{\max}$ | $R_{\text{mec}}$ baixo em todas as condições (efeito chão) | piloto do experimento com a implementação de referência; calibrar $T_{\max}$ e o teto de tokens **antes** do congelamento, nunca depois |
| Piloto do runner falha por estratégia, não por defeito do jogo | falso negativo em M6-A6 | M6-A6 com limiar calibrado; as demais asserções usam trilhas determinísticas, não o piloto |
| Não determinismo do provedor do LLM | variância entre execuções | é parte do fenômeno medido; controlado pelo $n$ por condição e relatado |
| Vazamento da suíte oculta | viés a favor de C2 | suíte fora de todos os *worktrees* dos agentes; hash da suíte registrado antes da coleta |
| Avaliação visual impossível sem GPU | aspectos estéticos não medidos | declarado como limitação; avaliação qualitativa separada, fora das métricas |
| Arte do Daggerfall (Bethesda) vazar para o git, o repositório-semente ou o artigo | violação dos termos de uso pessoal; experimento não replicável | perfil `daggerfall` ignorado pelo git; guardião de `CREDITS.md`; benchmark e figuras só com o perfil `free` (§7.4) |

---

## 8. Cronograma do estágio S4 e itens a congelar

| Passo | Entregável | Responsável |
|---|---|---|
| S4.1 | Este plano + registro em `DECISIONS.md`/`PROVENANCE.jsonl` | Opus 5.5 (este commit) |
| S4.2 | Revisão adversarial do plano (furos no contrato e nos gates) | `adversarial_reviewer` (modelo diferente do autor) |
| S4.3 | Implementação de referência M1 a M6 + runner + *linter* | `lead_game_developer` (Opus 5.5) |
| S4.4 | Suítes visível e oculta; referência passa 100%; R1 a R4 verdes | `lead_game_developer`, validado por outro modelo |
| S4.5 | Experimento-piloto (1 execução por condição) para calibrar orçamentos | orquestrador |
| S4.6 | **Congelamento:** GDD, suítes, $T_{\max}$, teto de tokens, modelo desenvolvedor, limiar de M6-A6, testes estatísticos | capitão + orientador, registrado em `DECISIONS.md` |
| S4.7 | Coleta: 30 execuções | orquestrador |

**Itens ainda em aberto (precisam de decisão registrada antes de S4.7):** modelo desenvolvedor do experimento; $T_{\max}$ definitivo; teto de tokens; limiar de M6-A6; adoção da correção de Holm e do Kruskal–Wallis; valores finais das constantes da §3.4.

---

## 9. Impacto sobre o manuscrito e o código existente

- `secoes/03_metodologia.tex`, subseção "Desenho Experimental e Benchmark de Jogo": descreve o benchmark 2D com cinco mecânicas ($M_1$ a $M_5$). Precisa ser reescrita para o ARPG com seis marcos, e $R_{\text{mec}}$ passa a ser sobre 6. A subseção "Camada de Simulação" continua válida e ganha a fronteira de entrada (§5.2), a cadeia de hashes (§5.3) e o teste de não interferência (§5.4). **Atualizado em 2026-10-07** (tarefa `tcc-paper-arpg`): as Seções 1 a 3, o Resumo/Abstract e a Figura do fluxo passaram a descrever o ARPG com seis marcos, a cadeia de hashes e o teste de não interferência.
- `game/scripts/*.gd` e `game/runs/*.json`: protótipo 2D de visão superior. Fica no histórico como prova de conceito do contrato de determinismo (inteiros, AABB semiaberta, hash por tick). Será substituído pela estrutura `sim/` + `view/` em S4.3, sem apagar o histórico git.
- `harness/config.yaml`: o papel `lead_game_developer` continua correto; a descrição "Projeto 2D" em `project.godot` muda em S4.3.
