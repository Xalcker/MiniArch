#!/bin/bash

# Script para configurar un Kiosko Web usando Chromium
# Instala Chromium y configura una URL por defecto.

# Colores ANSI
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

set -e

DEFAULT_URL="https://www.google.com"

echo -e "${BLUE}===================================================================${NC}"
echo -e "${CYAN}        🌐  Iniciando configuración de Kiosko Web  🌐${NC}"
echo -e "${BLUE}===================================================================${NC}"

# 1. Instalar Chromium
echo -e "${GREEN}Instalando Chromium...${NC}"
sudo pacman -S --noconfirm chromium

# 2. Configurar la URL
echo ""
echo -e "${YELLOW}Introduce la URL que deseas mostrar (ej: https://my-dashboard.com)${NC}"
read -p "[Presiona Enter para $DEFAULT_URL]: " KIOSK_URL
KIOSK_URL=${KIOSK_URL:-$DEFAULT_URL}

echo "$KIOSK_URL" > "$HOME/kiosk_url"
echo -e "${GREEN}URL configurada correctamente: ${CYAN}$KIOSK_URL${NC}"

# 3. Optimización de sistema (Opcional pero recomendado para Web)
# Ya incluido en la base, pero nos aseguramos de que no haya popups de Chromium
mkdir -p "$HOME/.config/chromium"
touch "$HOME/.config/chromium/First Run"

echo ""
echo -e "${BLUE}===================================================================${NC}"
echo -e "${GREEN}        ✅ ¡Instalación completada!${NC}"
echo -e "${BLUE}===================================================================${NC}"
echo -e "Chromium instalado y URL configurada en ${YELLOW}~/kiosk_url${NC}"
echo ""
echo -e "${YELLOW}Finalizando configuración del kiosko... el sistema se reiniciará en 5 segundos.${NC}"
echo -e "${BLUE}===================================================================${NC}"

# Autolimpieza: eliminar scripts de configuración
rm -f "$HOME/setup-yarg.sh" "$HOME/setup-retroarch.sh" "$HOME/setup-web.sh"

sleep 5
sudo reboot
