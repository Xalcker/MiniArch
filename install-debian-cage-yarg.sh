#!/usr/bin/env bash
# =============================================================================
# install-debian-cage-yarg.sh
# -----------------------------------------------------------------------------
# Orquestador para instalar Cage (Wayland/XWayland) + YARG en un sistema Debian 13.5
# minimal (netinst) ya instalado.
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
LOG_FILE="${LOG_FILE:-/var/log/debian-cage-install.log}"
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

# Cargar configuración de .env si existe
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    log "Cargando configuracion desde .env..."
    set -a
    # shellcheck disable=SC1090
    source <(grep -v '^#' "$SCRIPT_DIR/.env" | grep -v '^$')
    set +a
    log "Configuracion cargada desde .env"
else
    warn "No se encontro .env en $SCRIPT_DIR. Se usaran configuraciones por defecto o interactivas."
fi

# Variables por defecto
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
PLYMOUTH_ASSET_AVAILABLE=false

# Validaciones iniciales
validate_environment() {
    log "Validando entorno del sistema..."
    if [[ $EUID -ne 0 ]]; then
        log_error "Este script debe ejecutarse como root"
        return 1
    fi

    if [[ ! -f /etc/debian_version ]]; then
        log_error "Este script esta diseñado para ejecutarse en Debian. No se detecto /etc/debian_version."
        return 1
    fi
    log "Entorno validado correctamente."
    return 0
}

check_network() {
    log "Verificando conectividad de red..."
    if ! ping -c 3 -W 5 debian.org &> /dev/null; then
        log_error "Sin conexion de red. Verifique su conexion antes de continuar."
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
        if command -v file &>/dev/null; then
            local file_type
            file_type=$(file -b --mime-type "$PLYMOUTH_IMAGE_PATH")
            if [[ "$file_type" == "image/png" ]]; then
                PLYMOUTH_ASSET_AVAILABLE=true
                log "Imagen Plymouth validada correctamente."
            else
                warn "La imagen de Plymouth debe ser un archivo PNG valido. Se omitira personalizacion."
            fi
        else
            PLYMOUTH_ASSET_AVAILABLE=true
        fi
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
    echo -e "${YELLOW}Usuario kiosko:${NC} $KIOSK_USER"
    echo ""

    if [[ -z "$INSTALL_NVIDIA" ]]; then
        read -rp "$(echo -e "${BLUE}Instalar driver NVIDIA privativo? (s/N): ${NC}")" answer
        INSTALL_NVIDIA=false
        [[ "${answer,,}" == "s" || "${answer,,}" == "y" ]] && INSTALL_NVIDIA=true
    fi

    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        log "Se instalaran drivers NVIDIA oficiales desde repositorios non-free."
    else
        warn "Driver NVIDIA omitido. Se instalaran Mesa y Vulkan libres."
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

    case "$YARG_RELEASE_CHANNEL" in
        stable)
            log "Se usara YARG stable desde YARG_URL: $YARG_URL"
            ;;
        stable-latest|latest)
            YARG_RELEASE_CHANNEL="stable-latest"
            log "Se resolvera el stable mas reciente desde YARC-Official/YARG"
            ;;
        nightly)
            log "Se resolvera el nightly mas reciente desde YARG-BleedingEdge"
            ;;
        *)
            log_error "YARG_RELEASE_CHANNEL invalido: $YARG_RELEASE_CHANNEL. Use stable, stable-latest, nightly o ask."
            return 1
            ;;
    esac

    YARG_RESOLUTION="${YARG_RESOLUTION,,}"
    if [[ "$YARG_RESOLUTION" == "ask" ]]; then
        read -rp "$(echo -e "${BLUE}Resolucion de YARG: 4k, 2k, 1080p o 720p? [4k/2k/1080p/720p] (1080p): ${NC}")" answer
        YARG_RESOLUTION="${answer:-1080p}"
    fi

    if ! resolve_yarg_resolution "$YARG_RESOLUTION"; then
        return 1
    fi
    log "Resolucion de YARG seleccionada: $YARG_RESOLUTION (${YARG_SCREEN_WIDTH}x${YARG_SCREEN_HEIGHT})"
}

# Habilitar componentes de repositorio de Debian (contrib, non-free, non-free-firmware)
enable_debian_components() {
    log "Configurando componentes de repositorio Debian (contrib, non-free, non-free-firmware)..."
    local suite
    suite=$(grep -oP 'VERSION_CODENAME=\K\w+' /etc/os-release || echo "trixie")

    # 1. Formato Deb822 en /etc/apt/sources.list.d/debian.sources
    if [[ -f /etc/apt/sources.list.d/debian.sources ]]; then
        log "Modificando archivo de fuentes moderno (Deb822)..."
        cp /etc/apt/sources.list.d/debian.sources /etc/apt/sources.list.d/debian.sources.bak
        # Agregar contrib, non-free, non-free-firmware si no estan presentes
        sed -i 's/^Components: main$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
        sed -i 's/^Components: main non-free-firmware$/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources
    fi

    # 2. Formato tradicional en /etc/apt/sources.list
    if [[ -f /etc/apt/sources.list ]]; then
        log "Modificando archivo de fuentes tradicional..."
        cp /etc/apt/sources.list /etc/apt/sources.list.bak
        # Reemplazar 'main' al final de lineas de repos por los componentes adicionales de forma segura
        sed -i -E 's/(\bmain\b)(?!\b.*contrib\b)(?!\b.*non-free\b)/main contrib non-free non-free-firmware/g' /etc/apt/sources.list
    fi

    log "Actualizando lista de paquetes..."
    run_quiet apt-get update
}

