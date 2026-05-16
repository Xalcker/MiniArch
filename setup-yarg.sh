#!/bin/bash

# Script para descargar e instalar la última versión de YARG (Yet Another Rhythm Game)
# Versión: 0.14.0 (o superior si se actualiza el link)

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -e

# Variables dinámicas para evitar errores con sudo
REAL_USER="${SUDO_USER:-$USER}"
REAL_HOME=$(getent passwd "$REAL_USER" | cut -d: -f6)

YARG_URL="https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip"
INSTALL_DIR="$REAL_HOME/YARG"
ZIP_FILE="/tmp/YARG_Linux.zip"

echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        🎸 Iniciando descarga e instalación de YARG 🎸${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Activar multilib e instalar dependencias
echo -e "${BLUE}[0/5]${NC} Configurando repositorio multilib e instalando dependencias..."
sudo sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
sudo pacman -Syu --noconfirm lib32-pipewire lib32-alsa-plugins lib32-libpulse

# Crear directorio de instalación con el usuario correcto
sudo -u "$REAL_USER" mkdir -p "$INSTALL_DIR"

# Descargar el archivo
echo -e "${BLUE}[1/5]${NC} Descargando YARG desde: ${YELLOW}$YARG_URL${NC}"
if ! wget -O "$ZIP_FILE" "$YARG_URL"; then
    echo -e "${RED}ERROR: No se pudo descargar el archivo.${NC}"
    exit 1
fi

# Descomprimir como el usuario real
echo -e "${BLUE}[2/5]${NC} Descomprimiendo en ${YELLOW}$INSTALL_DIR${NC}..."
if ! sudo -u "$REAL_USER" unzip -o "$ZIP_FILE" -d "$INSTALL_DIR"; then
    echo -e "${RED}ERROR: Fallo al descomprimir el archivo.${NC}"
    exit 1
fi

# Dar permisos de ejecución al binario (buscando el correcto)
echo "Configurando permisos..."
sudo -u "$REAL_USER" find "$INSTALL_DIR" -maxdepth 1 -type f -name "YARG*" -exec chmod +x {} \;

# Crear carpeta de canciones
SONGS_DIR="$INSTALL_DIR/Songs"
echo "Creando carpeta de canciones en $SONGS_DIR..."
sudo -u "$REAL_USER" mkdir -p "$SONGS_DIR"

# Configuración de Samba
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        📡 Configurando Samba para compartir canciones${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Generar smb.conf (sobreescribir si es necesario para asegurar consistencia)
echo "Generando /etc/samba/smb.conf..."
sudo bash -c "cat > /etc/samba/smb.conf" << EOF
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
   force user = $REAL_USER
EOF

# Habilitar y arrancar servicios de Samba
echo "Iniciando servicios de red..."
sudo systemctl enable --now smb nmb

# Sincronizar el usuario con la base de datos de Samba
echo "Sincronizando usuario $REAL_USER con Samba..."
(echo "__KIOSK_PASSWORD__"; echo "__KIOSK_PASSWORD__") | sudo smbpasswd -s -a "$REAL_USER"

# Optimizaciones de Rendimiento para Kiosko YARG
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        🚀 Aplicando optimizaciones de rendimiento${NC}"
echo -e "${BLUE}===================================================================${NC}"

# 1. Configurar prioridad de tiempo real
sudo mkdir -p /etc/security/limits.d
sudo bash -c "cat > /etc/security/limits.d/99-yarg.conf" << EOF
$REAL_USER - rtprio 99
$REAL_USER - memlock unlimited
$REAL_USER - nice -20
EOF

# 2. Ajustar Swappiness
sudo bash -c "echo 'vm.swappiness=10' > /etc/sysctl.d/99-yarg.conf"
sudo sysctl -p /etc/sysctl.d/99-yarg.conf

# 3. CPU en modo performance
if command -v cpupower &> /dev/null; then
    sudo cpupower frequency-set -g performance || true
else
    sudo pacman -S --noconfirm cpupower || true
    sudo systemctl enable --now cpupower || true
    sudo cpupower frequency-set -g performance || true
fi

# 4. Deshabilitar ahorro de energía y cursor (evitando duplicados)
AUTOSTART_FILE="$REAL_HOME/.config/openbox/autostart"
if [ -f "$AUTOSTART_FILE" ]; then
    # Solo agregar si no están presentes
    grep -q "xset s off" "$AUTOSTART_FILE" || echo "xset s off && xset -dpms &" >> "$AUTOSTART_FILE"
    grep -q "unclutter" "$AUTOSTART_FILE" || {
        sudo pacman -S --noconfirm unclutter
        echo "unclutter -idle 2 -root &" >> "$AUTOSTART_FILE"
    }
fi

# Limpiar
rm -f "$ZIP_FILE"

echo -e "${BLUE}===================================================================${NC}"
echo -e "${GREEN}        ✅ ¡Instalación de YARG completada!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo -e "YARG instalado en: ${YELLOW}$INSTALL_DIR${NC}"
echo -e "Carpeta SONGS compartida en red como: ${GREEN}\\\\$(hostname)\\YARG-Songs${NC}"
echo ""
echo -e "${YELLOW}El sistema se reiniciará en 5 segundos para aplicar todos los cambios.${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Autolimpieza segura
rm -f "$REAL_HOME/setup-yarg.sh"

sleep 5
sudo reboot

