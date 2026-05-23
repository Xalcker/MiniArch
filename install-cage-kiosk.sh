#!/usr/bin/env bash
# =============================================================================
# install-cage-kiosk.sh
# -----------------------------------------------------------------------------
# Instalador automatizado de Arch Linux en modo kiosko minimalista con Cage y
# foot. Este camino no instala YARG ni OpenBox/X11; deja un terminal foot como
# aplicacion unica dentro de Cage para mantenimiento o usos propios.
# =============================================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="${LOG_FILE:-/var/log/arch-cage-kiosk-install.log}"
VERBOSE_INSTALL="${VERBOSE_INSTALL:-false}"

log() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO:${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR:${NC} $message" | tee -a "$LOG_FILE" >&2
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

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log "Cargando configuracion desde .env..."
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    set +a
    log "Configuracion cargada desde .env"
fi

DISK_DEVICE="${DISK_DEVICE:-ask}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"
ROOT_PASSWORD="${ROOT_PASSWORD:-}"
REQUIRE_ROOT_PASSWORD="${REQUIRE_ROOT_PASSWORD:-true}"
KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-minikiosk}"
TIMEZONE="${TIMEZONE:-America/Phoenix}"
ENABLE_SSH="${ENABLE_SSH:-false}"
ALLOW_INSECURE_DEFAULT_PASSWORD="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-true}"
PLYMOUTH_THEME_NAME="${PLYMOUTH_THEME_NAME:-arch-cage}"
PLYMOUTH_IMAGE_PATH="${PLYMOUTH_IMAGE_PATH:-./assets/plymouth-image.png}"
CURSOR_PATH="${CURSOR_PATH:-./assets/cursor/}"
PLYMOUTH_ASSET_AVAILABLE="${PLYMOUTH_ASSET_AVAILABLE:-false}"

source "$SCRIPT_DIR/lib/validation.sh" || { log_error "No se pudo importar validation.sh"; exit 1; }
source "$SCRIPT_DIR/lib/partitioning.sh" || { log_error "No se pudo importar partitioning.sh"; exit 1; }
source "$SCRIPT_DIR/lib/base_install.sh" || { log_error "No se pudo importar base_install.sh"; exit 1; }
source "$SCRIPT_DIR/lib/bootloader.sh" || { log_error "No se pudo importar bootloader.sh"; exit 1; }
source "$SCRIPT_DIR/lib/plymouth.sh" || { log_error "No se pudo importar plymouth.sh"; exit 1; }
source "$SCRIPT_DIR/lib/customization.sh" || { log_error "No se pudo importar customization.sh"; exit 1; }
source "$SCRIPT_DIR/lib/finalization.sh" || { log_error "No se pudo importar finalization.sh"; exit 1; }

INSTALL_MOUNTS_CREATED=0
INSTALL_SUCCESS=0

prompt_secret() {
    local var_name="$1"
    local label="$2"
    local current_value="${!var_name-}"
    local value confirmation

    [[ -n "$current_value" ]] && return 0

    while true; do
        read -rsp "$(echo -e "${BLUE}${label}: ${NC}")" value
        echo ""
        read -rsp "$(echo -e "${BLUE}Confirme ${label}: ${NC}")" confirmation
        echo ""

        [[ -n "$value" ]] || { log_error "$label no puede quedar vacio"; continue; }
        [[ "$value" == "$confirmation" ]] || { log_error "Las contrasenas no coinciden"; continue; }

        printf -v "$var_name" "%s" "$value"
        return 0
    done
}

install_cage_foot_base() {
    local packages=(
        base linux linux-firmware linux-headers
        sudo nano curl wget git dbus
        networkmanager grub efibootmgr
        mesa wayland cage foot ttf-dejavu
        vulkan-icd-loader vulkan-intel vulkan-radeon
    )

    log "Instalando sistema base Cage/foot (${#packages[@]} paquetes)"
    if ! run_quiet pacstrap -K /mnt "${packages[@]}"; then
        log_error "Fallo pacstrap para Cage/foot"
        return 1
    fi
}

configure_cage_foot_system() {
    log "Configurando hostname, locale y password root"

    echo "$KIOSK_HOSTNAME" > /mnt/etc/hostname
    echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    run_quiet arch-chroot /mnt locale-gen || { log_error "Fallo al generar locale"; return 1; }
    if [[ -n "$ROOT_PASSWORD" ]]; then
        echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd || { log_error "Fallo password root"; return 1; }
    else
        warn "ROOT_PASSWORD vacio; se conserva el estado de root definido por el sistema base."
    fi
}