# Instalación de paquetes del sistema
install_debian_packages() {
    log "Instalando paquetes base y dependencias del sistema kiosk..."
    local pkgs=(
        sudo nano curl wget unzip git dbus dbus-user-session file
        samba alsa-utils pulseaudio-utils
        pipewire wireplumber pipewire-pulse pipewire-alsa
        libasound2-plugins libpulse0 ffmpeg gstreamer1.0-libav gstreamer1.0-plugins-good
        usbutils bluez cage xwayland foot fonts-dejavu-core
        libhidapi-hidraw0 libsystemd0
    )

    if ! run_quiet apt-get install -y "${pkgs[@]}"; then
        log_error "Fallo al instalar paquetes base."
        return 1
    fi
}

install_gpu_drivers() {
    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        log "Instalando controladores NVIDIA oficiales..."
        local nv_pkgs=(
            linux-headers-$(uname -r)
            nvidia-driver
            nvidia-kernel-dkms
            nvidia-vulkan-icd
            libnvidia-egl-wayland1
        )
        if ! run_quiet apt-get install -y "${nv_pkgs[@]}"; then
            log_error "Fallo la instalacion de controladores NVIDIA."
            return 1
        fi
    else
        log "Instalando firmware y controladores libres (AMD/Intel/Mesa)..."
        local free_pkgs=(
            mesa-vulkan-drivers
            libvulkan1
            libegl1-mesa
            firmware-amd-graphics
            firmware-intel-graphics
            firmware-misc-nonfree
            firmware-sof-signed
        )
        # Si falla algun firmware no-libre por falta de repos, advertimos pero intentamos continuar
        if ! run_quiet apt-get install -y "${free_pkgs[@]}"; then
            warn "Algunos controladores o firmwares de GPU libres fallaron al instalar. Continuando..."
        fi
    fi
}

# Multiarch / 32-bit audio/Vulkan (opcional pero util para compatibilidad total)
configure_multiarch() {
    log "Configurando soporte multi-arquitectura de 32 bits..."
    dpkg --add-architecture i386
    run_quiet apt-get update

    local i386_pkgs=(
        libvulkan1:i386
        libhidapi-hidraw0:i386
        libpipewire-0.3-0:i386
        libpulse0:i386
        libasound2-plugins:i386
    )

    if ! run_quiet apt-get install -y "${i386_pkgs[@]}"; then
        warn "Algunas dependencias 32-bit (i386) fallaron al instalar. Se continuará con el sistema de 64-bit."
    fi
}

# Configurar límites de tiempo real y optimización del rendimiento
configure_performance_and_limits() {
    log "Configurando optimizaciones de rendimiento y prioridades de tiempo real..."
    mkdir -p /etc/security/limits.d /etc/sysctl.d

    cat > /etc/security/limits.d/99-yarg.conf << EOF
$KIOSK_USER - rtprio 99
$KIOSK_USER - memlock unlimited
$KIOSK_USER - nice -20
EOF

    echo 'vm.swappiness=10' > /etc/sysctl.d/99-yarg.conf
    run_quiet sysctl -p /etc/sysctl.d/99-yarg.conf

    # Servidor de audio PipeWire redirección en ALSA por defecto
    log "Redirigiendo ALSA por defecto hacia PipeWire..."
    cat > /etc/asound.conf << 'EOF'
pcm.!default {
    type pipewire
}

ctl.!default {
    type pipewire
}
EOF

    # Servicio systemd simple para CPU en modo performance en lugar de cpupower/cpufrequtils
    log "Creando servicio systemd cpu-performance para programar el governor al iniciar..."
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

    run_quiet systemctl daemon-reload
    run_quiet systemctl enable cpu-performance.service
    run_quiet systemctl start cpu-performance.service
}

# Configuración de udev rules para instrumentos USB (guitarras, baterias, etc.)
configure_hid_access() {
    log "Configurando acceso udev hidraw para periféricos e instrumentos..."
    mkdir -p /etc/udev/rules.d
    echo 'KERNEL=="hidraw*", TAG+="uaccess"' > /etc/udev/rules.d/69-hid.rules
    chmod 644 /etc/udev/rules.d/69-hid.rules
    run_quiet udevadm control --reload-rules
    run_quiet udevadm trigger
}

# Creación y configuración del usuario
create_kiosk_user() {
    log "Creando usuario kiosko '$KIOSK_USER'..."
    if id "$KIOSK_USER" &>/dev/null; then
        log "El usuario '$KIOSK_USER' ya existe."
    else
        if ! useradd -m -s /bin/bash "$KIOSK_USER"; then
            log_error "No se pudo crear el usuario $KIOSK_USER"
            return 1
        fi
    fi

    # Grupos necesarios
    for g in audio video input render sudo; do
        if getent group "$g" &>/dev/null; then
            usermod -aG "$g" "$KIOSK_USER"
        fi
    done

    # Contraseña
    if [[ -n "$KIOSK_PASSWORD" ]]; then
        echo "$KIOSK_USER:$KIOSK_PASSWORD" | chpasswd
    fi

    # Configurar sudo sin contraseña para el usuario kiosk
    log "Configurando sudoers para $KIOSK_USER..."
    mkdir -p /etc/sudoers.d
    echo "$KIOSK_USER ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/10-kiosk
    chmod 440 /etc/sudoers.d/10-kiosk
}

