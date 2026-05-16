#!/bin/bash

# Script para configurar un Kiosko Web usando Chromium
# Instala Chromium y configura una URL por defecto.

set -e

DEFAULT_URL="https://www.google.com"

echo "==================================================================="
echo "Iniciando configuración de Kiosko Web (Chromium)"
echo "==================================================================="

# 1. Instalar Chromium
echo "Instalando Chromium..."
sudo pacman -S --noconfirm chromium

# 2. Configurar la URL
echo ""
read -p "Introduce la URL que deseas mostrar (ej: https://my-dashboard.com) [Presiona Enter para $DEFAULT_URL]: " KIOSK_URL
KIOSK_URL=${KIOSK_URL:-$DEFAULT_URL}

echo "$KIOSK_URL" > "$HOME/kiosk_url"
echo "URL configurada: $KIOSK_URL"

# 3. Optimización de sistema (Opcional pero recomendado para Web)
# Ya incluido en la base, pero nos aseguramos de que no haya popups de Chromium
mkdir -p "$HOME/.config/chromium"
touch "$HOME/.config/chromium/First Run"

echo ""
echo "==================================================================="
echo "Instalación completada!"
echo "Chromium instalado y URL configurada en ~/kiosk_url"
echo ""
echo "Finalizando configuración del kiosko... el sistema se reiniciará en 5 segundos."
echo "==================================================================="

# Autolimpieza: eliminar scripts de configuración
rm -f "$HOME/setup-yarg.sh" "$HOME/setup-retroarch.sh" "$HOME/setup-web.sh"

sleep 5
sudo reboot
