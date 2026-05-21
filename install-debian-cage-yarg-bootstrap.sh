#!/usr/bin/env bash
# =============================================================================
# install-debian-cage-yarg-bootstrap.sh
# -----------------------------------------------------------------------------
# Orquestador para instalar Debian 13.5 + Cage + YARG desde cero (bootstrap)
# particionando y formateando el disco destino.
# Diseñado para ejecutarse desde el instalador Netinst o un entorno Live de Debian.
# Ejecutar como root.
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
LOG_FILE="${LOG_FILE:-/tmp/debian-bootstrap-install.log}"
VERBOSE_INSTALL="${VERBOSE_INSTALL:-false}"

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

run_quiet() {
    if [[ "${VERBOSE_INSTALL:-false}" == "true" ]]; then
        "$@"
        return $?
    fi

    "$@" >> "$LOG_FILE" 2>&1
}

# Cargar configuración desde .env si existe en el host
if [[ -f "$SCRIPT_DIR/.env" && ! "${1:-}" == "--in-chroot" ]]; then
    log "Cargando configuracion desde .env..."
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    set +a
    log "Configuracion cargada desde .env"
elif [[ -f "/tmp/chroot.env" && "${1:-}" == "--in-chroot" ]]; then
    # shellcheck disable=SC109
    source "/tmp/chroot.env"
fi

# Variables por defecto
DISK_DEVICE="${DISK_DEVICE:-/dev/sda}"
KIOSK_USER="${KIOSK_USER:-kiosk}"
KIOSK_PASSWORD="${KIOSK_PASSWORD:-}"
ALLOW_INSECURE_DEFAULT_PASSWORD="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"
KIOSK_HOSTNAME="${KIOSK_HOSTNAME:-minikiosk}"
TIMEZONE="${TIMEZONE:-America/Phoenix}"
ENABLE_SSH="${ENABLE_SSH:-false}"
INSTALL_NVIDIA="${INSTALL_NVIDIA:-}"
ENABLE_PLYMOUTH="${ENABLE_PLYMOUTH:-true}"
PLYMOUTH_THEME_NAME="${PLYMOUTH_THEME_NAME:-debian-cage}"
PLYMOUTH_IMAGE_PATH="${PLYMOUTH_IMAGE_PATH:-./assets/plymouth-image.png}"
CURSOR_PATH="${CURSOR_PATH:-./assets/cursor/}"
YARG_SONGS_DIR="${YARG_SONGS_DIR:-/opt/YARG/Songs}"
YARG_PERSISTENT_DATA_DIR="${YARG_PERSISTENT_DATA_DIR:-/home/$KIOSK_USER/.config/yarg-kiosk}"
YARG_RESOLUTION="${YARG_RESOLUTION:-ask}"
YARG_FORCE_SOFTWARE_RENDER="${YARG_FORCE_SOFTWARE_RENDER:-false}"
YARG_RELEASE_CHANNEL="${YARG_RELEASE_CHANNEL:-ask}"
YARG_STABLE_API_URL="${YARG_STABLE_API_URL:-https://api.github.com/repos/YARC-Official/YARG/releases/latest}"
YARG_STABLE_ASSET_REGEX="${YARG_STABLE_ASSET_REGEX:-linux.*(x86_64|x64|64).*\\.zip}"
YARG_NIGHTLY_API_URL="${YARG_NIGHTLY_API_URL:-https://api.github.com/repos/YARC-Official/YARG-BleedingEdge/releases/latest}"
YARG_NIGHTLY_ASSET_REGEX="${YARG_NIGHTLY_ASSET_REGEX:-linux.*(x86_64|x64|64).*\\.zip}"
YARG_URL="${YARG_URL:-https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip}"
DEBIAN_MIRROR_URL="${DEBIAN_MIRROR_URL:-http://deb.debian.org/debian}"
PLYMOUTH_ASSET_AVAILABLE=false

# Validaciones de entorno en Host o Chroot
validate_environment() {
    log "Validando entorno del sistema..."
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        return 1
    fi

    # Si estamos en el host, requerimos soporte UEFI y la presencia de debootstrap
    if [[ ! "${1:-}" == "--in-chroot" ]]; then
        if [[ ! -d /sys/firmware/efi ]]; then
            log_error "El sistema no fue arrancado en modo UEFI (/sys/firmware/efi no existe)."
            return 1
        fi
        
        if ! command -v debootstrap &>/dev/null; then
            log "Instalando debootstrap temporal en el entorno host..."
            if command -v apt-get &>/dev/null; then
                run_quiet apt-get update && run_quiet apt-get install -y debootstrap
            else
                log_error "debootstrap no esta instalado en el host y no se encontro apt-get."
                return 1
            fi
        fi
    fi
    log "Entorno validado correctamente."
    return 0
}

check_network() {
    log "Verificando conectividad de red..."
    if ! ping -c 3 -W 5 debian.org &> /dev/null; then
        log_error "Sin conexion de red. Es necesaria para el bootstrap del sistema."
        return 1
    fi
    log "Conectividad de red verificada correctamente."
    return 0
}

