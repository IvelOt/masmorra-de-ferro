#!/bin/sh
# Importa o projeto (gera o cache de class_name em game/.godot) e roda a suíte completa.
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path game --import >/dev/null 2>&1 || true
exec "$GODOT" --headless --path game -s res://tests/run_gates.gd
