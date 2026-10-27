#!/usr/bin/env python3
"""Valida um relatorio_provas.json contra experiment/schemas/relatorio_provas.schema.json.

Uso: python3 experiment/tools/validate_report.py <relatorio_provas.json> [--quiet]

Usa o pacote jsonschema se estiver instalado; senão, aplica o subconjunto do
JSON Schema que o esquema usa (type, required, properties, items, minLength,
minimum). Saída 0 = válido, 1 = inválido, 2 = arquivo ausente ou não é JSON.
Sem --quiet, imprime all_milestones_passed e o tamanho de cada lista.
"""
import json
import sys
from pathlib import Path

SCHEMA = Path(__file__).resolve().parent.parent / "schemas" / "relatorio_provas.schema.json"

TYPES = {
    "object": dict,
    "array": list,
    "string": str,
    "boolean": bool,
    "integer": int,
}


def check(value, schema: dict, path: str) -> list[str]:
    errors = []
    want = schema.get("type")
    if want:
        py = TYPES[want]
        # bool é subclasse de int em Python; JSON Schema os separa.
        if not isinstance(value, py) or (want == "integer" and isinstance(value, bool)):
            return [f"{path}: esperado {want}, veio {type(value).__name__}"]
    if want == "object":
        for key in schema.get("required", []):
            if key not in value:
                errors.append(f"{path}: campo obrigatório ausente '{key}'")
        for key, sub in schema.get("properties", {}).items():
            if key in value:
                errors += check(value[key], sub, f"{path}.{key}")
    if want == "array" and "items" in schema:
        for i, item in enumerate(value):
            errors += check(item, schema["items"], f"{path}[{i}]")
    if want == "string" and len(value) < schema.get("minLength", 0):
        errors.append(f"{path}: texto vazio")
    if want == "integer" and value < schema.get("minimum", value):
        errors.append(f"{path}: menor que {schema['minimum']}")
    return errors


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--quiet"]
    if len(args) != 1:
        print(__doc__.strip(), file=sys.stderr)
        return 2
    report_path = Path(args[0])
    try:
        report = json.loads(report_path.read_text(encoding="utf-8"))
    except FileNotFoundError:
        print(f"[validate_report] arquivo não encontrado: {report_path}", file=sys.stderr)
        return 2
    except json.JSONDecodeError as e:
        print(f"[validate_report] JSON inválido em {report_path}: {e}", file=sys.stderr)
        return 2
    schema = json.loads(SCHEMA.read_text(encoding="utf-8"))
    try:
        import jsonschema

        errors = [f"$.{'.'.join(map(str, e.path))}: {e.message}"
                  for e in jsonschema.Draft202012Validator(schema).iter_errors(report)]
    except ImportError:
        errors = check(report, schema, "$")
    for e in errors:
        print(e)
    if errors:
        print(f"[validate_report] {report_path}: {len(errors)} erro(s)")
        return 1
    if "--quiet" not in sys.argv:
        print(f"[validate_report] {report_path}: válido · all_milestones_passed={str(report['all_milestones_passed']).lower()}"
              f" · verified={len(report['verified'])} visual_findings={len(report['visual_findings'])} gap={len(report['gap'])}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