# Resolver URL de descarga de YARG
resolve_yarg_download_url() {
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

    log "Resolviendo URL de YARG ($channel_label) mas reciente..."
    local release_json
    if ! release_json=$(curl -fsSL "$api_url"); then
        log_error "Fallo al conectar con la API de GitHub: $api_url"
        return 1
    fi

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

    if [[ -z "$release_url" ]]; then
        log_error "No se pudo encontrar una descarga valida de Linux (ZIP) para YARG."
        return 1
    fi

    YARG_URL="$release_url"
    log "URL resuelta exitosamente: $YARG_URL"
}

# Descarga e instalación de YARG
install_yarg() {
    log "Descargando e instalando YARG en /opt/YARG..."
    local yarg_zip="/tmp/YARG.zip"
    mkdir -p /opt/YARG

    if ! run_quiet curl -fL --retry 3 --retry-delay 2 -o "$yarg_zip" "$YARG_URL"; then
        log_error "Fallo la descarga del zip de YARG."
        return 1
    fi

    if [[ ! -s "$yarg_zip" ]]; then
        log_error "El archivo descargado esta vacio."
        return 1
    fi

    if ! unzip -tq "$yarg_zip" >/dev/null; then
        log_error "El zip de YARG no es valido o esta corrupto."
        rm -f "$yarg_zip"
        return 1
    fi

    if ! run_quiet unzip -o "$yarg_zip" -d /opt/YARG; then
        log_error "Fallo al descomprimir YARG."
        rm -f "$yarg_zip"
        return 1
    fi

    find /opt/YARG -maxdepth 1 -type f -name 'YARG*' -exec chmod +x {} +
    mkdir -p "$YARG_SONGS_DIR"
    chown -R "$KIOSK_USER:$KIOSK_USER" /opt/YARG
    rm -f "$yarg_zip"
    log "YARG instalado correctamente."
}

configure_yarg_default_settings() {
    local settings_dir="$YARG_PERSISTENT_DATA_DIR"
    local settings_file="$settings_dir/settings.json"

    log "Estableciendo configuracion fija de canciones de YARG..."
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

# Configuración de Samba
configure_samba_share() {
    log "Configurando Samba para transferir canciones de forma remota..."
    mkdir -p /var/log/samba "$YARG_SONGS_DIR"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$YARG_SONGS_DIR"
    chmod 775 "$YARG_SONGS_DIR"

    local smb_conf="/etc/samba/smb.conf"
    if [[ ! -f "$smb_conf" ]] || ! grep -q '^\[global\]' "$smb_conf"; then
        cat > "$smb_conf" << EOF
[global]
   workgroup = WORKGROUP
   server string = YARG Debian Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/samba/%m.log
   max log size = 50
EOF
    fi

    if ! grep -q '^\[YARG-Songs\]' "$smb_conf"; then
        cat >> "$smb_conf" << EOF

[YARG-Songs]
   path = $YARG_SONGS_DIR
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $KIOSK_USER
EOF
    fi

    log "Activando servicio Samba (smbd)..."
    systemctl enable smbd
    systemctl restart smbd

    if systemctl list-unit-files | grep -q nmbd; then
        systemctl enable nmbd
        systemctl restart nmbd
    fi

    # Registrar usuario en Samba
    if [[ -n "$KIOSK_PASSWORD" ]]; then
        printf '%s\n%s\n' "$KIOSK_PASSWORD" "$KIOSK_PASSWORD" | smbpasswd -s -a "$KIOSK_USER"
    fi
}

install_yarg_update_script() {
    log "Instalando script updater /usr/local/bin/update-yarg..."
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

    release_url="\$(printf '%s\n' "\$release_json" \
        | grep -E '"browser_download_url":' \
        | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
        | grep -Ei "\$asset_regex" \
        | head -n 1 || true)"

    if [[ -z "\$release_url" ]]; then
        release_url="\$(printf '%s\n' "\$release_json" \
            | grep -E '"browser_download_url":' \
            | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
            | grep -Ei 'linux.*\.zip' \
            | head -n 1 || true)"
    fi

    if [[ -z "\$release_url" ]]; then
        echo "No se encontro el zip de Linux en el release \$channel_label." >&2
        return 1
    fi

    printf '%s\n' "\$release_url"
}

case "\$YARG_RELEASE_CHANNEL" in
    stable-latest|latest)
        echo "Buscando ultima stable desde \$YARG_STABLE_API_URL"
        YARG_URL="\$(resolve_latest_release_url "\$YARG_STABLE_API_URL" "\$YARG_STABLE_ASSET_REGEX" "stable")"
        ;;
    nightly)
        echo "Buscando ultima nightly desde \$YARG_NIGHTLY_API_URL"
        YARG_URL="\$(resolve_latest_release_url "\$YARG_NIGHTLY_API_URL" "\$YARG_NIGHTLY_ASSET_REGEX" "nightly")"
        ;;
    stable)
        ;;
    *)
        echo "Usando YARG_URL por defecto: \$YARG_URL"
        ;;
esac

