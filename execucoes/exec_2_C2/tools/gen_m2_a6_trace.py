#!/usr/bin/env python3
"""Gera game/tests/traces/m2_a6_door.jsonl (trilha dourada de M2-A6).

90 ticks move=1 (bloqueado pela porta), 1 tick use=1, 150 ticks move=1.
"""
import json
from pathlib import Path


def line(move: int = 0, use: bool = False) -> str:
    d = {"move": move, "strafe": 0, "turn": 0, "attack": False, "block": False, "use": use, "quaff": 0}
    return json.dumps(d, separators=(",", ":"))


def main() -> None:
    lines = [line(move=1)] * 90 + [line(use=True)] + [line(move=1)] * 150
    out = Path(__file__).resolve().parent.parent / "game" / "tests" / "traces" / "m2_a6_door.jsonl"
    out.write_text("\n".join(lines) + "\n")


if __name__ == "__main__":
    main()
