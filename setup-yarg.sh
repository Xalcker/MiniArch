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

# Crear carpeta de canciones
SONGS_DIR="$INSTALL_DIR/Songs"
echo "Creando carpeta de canciones en $SONGS_DIR..."
mkdir -p "$SONGS_DIR"

# Configuración de Samba
echo "==================================================================="
echo "Configurando Samba para compartir canciones..."
echo "==================================================================="

# Crear archivo de configuración básico si no existe
if [[ ! -f /etc/samba/smb.conf ]]; then
    echo "Generando /etc/samba/smb.conf..."
    sudo bash -c 'cat > /etc/samba/smb.conf' << EOF
[global]
   workgroup = WORKGROUP
   server string = YARG Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/samba/%m.log
   max log size = 50

[YARG-Songs]
   path = $SONGS_DIR
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $USER
EOF
fi

# Habilitar y arrancar servicios de Samba
echo "Iniciando servicios de red..."
sudo systemctl enable --now smb nmb

# Limpiar
rm -f "$ZIP_FILE"

echo "==================================================================="
echo "Instalación completada!"
echo "YARG instalado en: $INSTALL_DIR"
echo "Carpeta SONGS compartida en red como: \\\\$(hostname)\\YARG-Songs"
echo "==================================================================="