validate_security_config() {
    if [[ -z "$KIOSK_PASSWORD" ]]; then
        read -rsp "$(echo -e "${BLUE}Ingrese la contraseña para el usuario kiosko ($KIOSK_USER): ${NC}")" KIOSK_PASSWORD
        echo ""
    fi

    if [[ "$KIOSK_PASSWORD" == "kiosk" || "$KIOSK_PASSWORD" == "kiosk123" || "$KIOSK_PASSWORD" == "change-me" ]]; then
        if [[ "$ALLOW_INSECURE_DEFAULT_PASSWORD" != "true" ]]; then
            log_error "Contraseña de usuario kiosko insegura. Cambie la contraseña o configure ALLOW_INSECURE_DEFAULT_PASSWORD=true."
            return 1
        fi
        warn "Se permitio una contraseña insegura por configuracion ALLOW_INSECURE_DEFAULT_PASSWORD."
    fi
    return 0
}

preflight_optional_assets() {
    if [[ -n "$PLYMOUTH_IMAGE_PATH" && -f "$PLYMOUTH_IMAGE_PATH" ]]; then
        PLYMOUTH_ASSET_AVAILABLE=true
        log "Imagen Plymouth validada correctamente."
    else
        warn "No se encontro la imagen de Plymouth especificada. Se usara un fondo negro por defecto."
    fi
}

resolve_yarg_resolution() {
    local resolution="${1,,}"
    case "$resolution" in
        4k|2160p|3840x2160)
            YARG_RESOLUTION="4k"
            YARG_SCREEN_WIDTH=3840
            YARG_SCREEN_HEIGHT=2160
            ;;
        2k|1440p|2560x1440)
            YARG_RESOLUTION="2k"
            YARG_SCREEN_WIDTH=2560
            YARG_SCREEN_HEIGHT=1440
            ;;
        1080|1080p|1920x1080)
            YARG_RESOLUTION="1080p"
            YARG_SCREEN_WIDTH=1920
            YARG_SCREEN_HEIGHT=1080
            ;;
        720|720p|1280x720)
            YARG_RESOLUTION="720p"
            YARG_SCREEN_WIDTH=1280
            YARG_SCREEN_HEIGHT=720
            ;;
        *)
            log_error "YARG_RESOLUTION invalida: $1. Use 4k, 2k, 1080p, 720p o ask."
            return 1
            ;;
    esac
}

ask_initial_questions() {
    section "Configuracion inicial"
    
    # Preguntar por el disco si no esta preconfigurado en .env
    if [[ ! -b "$DISK_DEVICE" ]]; then
        echo "Discos disponibles:"
        lsblk -d -n -o NAME,SIZE,MODEL
        echo ""
        read -rp "$(echo -e "${BLUE}Ingrese el disco donde instalar (ej: /dev/sda): ${NC}")" DISK_DEVICE
    fi

    if [[ ! -b "$DISK_DEVICE" ]]; then
        log_error "El dispositivo de bloque $DISK_DEVICE no es valido."
        return 1
    fi

    echo -e "${YELLOW}Disco destino:${NC} $DISK_DEVICE"
    echo -e "${YELLOW}Usuario kiosko:${NC} $KIOSK_USER"
    echo ""

    if [[ -z "$INSTALL_NVIDIA" ]]; then
        read -rp "$(echo -e "${BLUE}Instalar driver NVIDIA privativo? (s/N): ${NC}")" answer
        INSTALL_NVIDIA=false
        [[ "${answer,,}" == "s" || "${answer,,}" == "y" ]] && INSTALL_NVIDIA=true
    fi

    YARG_RELEASE_CHANNEL="${YARG_RELEASE_CHANNEL,,}"
    if [[ "$YARG_RELEASE_CHANNEL" == "ask" ]]; then
        read -rp "$(echo -e "${BLUE}Canal de YARG: stable fijo, stable-latest o nightly? [stable/stable-latest/nightly] (stable): ${NC}")" answer
        case "${answer,,}" in
            ""|s|stable)
                YARG_RELEASE_CHANNEL="stable"
                ;;
            latest|stable-latest|sl)
                YARG_RELEASE_CHANNEL="stable-latest"
                ;;
            n|nightly)
                YARG_RELEASE_CHANNEL="nightly"
                ;;
            *)
                log_error "Opcion invalida: $answer. Responda stable, stable-latest o nightly."
                return 1
                ;;
        esac
    fi

    YARG_RESOLUTION="${YARG_RESOLUTION,,}"
    if [[ "$YARG_RESOLUTION" == "ask" ]]; then
        read -rp "$(echo -e "${BLUE}Resolucion de YARG: 4k, 2k, 1080p o 720p? [4k/2k/1080p/720p] (1080p): ${NC}")" answer
        YARG_RESOLUTION="${answer:-1080p}"
    fi

    if ! resolve_yarg_resolution "$YARG_RESOLUTION"; then
        return 1
    fi
}

get_partition_path() {
    local device="$1"
    local partition_number="$2"
    case "$device" in
        *[0-9]) echo "${device}p${partition_number}" ;;
        *) echo "${device}${partition_number}" ;;
    esac
}

