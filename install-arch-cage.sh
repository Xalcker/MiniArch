#!/usr/bin/env bash
# =============================================================================
# install-arch-cage.sh
# -----------------------------------------------------------------------------
# Orquestador para instalar Arch Linux + Cage (Wayland/XWayland) + YARG.
# Reutiliza los modulos compartidos del instalador kiosk original y conserva
# aqui solo lo especifico de Cage/YARG.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/arch-cage-install.log}"

log() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO:${NC} $message" | tee -a "$LOG_FILE"
}

log_action() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${CYAN}ACTION:${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR:${NC} $message" | tee -a "$LOG_FILE" >&2
}

section() {
    echo -e "\n${CYAN}== $1 ==${NC}"
}

step() {
    printf "${MAGENTA}  > [%s]${NC} %s\n" "$1" "$2"
}

warn() {
    echo -e "${YELLOW}  ! $1${NC}"
}

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    log_error "No existe $SCRIPT_DIR/.env. Cree el archivo .env antes de ejecutar el instalador Cage."
    exit 1
fi

log "Cargando configuracion desde .env..."
set -a
# shellcheck disable=SC1090
source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
set +a
log "Configuracion cargada desde .env"

DISK_DEVICE="${DISK_DEVICE:-/dev/sda}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-minikiosk}"
TIMEZONE="${TIMEZONE:-America/Phoenix}"
ENABLE_SSH="${ENABLE_SSH:-false}"
INSTALL_NVIDIA="${INSTALL_NVIDIA:-}"
ALLOW_INSECURE_DEFAULT_PASSWORD="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-true}"
PLYMOUTH_THEME_NAME="${PLYMOUTH_THEME_NAME:-arch-cage}"
PLYMOUTH_IMAGE_PATH="${PLYMOUTH_IMAGE_PATH:-./assets/plymouth-image.png}"
CURSOR_PATH="${CURSOR_PATH:-./assets/cursor/}"
PLYMOUTH_ASSET_AVAILABLE="${PLYMOUTH_ASSET_AVAILABLE:-false}"
YARG_SONGS_DIR="${YARG_SONGS_DIR:-/opt/YARG/Songs}"
YARG_PERSISTENT_DATA_DIR="${YARG_PERSISTENT_DATA_DIR:-/home/$KIOSK_USER/.config/yarg-kiosk}"
YARG_RELEASE_CHANNEL="${YARG_RELEASE_CHANNEL:-ask}"
YARG_NIGHTLY_API_URL="${YARG_NIGHTLY_API_URL:-https://api.github.com/repos/YARC-Official/YARG-BleedingEdge/releases/latest}"
YARG_NIGHTLY_ASSET_REGEX="${YARG_NIGHTLY_ASSET_REGEX:-linux.*(x86_64|x64|64).*\\.zip}"
YARG_URL="${YARG_URL:-https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip}"

source "$SCRIPT_DIR/lib/validation.sh" || { log_error "No se pudo importar validation.sh"; exit 1; }
source "$SCRIPT_DIR/lib/partitioning.sh" || { log_error "No se pudo importar partitioning.sh"; exit 1; }
source "$SCRIPT_DIR/lib/base_install.sh" || { log_error "No se pudo importar base_install.sh"; exit 1; }
source "$SCRIPT_DIR/lib/bootloader.sh" || { log_error "No se pudo importar bootloader.sh"; exit 1; }
source "$SCRIPT_DIR/lib/plymouth.sh" || { log_error "No se pudo importar plymouth.sh"; exit 1; }
source "$SCRIPT_DIR/lib/drivers.sh" || { log_error "No se pudo importar drivers.sh"; exit 1; }
source "$SCRIPT_DIR/lib/cage.sh" || { log_error "No se pudo importar cage.sh"; exit 1; }
source "$SCRIPT_DIR/lib/yarg.sh" || { log_error "No se pudo importar yarg.sh"; exit 1; }
source "$SCRIPT_DIR/lib/customization.sh" || { log_error "No se pudo importar customization.sh"; exit 1; }
source "$SCRIPT_DIR/lib/finalization.sh" || { log_error "No se pudo importar finalization.sh"; exit 1; }