echo "Descargando YARG desde \$YARG_URL"
curl -fsSL --retry 3 --retry-delay 2 -o "\$ZIP_FILE" "\$YARG_URL"
unzip -tq "\$ZIP_FILE" >/dev/null
mkdir -p "\$SONGS_DIR"
unzip -o "\$ZIP_FILE" -d "\$INSTALL_DIR" >/dev/null
find "\$INSTALL_DIR" -maxdepth 1 -type f -name "YARG*" -exec chmod +x {} +
chown -R "\$OWNER:\$OWNER" "\$INSTALL_DIR"
chown -R "\$OWNER:\$OWNER" "\$SONGS_DIR"
rm -f "\$ZIP_FILE"
echo "YARG actualizado en \$INSTALL_DIR."
EOF

    chmod +x /usr/local/bin/update-yarg
}

install_yarg_song_download_script() {
    local user_home="/home/$KIOSK_USER"
    local script_path="$user_home/download-yarg-songs.sh"
    local links_target="$user_home/links.csv"
    local links_source="$SCRIPT_DIR/links.csv"

    log "Instalando script para descarga de canciones..."
    mkdir -p "$user_home"

    if [[ -f "$links_source" ]]; then
        cp "$links_source" "$links_target"
    else
        touch "$links_target"
    fi

    cat > "$script_path" << EOF
#!/usr/bin/env bash
set -euo pipefail

LINKS_FILE="\${1:-\$HOME/links.csv}"
SONGS_DIR="${YARG_SONGS_DIR}"

if [[ -r /dev/tty ]]; then
    exec 3</dev/tty
else
    exec 3<&0
fi

trim() {
    local value="\$1"
    value="\${value#"\${value%%[![:space:]]*}"}"
    value="\${value%"\${value##*[![:space:]]}"}"
    printf '%s' "\$value"
}

sanitize_filename() {
    local value="\$1"
    value="\$(trim "\$value")"
    value="\${value//\"/}"
    value="\${value//\\'/}"
    value="\$(printf '%s' "\$value" | tr '/\\\\:*?<>|' '_' | tr -s ' ')"
    value="\${value%.}"
    value="\${value:-download}"
    printf '%s' "\$value"
}

unique_path() {
    local path="\$1"
    local dir base ext candidate i
    dir="\$(dirname -- "\$path")"
    base="\$(basename -- "\$path")"
    ext=""

    if [[ "\$base" == *.* ]]; then
        ext=".\${base##*.}"
        base="\${base%.*}"
    fi

    candidate="\$dir/\$base\$ext"
    i=1
    while [[ -e "\$candidate" ]]; do
        candidate="\$dir/\$base-\$i\$ext"
        i=\$((i + 1))
    done

    printf '%s' "\$candidate"
}

extract_url() {
    local line="\$1"
    printf '%s\n' "\$line" | grep -Eo 'https?://[^,"]+' | head -n 1 || true
}

extract_label() {
    local line="\$1"
    local url="\$2"
    local label

    label="\${line%%,*}"
    label="\$(trim "\$label")"
    label="\${label%\"}"
    label="\${label#\"}"

    if [[ -z "\$label" || "\$label" == "\$url" || "\$label" == http* ]]; then
        label="\$(basename "\${url%%\?*}")"
    fi

    printf '%s' "\${label:-download}"
}

google_drive_file_id() {
    local url="\$1"

    if [[ "\$url" =~ /file/d/([^/?#]+) ]]; then
        printf '%s' "\${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ "\$url" =~ [\?\&]id=([^&#]+) ]]; then
        printf '%s' "\${BASH_REMATCH[1]}"
        return 0
    fi

    printf ''
}

infer_extension() {
    local file_path="\$1"
    local mime

    if ! command -v file >/dev/null 2>&1; then
        printf ''
        return 0
    fi

    mime="\$(file -b --mime-type "\$file_path" 2>/dev/null || true)"
    case "\$mime" in
        application/zip) printf '.zip' ;;
        application/x-7z-compressed) printf '.7z' ;;
        application/x-rar*) printf '.rar' ;;
        audio/mpeg) printf '.mp3' ;;
        audio/ogg) printf '.ogg' ;;
        audio/flac) printf '.flac' ;;
        text/html) printf '.html' ;;
        *) printf '' ;;
    esac
}

