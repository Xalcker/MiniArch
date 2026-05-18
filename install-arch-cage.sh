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

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log "Cargando configuracion desde .env..."
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    set +a
fi

DISK_DEVICE="${DISK_DEVICE:-/dev/sda}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-kiosk}"
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-minikiosk}"
TIMEZONE="${TIMEZONE:-America/Phoenix}"
ENABLE_SSH="${ENABLE_SSH:-false}"
INSTALL_NVIDIA="${INSTALL_NVIDIA:-}"
YARG_URL="${YARG_URL:-https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip}"

source "$SCRIPT_DIR/lib/validation.sh" || { log_error "No se pudo importar validation.sh"; exit 1; }
source "$SCRIPT_DIR/lib/partitioning.sh" || { log_error "No se pudo importar partitioning.sh"; exit 1; }
source "$SCRIPT_DIR/lib/base_install.sh" || { log_error "No se pudo importar base_install.sh"; exit 1; }
source "$SCRIPT_DIR/lib/bootloader.sh" || { log_error "No se pudo importar bootloader.sh"; exit 1; }
source "$SCRIPT_DIR/lib/drivers.sh" || { log_error "No se pudo importar drivers.sh"; exit 1; }
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
}

install_cage_base_system() {
    local packages=(
        base linux linux-firmware linux-headers
        sudo nano curl wget unzip git
        networkmanager grub efibootmgr samba cpupower
        mesa wayland xorg-xwayland cage foot
        ttf-dejavu
        vulkan-icd-loader egl-wayland
        vulkan-intel intel-media-driver
        vulkan-radeon xf86-video-amdgpu
        virglrenderer
        hidapi systemd-libs
    )

    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        packages+=(nvidia-dkms nvidia-utils)
    fi

    if ! mountpoint -q /mnt; then
        log_error "/mnt no esta montado. Ejecute mount_partitions primero."
        return 1
    fi

    log "Instalando sistema base y stack Cage/Wayland (${#packages[@]} paquetes)"
    if ! pacstrap -K /mnt "${packages[@]}"; then
        log_error "Fallo pacstrap para sistema Cage/YARG"
        return 1
    fi

    return 0
}

configure_system_basics() {
    log "Configurando hostname, locale, zona horaria y root"

    echo "$KIOSK_HOSTNAME" > /mnt/etc/hostname
    echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    if ! arch-chroot /mnt locale-gen; then
        log_error "Fallo al generar locale"
        return 1
    fi

    if ! echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd; then
        log_error "Fallo al configurar password de root"
        return 1
    fi

    return 0
}

configure_nvidia_kernel_params() {
    if [[ "$INSTALL_NVIDIA" != "true" ]]; then
        return 0
    fi

    local grub_config="/mnt/etc/default/grub"
    if [[ ! -f "$grub_config" ]]; then
        log_error "No existe $grub_config"
        return 1
    fi

    log "Agregando nvidia_drm.modeset=1 a GRUB"
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config"; then
        if ! grep -q "nvidia_drm.modeset=1" "$grub_config"; then
            sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 nvidia_drm.modeset=1"/' "$grub_config"
        fi
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 nvidia_drm.modeset=1"' >> "$grub_config"
    fi

    if ! arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        log_error "Fallo al regenerar GRUB con parametros NVIDIA"
        return 1
    fi
}

create_cage_user() {
    if arch-chroot /mnt id "$KIOSK_USER" &> /dev/null; then
        log "El usuario $KIOSK_USER ya existe"
    else
        log "Creando usuario kiosko: $KIOSK_USER"
        if ! arch-chroot /mnt useradd -m -G wheel,audio,video,render,input -s /bin/bash "$KIOSK_USER"; then
            log_error "Fallo al crear usuario $KIOSK_USER"
            return 1
        fi
    fi

    if ! echo "$KIOSK_USER:$KIOSK_PASSWORD" | arch-chroot /mnt chpasswd; then
        log_error "Fallo al configurar password de $KIOSK_USER"
        return 1
    fi

    if ! arch-chroot /mnt bash -c "echo '%wheel ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/10-wheel"; then
        log_error "Fallo al configurar sudoers"
        return 1
    fi

    arch-chroot /mnt chmod 440 /etc/sudoers.d/10-wheel
}