INSTALL_MOUNTS_CREATED=0
INSTALL_SUCCESS=0

ask_initial_questions() {
    section "Configuracion inicial"
    echo -e "${YELLOW}Disco destino:${NC} $DISK_DEVICE"
    echo -e "${YELLOW}Usuario kiosko:${NC} $KIOSK_USER"
    echo ""

    if [[ -z "$INSTALL_NVIDIA" ]]; then
        read -rp "$(echo -e "${BLUE}Instalar driver NVIDIA? (s/N): ${NC}")" answer
        INSTALL_NVIDIA=false
        [[ "${answer,,}" == "s" || "${answer,,}" == "y" ]] && INSTALL_NVIDIA=true
    fi

    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        log "Se instalaran drivers NVIDIA (nvidia-dkms, nvidia-utils)"
    else
        warn "Driver NVIDIA omitido. Se instalaran Intel, AMD, Mesa y Vulkan base."
    fi

    YARG_RELEASE_CHANNEL="${YARG_RELEASE_CHANNEL,,}"
    if [[ "$YARG_RELEASE_CHANNEL" == "ask" ]]; then
        read -rp "$(echo -e "${BLUE}Canal de YARG: stable desde .env o nightly mas reciente? [stable/nightly] (stable): ${NC}")" answer
        case "${answer,,}" in
            ""|s|stable)
                YARG_RELEASE_CHANNEL="stable"
                ;;
            n|nightly)
                YARG_RELEASE_CHANNEL="nightly"
                ;;
            *)
                log_error "Opcion invalida: $answer. Responda stable o nightly."
                return 1
                ;;
        esac
    fi

    case "$YARG_RELEASE_CHANNEL" in
        stable)
            log "Se usara YARG stable desde YARG_URL: $YARG_URL"
            ;;
        nightly)
            log "Se resolvera el nightly mas reciente desde YARG-BleedingEdge"
            ;;
        *)
            log_error "YARG_RELEASE_CHANNEL invalido: $YARG_RELEASE_CHANNEL. Use stable, nightly o ask."
            return 1
            ;;
    esac
}