# Particionamiento GPT
partition_disk() {
    local device="$1"
    log "Particionando el disco $device..."
    
    # Asegurar que el disco no este ocupado
    umount -R /mnt 2>/dev/null || true
    swapoff -a 2>/dev/null || true

    # Crear tabla GPT
    run_quiet parted -s "$device" mklabel gpt
    
    # 1. ESP: 512MB
    run_quiet parted -s "$device" mkpart ESP fat32 1MiB 513MiB
    run_quiet parted -s "$device" set 1 esp on

    # 2. Root: 8GB
    run_quiet parted -s "$device" mkpart primary ext4 513MiB 8705MiB

    # 3. Swap: 2GB
    run_quiet parted -s "$device" mkpart primary linux-swap 8705MiB 10753MiB

    # 4. Home: Espacio restante
    run_quiet parted -s "$device" mkpart primary ext4 10753MiB 100%

    log "Particiones creadas en $device."
}

format_partitions() {
    local device="$1"
    local esp_partition root_partition swap_partition home_partition

    esp_partition=$(get_partition_path "$device" 1)
    root_partition=$(get_partition_path "$device" 2)
    swap_partition=$(get_partition_path "$device" 3)
    home_partition=$(get_partition_path "$device" 4)

    log "Formateando ESP (FAT32)..."
    run_quiet mkfs.fat -F32 "$esp_partition"

    log "Formateando Root (Ext4)..."
    run_quiet mkfs.ext4 -F "$root_partition"

    log "Inicializando Swap..."
    run_quiet mkswap "$swap_partition"

    log "Formateando Home (Ext4)..."
    run_quiet mkfs.ext4 -F "$home_partition"

    log "Formateo de particiones finalizado."
}

mount_partitions() {
    local device="$1"
    local esp_partition root_partition swap_partition home_partition

    esp_partition=$(get_partition_path "$device" 1)
    root_partition=$(get_partition_path "$device" 2)
    swap_partition=$(get_partition_path "$device" 3)
    home_partition=$(get_partition_path "$device" 4)

    log "Montando particiones en /mnt..."
    mount "$root_partition" /mnt
    
    mkdir -p /mnt/boot/efi
    mount "$esp_partition" /mnt/boot/efi

    mkdir -p /mnt/home
    mount "$home_partition" /mnt/home

    swapon "$swap_partition"
    log "Particiones montadas correctamente en /mnt."
}

# Ejecutar debootstrap para desplegar la base de Debian
bootstrap_system() {
    log "Ejecutando debootstrap para Debian Trixie (13.5) en /mnt..."
    # Paquetes basicos necesarios de inmediato
    local init_pkgs="udev,systemd,systemd-resolved,systemd-sysv,dbus,grub-efi-amd64,efibootmgr,linux-image-amd64,firmware-linux-free,firmware-linux,ca-certificates"
    
    if ! debootstrap --include="$init_pkgs" trixie /mnt "$DEBIAN_MIRROR_URL"; then
        log_error "debootstrap fallo."
        return 1
    fi
    log "Debian base instalada en /mnt."
}

generate_fstab() {
    log "Generando /mnt/etc/fstab..."
    local target_fstab="/mnt/etc/fstab"
    mkdir -p "/mnt/etc"
    
    local esp_uuid root_uuid swap_uuid home_uuid
    local esp_partition root_partition swap_partition home_partition
    
    esp_partition=$(get_partition_path "$DISK_DEVICE" 1)
    root_partition=$(get_partition_path "$DISK_DEVICE" 2)
    swap_partition=$(get_partition_path "$DISK_DEVICE" 3)
    home_partition=$(get_partition_path "$DISK_DEVICE" 4)
    
    esp_uuid=$(blkid -s UUID -o value "$esp_partition")
    root_uuid=$(blkid -s UUID -o value "$root_partition")
    swap_uuid=$(blkid -s UUID -o value "$swap_partition")
    home_uuid=$(blkid -s UUID -o value "$home_partition")
    
    cat > "$target_fstab" << EOF
# /etc/fstab: static file system information.
#
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=$root_uuid	/	ext4	errors=remount-ro	0	1
UUID=$esp_uuid	/boot/efi	vfat	umask=0077	0	2
UUID=$home_uuid	/home	ext4	defaults	0	2
UUID=$swap_uuid	none	swap	sw	0	0
EOF
    log "/etc/fstab generado exitosamente."
}

mount_virtual_filesystems() {
    log "Montando interfaces del kernel en /mnt..."
    for dir in dev proc sys sys/firmware/efi/efivars run; do
        mkdir -p "/mnt/$dir"
        mount --bind "/$dir" "/mnt/$dir"
    done
}

unmount_virtual_filesystems() {
    log "Desmontando interfaces del kernel..."
    for dir in run sys/firmware/efi/efivars sys proc dev; do
        umount -R "/mnt/$dir" 2>/dev/null || true
    done
}

# =============================================================================
# FUNCIONES EJECUTADAS DENTRO DE CHROOT
# =============================================================================

chroot_configure_system_basics() {
    log "Configurando bases del sistema chroot (hostname, locales, timezone)..."
    
    # Hostname
    echo "$KIOSK_HOSTNAME" > /etc/hostname
    cat > /etc/hosts << EOF
127.0.0.1   localhost
127.0.1.1   $KIOSK_HOSTNAME

# The following lines are desirable for IPv6 capable hosts
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

    # Timezone
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
    
    # Habilitar systemd-resolved por defecto
    systemctl enable systemd-resolved
}

