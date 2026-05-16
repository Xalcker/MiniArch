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

# Optimizaciones de Rendimiento para Kiosko YARG
echo "==================================================================="
echo "Aplicando optimizaciones de rendimiento..."
echo "==================================================================="

# 1. Configurar prioridad de tiempo real para el usuario (mejor audio)
sudo bash -c "cat > /etc/security/limits.d/99-yarg.conf" << EOF
$USER - rtprio 99
$USER - memlock unlimited
$USER - nice -20
EOF

# 2. Ajustar Swappiness para evitar uso de disco innecesario
sudo bash -c "echo 'vm.swappiness=10' > /etc/sysctl.d/99-yarg.conf"
sudo sysctl -p /etc/sysctl.d/99-yarg.conf

# 3. Intentar configurar CPU en modo performance (si cpupower está disponible)
if command -v cpupower &> /dev/null; then
    sudo cpupower frequency-set -g performance
else
    echo "Instalando cpupower para gestión de energía..."
    sudo pacman -S --noconfirm cpupower
    sudo systemctl enable --now cpupower
    sudo cpupower frequency-set -g performance
fi

# 4. Deshabilitar ahorro de energía de pantalla
echo "Deshabilitando ahorro de energía de pantalla..."
sudo bash -c "echo 'xset s off && xset -dpms' >> /home/$USER/.config/openbox/autostart"

# 5. Ocultar el cursor del mouse automáticamente (unclutter)
echo "Instalando unclutter para ocultar el cursor..."
sudo pacman -S --noconfirm unclutter
sudo bash -c "echo 'unclutter -idle 2 -root &' >> /home/$USER/.config/openbox/autostart"

# Limpiar
rm -f "$ZIP_FILE"

echo "==================================================================="
echo "Instalación completada!"
echo "YARG instalado en: $INSTALL_DIR"
echo "Carpeta SONGS compartida en red como: \\\\$(hostname)\\YARG-Songs"
echo ""
echo "Finalizando configuración del kiosko... el sistema se reiniciará en 5 segundos."
echo "==================================================================="

# Autolimpieza: eliminar scripts de configuración después del éxito
rm -f "$HOME/setup-yarg.sh" "$HOME/setup-retroarch.sh"

sleep 5
sudo reboot