download_to_temp() {
    local url="\$1"
    local tmp_file="\$2"
    local drive_id="\$3"

    if [[ -n "\$drive_id" ]]; then
        local cookie_file confirm html_probe drive_url form_action uuid
        cookie_file="\$(mktemp)"
        html_probe="\$(mktemp)"

        curl -fL --retry 3 --retry-delay 2 -c "\$cookie_file" \
            -o "\$tmp_file" "https://drive.google.com/uc?export=download&id=\$drive_id"

        if grep -qiE 'confirm=|download_warning|Google Drive' "\$tmp_file"; then
            cp "\$tmp_file" "\$html_probe"
            confirm="\$(sed -nE 's/.*confirm=([0-9A-Za-z_-]+).*/\1/p' "\$html_probe" | head -n 1)"

            if [[ -z "\$confirm" ]]; then
                confirm="\$(grep -Eo 'confirm=[0-9A-Za-z_-]+' "\$html_probe" | head -n 1 | cut -d= -f2)"
            fi

            drive_url="\$(grep -Eo 'https://drive\\.usercontent\\.google\\.com/download[^"]+' "\$html_probe" | head -n 1 | sed 's/&amp;/\\&/g')"
            if [[ -z "\$drive_url" ]]; then
                drive_url="\$(grep -Eo '/uc\\?export=download[^"]+' "\$html_probe" | head -n 1 | sed 's/&amp;/\\&/g')"
                [[ -n "\$drive_url" ]] && drive_url="https://drive.google.com\$drive_url"
            fi

            if [[ -n "\$drive_url" ]]; then
                curl -fL --retry 3 --retry-delay 2 -b "\$cookie_file" -o "\$tmp_file" "\$drive_url"
                rm -f "\$cookie_file" "\$html_probe"
                return 0
            fi

            form_action="\$(sed -nE 's/.*<form[^>]+id="download-form"[^>]+action="([^"]+)".*/\\1/p' "\$html_probe" | head -n 1 | sed 's/&amp;/\\&/g')"
            uuid="\$(sed -nE 's/.*name="uuid" value="([^"]+)".*/\\1/p' "\$html_probe" | head -n 1)"

            if [[ -n "\$form_action" ]]; then
                [[ -z "\$confirm" ]] && confirm="t"
                drive_url="\$form_action?id=\$drive_id&export=download&confirm=\$confirm"
                [[ -n "\$uuid" ]] && drive_url="\$drive_url&uuid=\$uuid"
                curl -fL --retry 3 --retry-delay 2 -b "\$cookie_file" -o "\$tmp_file" "\$drive_url"
                rm -f "\$cookie_file" "\$html_probe"
                return 0
            fi

            if [[ -z "\$confirm" ]]; then
                rm -f "\$cookie_file" "\$html_probe"
                echo "No se pudo descargar de Google Drive. Verifica que sea publico." >&2
                return 1
            fi

            curl -fL --retry 3 --retry-delay 2 -b "\$cookie_file" \
                -o "\$tmp_file" "https://drive.google.com/uc?export=download&confirm=\$confirm&id=\$drive_id"
        fi

        rm -f "\$cookie_file" "\$html_probe"
        return 0
    fi

    curl -fL --retry 3 --retry-delay 2 -o "\$tmp_file" "\$url"
}

download_link() {
    local url="\$1"
    local label="\$2"
    local drive_id tmp_file ext target

    drive_id="\$(google_drive_file_id "\$url")"
    tmp_file="\$(mktemp -p "\$SONGS_DIR" ".download.XXXXXX")"

    if ! download_to_temp "\$url" "\$tmp_file" "\$drive_id"; then
        rm -f "\$tmp_file"
        return 1
    fi

    if [[ ! -s "\$tmp_file" ]]; then
        rm -f "\$tmp_file"
        echo "La descarga quedo vacia." >&2
        return 1
    fi

    label="\$(sanitize_filename "\$label")"
    ext="\$(infer_extension "\$tmp_file")"

    if [[ "\$ext" == ".html" ]]; then
        rm -f "\$tmp_file"
        echo "La descarga devolvio HTML en vez de archivo. Revise permisos." >&2
        return 1
    fi

    if [[ "\$label" != *.* && -n "\$ext" && "\$ext" != ".html" ]]; then
        label="\$label\$ext"
    fi

    target="\$(unique_path "\$SONGS_DIR/\$label")"
    mv "\$tmp_file" "\$target"

    if [[ "\$target" == *.zip ]]; then
        read -r -p "Extraer ZIP en Songs y borrar el ZIP? [s/N]: " unzip_answer <&3
        case "\${unzip_answer,,}" in
            s|y|si|yes)
                unzip -o "\$target" -d "\$SONGS_DIR"
                rm -f "\$target"
                echo "Extraido en \$SONGS_DIR"
                ;;
            *)
                echo "Guardado zip en: \$target"
                ;;
        esac
    else
        echo "Guardado en: \$target"
    fi
}

if [[ ! -f "\$LINKS_FILE" ]]; then
    echo "No existe \$LINKS_FILE" >&2
    exit 1
fi

mkdir -p "\$SONGS_DIR"

line_number=0
while IFS= read -r raw_line || [[ -n "\$raw_line" ]]; do
    line_number=\$((line_number + 1))
    line="\$(trim "\$raw_line")"

    [[ -z "\$line" || "\$line" == \#* ]] && continue
    [[ "\${line,,}" =~ ^(name|nombre|title|titulo), ]] && continue

    url="\$(trim "\$(extract_url "\$line")")"
    if [[ -z "\$url" ]]; then
        echo "Linea \$line_number sin URL, omitida."
        continue
    fi

    label="\$(extract_label "\$line" "\$url")"

    echo ""
    echo "[\$line_number] \$label"
    echo "\$url"
    read -r -p "Descargar este enlace? [s/N]: " answer <&3
    case "\${answer,,}" in
        s|y|si|yes)
            if ! download_link "\$url" "\$label"; then
                echo "Fallo la descarga de: \$url" >&2
            fi
            ;;
        *)
            echo "Omitido."
            ;;
    esac
done < "\$LINKS_FILE"

echo ""
echo "Descargas finalizadas. Carpeta de canciones: \$SONGS_DIR"
EOF

    chmod +x "$script_path"
    ln -sfnT "$YARG_SONGS_DIR" "$user_home/Songs"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$user_home"
    chown -R "$KIOSK_USER:$KIOSK_USER" "$YARG_SONGS_DIR"
}