create_cage_foot_user() {
    if ! arch-chroot /mnt id "$KIOSK_USER" &> /dev/null; then
        log "Creando usuario kiosko: $KIOSK_USER"
        arch-chroot /mnt useradd -m -G wheel,video,render,input -s /bin/bash "$KIOSK_USER" || return 1
    fi

    echo "$KIOSK_USER:$KIOSK_PASSWORD" | arch-chroot /mnt chpasswd || return 1
    arch-chroot /mnt bash -c "echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-wheel" || return 1
    arch-chroot /mnt chmod 440 /etc/sudoers.d/10-wheel
}

install_cage_foot_wrapper() {
    log "Creando wrapper /usr/local/bin/run-cage-foot.sh"

    mkdir -p /mnt/usr/local/bin
    cat > /mnt/usr/local/bin/run-cage-foot.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage

if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
fi

exec /usr/bin/cage -- /usr/bin/foot
EOF
    chmod +x /mnt/usr/local/bin/run-cage-foot.sh
}

install_cage_foot_service() {
    local kiosk_uid

    kiosk_uid=$(arch-chroot /mnt id -u "$KIOSK_USER") || return 1

    log "Creando servicio systemd cage-kiosk.service"
    cat > /mnt/etc/systemd/system/cage-kiosk.service << EOF
[Unit]
Description=Kiosk Cage + foot
After=systemd-user-sessions.service network-online.target
Wants=network-online.target
Conflicts=getty@tty1.service

[Service]
User=$KIOSK_USER
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$kiosk_uid
ExecStartPre=+/usr/bin/mkdir -p /run/user/$kiosk_uid
ExecStartPre=+/usr/bin/chown $KIOSK_USER:$KIOSK_USER /run/user/$kiosk_uid
ExecStartPre=+/usr/bin/chmod 700 /run/user/$kiosk_uid
ExecStart=/usr/bin/dbus-run-session -- /usr/local/bin/run-cage-foot.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

    arch-chroot /mnt systemctl enable cage-kiosk.service || return 1
}

configure_graphical_target() {
    configure_network || return 1
    arch-chroot /mnt systemctl set-default graphical.target || return 1
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
    cleanup_mounts || log_error "La limpieza automatica no pudo completarse"
    return "$exit_status"
}

main() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        exit 1
    fi

    trap cleanup_on_exit EXIT

    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}        INSTALADOR ARCH LINUX + CAGE + FOOT${NC}"
    echo -e "${BLUE}===================================================================${NC}"

    prompt_secret KIOSK_PASSWORD "Password del usuario $KIOSK_USER"
    [[ "$REQUIRE_ROOT_PASSWORD" == "true" ]] && prompt_secret ROOT_PASSWORD "Password de root"

    if ! DISK_DEVICE="$(select_disk_device "$DISK_DEVICE")"; then
        log_error "No se selecciono un disco destino valido"
        exit 1
    fi

    log "Validando entorno..."
    validate_environment || exit 1
    validate_security_config || exit 1
    [[ "$ENABLE_PLYMOUTH" != "true" ]] || preflight_optional_assets "$PLYMOUTH_IMAGE_PATH" "$CURSOR_PATH" || exit 1
    check_network || exit 1
    check_disk "$DISK_DEVICE" || exit 1
    check_disk_empty "$DISK_DEVICE" || exit 1

    partition_disk "$DISK_DEVICE" || exit 1
    format_partitions "$DISK_DEVICE" || exit 1
    mount_partitions "$DISK_DEVICE" || exit 1
    INSTALL_MOUNTS_CREATED=1

    install_cage_foot_base || exit 1
    generate_fstab || exit 1
    configure_cage_foot_system || exit 1
    install_grub || exit 1
    configure_grub_silent || exit 1

    if [[ "$ENABLE_PLYMOUTH" == "true" ]]; then
        install_plymouth || warn "No se pudo instalar Plymouth; continuando."
        create_custom_theme "$PLYMOUTH_THEME_NAME" || warn "No se pudo crear tema Plymouth; continuando."
        if [[ "$PLYMOUTH_ASSET_AVAILABLE" == "true" ]]; then
            configure_plymouth "$PLYMOUTH_THEME_NAME" "$PLYMOUTH_IMAGE_PATH" || warn "No se pudo configurar Plymouth; continuando."
        fi
    fi

    create_cage_foot_user || exit 1
    install_cage_foot_wrapper || exit 1
    install_cage_foot_service || exit 1
    hide_system_messages "$KIOSK_USER" || warn "No se pudieron ocultar mensajes del sistema; continuando."
    configure_graphical_target || exit 1
    cleanup_and_finish "Arch Linux Cage/foot instalado correctamente." \
        "El sistema arrancara automaticamente con cage-kiosk.service." || exit 1
    INSTALL_MOUNTS_CREATED=0
    INSTALL_SUCCESS=1

    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${GREEN}        ARCH LINUX CAGE + FOOT INSTALADO CON EXITO${NC}"
    echo -e "${BLUE}===================================================================${NC}"
}

main "$@"
