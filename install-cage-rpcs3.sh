#!/usr/bin/env bash
# =============================================================================
# install-cage-rpcs3.sh
# -----------------------------------------------------------------------------
# Orquestador para instalar Arch Linux + Cage (Wayland/XWayland) + RPCS3, con
# arranque directo de un juego (por defecto Rock Band 3). Despues de instalar,
# la primera vez se abre la GUI de RPCS3 para instalar el firmware, agregar el
# juego y configurar controles/instrumentos; a partir de ahi arranca solo.
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/arch-cage-install.log}"
VERBOSE_INSTALL="${VERBOSE_INSTALL:-false}"

source "$SCRIPT_DIR/lib/common.sh" || { echo "No se pudo importar common.sh" >&2; exit 1; }

ENV_FILE_LOADED=false
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log "Cargando configuracion desde .env..."
    load_env_file "$SCRIPT_DIR/.env" || exit 1
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
KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-minirpcs3}"
TIMEZONE="${TIMEZONE:-America/Phoenix}"
ENABLE_SSH="${ENABLE_SSH:-false}"
INSTALL_NVIDIA="${INSTALL_NVIDIA:-}"
ALLOW_INSECURE_DEFAULT_PASSWORD="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-true}"
PLYMOUTH_THEME_NAME="${PLYMOUTH_THEME_NAME:-arch-cage}"
PLYMOUTH_IMAGE_PATH="${PLYMOUTH_IMAGE_PATH:-./assets/plymouth-image.png}"
PLYMOUTH_TARGET_RESOLUTION="${PLYMOUTH_TARGET_RESOLUTION:-1280x720}"
CURSOR_PATH="${CURSOR_PATH:-./assets/cursor/}"
PLYMOUTH_ASSET_AVAILABLE="${PLYMOUTH_ASSET_AVAILABLE:-false}"
RPCS3_URL="${RPCS3_URL:-}"
RPCS3_API_URL="${RPCS3_API_URL:-https://api.github.com/repos/RPCS3/rpcs3-binaries-linux/releases/latest}"
RPCS3_ASSET_REGEX="${RPCS3_ASSET_REGEX:-linux64.*\\.AppImage$}"
RPCS3_DOWNLOAD_FIRMWARE="${RPCS3_DOWNLOAD_FIRMWARE:-true}"
RPCS3_FIRMWARE_URL="${RPCS3_FIRMWARE_URL:-http://dus01.ps3.update.playstation.net/update/ps3/image/us/2026_0318_a2b60b6ac1d2e49e230144345616927c/PS3UPDAT.PUP}"
# Rock Band 3 Deluxe: ultima build para PS3 (nightly.link, rama develop) y
# perfiles de configuracion recomendados de la guia de MiloHax.
RB3DX_DOWNLOAD="${RB3DX_DOWNLOAD:-true}"
RB3DX_URL="${RB3DX_URL:-https://nightly.link/hmxmilohax/rock-band-3-deluxe/workflows/build/develop/RB3DX-PS3.zip}"
RB3DX_CONFIG_BASE_URL="${RB3DX_CONFIG_BASE_URL:-https://guides.milohax.org/downloads/rb3/rpcs3/customconfigs}"
RB3DX_DOWNLOAD_CONFIGS="${RB3DX_DOWNLOAD_CONFIGS:-true}"
RB3DX_DISCLAIMERS_URL="https://guides.milohax.org/en/rb3pc/intro/disclaimers/"
# Las rutas que dependen de KIOSK_USER se resuelven en resolve_user_paths(),
# despues de preguntar el usuario kiosko.
RPCS3_GAMES_DIR="${RPCS3_GAMES_DIR:-}"
RPCS3_GAME_PATH="${RPCS3_GAME_PATH:-}"
RPCS3_GAME_MATCH="${RPCS3_GAME_MATCH:-Rock Band 3}"
RPCS3_QT_PLATFORM="${RPCS3_QT_PLATFORM:-}"
RPCS3_EXIT_MENU="${RPCS3_EXIT_MENU:-always}"
# Bateria electronica MIDI por USB: true hace que el wrapper detecte el puerto
# antes de cada arranque y lo asigne como "Drums" en la configuracion del juego.
RPCS3_MIDI_DRUMS="${RPCS3_MIDI_DRUMS:-true}"
# Notas MIDI que el kit manda distintas a lo esperado, "NOTA=Pieza,NOTA=Pieza"
# (p. ej. "49=Ride,51=Crash" si crash y ride llegan invertidos). Vacio no toca
# rb3drums.yml.
RPCS3_MIDI_NOTE_OVERRIDE="${RPCS3_MIDI_NOTE_OVERRIDE:-}"
# Control del jugador 1: true instala la configuracion de entrada con el handler
# SDL (sin ella RPCS3 asigna el teclado y un control no navega por los menus).
# RPCS3_PAD_DEVICE es el nombre que SDL da al control, con su numero.
RPCS3_PAD_CONFIG="${RPCS3_PAD_CONFIG:-true}"
RPCS3_PAD_DEVICE="${RPCS3_PAD_DEVICE:-Xbox Series X Controller 1}"
# true instala el atajo para cerrar RPCS3 con Ctrl+Alt+Q (teclado).
RPCS3_EXIT_HOTKEY="${RPCS3_EXIT_HOTKEY:-true}"
# hdmi (HDMI/DP, por defecto), analog o auto: salida de audio preferida.
RPCS3_AUDIO_OUTPUT="${RPCS3_AUDIO_OUTPUT:-hdmi}"
# Volumen de la salida al arrancar (1.0 = 100 %); vacio no lo toca.
RPCS3_AUDIO_VOLUME="${RPCS3_AUDIO_VOLUME-1.0}"
# Buffer de audio de RPCS3 en ms para los perfiles RB3DX descargados: 32 es el de
# recommended; minimum y potato traen 100, que suma latencia en un juego de
# ritmo. Vacio deja el valor de cada perfil.
RPCS3_AUDIO_BUFFER_MS="${RPCS3_AUDIO_BUFFER_MS-32}"
# Microfonos USB para hasta 3 cantantes (jugadores en este orden): primero los
# individuales (RPCS3_MIC_SINGLE_MATCH, el Logitech oficial de Rock Band), luego
# los adaptadores estereo de dos microfonos (RPCS3_MIC_SPLIT_MATCH, el SingStar
# USBMIC: izquierdo = azul, derecho = rojo). Son expresiones regulares sobre el
# nombre de la fuente ALSA; ambas vacias desactivan la funcion.
RPCS3_MIC_SINGLE_MATCH="${RPCS3_MIC_SINGLE_MATCH-Logitech}"
RPCS3_MIC_SPLIT_MATCH="${RPCS3_MIC_SPLIT_MATCH-USBMIC|SingStar}"
# Volumen de captura de cada tipo (salen al maximo y cada microfono mueve la
# flecha del otro jugador): 75 % = +7 dB en el Logitech; 35 % = -4 dB en el
# SingStar USBMIC.
RPCS3_MIC_SINGLE_VOLUME="${RPCS3_MIC_SINGLE_VOLUME-75%}"
RPCS3_MIC_VOLUME="${RPCS3_MIC_VOLUME-35%}"
# RB3 mas la cache de shaders de RPCS3 no caben en el /home de un disco de 16 GB.
RPCS3_MIN_DISK_GB="${RPCS3_MIN_DISK_GB:-32}"

