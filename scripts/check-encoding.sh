#!/usr/bin/env bash
# Verifica que los archivos de texto del repo sean UTF-8 limpio:
#   - sin BOM (EF BB BF) al inicio
#   - sin doble codificacion UTF-8 (mojibake: acentos que aparecen como dos simbolos raros)
#   - sin finales de linea CRLF
#
# Uso: scripts/check-encoding.sh [directorio]   (por defecto, la raiz del repo)
# Sale con codigo 1 si encuentra algun problema.

set -euo pipefail

ROOT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Se arman con escapes para que este archivo no se detecte a si mismo.
MOJIBAKE=$'\xc3\x83|\xc3\x82'
BOM=$'\xef\xbb\xbf'

problems=0

report() {
    echo "ERROR: $1: $2" >&2
    problems=$((problems + 1))
}

has_crlf() {
    local total without_cr

    total=$(wc -c < "$1")
    without_cr=$(tr -d '\r' < "$1" | wc -c)
    [[ "$total" -ne "$without_cr" ]]
}

while IFS= read -r -d '' file; do
    rel="${file#"$ROOT"/}"

    if [[ "$(head -c 3 "$file")" == "$BOM" ]]; then
        report "$rel" "empieza con BOM (EF BB BF)"
    fi

    if LC_ALL=C grep -Eq "$MOJIBAKE" "$file"; then
        report "$rel" "contiene doble codificacion UTF-8 (mojibake)"
    fi

    if has_crlf "$file"; then
        report "$rel" "usa finales de linea CRLF"
    fi
done < <(find "$ROOT" \
    \( -path '*/.git' -o -path '*/node_modules' \) -prune -o \
    -type f \( -name '*.sh' -o -name '*.bats' -o -name '*.md' -o -name '*.example' -o -name '*.yml' \) \
    -print0)

if [[ $problems -gt 0 ]]; then
    echo "check-encoding: $problems problema(s) encontrado(s)." >&2
    exit 1
fi

echo "check-encoding: OK"
