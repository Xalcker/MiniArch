#!/usr/bin/env bash
# =============================================================================
# install-cage-clonehero.sh
# -----------------------------------------------------------------------------
# Orquestador para instalar Arch Linux + Cage (Wayland/XWayland) + Clone Hero.
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
VERBOSE_INSTALL="${VERBOSE_INSTALL:-false}"

log() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO:${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR:${NC} $message" | tee -a "$LOG_FILE" >&2
}

section() {
    echo -e "\n${CYAN}== $1 ==${NC}"
}

warn() {
    echo -e "${YELLOW}  ! $1${NC}"
}

run_quiet() {
    if [[ "${VERBOSE_INSTALL:-false}" == "true" ]]; then
        "$@"
        return $?
    fi

    "$@" >> "$LOG_FILE" 2>&1
}

ENV_FILE_LOADED=false
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log "Cargando configuracion desde .env..."
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    set +a
    ENV_FILE_LOADED=true
    log "Configuracion cargada desde .env"
else
    warn "No existe $SCRIPT_DIR/.env; se usara modo asistido interactivo."
fi

DISK_DEVICE="${DISK_DEVICE:-ask}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
REQUIRE_ROOT_PASSWORD="${REQUIRE_ROOT_PASSWORD:-true}"
KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-miniclonehero}"
TIMEZONE="${TIMEZONE:-America/Phoenix}"
ENABLE_SSH="${ENABLE_SSH:-false}"
INSTALL_NVIDIA="${INSTALL_NVIDIA:-}"
ALLOW_INSECURE_DEFAULT_PASSWORD="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-true}"
PLYMOUTH_THEME_NAME="${PLYMOUTH_THEME_NAME:-arch-cage}"
PLYMOUTH_IMAGE_PATH="${PLYMOUTH_IMAGE_PATH:-./assets/plymouth-image.png}"
CURSOR_PATH="${CURSOR_PATH:-./assets/cursor/}"
PLYMOUTH_ASSET_AVAILABLE="${PLYMOUTH_ASSET_AVAILABLE:-false}"
CLONEHERO_RELEASE_CHANNEL="${CLONEHERO_RELEASE_CHANNEL:-latest}"
CLONEHERO_API_URL="${CLONEHERO_API_URL:-https://api.github.com/repos/clonehero-game/releases/releases}"
CLONEHERO_ASSET_REGEX="${CLONEHERO_ASSET_REGEX:-linux.*(x86_64|x64|64|amd64).*(zip|tar\\.xz|tar\\.gz|appimage)$}"
CLONEHERO_URL="${CLONEHERO_URL:-}"
CLONEHERO_SONGS_DIR="${CLONEHERO_SONGS_DIR:-/home/$KIOSK_USER/Songs}"
CLONEHERO_DATA_DIR="${CLONEHERO_DATA_DIR:-/home/$KIOSK_USER/.clonehero}"
CLONEHERO_RESOLUTION="${CLONEHERO_RESOLUTION:-ask}"
CLONEHERO_FORCE_SOFTWARE_RENDER="${CLONEHERO_FORCE_SOFTWARE_RENDER:-false}"
CLONEHERO_EXIT_MENU="${CLONEHERO_EXIT_MENU:-always}"

source "$SCRIPT_DIR/lib/validation.sh" || { log_error "No se pudo importar validation.sh"; exit 1; }
source "$SCRIPT_DIR/lib/partitioning.sh" || { log_error "No se pudo importar partitioning.sh"; exit 1; }
source "$SCRIPT_DIR/lib/base_install.sh" || { log_error "No se pudo importar base_install.sh"; exit 1; }
source "$SCRIPT_DIR/lib/bootloader.sh" || { log_error "No se pudo importar bootloader.sh"; exit 1; }
source "$SCRIPT_DIR/lib/plymouth.sh" || { log_error "No se pudo importar plymouth.sh"; exit 1; }
source "$SCRIPT_DIR/lib/drivers.sh" || { log_error "No se pudo importar drivers.sh"; exit 1; }
source "$SCRIPT_DIR/lib/cage.sh" || { log_error "No se pudo importar cage.sh"; exit 1; }
source "$SCRIPT_DIR/lib/clonehero.sh" || { log_error "No se pudo importar clonehero.sh"; exit 1; }
source "$SCRIPT_DIR/lib/customization.sh" || { log_error "No se pudo importar customization.sh"; exit 1; }
source "$SCRIPT_DIR/lib/finalization.sh" || { log_error "No se pudo importar finalization.sh"; exit 1; }