# Configuración de Plymouth en Debian
configure_plymouth() {
    if [[ "$ENABLE_PLYMOUTH" != "true" ]]; then
        log "Plymouth deshabilitado en la configuracion."
        return 0
    fi

    log "Instalando paquetes Plymouth..."
    if ! run_quiet apt-get install -y plymouth plymouth-themes; then
        warn "No se pudo instalar Plymouth. Continuando sin pantalla de arranque personalizada."
        return 0
    fi

    local target_theme_dir="/usr/share/plymouth/themes/${PLYMOUTH_THEME_NAME}"
    log "Creando tema de Plymouth: $PLYMOUTH_THEME_NAME"
    mkdir -p "$target_theme_dir"

    # Generar archivos del tema
    cat > "${target_theme_dir}/${PLYMOUTH_THEME_NAME}.plymouth" << EOF
[Plymouth Theme]
Name=${PLYMOUTH_THEME_NAME}
Description=Custom kiosk theme with image
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

fun refresh_callback() {
    # No action
}
Plymouth.SetRefreshFunction(refresh_callback);
EOF

    local target_image="${target_theme_dir}/background.png"
    if [[ "$PLYMOUTH_ASSET_AVAILABLE" == "true" && -f "$PLYMOUTH_IMAGE_PATH" ]]; then
        log "Preparando imagen de Plymouth..."
        if command -v convert &>/dev/null; then
            run_quiet convert "$PLYMOUTH_IMAGE_PATH" -resize 1280x720! "$target_image"
        elif command -v magick &>/dev/null; then
            run_quiet magick "$PLYMOUTH_IMAGE_PATH" -resize 1280x720! "$target_image"
        else
            cp "$PLYMOUTH_IMAGE_PATH" "$target_image"
        fi
    else
        log "No hay imagen Plymouth disponible. Generando un background negro plano..."
        if command -v convert &>/dev/null; then
            run_quiet convert -size 1280x720 xc:black "$target_image"
        else
            warn "No se pudo generar background. El tema Plymouth podria fallar al iniciar."
        fi
    fi

    log "Activando el tema de Plymouth y reconstruyendo initramfs..."
    # plymouth-set-default-theme con -R reconstruye initramfs en Debian
    if ! run_quiet plymouth-set-default-theme -R "$PLYMOUTH_THEME_NAME"; then
        warn "Fallo al usar plymouth-set-default-theme -R. Reconstruyendo initramfs de forma manual..."
        plymouth-set-default-theme "$PLYMOUTH_THEME_NAME" || true
        run_quiet update-initramfs -u -k all || true
    fi
}

configure_grub_silent() {
    local grub_config="/etc/default/grub"
    if [[ ! -f "$grub_config" ]]; then
        log_error "No se encontro el archivo de configuracion de GRUB en $grub_config"
        return 1
    fi

    log "Configurando arranque silencioso de GRUB..."
    local silent_params="quiet loglevel=3 systemd.show_status=false rd.udev.log_priority=3 vt.global_cursor_default=0"
    
    if [[ "$ENABLE_PLYMOUTH" == "true" ]]; then
        silent_params="$silent_params splash"
    fi
    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        silent_params="$silent_params nvidia_drm.modeset=1"
    fi

    cp "$grub_config" "${grub_config}.bak"
    if grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config"; then
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$silent_params\"|" "$grub_config"
    else
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"$silent_params\"" >> "$grub_config"
    fi

    log "Regenerando la configuracion de GRUB..."
    if ! run_quiet update-grub; then
        log_error "Fallo al ejecutar update-grub."
        return 1
    fi
}

