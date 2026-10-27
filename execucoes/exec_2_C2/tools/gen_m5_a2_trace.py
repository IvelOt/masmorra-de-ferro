#!/usr/bin/env python3
"""Gera game/tests/traces/m5_a2_corridor.jsonl (trilha de M5-A2, sala test_door_room()).

90 ticks move=1 (bloqueia na porta em pos_x = 16000, célula 7), 1 tick use=1 (porta (8,4) abre),
22 ticks move=1, 40 ticks de input zero (para em pos_x = 19029, célula 9, sem entrar na sala 1).
Total: 153 linhas.
"""
import json
from pathlib import Path


def line(move: int = 0, use: bool = False) -> str:
    d = {"move": move, "strafe": 0, "turn": 0, "attack": False, "block": False, "use": use, "quaff": 0}
    return json.dumps(d, separators=(",", ":"))


def main() -> None:
    lines = [line(move=1)] * 90 + [line(use=True)] + [line(move=1)] * 22 + [line()] * 40
    out = Path(__file__).resolve().parent.parent / "game" / "tests" / "traces" / "m5_a2_corridor.jsonl"
    out.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