source "$SCRIPT_DIR/lib/validation.sh" || { log_error "No se pudo importar validation.sh"; exit 1; }
source "$SCRIPT_DIR/lib/partitioning.sh" || { log_error "No se pudo importar partitioning.sh"; exit 1; }
source "$SCRIPT_DIR/lib/base_install.sh" || { log_error "No se pudo importar base_install.sh"; exit 1; }
source "$SCRIPT_DIR/lib/bootloader.sh" || { log_error "No se pudo importar bootloader.sh"; exit 1; }
source "$SCRIPT_DIR/lib/plymouth.sh" || { log_error "No se pudo importar plymouth.sh"; exit 1; }
source "$SCRIPT_DIR/lib/drivers.sh" || { log_error "No se pudo importar drivers.sh"; exit 1; }
source "$SCRIPT_DIR/lib/cage.sh" || { log_error "No se pudo importar cage.sh"; exit 1; }
source "$SCRIPT_DIR/lib/rpcs3.sh" || { log_error "No se pudo importar rpcs3.sh"; exit 1; }
source "$SCRIPT_DIR/lib/customization.sh" || { log_error "No se pudo importar customization.sh"; exit 1; }
source "$SCRIPT_DIR/lib/finalization.sh" || { log_error "No se pudo importar finalization.sh"; exit 1; }

INSTALL_MOUNTS_CREATED=0
INSTALL_SUCCESS=0

