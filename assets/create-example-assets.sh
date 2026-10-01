#!/usr/bin/env bash
# =============================================================================
# create-example-assets.sh
# -----------------------------------------------------------------------------
# Genera una imagen de ejemplo para Plymouth (degradado con texto) en
# assets/plymouth-image.png, usando ImageMagick (`magick` o `convert`).
#
# Uso:
#   bash create-example-assets.sh [ANCHOxALTO]
#
# Ejemplos:
#   bash create-example-assets.sh            # 1920x1080
#   bash create-example-assets.sh 1280x720
#
# El cursor no se genera aqui: el instalador lo crea a partir de
# assets/cursor/guitar-pick-left.png (ver assets/cursor/README.md).
# =============================================================================

set -euo pipefail

RESOLUTION="${1:-1920x1080}"
OUTPUT_NAME="plymouth-image.png"

if [[ ! "$RESOLUTION" =~ ^[0-9]+x[0-9]+$ ]]; then
    echo "ERROR: resolucion invalida '$RESOLUTION'. Use ANCHOxALTO, por ejemplo 1920x1080." >&2
    exit 1
fi

if command -v magick &> /dev/null; then
    IM=(magick)
elif command -v convert &> /dev/null; then
    IM=(convert)
else
    echo "ERROR: ImageMagick no esta instalado." >&2
    echo "" >&2
    echo "Instalalo con:" >&2
    echo "  - Arch Linux:    sudo pacman -S imagemagick" >&2
    echo "  - Ubuntu/Debian: sudo apt-get install imagemagick" >&2
    echo "  - macOS:         brew install imagemagick" >&2
    exit 1
fi

# Se escribe junto al script (assets/), sin importar desde donde se ejecute.
cd "$(dirname "${BASH_SOURCE[0]}")"

HEIGHT="${RESOLUTION#*x}"
TITLE_SIZE=$((HEIGHT / 9))
SUBTITLE_SIZE=$((HEIGHT / 18))
TITLE_OFFSET=$((HEIGHT / 14))

echo "Creando $OUTPUT_NAME ($RESOLUTION)..."

"${IM[@]}" -size "$RESOLUTION" gradient:'#0f2027-#2c5364' \
    -gravity center \
    -fill white -pointsize "$TITLE_SIZE" -annotate "+0-${TITLE_OFFSET}" "Arch Linux" \
    -fill '#e0e0e0' -pointsize "$SUBTITLE_SIZE" -annotate "+0+${TITLE_OFFSET}" "Modo Kiosko" \
    "$OUTPUT_NAME"

if [[ ! -s "$OUTPUT_NAME" ]]; then
    echo "ERROR: no se pudo crear $OUTPUT_NAME" >&2
    exit 1
fi

echo "Listo: $(pwd)/$OUTPUT_NAME"
if command -v identify &> /dev/null; then
    identify "$OUTPUT_NAME"
fi
echo ""
echo "Se usa con PLYMOUTH_IMAGE_PATH o renombrada como yarg_1080p.png, clonehero_1080p.png, etc."
echo "(ver assets/README.md)."
