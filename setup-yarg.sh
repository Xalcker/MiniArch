#!/bin/bash

# Script para descargar e instalar la última versión de YARG (Yet Another Rhythm Game)
# Versión: 0.14.0 (o superior si se actualiza el link)

set -e

YARG_URL="https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip"
INSTALL_DIR="$HOME/YARG"
ZIP_FILE="/tmp/YARG_Linux.zip"

echo "==================================================================="
echo "Iniciando descarga e instalación de YARG"
echo "==================================================================="

# Crear directorio de instalación
mkdir -p "$INSTALL_DIR"

# Descargar el archivo
echo "Descargando YARG desde: $YARG_URL"
if ! wget -O "$ZIP_FILE" "$YARG_URL"; then
    echo "ERROR: No se pudo descargar el archivo."
    exit 1
fi

# Descomprimir
echo "Descomprimiendo en $INSTALL_DIR..."
if ! unzip -o "$ZIP_FILE" -d "$INSTALL_DIR"; then
    echo "ERROR: Fallo al descomprimir el archivo."
    exit 1
fi

# Dar permisos de ejecución si es necesario
echo "Configurando permisos..."
find "$INSTALL_DIR" -type f -name "YARG*" -exec chmod +x {} \;

# Limpiar
rm -f "$ZIP_FILE"

echo "==================================================================="
echo "YARG instalado correctamente en $INSTALL_DIR"
echo "Puedes ejecutarlo con: $INSTALL_DIR/YARG"
echo "==================================================================="