INSTALL_MOUNTS_CREATED=0
INSTALL_SUCCESS=0

resolve_clonehero_resolution() {
    local resolution="${1,,}"

    case "$resolution" in
        4k|2160p|3840x2160)
            CLONEHERO_RESOLUTION="4k"
            CLONEHERO_SCREEN_WIDTH=3840
            CLONEHERO_SCREEN_HEIGHT=2160
            ;;
        2k|1440p|2560x1440)
            CLONEHERO_RESOLUTION="2k"
            CLONEHERO_SCREEN_WIDTH=2560
            CLONEHERO_SCREEN_HEIGHT=1440
            ;;
        1080|1080p|1920x1080)
            CLONEHERO_RESOLUTION="1080p"
            CLONEHERO_SCREEN_WIDTH=1920
            CLONEHERO_SCREEN_HEIGHT=1080
            ;;
        720|720p|1280x720)
            CLONEHERO_RESOLUTION="720p"
            CLONEHERO_SCREEN_WIDTH=1280
            CLONEHERO_SCREEN_HEIGHT=720
            ;;
        *)
            log_error "CLONEHERO_RESOLUTION invalida: $1. Use 4k, 2k, 1080p, 720p o ask."
            return 1
            ;;
    esac
}

prompt_value() {
    local var_name="$1"
    local label="$2"
    local default_value="$3"
    local current_value="${!var_name-}"
    local answer

    if [[ -n "$current_value" && "$ENV_FILE_LOADED" == "true" ]]; then
        return 0
    fi

    read -rp "$(echo -e "${BLUE}${label} (${current_value:-$default_value}): ${NC}")" answer
    answer="${answer:-${current_value:-$default_value}}"
    printf -v "$var_name" "%s" "$answer"
}

prompt_bool() {
    local var_name="$1"
    local label="$2"
    local default_value="$3"
    local current_value="${!var_name-}"
    local prompt_default answer normalized

    if [[ -n "$current_value" && "$ENV_FILE_LOADED" == "true" ]]; then
        return 0
    fi

    prompt_default="$default_value"
    [[ "$prompt_default" == "true" ]] && prompt_default="s"
    [[ "$prompt_default" == "false" ]] && prompt_default="N"

    read -rp "$(echo -e "${BLUE}${label} (s/N, default ${prompt_default}): ${NC}")" answer
    answer="${answer:-${current_value:-$default_value}}"
    normalized="${answer,,}"

    case "$normalized" in
        s|si|sí|y|yes|true|1)
            printf -v "$var_name" "%s" "true"
            ;;
        n|no|false|0)
            printf -v "$var_name" "%s" "false"
            ;;
        *)
            log_error "Respuesta invalida para $label: $answer"
            return 1
            ;;
    esac
}

prompt_password() {
    local var_name="$1"
    local label="$2"
    local current_value="${!var_name-}"
    local password confirmation

    if [[ -n "$current_value" && "$ENV_FILE_LOADED" == "true" ]]; then
        return 0
    fi

    while true; do
        read -rsp "$(echo -e "${BLUE}${label}: ${NC}")" password
        echo ""
        read -rsp "$(echo -e "${BLUE}Confirme ${label}: ${NC}")" confirmation
        echo ""

        if [[ -z "$password" ]]; then
            log_error "$label no puede quedar vacia"
            continue
        fi

        if [[ "$password" != "$confirmation" ]]; then
            log_error "Las contrasenas no coinciden"
            continue
        fi

        printf -v "$var_name" "%s" "$password"
        return 0
    done
}