chroot_enable_debian_components() {
    log "Habilitando contrib y non-free en apt dentro del chroot..."
    local suite
    suite=$(grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release || echo "trixie")

    # Modificar Deb822 si existe
    if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
        perl -pi -e '
        if (/^Components:\s+(.+)$/) {
            my $comps = $1;
            if ($comps =~ /\bmain\b/) {
                my %seen;
                my @new_comps;
                foreach my $c (split(/\s+/, $comps), "contrib", "non-free", "non-free-firmware") {
                    push @new_comps, $c unless $seen{$c}++;
                }
                $_ = "Components: " . join(" ", @new_comps) . "\n";
            }
        }
        ' /etc/apt/sources.list.d/debian.sources
    fi

    # Modificar sources.list tradicional si existe
    if [[ -f /etc/apt/sources.list ]]; then
        perl -pi -e '
        if (/^deb(-src)?\s+(\S+)\s+(\S+)\s+(.+)$/) {
            my ($type, $url, $suite, $comps) = ($1, $2, $3, $4);
            if ($comps =~ /\bmain\b/) {
                my %seen;
                my @new_comps;
                foreach my $c (split(/\s+/, $comps), "contrib", "non-free", "non-free-firmware") {
                    push @new_comps, $c unless $seen{$c}++;
                }
                $_ = "deb$type $url $suite " . join(" ", @new_comps) . "\n";
            }
        }
        ' /etc/apt/sources.list
    fi

    # Si por alguna razon el sources.list esta vacio (debootstrap minimo), creamos uno basico
    if [[ ! -s /etc/apt/sources.list && ! -f /etc/apt/sources.list.d/debian.sources ]]; then
        cat > /etc/apt/sources.list << EOF
deb http://deb.debian.org/debian/ $suite main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ $suite main contrib non-free non-free-firmware
deb http://deb.debian.org/debian/ $suite-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian/ $suite-updates main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $suite-security main contrib non-free non-free-firmware
deb-src http://security.debian.org/debian-security $suite-security main contrib non-free non-free-firmware
EOF
    fi

    run_quiet apt-get update
}

chroot_install_grub() {
    log "Instalando GRUB bootloader..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
    update-grub
}

chroot_install_kiosk_packages() {
    log "Instalando paquetes base del sistema de audio, wayland y kiosk..."
    local pkgs=(
        sudo nano curl wget unzip git dbus dbus-user-session file
        samba alsa-utils pulseaudio-utils imagemagick
        pipewire wireplumber pipewire-pulse pipewire-alsa
        libasound2-plugins libpulse0 ffmpeg gstreamer1.0-libav gstreamer1.0-plugins-good
        usbutils bluez cage xwayland foot fonts-dejavu-core
        libhidapi-hidraw0 libsystemd0
    )
    
    run_quiet apt-get install -y "${pkgs[@]}"
}

chroot_install_gpu_drivers() {
    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        log "Instalando controladores NVIDIA oficiales inside chroot..."
        local nv_pkgs=(
            linux-headers-amd64
            nvidia-driver
            nvidia-kernel-dkms
            nvidia-vulkan-icd
            libnvidia-egl-wayland1
        )
        run_quiet apt-get install -y "${nv_pkgs[@]}"
    else
        log "Instalando controladores GPU libres..."
        local free_pkgs=(
            mesa-vulkan-drivers
            libvulkan1
            libegl1-mesa
            firmware-amd-graphics
            firmware-intel-graphics
            firmware-misc-nonfree
            firmware-sof-signed
        )
        run_quiet apt-get install -y "${free_pkgs[@]}" || warn "Fallo al instalar algun firmware libre de GPU."
    fi
}

chroot_configure_multiarch() {
    log "Habilitando soporte i386 en chroot..."
    dpkg --add-architecture i386
    run_quiet apt-get update
    
    local i386_pkgs=(
        libvulkan1:i386
        libhidapi-hidraw0:i386
        libpipewire-0.3-0:i386
        libpulse0:i386
        libasound2-plugins:i386
    )
    run_quiet apt-get install -y "${i386_pkgs[@]}" || warn "Dependencias 32 bits fallaron al instalar."
}

chroot_configure_performance() {
    log "Configurando optimizaciones y CPU performance..."
    mkdir -p /etc/security/limits.d /etc/sysctl.d

    cat > /etc/security/limits.d/99-yarg.conf << EOF
$KIOSK_USER - rtprio 99
$KIOSK_USER - memlock unlimited
$KIOSK_USER - nice -20
EOF

    echo 'vm.swappiness=10' > /etc/sysctl.d/99-yarg.conf
    
    # ALSA por defecto a Pipewire
    cat > /etc/asound.conf << 'EOF'
pcm.!default {
    type pipewire
}
ctl.!default {
    type pipewire
}
EOF

    # Servicio de CPU governor
    cat > /etc/systemd/system/cpu-performance.service << 'EOF'
[Unit]
Description=Set CPU governor to performance
After=sysfs.target

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'for g in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do [ -f "$g" ] && echo performance > "$g"; done || true'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    systemctl enable cpu-performance.service
}

chroot_configure_hid() {
    log "Configurando reglas udev..."
    mkdir -p /etc/udev/rules.d
    echo 'KERNEL=="hidraw*", TAG+="uaccess"' > /etc/udev/rules.d/69-hid.rules
    chmod 644 /etc/udev/rules.d/69-hid.rules
}

