#!/usr/bin/env python3
"""Linter do contrato de simulação (plano S4 §5.1).

1. game/sim/*.gd: sem float, sem trigonometria/RNG/tempo do motor, sem nós.
2. game/view/*.gd e game/input/*.gd: sem atribuição a campos do núcleo.
Comentários (# ...) e strings são ignorados. Saída 0 = limpo, 1 = violação.
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent / "game"

FORBIDDEN = [
    (r"\b\d+\.\d*|\.\d+\b", "literal float"),
    (r"\bfloat\b", "tipo float"),
    (r"\bVector[234]i?\b", "Vector"),
    (r"\bTransform[23]D\b|\bBasis\b|\bQuaternion\b", "transformação de float"),
    (r"\b(sin|cos|tan|atan2|atan|sqrt|pow|lerp|lerpf|snapped|fmod|floor|ceil|round)\s*\(", "função de float"),
    (r"\brandf\b|\brandi\b|\brandf_range\b|\brandi_range\b|RandomNumberGenerator|\brandomize\b", "RNG do motor"),
    (r"\bTime\.|OS\.get_ticks|\bdelta\b", "tempo real"),
    (r"\bextends\s+(Node|Node2D|Node3D|Control|Object)\b", "núcleo deve estender RefCounted"),
    (r"\bget_tree\s*\(|\bsignal\b|\bawait\b|PhysicsServer[23]D|\bget_node\s*\(", "API de cena/sinais"),
]

ASSIGN_TO_SIM = re.compile(r"\b(sim|_sim|world_sim|player_sim)\.(?:\w+\.)*\w+\s*(?:[+\-*/%|&^]?=)(?!=)")


def strip(line: str) -> str:
    line = re.sub(r'"(?:\\.|[^"\\])*"', '""', line)
    line = re.sub(r"'(?:\\.|[^'\\])*'", "''", line)
    return line.split("#", 1)[0]


def main() -> int:
    errors = []
    for f in sorted((ROOT / "sim").glob("*.gd")):
        if f.name == "trig_table.gd":
            # tabela gerada: só inteiros; checa apenas as regras de nós/RNG/tempo
            rules = FORBIDDEN[1:]
        else:
            rules = FORBIDDEN
        for n, raw in enumerate(f.read_text().splitlines(), 1):
            line = strip(raw)
            for pat, why in rules:
                if re.search(pat, line):
                    errors.append(f"{f.relative_to(ROOT.parent)}:{n}: {why}: {raw.strip()}")
        if not re.search(r"^extends RefCounted\b", f.read_text(), re.M):
            errors.append(f"{f.relative_to(ROOT.parent)}: não estende RefCounted")
    for d in ("view", "input"):
        for f in sorted((ROOT / d).glob("*.gd")):
            for n, raw in enumerate(f.read_text().splitlines(), 1):
                line = strip(raw)
                if ASSIGN_TO_SIM.search(line):
                    errors.append(f"{f.relative_to(ROOT.parent)}:{n}: apresentação escreve no núcleo: {raw.strip()}")
    for e in errors:
        print(e)
    print(f"[lint_sim] {len(errors)} violação(ões)")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