ask_guided_configuration() {
    section "Modo asistido"

    if [[ "$ENV_FILE_LOADED" == "true" ]]; then
        echo -e "${YELLOW}Se cargaron valores desde .env; solo se preguntara lo que falte o este en ask.${NC}"
    else
        echo -e "${YELLOW}No se encontro .env. Responda estas preguntas para continuar sin archivo de configuracion.${NC}"
    fi
    echo ""

    prompt_value KIOSK_USER "Usuario kiosko" "kiosk" || return 1
    prompt_password KIOSK_PASSWORD "Password del usuario $KIOSK_USER" || return 1

    if [[ "$REQUIRE_ROOT_PASSWORD" == "true" ]]; then
        prompt_password ROOT_PASSWORD "Password de root" || return 1
    fi

    prompt_value KIOSK_HOSTNAME "Hostname del kiosko" "miniclonehero" || return 1
    prompt_value TIMEZONE "Zona horaria" "America/Phoenix" || return 1
    prompt_bool ENABLE_SSH "Habilitar SSH para mantenimiento remoto" "false" || return 1
    prompt_bool ENABLE_PLYMOUTH "Habilitar Plymouth" "true" || return 1
    prompt_bool CLONEHERO_FORCE_SOFTWARE_RENDER "Forzar render por software para Clone Hero" "false" || return 1

    if [[ -z "${CLONEHERO_EXIT_MENU:-}" || "$ENV_FILE_LOADED" != "true" ]]; then
        local answer="${CLONEHERO_EXIT_MENU:-always}"
        read -rp "$(echo -e "${BLUE}Que hacer al salir de Clone Hero? [always/restart/never] (${answer}): ${NC}")" answer
        CLONEHERO_EXIT_MENU="${answer:-${CLONEHERO_EXIT_MENU:-always}}"
    fi

    case "${CLONEHERO_EXIT_MENU,,}" in
        always|restart|relaunch|volver|clonehero|never|off|false|no)
            ;;
        *)
            log_error "CLONEHERO_EXIT_MENU invalido: $CLONEHERO_EXIT_MENU. Use always, restart o never."
            return 1
            ;;
    esac

    if [[ "$ENV_FILE_LOADED" != "true" || -z "${CLONEHERO_DATA_DIR:-}" ]]; then
        CLONEHERO_DATA_DIR="/home/$KIOSK_USER/.clonehero"
    fi
}

