#!/bin/bash

# Script para crear assets de ejemplo para el instalador de Arch Linux Kiosko
# Requiere ImageMagick instalado

set -e

echo "=== Creador de Assets de Ejemplo para Arch Linux Kiosko ==="
echo ""

# Verificar si ImageMagick está instalado
if ! command -v convert &> /dev/null; then
    echo "ERROR: ImageMagick no está instalado."
    echo ""
    echo "Instalar en:"
    echo "  - Ubuntu/Debian: sudo apt-get install imagemagick"
    echo "  - macOS: brew install imagemagick"
    echo "  - Arch Linux: sudo pacman -S imagemagick"
    echo "  - Windows: Descargar desde https://imagemagick.org/"
    exit 1
fi

echo "✓ ImageMagick detectado"
echo ""

# Crear imagen de Plymouth
echo "Creando imagen de Plymouth (1280x720)..."

convert -size 1280x720 gradient:#0f2027-#203a43-#2c5364 \
    -font Arial-Bold -pointsize 80 -fill white \
    -gravity center -annotate +0-50 "Arch Linux" \
    -pointsize 40 -fill "#e0e0e0" -annotate +0+50 "Modo Kiosko" \
    plymouth-image.png

if [ -f "plymouth-image.png" ]; then
    echo "✓ Imagen de Plymouth creada: plymouth-image.png"
    
    # Verificar la imagen
    if command -v identify &> /dev/null; then
        echo "  Detalles: $(identify plymouth-image.png)"
    fi
else
    echo "✗ Error al crear la imagen de Plymouth"
    exit 1
fi

echo ""

# Crear cursor (requiere xcursorgen)
echo "Verificando herramientas para cursor..."

if command -v xcursorgen &> /dev/null; then
    echo "✓ xcursorgen detectado"
    echo ""
    echo "Creando cursor personalizado..."
    
    # Crear directorio de cursors
    mkdir -p cursor/cursors
    
    # Crear imagen de cursor simple (flecha negra)
    convert -size 32x32 xc:transparent \
        -fill black -stroke white -strokewidth 1 \
        -draw "polygon 2,2 2,24 12,18 16,28 20,26 16,16 28,16" \
        cursor_temp.png
    
    # Crear configuración para xcursorgen
    echo "32 2 2 cursor_temp.png" > cursor_temp.cfg
    
    # Generar cursor
    xcursorgen cursor_temp.cfg cursor/cursors/default
    
    # Crear enlaces simbólicos para otros tipos
    cd cursor/cursors
    ln -sf default pointer
    ln -sf default hand
    ln -sf default hand1
    ln -sf default hand2
    ln -sf default text
    ln -sf default xterm
    ln -sf default wait
    ln -sf default watch
    ln -sf default left_ptr
    ln -sf default arrow
    cd ../..
    
    # Crear index.theme
    cat > cursor/index.theme << 'EOF'
[Icon Theme]
Name=Kiosk Cursor
Comment=Cursor de ejemplo para Arch Linux Kiosko
Example=default
EOF
    
    # Limpiar archivos temporales
    rm cursor_temp.png cursor_temp.cfg
    
    echo "✓ Cursor creado en: cursor/"
    echo "  Archivos: $(ls cursor/cursors/ | wc -l) cursors"
else
    echo "⚠ xcursorgen no está instalado - saltando creación de cursor"
    echo ""
    echo "Para crear cursor personalizado, instala:"
    echo "  - Ubuntu/Debian: sudo apt-get install x11-apps"
    echo "  - Arch Linux: sudo pacman -S xorg-xcursorgen"
    echo ""
    echo "Creando estructura básica de cursor..."
    
    mkdir -p cursor/cursors
    
    cat > cursor/index.theme << 'EOF'
[Icon Theme]
Name=Kiosk Cursor
Comment=Cursor de ejemplo para Arch Linux Kiosko (requiere archivos de cursor)
EOF
    
    cat > cursor/cursors/README.txt << 'EOF'
Este directorio debe contener archivos de cursor en formato X11.

Para agregar cursors:
1. Copia archivos de cursor desde /usr/share/icons/default/cursors/
2. O usa xcursorgen para crear cursors personalizados

Ejemplo:
  cp /usr/share/icons/Adwaita/cursors/* .
EOF
    
    echo "✓ Estructura de cursor creada (sin archivos de cursor)"
fi

echo ""
echo "=== Resumen ==="
echo ""
echo "Assets creados en el directorio actual:"
echo "  - plymouth-image.png (1280x720 PNG)"
echo "  - cursor/ (directorio con cursor personalizado)"
echo ""
echo "Para usar estos assets:"
echo "  1. Copia plymouth-image.png a assets/"
echo "  2. Copia el contenido de cursor/ a assets/cursor/"
echo "  3. O transfiérelos directamente a la VM con SCP"
echo ""
echo "Ejemplo de transferencia SCP:"
echo "  scp plymouth-image.png root@<IP_VM>:/root/arch-kiosk-installer/assets/"
echo "  scp -r cursor/* root@<IP_VM>:/root/arch-kiosk-installer/assets/cursor/"
echo ""
echo "✓ Completado"
