#!/usr/bin/env python3
"""Gera game/tests/traces/demo_iter2.jsonl (modo --demo, sala `combat`; plano §8).

Uma linha por tick (formato da rodada 1), 390 ticks:
  1–40     move=1               avanço em direção ao boneco
  41–60    turn=+16             giro de 320 BAM para a esquerda (L -> NE)
  61–80    turn=-16             volta ao rumo L
  81–120   move=1 em 81..80+N   aproxima-se do boneco; zero no resto da janela
  121, 150 attack=true          dois golpes (borda, um tick cada)
  180–260  block=true           escudo erguido; move=1 em 200–230 (empuxo pela metade)
  261–299  zero                 vigor regenerando
  300–390  strafe=1 em 300–330  automapa aberto pela view nos ticks 300–390

Ajuste de N (medido com o núcleo, boneco em (17408, 15360)): com N = ADVANCE_TICKS = 24 o
jogador fica em pos_x = 15897 no tick 120 (1511 u ≈ 1,48 m do boneco) e, deslizando por
inércia, em pos_x 15996..16026 na 1ª janela ACTIVE (127–132) e 16032 na 2ª (156–161):
along = 1412..1376 <= SWORD_REACH + 384 = 2022, side = 0 -> os dois golpes acertam
(HP do boneco 100 -> 75 no tick 127 -> 50 no tick 156; vigor 100 -> 88 -> 77).
Com N = 18 o jogador para a 2252 u e nenhum golpe acerta.
Na fase de bloqueio (move=1 em 200–230) o jogador atravessa o boneco (pos_x 18037 no tick 260):
colisão jogador×entidade é contrato de M4 (plano §4.2).
"""
import json
from pathlib import Path

TOTAL = 390
ADVANCE_TICKS = 24


def line(move=0, strafe=0, turn=0, attack=False, block=False) -> str:
    d = {"move": move, "strafe": strafe, "turn": turn, "attack": attack, "block": block, "use": False, "quaff": 0}
    return json.dumps(d, separators=(",", ":"))


def tick_input(t: int) -> str:
    if 1 <= t <= 40:
        return line(move=1)
    if 41 <= t <= 60:
        return line(turn=16)
    if 61 <= t <= 80:
        return line(turn=-16)
    if 81 <= t <= 80 + ADVANCE_TICKS:
        return line(move=1)
    if t in (121, 150):
        return line(attack=True)
    if 180 <= t <= 260:
        return line(move=1 if 200 <= t <= 230 else 0, block=True)
    if 300 <= t <= 330:
        return line(strafe=1)
    return line()


def main() -> None:
    lines = [tick_input(t) for t in range(1, TOTAL + 1)]
    out = Path(__file__).resolve().parent.parent / "game" / "tests" / "traces" / "demo_iter2.jsonl"
    out.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