chroot_create_kiosk_user() {
    log "Creando usuario kiosko $KIOSK_USER..."
    if ! id "$KIOSK_USER" &>/dev/null; then
        useradd -m -s /bin/bash "$KIOSK_USER"
    fi

    for g in audio video input render sudo; do
        if getent group "$g" &>/dev/null; then
            usermod -aG "$g" "$KIOSK_USER"
        fi
    done

    if [[ -n "$KIOSK_PASSWORD" ]]; then
        echo "$KIOSK_USER:$KIOSK_PASSWORD" | chpasswd
    fi

    mkdir -p /etc/sudoers.d
    echo "$KIOSK_USER ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-kiosk
    chmod 440 /etc/sudoers.d/10-kiosk
}

chroot_resolve_yarg_url() {
    local api_url asset_regex channel_label

    case "$YARG_RELEASE_CHANNEL" in
        stable-latest|latest)
            api_url="$YARG_STABLE_API_URL"
            asset_regex="$YARG_STABLE_ASSET_REGEX"
            channel_label="stable"
            ;;
        nightly)
            api_url="$YARG_NIGHTLY_API_URL"
            asset_regex="$YARG_NIGHTLY_ASSET_REGEX"
            channel_label="nightly"
            ;;
        *)
            return 0
            ;;
    esac

    log "Resolviendo YARG ($channel_label)..."
    local release_json
    release_json=$(curl -fsSL "$api_url")
    
    local release_url
    release_url=$(printf '%s\n' "$release_json" \
        | grep -E '"browser_download_url":' \
        | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
        | grep -Ei "$asset_regex" \
        | head -n 1 || true)

    if [[ -z "$release_url" ]]; then
        release_url=$(printf '%s\n' "$release_json" \
            | grep -E '"browser_download_url":' \
            | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
            | grep -Ei 'linux.*\.zip' \
            | head -n 1 || true)
    fi

    if [[ -n "$release_url" ]]; then
        YARG_URL="$release_url"
    fi
}

chroot_install_yarg() {
    log "Instalando YARG..."
    local yarg_zip="/tmp/YARG.zip"
    mkdir -p /opt/YARG

    curl -fL --retry 3 --retry-delay 2 -o "$yarg_zip" "$YARG_URL"
    unzip -o "$yarg_zip" -d /opt/YARG
    find /opt/YARG -maxdepth 1 -type f -name 'YARG*' -exec chmod +x {} +
    mkdir -p "$YARG_SONGS_DIR"
    chown -R "$KIOSK_USER:$KIOSK_USER" /opt/YARG
    rm -f "$yarg_zip"
}

chroot_configure_yarg_settings() {
    local settings_dir="$YARG_PERSISTENT_DATA_DIR"
    local settings_file="$settings_dir/settings.json"
    mkdir -p "$settings_dir"

    cat > "$settings_file" << EOF
{
  "SongFolders": [
    "$YARG_SONGS_DIR"
  ],
  "ShowAntiPiracyDialog": false,
  "ShowEngineInconsistencyDialog": false,
  "ShowExperimentalWarningDialog": false
}
EOF
    chown -R "$KIOSK_USER:$KIOSK_USER" "$settings_dir"
}

chroot_configure_samba() {
    log "Configurando Samba..."
    mkdir -p /var/log/samba "$YARG_SONGS_DIR"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$YARG_SONGS_DIR"
    chmod 775 "$YARG_SONGS_DIR"

    local smb_conf="/etc/samba/smb.conf"
    cat > "$smb_conf" << EOF
[global]
   workgroup = WORKGROUP
   server string = YARG Debian Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/samba/%m.log
   max log size = 50

[YARG-Songs]
   path = $YARG_SONGS_DIR
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $KIOSK_USER
EOF

    systemctl enable smbd
    if [[ -n "$KIOSK_PASSWORD" ]]; then
        printf '%s\n%s\n' "$KIOSK_PASSWORD" "$KIOSK_PASSWORD" | smbpasswd -s -a "$KIOSK_USER"
    fi
}

chroot_install_update_script() {
    log "Instalando scripts de mantenimiento..."
    mkdir -p /usr/local/bin

    cat > /usr/local/bin/update-yarg << EOF
#!/usr/bin/env bash
set -euo pipefail
YARG_URL="$YARG_URL"
YARG_RELEASE_CHANNEL="$YARG_RELEASE_CHANNEL"
YARG_STABLE_API_URL="$YARG_STABLE_API_URL"
YARG_STABLE_ASSET_REGEX="$YARG_STABLE_ASSET_REGEX"
YARG_NIGHTLY_API_URL="$YARG_NIGHTLY_API_URL"
YARG_NIGHTLY_ASSET_REGEX="$YARG_NIGHTLY_ASSET_REGEX"
INSTALL_DIR="/opt/YARG"
SONGS_DIR="$YARG_SONGS_DIR"
ZIP_FILE="/tmp/YARG_Linux.zip"
OWNER="$KIOSK_USER"

if [[ \${EUID} -ne 0 ]]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi

resolve_latest_release_url() {
    local api_url="\$1"
    local asset_regex="\$2"
    local channel_label="\$3"
    local release_json release_url
    release_json="\$(curl -fsSL "\$api_url")"
    release_url="\$(printf '%s\n' "\$release_json" | grep -E '"browser_download_url":' | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' | grep -Ei "\$asset_regex" | head -n 1 || true)"
    [[ -z "\$release_url" ]] && release_url="\$(printf '%s\n' "\$release_json" | grep -E '"browser_download_url":' | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' | grep -Ei 'linux.*\.zip' | head -n 1 || true)"
    printf '%s\n' "\$release_url"
}

case "\$YARG_RELEASE_CHANNEL" in
    stable-latest|latest)
        YARG_URL="\$(resolve_latest_release_url "\$YARG_STABLE_API_URL" "\$YARG_STABLE_ASSET_REGEX" "stable")"
        ;;
    nightly)
        YARG_URL="\$(resolve_latest_release_url "\$YARG_NIGHTLY_API_URL" "\$YARG_NIGHTLY_ASSET_REGEX" "nightly")"
        ;;