cleanup_on_exit() {
    local exit_status=$?

    if [[ ${INSTALL_SUCCESS:-0} -eq 1 || $exit_status -eq 0 ]]; then
        return 0
    fi

    if [[ ${INSTALL_MOUNTS_CREATED:-0} -ne 1 ]]; then
        return "$exit_status"
    fi

    log_error "Instalacion interrumpida. Intentando desmontar particiones y desactivar swap..."
    cleanup_mounts || log_error "No se pudo completar la limpieza automatica"
    return "$exit_status"
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        exit 1
    fi

    trap cleanup_on_exit EXIT

    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}        INSTALADOR ARCH LINUX + CAGE + YARG${NC}"
    echo -e "${BLUE}===================================================================${NC}"

    ask_initial_questions

    section "Validacion"
    if ! validate_environment; then
        log_error "Validacion de entorno fallida: no se esta ejecutando en el instalador live de Arch Linux"
        exit 1
    fi

    if ! validate_security_config; then
        log_error "Configuracion de seguridad invalida"
        exit 1
    fi

    if [[ "$ENABLE_PLYMOUTH" == "true" ]]; then
        if ! preflight_optional_assets "$PLYMOUTH_IMAGE_PATH" "$CURSOR_PATH"; then
            log_error "Validacion de assets Plymouth/cursor fallida"
            exit 1
        fi
    fi

    if ! check_network; then
        log_error "Sin conexion de red: no se puede continuar con la instalacion"
        exit 1
    fi

    if ! resolve_yarg_download_url; then
        log_error "Fallo al resolver la URL de descarga de YARG"
        exit 1
    fi

    if ! check_disk "$DISK_DEVICE"; then
        log_error "Disco invalido o insuficiente: se requiere al menos 16GB"
        exit 1
    fi

    if ! check_disk_empty "$DISK_DEVICE"; then
        log_error "Operacion cancelada: no se confirmo la destruccion de datos"
        exit 1
    fi

    section "Particionado y montaje"
    if ! partition_disk "$DISK_DEVICE"; then
        log_error "Fallo en particionamiento del disco"
        exit 1
    fi

    if ! format_partitions "$DISK_DEVICE"; then
        log_error "Fallo en formateo de particiones"
        exit 1
    fi

    if ! mount_partitions "$DISK_DEVICE"; then
        log_error "Fallo en montaje de particiones"
        exit 1
    fi
    INSTALL_MOUNTS_CREATED=1

    section "Sistema base"
    if ! install_cage_base_system; then
        log_error "Fallo en instalacion del sistema base Cage/YARG"
        exit 1
    fi

    if ! generate_fstab; then
        log_error "Fallo en generacion de fstab"
        exit 1
    fi

    section "Bootloader y sistema"
    if ! configure_system_basics; then
        log_error "Fallo en configuracion basica del sistema"
        exit 1
    fi

    if ! install_grub; then
        log_error "Fallo en instalacion de GRUB"
        exit 1
    fi

    if ! configure_grub_silent; then
        log_error "Fallo en configuracion silenciosa de GRUB"
        exit 1
    fi

    if ! configure_cage_plymouth; then
        log_error "Fallo en instalacion/configuracion de Plymouth"
        exit 1
    fi

    if ! configure_nvidia_kernel_params; then
        log_error "Fallo en configuracion de parametros NVIDIA"
        exit 1
    fi

    section "Stack YARG"
    if ! install_audio_system; then
        log_error "Fallo en instalacion/configuracion del sistema de audio"
        exit 1
    fi

    if ! create_cage_user; then
        log_error "Fallo en creacion/configuracion del usuario kiosko"
        exit 1
    fi

    if ! configure_multilib_yarg_deps; then
        log_error "Fallo en configuracion de multilib/dependencias YARG"
        exit 1
    fi

    if ! configure_hid_access; then
        log_error "Fallo en configuracion de acceso HID"
        exit 1
    fi

    if ! install_yarg; then
        log_error "Fallo en instalacion de YARG"
        exit 1
    fi

    if ! configure_yarg_default_settings; then
        log_error "Fallo en configuracion inicial de YARG"
        exit 1
    fi

    if ! configure_yarg_samba_share; then
        log_error "Fallo en configuracion de Samba para YARG"
        exit 1
    fi

    if ! configure_yarg_performance; then
        log_error "Fallo en optimizaciones de rendimiento para YARG"
        exit 1
    fi

    if ! install_yarg_update_script; then
        log_error "Fallo en instalacion del updater de YARG"
        exit 1
    fi

    if ! install_cage_wrapper; then
        log_error "Fallo en creacion del wrapper de Cage/YARG"
        exit 1
    fi

    if ! install_cage_service; then
        log_error "Fallo en configuracion del servicio cage-kiosk"
        exit 1
    fi

    section "Red y limpieza visual"
    if ! configure_network_target; then
        log_error "Fallo en configuracion de red/target grafico"
        exit 1
    fi

    if ! hide_system_messages "$KIOSK_USER"; then
        log_error "Fallo en limpieza visual de mensajes del sistema"
        exit 1
    fi

    section "Finalizacion"
    if ! cleanup_and_finish; then
        log_error "Fallo en limpieza/finalizacion de la instalacion"
        exit 1
    fi
    INSTALL_MOUNTS_CREATED=0
    INSTALL_SUCCESS=1

    echo -e "${GREEN}"
    echo "Instalacion completada."
    echo "Cage + YARG quedan instalados en /opt/YARG."
    echo "Servicio habilitado: cage-kiosk.service."
    echo "Wrapper: /usr/local/bin/run-yarg.sh."
    echo -e "${NC}"
    echo "Reinicia con: reboot"
}

main "$@"
