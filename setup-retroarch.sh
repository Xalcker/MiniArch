#!/bin/bash

# Script para descargar e instalar RetroArch y configurar el kiosko
# Este script instalará RetroArch y núcleos comunes de libretro.

set -e

echo "==================================================================="
echo "Iniciando instalación y configuración de RetroArch"
echo "==================================================================="

# 1. Instalar RetroArch y cores básicos
echo "Instalando paquetes desde los repositorios oficiales..."
sudo pacman -S --noconfirm retroarch libretro-cores libretro-nestopia libretro-snes9x libretro-genesis-plus-gx libretro-mgba libretro-beetle-psx libretro-fbneo

# 2. Crear directorios para ROMS
ROM_DIR="$HOME/ROMS"
echo "Creando directorios para juegos en $ROM_DIR..."
mkdir -p "$ROM_DIR/NES" "$ROM_DIR/SNES" "$ROM_DIR/Genesis" "$ROM_DIR/GBA" "$ROM_DIR/PS1" "$ROM_DIR/Arcade"

# 3. Configurar Samba para compartir ROMS
echo "==================================================================="
echo "Configurando Samba para compartir ROMS..."
echo "==================================================================="

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
echo "==================================================================="
echo "Instalación completada!"
echo "RetroArch instalado y cores básicos configurados."
echo "Carpeta de ROMS compartida en: \\\\$(hostname)\\Retro-ROMS"
echo ""
echo "Finalizando configuración del kiosko... el sistema se reiniciará en 5 segundos."
echo "==================================================================="

# Autolimpieza: eliminar scripts de configuración después del éxito
rm -f "$HOME/setup-yarg.sh" "$HOME/setup-retroarch.sh"

sleep 5
sudo reboot
