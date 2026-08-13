#!/usr/bin/env bash
# Thin wrapper around apigen_openapi_check.py — validates that an OpenAPI
# spec has what ApiGen's generator actually needs (ground-truth x-apigen-*
# rules, not just what the example specs suggest).
#
# Usage: apigen-openapi-check.sh <openapi-path>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PY="${PYTHON:-}"
if [ -z "$PY" ]; then
  if command -v python3 >/dev/null 2>&1; then
    PY=python3
  elif command -v python >/dev/null 2>&1; then
    PY=python
  else
    echo "ERROR: no se encontro python3/python en el PATH." >&2
    echo "Este validador requiere Python 3 + PyYAML: pip install pyyaml" >&2
    exit 2
  fi
fi

exec "$PY" "$SCRIPT_DIR/apigen_openapi_check.py" "$@"