ask_initial_questions() {
    section "Configuracion inicial"
    if ! ask_guided_configuration; then
        return 1
    fi

    if ! DISK_DEVICE="$(select_disk_device "$DISK_DEVICE")"; then
        log_error "No se selecciono un disco destino valido"
        return 1
    fi

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

    CLONEHERO_RELEASE_CHANNEL="${CLONEHERO_RELEASE_CHANNEL,,}"
    if [[ "$CLONEHERO_RELEASE_CHANNEL" == "ask" ]]; then
        read -rp "$(echo -e "${BLUE}Canal de Clone Hero: latest desde GitHub o URL fija? [latest/url] (latest): ${NC}")" answer
        case "${answer,,}" in
            ""|l|latest)
                CLONEHERO_RELEASE_CHANNEL="latest"
                ;;
            url|fixed|fija)
                CLONEHERO_RELEASE_CHANNEL="url"
                ;;
            *)
                log_error "Opcion invalida: $answer. Responda latest o url."
                return 1
                ;;
        esac
    fi

    case "$CLONEHERO_RELEASE_CHANNEL" in
        latest)
            log "Se resolvera el release mas reciente desde clonehero-game/releases"
            ;;
        url|stable)
            CLONEHERO_RELEASE_CHANNEL="url"
            if [[ -z "$CLONEHERO_URL" ]]; then
                log_error "CLONEHERO_URL no puede estar vacio cuando CLONEHERO_RELEASE_CHANNEL=url"
                return 1
            fi
            log "Se usara Clone Hero desde CLONEHERO_URL: $CLONEHERO_URL"
            ;;
        *)
            log_error "CLONEHERO_RELEASE_CHANNEL invalido: $CLONEHERO_RELEASE_CHANNEL. Use latest, url o ask."
            return 1
            ;;
    esac

    CLONEHERO_RESOLUTION="${CLONEHERO_RESOLUTION,,}"
    if [[ "$CLONEHERO_RESOLUTION" == "ask" ]]; then
        read -rp "$(echo -e "${BLUE}Resolucion de Clone Hero: 4k, 2k, 1080p o 720p? [4k/2k/1080p/720p] (1080p): ${NC}")" answer
        CLONEHERO_RESOLUTION="${answer:-1080p}"
    fi

    if ! resolve_clonehero_resolution "$CLONEHERO_RESOLUTION"; then
        return 1
    fi

    log "Resolucion de Clone Hero seleccionada: $CLONEHERO_RESOLUTION (${CLONEHERO_SCREEN_WIDTH}x${CLONEHERO_SCREEN_HEIGHT})"
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
    echo -e "${CYAN}        INSTALADOR ARCH LINUX + CAGE + CLONE HERO${NC}"
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

    if ! resolve_clonehero_download_url; then
        log_error "Fallo al resolver la URL de descarga de Clone Hero"
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
        log_error "Fallo en instalacion del sistema base Cage/Clone Hero"
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

    NVIDIA_DRIVERS_INSTALLED=false
    if install_nvidia_drivers_if_requested; then
        [[ "$INSTALL_NVIDIA" == "true" ]] && NVIDIA_DRIVERS_INSTALLED=true
    else
        warn "No se pudieron instalar drivers NVIDIA ahora; se continuara con Mesa/Intel/AMD."
        warn "Puede instalar NVIDIA despues desde el menu de mantenimiento o con pacman."
    fi

    if [[ "${NVIDIA_DRIVERS_INSTALLED:-false}" == "true" ]]; then
        if ! configure_nvidia_kernel_params; then
            log_error "Fallo en configuracion de parametros NVIDIA"
            exit 1
        fi
    fi

    section "Stack Clone Hero"
    if ! install_audio_system; then
        log_error "Fallo en instalacion/configuracion del sistema de audio"
        exit 1
    fi

    if ! create_cage_user; then
        log_error "Fallo en creacion/configuracion del usuario kiosko"
        exit 1
    fi

    if [[ -e "$CURSOR_PATH" ]]; then
        if ! install_custom_cursor "$CURSOR_PATH" "$KIOSK_USER"; then
            warn "Fallo en instalacion del cursor personalizado; se continuara con el cursor predeterminado."
        fi
    else
        warn "No se encontro CURSOR_PATH=$CURSOR_PATH; se omitira cursor personalizado."
    fi

    if ! configure_multilib_yarg_deps; then
        log_error "Fallo en configuracion de multilib/dependencias de audio"
        exit 1
    fi

    if ! configure_hid_access; then
        log_error "Fallo en configuracion de acceso HID"
        exit 1
    fi

    if ! install_clonehero; then
        log_error "Fallo en instalacion de Clone Hero"
        exit 1
    fi

    if ! configure_clonehero_default_settings; then
        log_error "Fallo en configuracion inicial de Clone Hero"
        exit 1
    fi

    if ! configure_clonehero_samba_share; then
        log_error "Fallo en configuracion de Samba para Clone Hero"
        exit 1
    fi

    if ! configure_clonehero_performance; then
        log_error "Fallo en optimizaciones de rendimiento para Clone Hero"
        exit 1
    fi

    if ! install_clonehero_update_script; then
        log_error "Fallo en instalacion del updater de Clone Hero"
        exit 1
    fi

    if ! install_clonehero_song_download_script; then
        log_error "Fallo en instalacion del descargador de canciones Clone Hero"
        exit 1
    fi

    if ! install_clonehero_cage_wrapper; then
        log_error "Fallo en creacion del wrapper de Cage/Clone Hero"
        exit 1
    fi

    if ! install_clonehero_cage_service; then
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
    if ! cleanup_and_finish \
        "Cage + Clone Hero quedan instalados en /opt/CloneHero." \
        "El sistema arrancara automaticamente con cage-kiosk.service en modo grafico."; then
        log_error "Fallo en limpieza/finalizacion de la instalacion"
        exit 1
    fi
    INSTALL_MOUNTS_CREATED=0
    INSTALL_SUCCESS=1

    echo -e "${GREEN}"
    echo "Servicio habilitado: cage-kiosk.service."
    echo "Wrapper: /usr/local/bin/run-clonehero.sh."
    echo -e "${NC}"
}

main "$@"