configure_multilib_yarg_deps() {
    log "Habilitando multilib e instalando dependencias 32-bit de YARG"

    sed -i '/\[multilib\]/,/Include/s/^#//' /mnt/etc/pacman.conf

    if ! arch-chroot /mnt pacman -Syu --noconfirm \
        lib32-pipewire lib32-alsa-plugins lib32-libpulse \
        hidapi systemd-libs pulseaudio-alsa pulsemixer; then
        log_error "Fallo al instalar dependencias multilib/YARG"
        return 1
    fi
}

configure_hid_access() {
    log "Configurando acceso udev a dispositivos hidraw"

    mkdir -p /mnt/etc/udev/rules.d
    echo 'KERNEL=="hidraw*", TAG+="uaccess"' > /mnt/etc/udev/rules.d/69-hid.rules
    chmod 644 /mnt/etc/udev/rules.d/69-hid.rules
}

install_yarg() {
    log "Descargando e instalando YARG en /opt/YARG"

    local yarg_zip="/mnt/tmp/YARG.zip"

    mkdir -p /mnt/tmp /mnt/opt/YARG

    if ! curl -fL --retry 3 --retry-delay 2 -o "$yarg_zip" "$YARG_URL"; then
        log_error "Fallo al descargar YARG"
        return 1
    fi

    if [[ ! -s "$yarg_zip" ]]; then
        log_error "La descarga de YARG no genero un ZIP valido en $yarg_zip"
        return 1
    fi

    if ! arch-chroot /mnt unzip -tq /tmp/YARG.zip >/dev/null; then
        log_error "El ZIP descargado de YARG no es valido"
        return 1
    fi

    if ! arch-chroot /mnt unzip -o /tmp/YARG.zip -d /opt/YARG; then
        log_error "Fallo al descomprimir YARG"
        return 1
    fi

    arch-chroot /mnt find /opt/YARG -maxdepth 1 -type f -name 'YARG*' -exec chmod +x {} +
    arch-chroot /mnt mkdir -p /opt/YARG/Songs
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" /opt/YARG
    rm -f "$yarg_zip"
}

configure_yarg_samba_share() {
    local songs_dir="/opt/YARG/Songs"
    local smb_conf="/mnt/etc/samba/smb.conf"

    log "Configurando Samba para compartir canciones de YARG"

    mkdir -p /mnt/etc/samba /mnt/var/log/samba /mnt/opt/YARG/Songs
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$songs_dir"
    arch-chroot /mnt chmod 775 "$songs_dir"

    if [[ ! -f "$smb_conf" ]] || ! grep -q '^\[global\]' "$smb_conf"; then
        cat > "$smb_conf" << EOF
[global]
   workgroup = WORKGROUP
   server string = YARG Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/samba/%m.log
   max log size = 50
EOF
    fi

    if ! grep -q '^\[YARG-Songs\]' "$smb_conf"; then
        cat >> "$smb_conf" << EOF

[YARG-Songs]
   path = $songs_dir
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $KIOSK_USER
EOF
    fi

    if ! arch-chroot /mnt systemctl enable smb.service nmb.service; then
        log_error "Fallo al habilitar servicios Samba"
        return 1
    fi

    if ! printf '%s\n%s\n' "$KIOSK_PASSWORD" "$KIOSK_PASSWORD" | arch-chroot /mnt smbpasswd -s -a "$KIOSK_USER"; then
        log_error "Fallo al registrar $KIOSK_USER en Samba"
        return 1
    fi
}

configure_yarg_performance() {
    log "Aplicando optimizaciones de rendimiento para YARG"

    mkdir -p /mnt/etc/security/limits.d /mnt/etc/sysctl.d /mnt/etc/default

    cat > /mnt/etc/security/limits.d/99-yarg.conf << EOF
$KIOSK_USER - rtprio 99
$KIOSK_USER - memlock unlimited
$KIOSK_USER - nice -20
EOF

    echo 'vm.swappiness=10' > /mnt/etc/sysctl.d/99-yarg.conf

    cat > /mnt/etc/default/cpupower << 'EOF'
governor='performance'
min_freq=''
max_freq=''
EOF

    if ! arch-chroot /mnt systemctl enable cpupower.service; then
        log_error "Fallo al habilitar cpupower.service"
        return 1
    fi
}

