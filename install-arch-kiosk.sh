#!/bin/bash

################################################################################
# Instalador Automatizado de Arch Linux Modo Kiosko
#
# Este script automatiza la instalación de Arch Linux configurado como un
# sistema tipo kiosko con arranque directo a X, interfaz gráfica minimalista
# (OpenBox), y personalización visual completa del proceso de arranque y
# apagado mediante Plymouth.
#
# Requisitos:
# - Ejecutar desde el instalador live de Arch Linux
# - Disco de al menos 16GB en /dev/sda
# - Conexión de red activa
################################################################################

set -e  # Salir inmediatamente si un comando falla
set -u  # Tratar variables no definidas como error

# Colores ANSI para terminal
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

################################################################################
# Funciones de Logging Tempranas
################################################################################

# Archivo de log temporal (se sobrescribirá con el valor de .env si existe)
LOG_FILE="${LOG_FILE:-/var/log/arch-kiosk-install.log}"

# Función para logging general
log() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO:${NC} $message" | tee -a "$LOG_FILE"
}

# Función para logging de alertas (acciones en curso)
log_action() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${CYAN}ACTION:${NC} $message" | tee -a "$LOG_FILE"
}

# Función para logging de errores
log_error() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR:${NC} $message" | tee -a "$LOG_FILE" >&2
}

################################################################################
# Cargar Configuración desde .env (si existe)
################################################################################

# Directorio del script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Cargar archivo .env si existe
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log "Cargando configuración desde .env..."
    # Exportar variables del archivo .env (ignorar comentarios y líneas vacías)
    set -a
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    set +a
    log "Configuración cargada desde .env"
fi

################################################################################
# Variables Globales de Configuración (valores por defecto)
################################################################################

# Configuración del disco
DISK_DEVICE="${DISK_DEVICE:-/dev/sda}"
ESP_SIZE="${ESP_SIZE:-512M}"
ROOT_SIZE="${ROOT_SIZE:-8G}"
SWAP_SIZE="${SWAP_SIZE:-2G}"

# Configuración del usuario
KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"

# Configuración de Plymouth
PLYMOUTH_THEME_NAME="${PLYMOUTH_THEME_NAME:-arch-kiosk}"
PLYMOUTH_IMAGE_PATH="${PLYMOUTH_IMAGE_PATH:-./assets/plymouth-image.png}"

# Configuración del cursor
CURSOR_PATH="${CURSOR_PATH:-./assets/cursor/}"

# Configuración de servicios y seguridad
ALLOW_INSECURE_DEFAULT_PASSWORD="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"
ENABLE_SSH="${ENABLE_SSH:-true}"
PLYMOUTH_ASSET_AVAILABLE="${PLYMOUTH_ASSET_AVAILABLE:-false}"

# Configuración de zona horaria
TIMEZONE="${TIMEZONE:-America/Mexico_City}"

# Archivo de log
LOG_FILE="${LOG_FILE:-/var/log/arch-kiosk-install.log}"

################################################################################
# Función Principal
################################################################################