esac

echo "Descargando YARG..."
curl -fsSL --retry 3 --retry-delay 2 -o "\$ZIP_FILE" "\$YARG_URL"
unzip -o "\$ZIP_FILE" -d "\$INSTALL_DIR" >/dev/null
find "\$INSTALL_DIR" -maxdepth 1 -type f -name "YARG*" -exec chmod +x {} +
chown -R "\$OWNER:\$OWNER" "\$INSTALL_DIR"
rm -f "\$ZIP_FILE"
echo "YARG actualizado."
EOF
    chmod +x /usr/local/bin/update-yarg

    # Script descargador de canciones
    local user_home="/home/$KIOSK_USER"
    cat > "$user_home/download-yarg-songs.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
LINKS_FILE="${1:-$HOME/links.csv}"
SONGS_DIR="/opt/YARG/Songs"

if [[ ! -f "$LINKS_FILE" ]]; then
    echo "Falta el archivo de enlaces $LINKS_FILE" >&2
    exit 1
fi

while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    url=$(printf '%s\n' "$line" | grep -Eo 'https?://[^,"]+' | head -n 1 || true)
    [[ -z "$url" ]] && continue
    echo "Descargando enlace: $url"
    curl -fL --retry 3 --retry-delay 2 -O --output-dir "$SONGS_DIR" "$url" || true
done < "$LINKS_FILE"
EOF
    chmod +x "$user_home/download-yarg-songs.sh"
    touch "$user_home/links.csv"
    ln -sfnT "$YARG_SONGS_DIR" "$user_home/Songs"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$user_home"
}

chroot_configure_plymouth() {
    if [[ "$ENABLE_PLYMOUTH" != "true" ]]; then
        return 0
    fi
    log "Configurando Plymouth..."
    local target_theme_dir="/usr/share/plymouth/themes/${PLYMOUTH_THEME_NAME}"
    mkdir -p "$target_theme_dir"

    cat > "${target_theme_dir}/${PLYMOUTH_THEME_NAME}.plymouth" << EOF
[Plymouth Theme]
Name=${PLYMOUTH_THEME_NAME}
Description=Custom kiosk theme
ModuleName=script

[script]
ImageDir=${target_theme_dir}
ScriptFile=${target_theme_dir}/${PLYMOUTH_THEME_NAME}.script
EOF

    cat > "${target_theme_dir}/${PLYMOUTH_THEME_NAME}.script" << 'EOF'
image = Image("background.png");
sprite = Sprite(image);
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
image_width = image.GetWidth();
image_height = image.GetHeight();
sprite.SetX((screen_width - image_width) / 2);
sprite.SetY((screen_height - image_height) / 2);
fun refresh_callback() {}
Plymouth.SetRefreshFunction(refresh_callback);
EOF

    local target_image="${target_theme_dir}/background.png"
    if [[ -f "/tmp/plymouth-image.png" ]]; then
        log "Copiando imagen de Plymouth directamente sin redimensionar..."
        cp "/tmp/plymouth-image.png" "$target_image"
    else
        # Fondo negro de respaldo
        if command -v convert &>/dev/null; then
            convert -size 1280x720 xc:black "$target_image"
        fi
    fi

    plymouth-set-default-theme "$PLYMOUTH_THEME_NAME" || true
    # update-initramfs se correra despues cuando el kernel este instalado
}

chroot_configure_grub_silent() {
    local grub_config="/etc/default/grub"
    [[ ! -f "$grub_config" ]] && return 0

    log "Configurando GRUB en modo silencioso..."
    local silent_params="quiet loglevel=3 systemd.show_status=false rd.udev.log_priority=3 vt.global_cursor_default=0"
    if [[ "$ENABLE_PLYMOUTH" == "true" ]]; then
        silent_params="$silent_params splash"
    fi
    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        silent_params="$silent_params nvidia_drm.modeset=1"
    fi

    sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$silent_params\"|" "$grub_config"
    update-grub
}

