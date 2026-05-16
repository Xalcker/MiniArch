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

# 3. Configurar RetroArch para compatibilidad con VM (evitar pantalla negra)
echo -e "${BLUE}[3/4]${NC} Optimizando configuración para entorno virtual..."
mkdir -p "$HOME/.config/retroarch"
cat > "$HOME/.config/retroarch/retroarch.cfg" << EOF
# Driver de video compatible con Proxmox/VM
video_driver = "sdl2"
video_vsync = "false"
# Menú ligero (RGUI) que no requiere aceleración 3D
menu_driver = "rgui"
# Pantalla completa
video_fullscreen = "true"
# Rutas de búsqueda
libretro_directory = "/usr/lib/libretro"
content_directory = "$ROM_DIR"
EOF
chown -R $USER:$USER "$HOME/.config/retroarch"

# 4. Configurar Samba para compartir ROMS
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

# Sincronizar el usuario con la base de datos de Samba
echo "Sincronizando usuario $USER con Samba..."
(echo "__KIOSK_PASSWORD__"; echo "__KIOSK_PASSWORD__") | sudo smbpasswd -s -a $USER

# Optimizaciones de Rendimiento
echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        🚀 Aplicando optimizaciones de rendimiento${NC}"
echo -e "${BLUE}===================================================================${NC}"

# 1. Ajustar Swappiness
sudo bash -c "echo 'vm.swappiness=10' > /etc/sysctl.d/99-retroarch.conf"
sudo sysctl -p /etc/sysctl.d/99-retroarch.conf

# 2. Configurar CPU en modo performance
if command -v cpupower &> /dev/null; then
    sudo cpupower frequency-set -g performance || echo -e "${YELLOW}Aviso: No se pudo cambiar el modo de CPU (típico en VMs). Continuando...${NC}"
else
    sudo pacman -S --noconfirm cpupower || true
    if command -v cpupower &> /dev/null; then
        sudo systemctl enable --now cpupower || true
        sudo cpupower frequency-set -g performance || echo -e "${YELLOW}Aviso: No se pudo cambiar el modo de CPU (típico en VMs). Continuando...${NC}"
    fi
fi

# 3. Deshabilitar ahorro de energía de pantalla
echo "Deshabilitando ahorro de energía de pantalla..."
sudo bash -c "echo 'xset s off && xset -dpms' >> /home/$USER/.config/openbox/autostart"

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