# Función main que orquesta la ejecución secuencial de todos los módulos
main() {
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}        🚀 INSTALADOR DE ARCH LINUX MODO KIOSKO 🚀${NC}"
    echo -e "${BLUE}===================================================================${NC}"

    # Importar todos los módulos
    log "Importando módulos del sistema..."
    source lib/validation.sh || { log_error "No se pudo importar módulo de validación"; exit 1; }
    source lib/partitioning.sh || { log_error "No se pudo importar módulo de particionamiento"; exit 1; }
    source lib/base_install.sh || { log_error "No se pudo importar módulo de instalación base"; exit 1; }
    source lib/bootloader.sh || { log_error "No se pudo importar módulo de bootloader"; exit 1; }
    source lib/plymouth.sh || { log_error "No se pudo importar módulo de Plymouth"; exit 1; }
    source lib/drivers.sh || { log_error "No se pudo importar módulo de drivers"; exit 1; }
    source lib/gui.sh || { log_error "No se pudo importar módulo de GUI"; exit 1; }
    source lib/customization.sh || { log_error "No se pudo importar módulo de personalización"; exit 1; }
    source lib/finalization.sh || { log_error "No se pudo importar módulo de finalización"; exit 1; }
    log "Todos los módulos importados correctamente"

    INSTALL_MOUNTS_CREATED=0
    INSTALL_SUCCESS=0
    trap cleanup_on_exit EXIT

    # Fase 1: Validación del entorno
    log "==================================================================="
    log "Fase 1: Validación del entorno de ejecución"
    log "==================================================================="

    log "Validando entorno de Arch Linux..."
    if ! validate_environment; then
        log_error "Validación de entorno fallida: No se está ejecutando en el instalador de Arch Linux"
        exit 1
    fi
    log "Entorno validado correctamente"

    log "Validando configuración de seguridad..."
    if ! validate_security_config; then
        log_error "Configuración de seguridad inválida"
        exit 1
    fi
    log "Configuración de seguridad validada"

    log "Validando assets opcionales..."
    if ! preflight_optional_assets "$PLYMOUTH_IMAGE_PATH" "$CURSOR_PATH"; then
        log_error "Validación de assets opcionales fallida"
        exit 1
    fi
    log "Validación de assets opcionales completada"

    log "Verificando conexión de red..."
    if ! check_network; then
        log_error "Sin conexión de red: No se puede continuar con la instalación"
        exit 1
    fi
    log "Conexión de red verificada"

    log "Verificando disco $DISK_DEVICE..."
    if ! check_disk "$DISK_DEVICE"; then
        log_error "Disco inválido o insuficiente: Se requiere al menos 16GB"
        exit 1
    fi
    log "Disco verificado correctamente"

    log "Verificando si el disco está vacío..."
    if ! check_disk_empty "$DISK_DEVICE"; then
        log_error "Operación cancelada: El usuario no confirmó la destrucción de datos"
        exit 1
    fi
    log "Verificación de disco vacío completada"

    # Fase 2: Particionamiento y montaje
    log "==================================================================="
    log "Fase 2: Particionamiento y montaje del disco"
    log "==================================================================="

    log "Particionando disco $DISK_DEVICE..."
    if ! partition_disk "$DISK_DEVICE"; then
        log_error "Fallo en particionamiento del disco"
        exit 1
    fi
    log "Disco particionado correctamente"

    log "Formateando particiones..."
    if ! format_partitions "$DISK_DEVICE"; then
        log_error "Fallo en formateo de particiones"
        exit 1
    fi
    log "Particiones formateadas correctamente"

    log "Montando particiones..."
    if ! mount_partitions "$DISK_DEVICE"; then
        log_error "Fallo en montaje de particiones"
        exit 1
    fi
    INSTALL_MOUNTS_CREATED=1
    log "Particiones montadas correctamente"

    # Fase 3: Instalación del sistema base
    log "==================================================================="
    log "Fase 3: Instalación del sistema base"
    log "==================================================================="

    log "Instalando sistema base con pacstrap..."
    if ! install_base_system; then
        log_error "Fallo en instalación del sistema base"
        exit 1
    fi
    log "Sistema base instalado correctamente"

    log "Generando archivo fstab..."
    if ! generate_fstab; then
        log_error "Fallo en generación de fstab"
        exit 1
    fi
    log "Archivo fstab generado correctamente"

    # Fase 4: Configuración en chroot
    log "==================================================================="
    log "Fase 4: Configuración del sistema (en chroot)"
    log "==================================================================="

    log "Instalando GRUB..."
    if ! install_grub; then
        log_error "Fallo en instalación de GRUB: El sistema no será arrancable"
        exit 1
    fi
    log "GRUB instalado correctamente"

    log "Configurando GRUB para arranque silencioso..."
    if ! configure_grub_silent; then
        log_error "Fallo en configuración de GRUB"
        exit 1
    fi
    log "GRUB configurado correctamente"

    log "Instalando Plymouth..."
    if ! install_plymouth; then
        log "Advertencia: No se pudo instalar Plymouth (no crítico, continuando sin pantalla de arranque personalizada)"
    else
        log "Plymouth instalado correctamente"

        log "Creando tema personalizado de Plymouth: $PLYMOUTH_THEME_NAME..."
        if ! create_custom_theme "$PLYMOUTH_THEME_NAME"; then
            log "Advertencia: No se pudo crear tema de Plymouth (no crítico)"
        else
            log "Tema de Plymouth creado correctamente"

            if [[ "$PLYMOUTH_ASSET_AVAILABLE" == "true" ]]; then
                log "Configurando Plymouth con imagen personalizada..."
                if ! configure_plymouth "$PLYMOUTH_THEME_NAME" "$PLYMOUTH_IMAGE_PATH"; then
                    log "Advertencia: No se pudo configurar Plymouth (no crítico)"
                else
                    log "Plymouth configurado correctamente"
                fi
            else
                log "Plymouth instalado, pero sin imagen válida; se omite configuración personalizada"
            fi
        fi
    fi

    log "Instalando drivers gráficos (AMD, Intel, NVIDIA, Mesa)..."
    if ! install_graphics_drivers; then
        log_error "Fallo en instalación de drivers gráficos"
        exit 1
    fi
    log "Drivers gráficos instalados correctamente"

    log "Instalando sistema de audio PipeWire..."
    if ! install_audio_system; then
        log_error "Fallo en instalación de sistema de audio"
        exit 1
    fi
    log "Sistema de audio instalado correctamente"

    log "Instalando OpenBox y servidor X..."
    if ! install_openbox; then
        log_error "Fallo en instalación de OpenBox"
        exit 1
    fi
    log "OpenBox instalado correctamente"

    log "Creando usuario del sistema: $KIOSK_USER..."
    if ! create_user "$KIOSK_USER"; then
        log_error "Fallo en creación de usuario"
        exit 1
    fi
    log "Usuario creado correctamente"

    log "Configurando autologin para $KIOSK_USER..."
    if ! configure_autologin "$KIOSK_USER"; then
        log_error "Fallo en configuración de autologin"
        exit 1
    fi
    log "Autologin configurado correctamente"

    log "Configurando autostart de X para $KIOSK_USER..."
    if ! configure_autostart_x "$KIOSK_USER"; then
        log_error "Fallo en configuración de autostart X"
        exit 1
    fi
    log "Autostart de X configurado correctamente"

    log "Configurando la aplicación del kiosko con apagado automático para $KIOSK_USER..."
    if ! configure_kiosk_autostart "$KIOSK_USER"; then
        log_error "Fallo en configuración de autostart del kiosko"
        exit 1
    fi
    log "Aplicación del kiosko con apagado automático configurada correctamente"

    log "Ocultando mensajes del sistema..."
    if ! hide_system_messages "$KIOSK_USER"; then
        log_error "Fallo en ocultación de mensajes del sistema"
        exit 1
    fi
    log "Mensajes del sistema ocultados correctamente"

    log "Instalando scripts adicionales..."
    if ! install_extra_scripts "$KIOSK_USER"; then
        log "Advertencia: No se pudieron instalar los scripts adicionales (no crítico)"
    else
        log "Scripts adicionales instalados correctamente"
    fi

    log "Instalando cursor personalizado..."
    if ! install_custom_cursor "$CURSOR_PATH" "$KIOSK_USER"; then
        log "Advertencia: No se pudo instalar cursor personalizado (no crítico)"
    else
        log "Cursor personalizado instalado correctamente"
    fi

    if [[ "$PLYMOUTH_ASSET_AVAILABLE" == "true" ]]; then
        log "Aplicando imagen personalizada de Plymouth..."
        if ! apply_plymouth_image "$PLYMOUTH_IMAGE_PATH" "$PLYMOUTH_THEME_NAME"; then
            log "Advertencia: No se pudo aplicar imagen de Plymouth (no crítico)"
        else
            log "Imagen de Plymouth aplicada correctamente"
        fi
    else
        log "Sin imagen Plymouth válida; se omite aplicación de imagen personalizada"
    fi

    # Fase 5: Configuración de red y finalización
    log "==================================================================="
    log "Fase 5: Configuración de red y finalización"
    log "==================================================================="

    log "Configurando NetworkManager y zona horaria..."
    if ! configure_network; then
        log_error "Fallo en configuración de red"
        exit 1
    fi
    log "Red configurada correctamente"

    log "Ejecutando limpieza y finalización..."
    if ! cleanup_and_finish; then
        log_error "Fallo en limpieza final"
        exit 1
    fi
    INSTALL_MOUNTS_CREATED=0
    log "Limpieza completada correctamente"

    log "Instalación completada exitosamente!"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${GREEN}        ✅ ¡ARCH LINUX KIOSKO INSTALADO CON ÉXITO!${NC}"
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${YELLOW}Próximos pasos:${NC}"
    echo -e "1. Reinicia el sistema: ${CYAN}reboot${NC}"
    echo -e "2. Al iniciar, elige tu 'Sabor' (YARG, RetroArch o Web)."
    echo -e "${BLUE}===================================================================${NC}"
    INSTALL_SUCCESS=1
}

cleanup_on_exit() {
    local exit_status=$?

    if [[ ${INSTALL_SUCCESS:-0} -eq 1 || $exit_status -eq 0 ]]; then
        return 0
    fi

    if [[ ${INSTALL_MOUNTS_CREATED:-0} -ne 1 ]]; then
        return "$exit_status"
    fi

    log_error "Instalación interrumpida. Intentando desmontar particiones y desactivar swap..."
    cleanup_mounts || log_error "La limpieza automática no pudo completarse; revise montajes y swap manualmente"
    return "$exit_status"
}

################################################################################
# Punto de Entrada
################################################################################

# Verificar que el script se ejecuta como root
if [[ $EUID -ne 0 ]]; then
    log_error "Este script debe ejecutarse como root"
    exit 1
fi

# Ejecutar función principal
main "$@"