chroot_install_custom_cursor() {
    log "Instalando cursores personalizados si existen..."
    if [[ -d "/tmp/cursor" ]]; then
        mkdir -p /usr/share/icons/default
        cp -r /tmp/cursor/* /usr/share/icons/default/
        
        cat > /usr/share/icons/default/index.theme << 'EOF'
[Icon Theme]
Name=Default
Inherits=default
EOF

        local user_home="/home/$KIOSK_USER"
        mkdir -p "$user_home/.icons/default"
        cp /usr/share/icons/default/index.theme "$user_home/.icons/default/"
        chown -R "$KIOSK_USER:$KIOSK_USER" "$user_home/.icons"
    fi
}

chroot_hide_system_messages() {
    local user_home="/home/$KIOSK_USER"
    touch "$user_home/.hushlogin"
    chown "$KIOSK_USER:$KIOSK_USER" "$user_home/.hushlogin"
    echo "" > /etc/motd

    if [[ -f /etc/systemd/system.conf ]]; then
        sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' /etc/systemd/system.conf
    fi
    if [[ -f /etc/systemd/logind.conf ]]; then
        sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' /etc/systemd/logind.conf
    fi
}

chroot_install_cage_wrapper() {
    log "Creando wrapper run-yarg.sh..."
    mkdir -p /usr/local/bin

    cat > /usr/local/bin/run-yarg.sh <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

YARG_FORCE_SOFTWARE_RENDER="__YARG_FORCE_SOFTWARE_RENDER__"
if [[ "${YARG_FORCE_SOFTWARE_RENDER,,}" == "true" ]]; then
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export WLR_NO_HARDWARE_CURSORS=1
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
fi

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        export YARG_DBUS_SESSION_STARTED=1
        exec dbus-run-session -- "$0"
    fi
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage

if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
fi

export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
YARG_SCREEN_WIDTH="__YARG_SCREEN_WIDTH__"
YARG_SCREEN_HEIGHT="__YARG_SCREEN_HEIGHT__"

wait_for_path() {
    for _ in $(seq 1 100); do
        [[ -e "$1" ]] && return 0
        sleep 0.1
    done
    return 1
}

wait_for_pulse_sink() {
    for _ in $(seq 1 50); do
        if command -v pactl >/dev/null 2>&1; then
            pactl list short sinks 2>/dev/null | grep -q . && return 0
        fi
        sleep 0.1
    done
    return 1
}

if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
    pipewire 2>/dev/null &
fi

wait_for_path "$XDG_RUNTIME_DIR/pipewire-0" || true

if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
    wireplumber 2>/dev/null &
fi

sleep 1

if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
    pipewire-pulse 2>/dev/null &
fi

wait_for_pulse_sink || true

YARG_BIN=$(find /opt/YARG -maxdepth 1 -type f -name "YARG*" -executable -print -quit 2>/dev/null)
if [[ -n "$YARG_BIN" ]]; then
    YARG_ARGS=(-persistent-data-path "__YARG_PERSISTENT_DATA_DIR__")
    if [[ -n "$YARG_SCREEN_WIDTH" && -n "$YARG_SCREEN_HEIGHT" ]]; then
        YARG_ARGS+=(
            -screen-width "$YARG_SCREEN_WIDTH"
            -screen-height "$YARG_SCREEN_HEIGHT"
            -screen-fullscreen 1
        )
    fi
    exec /usr/bin/cage -- "$YARG_BIN" "${YARG_ARGS[@]}"
fi

exec /usr/bin/cage /usr/bin/foot
WRAPPER

    chmod +x /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_PERSISTENT_DATA_DIR__#$YARG_PERSISTENT_DATA_DIR#g" /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_WIDTH__#${YARG_SCREEN_WIDTH:-}#g" /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_HEIGHT__#${YARG_SCREEN_HEIGHT:-}#g" /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_FORCE_SOFTWARE_RENDER__#${YARG_FORCE_SOFTWARE_RENDER:-false}#g" /usr/local/bin/run-yarg.sh
}

chroot_install_cage_service() {
    log "Creando servicio cage-kiosk.service..."
    local kiosk_uid
    kiosk_uid=$(id -u "$KIOSK_USER")

    cat > /etc/systemd/system/cage-kiosk.service << EOF
[Unit]
Description=Kiosk YARG con Cage (Debian Bootstrap)
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
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$kiosk_uid
ExecStartPre=+/bin/mkdir -p /run/user/$kiosk_uid
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire-pulse
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x wireplumber
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire
ExecStartPre=-/bin/rm -f /run/user/$kiosk_uid/pipewire-0 /run/user/$kiosk_uid/pipewire-0.lock /run/user/$kiosk_uid/pulse/native
ExecStartPre=+/bin/chown $KIOSK_USER:$KIOSK_USER /run/user/$kiosk_uid
ExecStartPre=+/bin/chmod 700 /run/user/$kiosk_uid
ExecStart=/usr/bin/dbus-run-session -- /usr/local/bin/run-yarg.sh
ExecStopPost=-/usr/bin/pkill -u $KIOSK_USER -x pipewire-pulse
ExecStopPost=-/usr/bin/pkill -u $KIOSK_USER -x wireplumber
ExecStopPost=-/usr/bin/pkill -u $KIOSK_USER -x pipewire
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

    systemctl set-default graphical.target
    systemctl enable cage-kiosk.service
}

chroot_configure_ssh() {
    if [[ "$ENABLE_SSH" == "true" ]]; then
        log "Instalando y activando SSH..."
        run_quiet apt-get install -y openssh-server
        systemctl enable ssh
    fi
}

chroot_finalize() {
    log "Corriendo update-initramfs para Plymouth..."
    run_quiet update-initramfs -u -k all || true
    log "Configuracion interna de chroot completada exitosamente."
}

# =============================================================================
# ENTRYPOINT PRINCIPAL DEL SCRIPT
# =============================================================================

# Si recibimos --in-chroot, ejecutamos la fase de configuracion interna
if [[ "${1:-}" == "--in-chroot" ]]; then
    validate_environment "--in-chroot"

    section "1. Repositorios y Paquetes de Sistema"
    chroot_configure_system_basics
    chroot_enable_debian_components
    chroot_install_grub
    chroot_install_kiosk_packages
    chroot_install_gpu_drivers
    chroot_configure_multiarch

    section "2. Optimizaciones y Usuario"
    chroot_create_kiosk_user
    chroot_configure_performance
    chroot_configure_hid
    chroot_configure_samba

    section "3. Instalacion y Setup YARG"
    chroot_resolve_yarg_url
    chroot_install_yarg
    chroot_configure_yarg_settings
    chroot_install_update_script

    section "4. Cage y Visuales"
    chroot_install_custom_cursor
    chroot_configure_plymouth
    chroot_configure_grub_silent
    chroot_hide_system_messages
    chroot_install_cage_wrapper
    chroot_install_cage_service
    chroot_configure_ssh
    chroot_finalize

    exit 0
fi

# =============================================================================
# FASE EJECUTADA EN EL HOST
# =============================================================================

main() {
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}     BOOTSTRAP INSTALADOR DEBIAN 13.5 + CAGE + YARG KIOSK${NC}"
    echo -e "${BLUE}===================================================================${NC}"

    validate_environment
    check_network
    ask_initial_questions
    validate_security_config
    preflight_optional_assets

    section "1. Particionando y Formateando Disco"
    partition_disk "$DISK_DEVICE"
    format_partitions "$DISK_DEVICE"
    mount_partitions "$DISK_DEVICE"

    section "2. Bootstrap del Sistema Base"
    bootstrap_system
    generate_fstab

    # Copiar configuraciones y assets temporales al chroot
    log "Copiando assets y configuracion al entorno chroot..."
    
    # 1. Guardar variables de entorno para que el chroot las lea
    cat > /mnt/tmp/chroot.env << EOF
DISK_DEVICE="$DISK_DEVICE"
KIOSK_USER="$KIOSK_USER"
KIOSK_PASSWORD="$KIOSK_PASSWORD"
KIOSK_HOSTNAME="$KIOSK_HOSTNAME"
TIMEZONE="$TIMEZONE"
ENABLE_SSH="$ENABLE_SSH"
INSTALL_NVIDIA="$INSTALL_NVIDIA"
ENABLE_PLYMOUTH="$ENABLE_PLYMOUTH"
PLYMOUTH_THEME_NAME="$PLYMOUTH_THEME_NAME"
YARG_SONGS_DIR="$YARG_SONGS_DIR"
YARG_PERSISTENT_DATA_DIR="$YARG_PERSISTENT_DATA_DIR"
YARG_RELEASE_CHANNEL="$YARG_RELEASE_CHANNEL"
YARG_STABLE_API_URL="$YARG_STABLE_API_URL"
YARG_STABLE_ASSET_REGEX="$YARG_STABLE_ASSET_REGEX"
YARG_NIGHTLY_API_URL="$YARG_NIGHTLY_API_URL"
YARG_NIGHTLY_ASSET_REGEX="$YARG_NIGHTLY_ASSET_REGEX"
YARG_URL="$YARG_URL"
YARG_SCREEN_WIDTH="${YARG_SCREEN_WIDTH:-}"
YARG_SCREEN_HEIGHT="${YARG_SCREEN_HEIGHT:-}"
YARG_FORCE_SOFTWARE_RENDER="$YARG_FORCE_SOFTWARE_RENDER"
DEBIAN_MIRROR_URL="$DEBIAN_MIRROR_URL"
EOF

    # 2. Copiar imagen de Plymouth si esta disponible
    if [[ "$PLYMOUTH_ASSET_AVAILABLE" == "true" ]]; then
        cp "$PLYMOUTH_IMAGE_PATH" /mnt/tmp/plymouth-image.png
    fi

    # 3. Copiar cursores si estan disponibles
    if [[ -d "$CURSOR_PATH" ]]; then
        cp -r "$CURSOR_PATH" /mnt/tmp/cursor
    fi

    # 4. Copiar este script al chroot para ejecutarlo internamente
    cp "$0" /mnt/tmp/install.sh
    chmod +x /mnt/tmp/install.sh

    section "3. Configurando Sistema vía Chroot"
    mount_virtual_filesystems
    
    # Ejecutar re-entrada del script dentro de chroot
    if ! chroot /mnt /tmp/install.sh --in-chroot; then
        log_error "Fallo durante la configuracion interna en chroot."
        unmount_virtual_filesystems
        exit 1
    fi

    # Limpiar archivos temporales
    rm -f /mnt/tmp/chroot.env /mnt/tmp/plymouth-image.png /mnt/tmp/install.sh
    rm -rf /mnt/tmp/cursor

    unmount_virtual_filesystems

    section "Instalacion finalizada"
    echo ""
    echo -e "${GREEN}===================================================================${NC}"
    echo -e "${GREEN}  ¡DEBIAN CAGE + YARG INSTALADO Y DESPLEGADO EXITOSAMENTE!${NC}"
    echo -e "${GREEN}===================================================================${NC}"
    echo ""
    echo "El disco $DISK_DEVICE ha sido preparado con Debian 13.5 y el kiosko YARG."
    echo "Puede reiniciar el equipo ahora."
    echo ""
    echo -e "${BLUE}===================================================================${NC}"
}

main "$@"