install_custom_cursor() {
    if [[ -z "$CURSOR_PATH" || ! -e "$CURSOR_PATH" ]]; then
        warn "No se especifico o no se encontro una ruta valida para el cursor en CURSOR_PATH. Omitiendo..."
        return 0
    fi

    log "Instalando cursor personalizado..."
    mkdir -p /usr/share/icons/default

    if [[ -d "$CURSOR_PATH" ]]; then
        cp -r "$CURSOR_PATH"/* /usr/share/icons/default/
    else
        cp "$CURSOR_PATH" /usr/share/icons/default/
    fi

    cat > /usr/share/icons/default/index.theme << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF

    # Configurar para el usuario kiosk
    local user_home="/home/$KIOSK_USER"
    mkdir -p "$user_home/.icons/default"
    cat > "$user_home/.icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF

    chown -R "$KIOSK_USER:$KIOSK_USER" "$user_home/.icons"
}

hide_system_messages() {
    local user_home="/home/$KIOSK_USER"
    log "Ocultando mensajes del sistema al loguearse..."

    touch "$user_home/.hushlogin"
    chown "$KIOSK_USER:$KIOSK_USER" "$user_home/.hushlogin"

    echo "" > /etc/motd

    # Desactivar visualizacion de estado en systemd
    if [[ -f /etc/systemd/system.conf ]]; then
        if grep -q "^#*ShowStatus=" /etc/systemd/system.conf; then
            sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' /etc/systemd/system.conf
        else
            echo "ShowStatus=no" >> /etc/systemd/system.conf
        fi
    fi

    # Desactivar VTs automaticos de getty
    if [[ -f /etc/systemd/logind.conf ]]; then
        if grep -q "^#*NAutoVTs=" /etc/systemd/logind.conf; then
            sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' /etc/systemd/logind.conf
        else
            echo "NAutoVTs=0" >> /etc/systemd/logind.conf
        fi
    fi
}

install_cage_wrapper() {
    log "Creando el wrapper de inicio /usr/local/bin/run-yarg.sh..."
    mkdir -p /usr/local/bin

    cat > /usr/local/bin/run-yarg.sh <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

echo "run-yarg: iniciado como $(id -un) pid=$$" >&2

YARG_FORCE_SOFTWARE_RENDER="__YARG_FORCE_SOFTWARE_RENDER__"

case "${YARG_FORCE_SOFTWARE_RENDER,,}" in
    true|yes|si|1)
        echo "run-yarg: usando render por software por configuracion" >&2
        export WLR_RENDERER_ALLOW_SOFTWARE=1
        export WLR_NO_HARDWARE_CURSORS=1
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        ;;
esac

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
echo "run-yarg: XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" >&2

dbus_session_is_usable() {
    local dbus_path=""

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        return 1
    fi

    case "$DBUS_SESSION_BUS_ADDRESS" in
        unix:path=*)
            dbus_path="${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
            dbus_path="${dbus_path%%,*}"
            [[ -S "$dbus_path" ]] || return 1
            ;;
    esac

    if command -v dbus-send >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        timeout 1 dbus-send --session --dest=org.freedesktop.DBus \
            --type=method_call / org.freedesktop.DBus.ListNames >/dev/null 2>&1
        return $?
    fi

    return 0
}

if ! dbus_session_is_usable; then
    echo "run-yarg: DBus de sesion ausente o invalido" >&2
    unset DBUS_SESSION_BUS_ADDRESS
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -z "${YARG_DBUS_SESSION_STARTED:-}" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        echo "run-yarg: iniciando DBus de sesion" >&2
        export YARG_DBUS_SESSION_STARTED=1
        exec dbus-run-session -- "$0"
    fi
    echo "Aviso: dbus-run-session no esta disponible; continuando sin DBus de sesion." >&2
fi

echo "run-yarg: DBus=${DBUS_SESSION_BUS_ADDRESS:-sin-dbus}" >&2

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage

# Localizar Xwayland dinamicamente
if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
elif [[ -x /usr/lib/xorg/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/lib/xorg/Xwayland
else
    unset WLR_XWAYLAND
fi

export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
YARG_SCREEN_WIDTH="__YARG_SCREEN_WIDTH__"
YARG_SCREEN_HEIGHT="__YARG_SCREEN_HEIGHT__"

wait_for_path() {
    local path="$1"
    local attempts="${2:-100}"

    for _ in $(seq 1 "$attempts"); do
        [[ -e "$path" ]] && return 0
        sleep 0.1
    done
    return 1
}

wait_for_pulse_sink() {
    local attempts="${1:-50}"

    if ! command -v pactl >/dev/null 2>&1; then
        return 1
    fi

    for _ in $(seq 1 "$attempts"); do
        if command -v timeout >/dev/null 2>&1; then
            if timeout 1 pactl list short sinks 2>/dev/null | grep -q .; then
                return 0
            fi
        elif pactl list short sinks 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 0.1
    done
    return 1
}

wait_for_alsa_default() {
    local attempts="${1:-50}"

    if ! command -v aplay >/dev/null 2>&1; then
        return 1
    fi

    for _ in $(seq 1 "$attempts"); do
        if command -v timeout >/dev/null 2>&1; then
            if timeout 2 aplay -q -D default -t raw -f S16_LE -c 2 -r 48000 -d 1 /dev/zero >/dev/null 2>&1; then
                return 0
            fi
        elif aplay -q -D default -t raw -f S16_LE -c 2 -r 48000 -d 1 /dev/zero >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.2
    done
    return 1
}

# Lanzamiento manual de Pipewire (para evitar conflictos de sesion systemd --user)
if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
    echo "run-yarg: iniciando pipewire" >&2
    pipewire 2>&1 | sed 's/^/[pipewire] /' &
fi

wait_for_path "$XDG_RUNTIME_DIR/pipewire-0" 100 || \
    echo "Aviso: PipeWire no creo $XDG_RUNTIME_DIR/pipewire-0 a tiempo." >&2

if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
    echo "run-yarg: iniciando wireplumber" >&2
    wireplumber 2>&1 | sed 's/^/[wireplumber] /' &
fi

sleep 1

if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
    echo "run-yarg: iniciando pipewire-pulse" >&2
    pipewire-pulse 2>&1 | sed 's/^/[pipewire-pulse] /' &
fi

echo "run-yarg: esperando sink Pulse/PipeWire" >&2
wait_for_pulse_sink 50 || \
    echo "Aviso: no se encontro un sink Pulse/PipeWire antes de iniciar YARG." >&2

echo "run-yarg: esperando ALSA default via PipeWire" >&2
wait_for_alsa_default 50 || \
    echo "Aviso: ALSA default no abrio antes de iniciar YARG." >&2

YARG_BIN=$(find /opt/YARG -maxdepth 1 -type f -name "YARG*" -executable -print -quit 2>/dev/null)

if [[ -n "$YARG_BIN" ]]; then
    echo "Iniciando YARG: $YARG_BIN" >&2
    YARG_ARGS=(-persistent-data-path "__YARG_PERSISTENT_DATA_DIR__")

    if [[ -n "$YARG_SCREEN_WIDTH" && -n "$YARG_SCREEN_HEIGHT" ]]; then
        echo "run-yarg: resolucion YARG ${YARG_SCREEN_WIDTH}x${YARG_SCREEN_HEIGHT}" >&2
        YARG_ARGS+=(
            -screen-width "$YARG_SCREEN_WIDTH"
            -screen-height "$YARG_SCREEN_HEIGHT"
            -screen-fullscreen 1
        )
    fi

    exec /usr/bin/cage -- "$YARG_BIN" "${YARG_ARGS[@]}"
fi

echo "No se encontro YARG en /opt/YARG; abriendo foot." >&2
exec /usr/bin/cage /usr/bin/foot
WRAPPER

    chmod +x /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_PERSISTENT_DATA_DIR__#$YARG_PERSISTENT_DATA_DIR#g" /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_WIDTH__#${YARG_SCREEN_WIDTH:-}#g" /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_HEIGHT__#${YARG_SCREEN_HEIGHT:-}#g" /usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_FORCE_SOFTWARE_RENDER__#${YARG_FORCE_SOFTWARE_RENDER:-false}#g" /usr/local/bin/run-yarg.sh
}

install_cage_service() {
    log "Creando el servicio cage-kiosk.service..."
    local kiosk_uid
    if ! kiosk_uid=$(id -u "$KIOSK_USER"); then
        log_error "No se pudo obtener el UID de $KIOSK_USER."
        return 1
    fi

    # Resolver rutas de comandos del sistema de forma dinamica
    local MKDIR_PATH PKILL_PATH RM_PATH CHOWN_PATH CHMOD_PATH DBUS_SESSION_PATH
    MKDIR_PATH=$(which mkdir || echo "/bin/mkdir")
    PKILL_PATH=$(which pkill || echo "/usr/bin/pkill")
    RM_PATH=$(which rm || echo "/bin/rm")
    CHOWN_PATH=$(which chown || echo "/bin/chown")
    CHMOD_PATH=$(which chmod || echo "/bin/chmod")
    DBUS_SESSION_PATH=$(which dbus-run-session || echo "/usr/bin/dbus-run-session")

    cat > /etc/systemd/system/cage-kiosk.service << EOF
[Unit]
Description=Kiosk YARG con Cage (Debian)
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
ExecStartPre=+$MKDIR_PATH -p /run/user/$kiosk_uid
ExecStartPre=-$PKILL_PATH -u $KIOSK_USER -x pipewire-pulse
ExecStartPre=-$PKILL_PATH -u $KIOSK_USER -x wireplumber
ExecStartPre=-$PKILL_PATH -u $KIOSK_USER -x pipewire
ExecStartPre=-$RM_PATH -f /run/user/$kiosk_uid/pipewire-0 /run/user/$kiosk_uid/pipewire-0.lock /run/user/$kiosk_uid/pulse/native
ExecStartPre=+$CHOWN_PATH $KIOSK_USER:$KIOSK_USER /run/user/$kiosk_uid
ExecStartPre=+$CHMOD_PATH 700 /run/user/$kiosk_uid
ExecStart=$DBUS_SESSION_PATH -- /usr/local/bin/run-yarg.sh
ExecStopPost=-$PKILL_PATH -u $KIOSK_USER -x pipewire-pulse
ExecStopPost=-$PKILL_PATH -u $KIOSK_USER -x wireplumber
ExecStopPost=-$PKILL_PATH -u $KIOSK_USER -x pipewire
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF

    # Habilitar target gráfico por defecto y arrancar el servicio
    log "Habilitando servicio y estableciendo target grafico..."
    systemctl daemon-reload
    systemctl set-default graphical.target
    systemctl enable cage-kiosk.service
}

# Habilitar servicio SSH si corresponde
configure_ssh() {
    if [[ "$ENABLE_SSH" == "true" ]]; then
        log "Instalando y habilitando SSH..."
        if run_quiet apt-get install -y openssh-server; then
            systemctl enable ssh
            systemctl start ssh
            log "SSH habilitado correctamente."
        else
            log_error "Fallo al instalar openssh-server."
        fi
    else
        log "SSH deshabilitado en la configuracion."
    fi
}

main() {
    echo -e "${BLUE}===================================================================${NC}"
    echo -e "${CYAN}        INSTALADOR DEBIAN 13.5 + CAGE + YARG KIOSK${NC}"
    echo -e "${BLUE}===================================================================${NC}"

    validate_environment
    check_network
    ask_initial_questions
    validate_security_config
    preflight_optional_assets

    section "1. Repositorios y dependencias"
    enable_debian_components
    install_debian_packages
    install_gpu_drivers
    configure_multiarch

    section "2. Optimizaciones del sistema"
    create_kiosk_user
    configure_performance_and_limits
    configure_hid_access
    configure_samba_share

    section "3. Instalacion de YARG"
    resolve_yarg_download_url
    install_yarg
    configure_yarg_default_settings
    install_yarg_update_script
    install_yarg_song_download_script

    section "4. Configuracion de Cage y Visuales"
    install_custom_cursor
    configure_plymouth
    configure_grub_silent
    hide_system_messages
    install_cage_wrapper
    install_cage_service
    configure_ssh

    section "Instalacion finalizada"
    echo ""
    echo -e "${GREEN}===================================================================${NC}"
    echo -e "${GREEN}  ¡KIOSKO YARG CON CAGE INSTALADO EXITOSAMENTE!${NC}"
    echo -e "${GREEN}===================================================================${NC}"
    echo ""
    echo "El sistema ha sido configurado para arrancar directamente en YARG."
    echo "Puede reiniciar para aplicar todos los cambios ejecutando: reboot"
    echo ""
    echo -e "${BLUE}===================================================================${NC}"
}

main "$@"
