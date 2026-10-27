#!/usr/bin/env python3
"""Gera game/sim/trig_table.gd: seno Q16 com 4096 entradas (BAM de 12 bits).

SIN_Q16[i] = round(sin(2*pi*i/4096) * 65536)  (arredondamento do Python 3).
Imprime o SHA-256 dos 4096 valores em int32 little-endian, que é o valor
registrado no gate M1-A6.
"""
import hashlib
import math
import struct
from pathlib import Path

N = 4096


def table() -> list[int]:
    return [round(math.sin(2 * math.pi * i / N) * 65536) for i in range(N)]


def main() -> None:
    t = table()
    sha = hashlib.sha256(struct.pack("<%di" % N, *t)).hexdigest()
    rows = []
    for i in range(0, N, 16):
        rows.append("\t" + ", ".join(str(v) for v in t[i:i + 16]) + ",")
    body = "\n".join(rows)
    out = Path(__file__).resolve().parent.parent / "game" / "sim" / "trig_table.gd"
    out.write_text(
        "class_name TrigTable\n"
        "extends RefCounted\n"
        "## GERADO por tools/gen_trig_table.py; não editar à mão.\n"
        "## Seno em Q16 (65536 = 1) para ângulos BAM de 12 bits (4096 = 1 volta).\n"
        f"## SHA-256 (int32 LE): {sha}\n\n"
        f"const TABLE_SHA256: String = \"{sha}\"\n\n"
        f"const SIN_Q16: PackedInt32Array = [\n{body}\n]\n\n\n"
        "static func sin_q16(a: int) -> int:\n"
        "\treturn SIN_Q16[a & 4095]\n\n\n"
        "static func cos_q16(a: int) -> int:\n"
        "\treturn SIN_Q16[(a + 1024) & 4095]\n"
    )
    print(sha)


if __name__ == "__main__":
    main()