resolve_user_paths() {
    RPCS3_GAMES_DIR="${RPCS3_GAMES_DIR:-/home/$KIOSK_USER/Games}"
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

    prompt_value KIOSK_HOSTNAME "Hostname del kiosko" "minirpcs3" || return 1
    prompt_value TIMEZONE "Zona horaria" "America/Phoenix" || return 1
    prompt_bool ENABLE_SSH "Habilitar SSH para mantenimiento remoto" "false" || return 1
    prompt_bool ENABLE_PLYMOUTH "Habilitar Plymouth" "true" || return 1
    prompt_value RPCS3_GAME_MATCH "Titulo del juego a arrancar (busca en PARAM.SFO)" "Rock Band 3" || return 1

    if [[ -z "${RPCS3_EXIT_MENU:-}" || "$ENV_FILE_LOADED" != "true" ]]; then
        local answer="${RPCS3_EXIT_MENU:-always}"
        read -rp "$(echo -e "${BLUE}Que hacer al salir del juego? [always/restart/never] (${answer}): ${NC}")" answer
        RPCS3_EXIT_MENU="${answer:-${RPCS3_EXIT_MENU:-always}}"
    fi

    case "${RPCS3_EXIT_MENU,,}" in
        always|restart|relaunch|volver|rpcs3|never|off|false|no)
            ;;
        *)
            log_error "RPCS3_EXIT_MENU invalido: $RPCS3_EXIT_MENU. Use always, restart o never."
            return 1
            ;;
    esac

    if [[ -n "$RPCS3_AUDIO_VOLUME" && ! "$RPCS3_AUDIO_VOLUME" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then
        log_error "RPCS3_AUDIO_VOLUME invalido: $RPCS3_AUDIO_VOLUME. Use un numero entre 0 y 1 (por ejemplo 1.0) o vacio."
        return 1
    fi

    case "${RPCS3_QT_PLATFORM,,}" in
        ""|wayland|xcb)
            ;;
        *)
            log_error "RPCS3_QT_PLATFORM invalido: $RPCS3_QT_PLATFORM. Use vacio, wayland o xcb."
            return 1
            ;;
    esac

    resolve_user_paths
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

    resolve_nvidia_choice

    # RPCS3 corre a la resolucion nativa de la pantalla (se ajusta en su GUI);
    # aqui solo se elige la imagen de Plymouth.
    select_plymouth_image "rpcs3" "1080p" 1920 1080
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        exit 1
    fi

    trap cleanup_on_exit EXIT

    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}        INSTALADOR ARCH LINUX + CAGE + RPCS3${NC}"
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

    if ! resolve_rpcs3_download_url; then
        log_error "Fallo al resolver la URL de descarga de RPCS3"
        exit 1
    fi

    if ! check_disk "$DISK_DEVICE" "$RPCS3_MIN_DISK_GB"; then
        log_error "Disco invalido o insuficiente: RPCS3 requiere al menos ${RPCS3_MIN_DISK_GB}GB"
        exit 1
    fi

    if ! validate_partition_plan "$DISK_DEVICE"; then
        log_error "El esquema de particiones (ESP_SIZE, ROOT_SIZE, SWAP_SIZE) no cabe en el disco"
        exit 1
    fi

    if ! check_disk_empty "$DISK_DEVICE"; then
        log_error "Operacion cancelada: no se confirmo la destruccion de datos"
        exit 1
    fi

    section "Particionado y montaje"
    if ! prepare_disk_for_install "$DISK_DEVICE"; then
        log_error "No se pudo liberar y limpiar el disco destino"
        exit 1
    fi

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
        log_error "Fallo en instalacion del sistema base Cage/RPCS3"
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

    section "Stack RPCS3"
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

    if ! install_rpcs3_dependencies; then
        log_error "Fallo en instalacion de dependencias de RPCS3"
        exit 1
    fi

    if ! configure_hid_access; then
        log_error "Fallo en configuracion de acceso HID"
        exit 1
    fi

    configure_rpcs3_usb_access

    if ! install_rpcs3; then
        log_error "Fallo en instalacion de RPCS3"
        exit 1
    fi

    download_rpcs3_firmware
    download_rb3dx
    download_rb3dx_config_profiles

    if ! configure_rpcs3_games_dir; then
        log_error "Fallo en la carpeta de juegos de RPCS3"
        exit 1
    fi

    if ! configure_rpcs3_samba_share; then
        log_error "Fallo en configuracion de Samba para RPCS3"
        exit 1
    fi

    if ! configure_rpcs3_performance; then
        log_error "Fallo en optimizaciones de rendimiento para RPCS3"
        exit 1
    fi

    configure_rpcs3_audio_output

    if ! install_rpcs3_update_script; then
        log_error "Fallo en instalacion del updater de RPCS3"
        exit 1
    fi

    install_rpcs3_exit_hotkey

    install_rpcs3_midi_config
    install_rpcs3_input_config

    if ! install_rpcs3_cage_wrapper; then
        log_error "Fallo en creacion del wrapper de Cage/RPCS3"
        exit 1
    fi

    if ! install_rpcs3_cage_service; then
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
        "Cage + RPCS3 quedan instalados en /opt/RPCS3." \
        "En el primer arranque se abre la GUI de RPCS3 para instalar firmware, juego y controles.
Antes de configurar Rock Band 3 lea las advertencias y la guia: $RB3DX_DISCLAIMERS_URL
Perfiles de RB3DX en /home/$KIOSK_USER/RB3DX-config-*.zip; aplique uno con: unzip -o RB3DX-config-minimum.zip -d ~/.config/rpcs3 (RB3DX necesita Debug Console Mode)."; then
        log_error "Fallo en limpieza/finalizacion de la instalacion"
        exit 1
    fi
    INSTALL_MOUNTS_CREATED=0
    INSTALL_SUCCESS=1

    echo -e "${GREEN}"
    echo "Servicio habilitado: cage-kiosk.service."
    echo "Wrapper: /usr/local/bin/run-rpcs3.sh."
    echo "Juegos por red: \\\\${KIOSK_HOSTNAME}\\RPCS3-Games"
    echo -e "${NC}"
}

main "$@"
