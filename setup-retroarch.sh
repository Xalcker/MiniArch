#!/bin/bash

# Script para descargar e instalar RetroArch y configurar el kiosko
# Este script instalará RetroArch y núcleos comunes de libretro.

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -e

echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        🕹️  Iniciando instalación de RetroArch 🕹️${NC}"
echo -e "${BLUE}===================================================================${NC}"

# 1. Instalar RetroArch y cores básicos
echo -e "${BLUE}[1/4]${NC} Sincronizando repositorios e instalando paquetes..."
# Sincronizar para asegurar que encontramos los paquetes actualizados
sudo pacman -Sy
# Instalamos retroarch y cores individuales verificados en repositorios oficiales
sudo pacman -S --noconfirm retroarch libretro-nestopia libretro-snes9x libretro-genesis-plus-gx libretro-mgba libretro-beetle-psx libretro-gambatte

# 2. Crear directorios para ROMS
ROM_DIR="$HOME/ROMS"
echo -e "${BLUE}[2/4]${NC} Creando directorios para juegos en ${YELLOW}$ROM_DIR${NC}..."
mkdir -p "$ROM_DIR/NES" "$ROM_DIR/SNES" "$ROM_DIR/Genesis" "$ROM_DIR/GBA" "$ROM_DIR/PS1" "$ROM_DIR/Arcade"

# 3. Configurar Samba para compartir ROMS
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        📡 Configurando Samba para compartir ROMS${NC}"
echo -e "${BLUE}===================================================================${NC}"

if [[ -f /etc/samba/smb.conf ]]; then
    # Si ya existe (posiblemente por YARG), añadir la sección de ROMS
    if ! grep -q "\[Retro-ROMS\]" /etc/samba/smb.conf; then
        sudo bash -c 'cat >> /etc/samba/smb.conf' << EOF

[Retro-ROMS]
   path = $ROM_DIR
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $USER
EOF
        sudo systemctl restart smb nmb
    fi
else
    # Si no existe, crear uno básico
    sudo bash -c 'cat > /etc/samba/smb.conf' << EOF
[global]
   workgroup = WORKGROUP
   server string = Retro Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/log.samba
   max log size = 50

[Retro-ROMS]
   path = $ROM_DIR
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $USER
EOF
    sudo systemctl enable --now smb nmb
fi

# 4. Actualizar autostart para priorizar RetroArch (si el usuario lo desea)
# Por ahora, solo informamos al usuario o creamos un respaldo.
AUTOSTART_FILE="$HOME/.config/openbox/autostart"

echo ""
echo -e "${BLUE}===================================================================${NC}"
echo -e "${GREEN}        ✅ ¡Instalación completada!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo -e "RetroArch instalado y cores básicos configurados."
echo -e "Carpeta de ROMS compartida en: ${GREEN}\\\\$(hostname)\\Retro-ROMS${NC}"
echo ""
echo -e "${YELLOW}Finalizando configuración del kiosko... el sistema se reiniciará en 5 segundos.${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Autolimpieza: eliminar scripts de configuración después del éxito
rm -f "$HOME/setup-yarg.sh" "$HOME/setup-retroarch.sh"

sleep 5
sudo reboot