install_yarg_update_script() {
    log "Instalando updater /usr/local/bin/update-yarg"

    mkdir -p /mnt/usr/local/bin
    cat > /mnt/usr/local/bin/update-yarg << EOF
#!/usr/bin/env bash
set -euo pipefail

YARG_URL="$YARG_URL"
INSTALL_DIR="/opt/YARG"
ZIP_FILE="/tmp/YARG_Linux.zip"
OWNER="$KIOSK_USER"

if [[ \${EUID} -ne 0 ]]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi

curl -L -o "\$ZIP_FILE" "\$YARG_URL"
mkdir -p "\$INSTALL_DIR/Songs"
unzip -o "\$ZIP_FILE" -d "\$INSTALL_DIR"
find "\$INSTALL_DIR" -maxdepth 1 -type f -name "YARG*" -exec chmod +x {} +
chown -R "\$OWNER:\$OWNER" "\$INSTALL_DIR"
rm -f "\$ZIP_FILE"

echo "YARG actualizado en \$INSTALL_DIR"
EOF

    chmod +x /mnt/usr/local/bin/update-yarg
}

install_cage_wrapper() {
    log "Creando wrapper /usr/local/bin/run-yarg.sh"

    mkdir -p /mnt/usr/local/bin
    cat > /mnt/usr/local/bin/run-yarg.sh <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export WLR_NO_HARDWARE_CURSORS=1
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export WLR_XWAYLAND=1

if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
    pipewire &
fi

if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
    pipewire-pulse &
fi

if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
    wireplumber &
fi

YARG_BIN=$(find /opt/YARG -maxdepth 1 -type f -name "YARG*" -executable -print -quit 2>/dev/null)

if [[ -n "$YARG_BIN" ]]; then
    exec /usr/bin/cage "$YARG_BIN"
fi

exec /usr/bin/cage /usr/bin/foot
WRAPPER

    chmod +x /mnt/usr/local/bin/run-yarg.sh
}

install_cage_service() {
    log "Creando servicio systemd cage-kiosk.service"

    cat > /mnt/etc/systemd/system/cage-kiosk.service << EOF
[Unit]
Description=Kiosk YARG con Cage
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
Environment=XDG_RUNTIME_DIR=/run/user/%U
ExecStartPre=+/usr/bin/mkdir -p /run/user/%U
ExecStartPre=+/usr/bin/chown $KIOSK_USER:$KIOSK_USER /run/user/%U
ExecStartPre=+/usr/bin/chmod 700 /run/user/%U
ExecStart=/usr/local/bin/run-yarg.sh
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

    if ! arch-chroot /mnt systemctl enable cage-kiosk.service; then
        log_error "Fallo al habilitar cage-kiosk.service"
        return 1
    fi
}

configure_network_target() {
    if ! configure_network; then
        return 1
    fi

    if ! arch-chroot /mnt systemctl set-default graphical.target; then
        log_error "Fallo al configurar graphical.target"
        return 1
    fi
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
    validate_environment
    check_network
    check_disk "$DISK_DEVICE"
    check_disk_empty "$DISK_DEVICE"

    section "Particionado y montaje"
    partition_disk "$DISK_DEVICE"
    format_partitions "$DISK_DEVICE"
    mount_partitions "$DISK_DEVICE"
    INSTALL_MOUNTS_CREATED=1

    section "Sistema base"
    install_cage_base_system
    generate_fstab

    section "Bootloader y sistema"
    configure_system_basics
    install_grub
    configure_grub_silent
    configure_nvidia_kernel_params

    section "Stack YARG"
    install_audio_system
    create_cage_user
    configure_multilib_yarg_deps
    configure_hid_access
    install_yarg
    configure_yarg_samba_share
    configure_yarg_performance
    install_yarg_update_script
    install_cage_wrapper
    install_cage_service

    section "Red y limpieza visual"
    configure_network_target
    hide_system_messages "$KIOSK_USER"

    section "Finalizacion"
    cleanup_and_finish
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
