#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# RPCS3: descarga del AppImage, firmware, Samba, wrapper de arranque directo,
# menu de mantenimiento, servicio systemd y updater para el camino Cage/RPCS3.
#
# El AppImage se extrae a /opt/RPCS3 (no requiere FUSE). El wrapper lanza el
# juego (por defecto Rock Band 3) con `rpcs3 --no-gui`; si no encuentra el
# juego abre la GUI de RPCS3 para la configuracion inicial.

# rpcs3_render PLANTILLA CLAVE=valor...
# Sustituye __CLAVE__ por valor en PLANTILLA y la imprime. Evita sed para que
# los valores puedan contener /, #, & o \ sin escapes.
rpcs3_render() {
    local out="$1"
    local pair

    shift
    for pair in "$@"; do
        # Reemplazo entre comillas: en Bash 5.2 un & sin citar se expande al patron.
        out="${out//"__${pair%%=*}__"/"${pair#*=}"}"
    done

    printf '%s\n' "$out"
}

# Busca el primer asset cuyo nombre coincide con $2 en el JSON de release $1.
rpcs3_pick_asset_url() {
    local release_json="$1"
    local asset_regex="$2"

    printf '%s\n' "$release_json" \
        | grep -E '"browser_download_url":' \
        | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
        | grep -Ei "$asset_regex" \
        | head -n 1 || true
}

resolve_rpcs3_download_url() {
    local release_json release_url

    if [[ -n "${RPCS3_URL:-}" ]]; then
        log "Se usara RPCS3 desde RPCS3_URL: $RPCS3_URL"
        return 0
    fi

    log "Resolviendo URL del AppImage mas reciente de RPCS3"
    if ! release_json=$(curl -fsSL "$RPCS3_API_URL"); then
        log_error "Fallo al consultar $RPCS3_API_URL"
        return 1
    fi

    release_url=$(rpcs3_pick_asset_url "$release_json" "$RPCS3_ASSET_REGEX")
    if [[ -z "$release_url" ]]; then
        log_error "No se encontro un AppImage de Linux en el ultimo release de RPCS3"
        return 1
    fi

    RPCS3_URL="$release_url"
    log "RPCS3 seleccionado: $RPCS3_URL"
}

install_rpcs3_dependencies() {
    log "Instalando dependencias de RPCS3 y reafirmando ALSA hacia PipeWire"

    ensure_pacman_download_user || return 1
    repair_chroot_ca_certificates || return 1

    # libusb/libevdev: instrumentos y mandos; openal/alsa-plugins: audio.
    if ! run_quiet arch-chroot /mnt pacman -S --needed --noconfirm \
        libusb libevdev openal alsa-plugins pipewire-alsa pulsemixer; then
        log_error "Fallo al instalar dependencias de RPCS3"
        return 1
    fi

    cat > /mnt/etc/asound.conf << 'EOF'
pcm.!default {
    type pipewire
}

ctl.!default {
    type pipewire
}
EOF
}

# rpcs3_unsquash_appimage APPIMAGE DESTINO
# Extrae un AppImage tipo 2 sin ejecutarlo ni usar FUSE. Los AppImage nuevos
# de RPCS3 (uruntime) traen una imagen DwarFS; los clasicos, un squashfs que
# empieza justo despues del runtime ELF (fin de la tabla de secciones).
rpcs3_unsquash_appimage() {
    local image="$1" dest="$2"
    local shoff shentsize shnum offset

    rm -rf "$dest"
    mkdir -p "$dest"

    # dwarfs no esta en los repos de Arch: se usa el binario estatico oficial.
    local dwarfs_bin="/tmp/dwarfs-universal"
    if run_quiet curl -fL --retry 3 --retry-delay 2 -o "$dwarfs_bin" \
        "${DWARFS_UNIVERSAL_URL:-https://github.com/mhx/dwarfs/releases/download/v0.15.8/dwarfs-universal-0.15.8-Linux-x86_64}"; then
        chmod +x "$dwarfs_bin"
        if run_quiet "$dwarfs_bin" --tool=dwarfsextract -i "$image" -O auto -o "$dest" \
            && [[ -x "$dest/AppRun" ]]; then
            return 0
        fi
    fi

    command -v unsquashfs >/dev/null 2>&1 \
        || run_quiet pacman -Sy --noconfirm --needed squashfs-tools || return 1

    shoff=$(od -An -t u8 -j 40 -N 8 "$image" | tr -d ' ')
    shentsize=$(od -An -t u2 -j 58 -N 2 "$image" | tr -d ' ')
    shnum=$(od -An -t u2 -j 60 -N 2 "$image" | tr -d ' ')
    [[ -n "$shoff" && -n "$shentsize" && -n "$shnum" ]] || return 1
    offset=$((shoff + shentsize * shnum))

    rm -rf "$dest"
    run_quiet unsquashfs -f -q -o "$offset" -d "$dest" "$image" || return 1
    [[ -x "$dest/AppRun" ]]
}

install_rpcs3() {
    log "Descargando e instalando RPCS3 en /opt/RPCS3"

    local appimage="/mnt/root/RPCS3.AppImage"
    local chroot_appimage="/root/RPCS3.AppImage"

    mkdir -p /mnt/root /mnt/opt

    if ! run_quiet curl -fL --retry 3 --retry-delay 2 -o "$appimage" "$RPCS3_URL"; then
        log_error "Fallo al descargar RPCS3"
        return 1
    fi

    if [[ ! -s "$appimage" ]]; then
        log_error "La descarga de RPCS3 quedo vacia en $appimage"
        return 1
    fi

    # --appimage-extract no necesita FUSE; crea ./squashfs-root.
    chmod +x "$appimage"
    rm -rf /mnt/opt/RPCS3 /mnt/opt/RPCS3.new

    # Primero dentro del chroot; si el runtime del AppImage falla ahi (p. ej.
    # por falta de /dev, /proc o espacio), se reintenta desde el sistema live,
    # que tiene un entorno completo, extrayendo directo sobre /mnt/opt.
    if ! run_quiet arch-chroot /mnt bash -c \
        'set -e; mkdir -p /opt/RPCS3.new; cd /opt/RPCS3.new; "$1" --appimage-extract >/dev/null; mv squashfs-root /opt/RPCS3; cd /; rmdir /opt/RPCS3.new' \
        _ "$chroot_appimage"; then
        # Los AppImage con runtime nuevo (uruntime) intentan FUSE incluso con
        # --appimage-extract y fallan en el chroot. Se lee el squashfs directo.
        warn "Fallo --appimage-extract; extrayendo la imagen sin FUSE"
        rm -rf /mnt/opt/RPCS3 /mnt/opt/RPCS3.new
        if ! rpcs3_unsquash_appimage "$appimage" /mnt/opt/RPCS3; then
            log_error "Fallo al extraer el AppImage de RPCS3 (revise ${LOG_FILE:-el log de instalacion})"
            return 1
        fi
    fi

    if ! arch-chroot /mnt test -x /opt/RPCS3/AppRun; then
        log_error "No se encontro /opt/RPCS3/AppRun tras extraer el AppImage"
        return 1
    fi

    run_quiet arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" /opt/RPCS3
    rm -f "$appimage"
}

# Descarga el firmware oficial de PS3 al home del usuario. Es opcional: si falla
# solo se avisa; se instala una vez desde RPCS3 (File > Install Firmware).
download_rpcs3_firmware() {
    if [[ "${RPCS3_DOWNLOAD_FIRMWARE:-true}" != "true" ]]; then
        log "Descarga de firmware omitida (RPCS3_DOWNLOAD_FIRMWARE=false)"
        return 0
    fi

    local target="/mnt/home/$KIOSK_USER/PS3UPDAT.PUP"

    log "Descargando firmware de PS3 en /home/$KIOSK_USER/PS3UPDAT.PUP"
    mkdir -p "/mnt/home/$KIOSK_USER"

    if ! run_quiet curl -fL --retry 3 --retry-delay 2 -o "$target" "$RPCS3_FIRMWARE_URL" || [[ ! -s "$target" ]]; then
        rm -f "$target"
        warn "No se pudo descargar el firmware desde $RPCS3_FIRMWARE_URL; descargalo manualmente desde playstation.com."
        return 0
    fi

    run_quiet arch-chroot /mnt chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/PS3UPDAT.PUP"
}

# Descarga la ultima build de Rock Band 3 Deluxe para PS3 al home del usuario.
# Es opcional: si falla solo se avisa; el paquete se instala despues desde RPCS3.
download_rb3dx() {
    if [[ "${RB3DX_DOWNLOAD:-true}" != "true" ]]; then
        log "Descarga de RB3DX omitida (RB3DX_DOWNLOAD=false)"
        return 0
    fi

    local target="/mnt/home/$KIOSK_USER/RB3DX-PS3.zip"

    log "Descargando Rock Band 3 Deluxe (PS3) en /home/$KIOSK_USER/RB3DX-PS3.zip"
    mkdir -p "/mnt/home/$KIOSK_USER"

    if ! run_quiet curl -fL --retry 3 --retry-delay 2 -o "$target" "$RB3DX_URL" || [[ ! -s "$target" ]]; then
        rm -f "$target"
        warn "No se pudo descargar RB3DX desde $RB3DX_URL; descargalo manualmente desde https://rb3dx.milohax.org/downloads/"
        return 0
    fi

    run_quiet arch-chroot /mnt chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/RB3DX-PS3.zip"
}

# Descarga los tres perfiles de configuracion de RB3DX de la guia de MiloHax
# (recommended, minimum y potato) al home del usuario, sin descomprimirlos: se
# instala uno desde el primer arranque, al configurar el juego. Cada zip trae
# config/custom_configs/config_BLUS30463.yml y dx_high_memory.dta. En Linux el
# perfil va en ~/.config/rpcs3/custom_configs/ (no en config/custom_configs/,
# que es la ruta de Windows y RPCS3 no lee aqui). Es opcional: si falla solo se avisa.
download_rb3dx_config_profiles() {
    if [[ "${RB3DX_DOWNLOAD_CONFIGS:-true}" != "true" ]]; then
        log "Descarga de perfiles de RB3DX omitida (RB3DX_DOWNLOAD_CONFIGS=false)"
        return 0
    fi

    local profile target

    mkdir -p "/mnt/home/$KIOSK_USER"

    for profile in recommended minimum potato; do
        target="/mnt/home/$KIOSK_USER/RB3DX-config-$profile.zip"
        log "Descargando perfil de configuracion de RB3DX: $profile"

        if ! run_quiet curl -fL --retry 3 --retry-delay 2 -o "$target" "${RB3DX_CONFIG_BASE_URL%/}/$profile.zip" || [[ ! -s "$target" ]]; then
            rm -f "$target"
            warn "No se pudo descargar el perfil $profile; descargalo desde https://guides.milohax.org/en/rb3pc/intro/quickconfig/"
            continue
        fi

        run_quiet arch-chroot /mnt chown "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/RB3DX-config-$profile.zip"
    done
}


configure_rpcs3_games_dir() {
    log "Creando carpeta de juegos de RPCS3: $RPCS3_GAMES_DIR"

    mkdir -p "/mnt${RPCS3_GAMES_DIR}"
    if ! arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$RPCS3_GAMES_DIR" "/home/$KIOSK_USER"; then
        log_error "Fallo al asignar permisos de la carpeta de juegos de RPCS3"
        return 1
    fi
}

configure_rpcs3_samba_share() {
    local games_dir="$RPCS3_GAMES_DIR"
    local smb_conf="/mnt/etc/samba/smb.conf"

    log "Configurando Samba para compartir los juegos de RPCS3"

    mkdir -p /mnt/etc/samba /mnt/var/log/samba "/mnt${games_dir}"
    run_quiet arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$games_dir"
    run_quiet arch-chroot /mnt chmod 775 "$games_dir"

    if [[ ! -f "$smb_conf" ]] || ! grep -q '^\[global\]' "$smb_conf"; then
        cat > "$smb_conf" << EOF
[global]
   workgroup = WORKGROUP
   server string = RPCS3 Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/samba/%m.log
   max log size = 50
EOF
    fi

    if ! grep -q '^\[RPCS3-Games\]' "$smb_conf"; then
        cat >> "$smb_conf" << EOF

[RPCS3-Games]
   path = $games_dir
   writable = yes
   browsable = yes
   guest ok = yes
   create mask = 0775
   directory mask = 0775
   force user = $KIOSK_USER
EOF
    fi

    if ! run_quiet arch-chroot /mnt systemctl enable smb.service nmb.service; then
        log_error "Fallo al habilitar servicios Samba"
        return 1
    fi

    if ! printf '%s\n%s\n' "$KIOSK_PASSWORD" "$KIOSK_PASSWORD" | arch-chroot /mnt smbpasswd -s -a "$KIOSK_USER"; then
        log_error "Fallo al registrar $KIOSK_USER en Samba"
        return 1
    fi
}

# Elige por que salida suena RPCS3 (RPCS3_AUDIO_OUTPUT): hdmi/dp (por defecto),
# analog o auto (deja la eleccion de WirePlumber). Se logra subiendo la
# prioridad de los sinks HDMI/DP o analogicos con una regla de WirePlumber en
# el home del usuario; si el dispositivo preferido no existe, WirePlumber cae
# solo al otro. El wrapper arranca wireplumber como el usuario, asi que toma
# ~/.config/wireplumber/wireplumber.conf.d/.
configure_rpcs3_audio_output() {
    local output="${RPCS3_AUDIO_OUTPUT:-hdmi}"
    local conf_dir="/mnt/home/$KIOSK_USER/.config/wireplumber/wireplumber.conf.d"
    local pattern

    case "${output,,}" in
        hdmi|dp)
            pattern='~alsa_output.*hdmi.*'
            ;;
        analog)
            pattern='~alsa_output.*analog.*'
            ;;
        auto)
            log "Salida de audio automatica (RPCS3_AUDIO_OUTPUT=auto)"
            return 0
            ;;
        *)
            warn "RPCS3_AUDIO_OUTPUT invalido: $output; se deja la salida automatica."
            return 0
            ;;
    esac

    log "Priorizando la salida de audio: ${output,,}"
    mkdir -p "$conf_dir"

    cat > "$conf_dir/51-rpcs3-audio-output.conf" << EOF_CONF
monitor.alsa.rules = [
  {
    matches = [ { node.name = "$pattern" } ]
    actions = { update-props = { priority.session = 3000, priority.driver = 3000 } }
  }
]
EOF_CONF

    run_quiet arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.config"
}

configure_rpcs3_performance() {
    log "Aplicando optimizaciones de rendimiento para RPCS3"

    mkdir -p /mnt/etc/security/limits.d /mnt/etc/sysctl.d /mnt/etc/default

    cat > /mnt/etc/security/limits.d/99-rpcs3.conf << EOF
$KIOSK_USER - rtprio 99
$KIOSK_USER - memlock unlimited
$KIOSK_USER - nice -20
EOF

    echo 'vm.swappiness=10' > /mnt/etc/sysctl.d/99-rpcs3.conf
    # RPCS3 abre muchos mapeos de memoria (PPU/SPU); el default de Linux no alcanza.
    echo 'vm.max_map_count=2147483642' >> /mnt/etc/sysctl.d/99-rpcs3.conf

    cat > /mnt/etc/default/cpupower << 'EOF'
governor='performance'
min_freq=''
max_freq=''
EOF

    if ! run_quiet arch-chroot /mnt systemctl enable cpupower.service; then
        log_error "Fallo al habilitar cpupower.service"
        return 1
    fi
}

# ---------------------------------------------------------------------------
# Plantillas
# ---------------------------------------------------------------------------

read -r -d '' RPCS3_UPDATE_TEMPLATE <<'TEMPLATE' || true
#!/usr/bin/env bash
set -euo pipefail

RPCS3_URL="__RPCS3_URL__"
RPCS3_API_URL="__RPCS3_API_URL__"
RPCS3_ASSET_REGEX='__RPCS3_ASSET_REGEX__'
INSTALL_DIR="/opt/RPCS3"
OWNER="__OWNER__"

if [[ ${EUID} -ne 0 ]]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi

WORK_DIR="$(mktemp -d /var/tmp/update-rpcs3.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Resolviendo latest desde $RPCS3_API_URL"
RELEASE_JSON="$(curl -fsSL "$RPCS3_API_URL")"
LATEST_URL="$(printf '%s\n' "$RELEASE_JSON" \
    | grep -E '"browser_download_url":' \
    | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
    | grep -Ei "$RPCS3_ASSET_REGEX" \
    | head -n 1 || true)"

if [[ -z "$LATEST_URL" ]]; then
    echo "No se encontro un AppImage de Linux en el ultimo release; se usa $RPCS3_URL" >&2
    LATEST_URL="$RPCS3_URL"
fi

echo "Descargando RPCS3 desde: $LATEST_URL"
curl -fL --retry 3 --retry-delay 2 -o "$WORK_DIR/RPCS3.AppImage" "$LATEST_URL"
chmod +x "$WORK_DIR/RPCS3.AppImage"

# Se extrae primero y solo se reemplaza la instalacion si la extraccion salio bien.
(cd "$WORK_DIR" && ./RPCS3.AppImage --appimage-extract >/dev/null) || true
if [[ ! -x "$WORK_DIR/squashfs-root/AppRun" ]]; then
    # Runtime nuevo sin FUSE disponible: se lee la imagen directo (DwarFS en
    # los AppImage actuales; squashfs en los clasicos).
    img="$WORK_DIR/RPCS3.AppImage"
    rm -rf "$WORK_DIR/squashfs-root"
    mkdir -p "$WORK_DIR/squashfs-root"
    # dwarfs no esta en los repos de Arch: se usa el binario estatico oficial.
    DWARFS_BIN="$WORK_DIR/dwarfs-universal"
    if curl -fL --retry 3 --retry-delay 2 -o "$DWARFS_BIN" \
        "https://github.com/mhx/dwarfs/releases/download/v0.15.8/dwarfs-universal-0.15.8-Linux-x86_64"; then
        chmod +x "$DWARFS_BIN"
        "$DWARFS_BIN" --tool=dwarfsextract -i "$img" -O auto -o "$WORK_DIR/squashfs-root" || true
    fi
    if [[ ! -x "$WORK_DIR/squashfs-root/AppRun" ]]; then
        command -v unsquashfs >/dev/null 2>&1 || pacman -Sy --noconfirm --needed squashfs-tools
        shoff=$(od -An -t u8 -j 40 -N 8 "$img" | tr -d ' ')
        shentsize=$(od -An -t u2 -j 58 -N 2 "$img" | tr -d ' ')
        shnum=$(od -An -t u2 -j 60 -N 2 "$img" | tr -d ' ')
        rm -rf "$WORK_DIR/squashfs-root"
        unsquashfs -f -q -o "$((shoff + shentsize * shnum))" -d "$WORK_DIR/squashfs-root" "$img" || true
    fi
fi
if [[ ! -x "$WORK_DIR/squashfs-root/AppRun" ]]; then
    echo "El AppImage descargado no contiene AppRun; no se modifica $INSTALL_DIR." >&2
    exit 1
fi

rm -rf "$INSTALL_DIR.old"
[[ -d "$INSTALL_DIR" ]] && mv "$INSTALL_DIR" "$INSTALL_DIR.old"
mv "$WORK_DIR/squashfs-root" "$INSTALL_DIR"
chown -R "$OWNER:$OWNER" "$INSTALL_DIR"
rm -rf "$INSTALL_DIR.old"

echo "RPCS3 actualizado en $INSTALL_DIR"
TEMPLATE

read -r -d '' RPCS3_MENU_TEMPLATE <<'TEMPLATE' || true
#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"
GUI_FLAG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/rpcs3-open-gui"

pause_menu() {
    echo ""
    read -r -p "Presione Enter para volver al menu..."
}

show_hostname() {
    if command -v hostname >/dev/null 2>&1; then
        hostname
    elif [[ -r /etc/hostname ]]; then
        cat /etc/hostname
    else
        echo "desconocido"
    fi
}

show_hostname_ips() {
    if command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null || true
    elif command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' '
        echo ""
    fi
}

show_ip_addresses() {
    clear
    echo "Direcciones IP"
    echo "=============="
    echo ""
    if command -v ip >/dev/null 2>&1; then
        ip -br addr show scope global || true
    fi
    echo ""
    echo "Hostname: $(show_hostname)"
    echo "IPs: $(show_hostname_ips)"
    echo "Juegos por red: \\\\$(show_hostname)\\RPCS3-Games"
    pause_menu
}

open_shell() {
    clear
    echo "Shell de mantenimiento"
    echo "Escriba 'exit' para volver al menu."
    echo ""
    "${SHELL:-/bin/bash}"
}

update_rpcs3() {
    clear
    echo "Actualizar RPCS3"
    echo "================"
    echo ""

    if [[ ! -x /usr/local/bin/update-rpcs3 ]]; then
        echo "No se encontro /usr/local/bin/update-rpcs3."
        pause_menu
        return
    fi

    if sudo /usr/local/bin/update-rpcs3; then
        echo ""
        echo "Actualizacion completada."
    else
        echo ""
        echo "La actualizacion fallo. Revisa journalctl -u cage-kiosk.service -b."
    fi

    pause_menu
}

while true; do
    clear
    cat <<'EOF'
Menu de mantenimiento RPCS3
===========================

1) Configurar sonido
2) Configurar WiFi
3) Ver direccion IP
4) Salir a Shell
5) Volver al juego
6) Abrir RPCS3 (configuracion, firmware, juegos y controles)
7) Actualizar RPCS3
8) Reiniciar Kiosko
9) Apagar Kiosko

EOF

    read -r -p "Seleccione una opcion: " option

    case "$option" in
        1)
            if command -v pulsemixer >/dev/null 2>&1; then
                pulsemixer || true
            else
                echo "pulsemixer no esta instalado."
                pause_menu
            fi
            ;;
        2)
            if command -v nmtui >/dev/null 2>&1; then
                nmtui || true
            else
                echo "nmtui no esta disponible."
                pause_menu
            fi
            ;;
        3)
            show_ip_addresses
            ;;
        4)
            open_shell
            ;;
        5)
            exit 0
            ;;
        6)
            # El wrapper ve este archivo al salir del menu y abre la GUI de RPCS3.
            touch "$GUI_FLAG"
            exit 0
            ;;
        7)
            update_rpcs3
            ;;
        8)
            echo "Reiniciando servicio cage-kiosk..."
            sudo systemctl restart cage-kiosk.service
            exit 0
            ;;
        9)
            echo "Apagando kiosko..."
            sudo systemctl poweroff
            exit 0
            ;;
        *)
            echo "Opcion invalida."
            sleep 1
            ;;
    esac
done
TEMPLATE

read -r -d '' RPCS3_WRAPPER_TEMPLATE <<'TEMPLATE' || true
#!/usr/bin/env bash
set -euo pipefail

echo "run-rpcs3: iniciado como $(id -un) pid=$$" >&2

RPCS3_GAMES_DIR="__RPCS3_GAMES_DIR__"
RPCS3_GAME_PATH="__RPCS3_GAME_PATH__"
RPCS3_GAME_MATCH="__RPCS3_GAME_MATCH__"
RPCS3_EXIT_MENU="__RPCS3_EXIT_MENU__"
RPCS3_QT_PLATFORM="__RPCS3_QT_PLATFORM__"
RPCS3_AUDIO_VOLUME="__RPCS3_AUDIO_VOLUME__"

export HOME="${HOME:-__RPCS3_HOME__}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"

RPCS3_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/rpcs3"
GUI_FLAG="$XDG_RUNTIME_DIR/rpcs3-open-gui"

if [[ -n "$RPCS3_QT_PLATFORM" ]]; then
    export QT_QPA_PLATFORM="$RPCS3_QT_PLATFORM"
fi

if [[ -d /usr/share/icons/MiniArchPick ]]; then
    export XCURSOR_THEME=MiniArchPick
    export XCURSOR_SIZE=64
fi
if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
else
    unset WLR_XWAYLAND
fi

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
    echo "run-rpcs3: DBus de sesion ausente o invalido" >&2
    unset DBUS_SESSION_BUS_ADDRESS
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -z "${RPCS3_DBUS_SESSION_STARTED:-}" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        echo "run-rpcs3: iniciando DBus de sesion" >&2
        export RPCS3_DBUS_SESSION_STARTED=1
        exec dbus-run-session -- "$0"
    fi
fi

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
            timeout 1 pactl list short sinks 2>/dev/null | grep -q . && return 0
        elif pactl list short sinks 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 0.1
    done

    return 1
}

start_audio() {
    if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
        echo "run-rpcs3: iniciando pipewire" >&2
        pipewire 2>&1 | sed 's/^/[pipewire] /' &
    fi

    wait_for_path "$XDG_RUNTIME_DIR/pipewire-0" 100 || \
        echo "Aviso: PipeWire no creo $XDG_RUNTIME_DIR/pipewire-0 a tiempo." >&2

    if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
        echo "run-rpcs3: iniciando wireplumber" >&2
        wireplumber 2>&1 | sed 's/^/[wireplumber] /' &
    fi

    sleep 1

    if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
        echo "run-rpcs3: iniciando pipewire-pulse" >&2
        pipewire-pulse 2>&1 | sed 's/^/[pipewire-pulse] /' &
    fi

    echo "run-rpcs3: esperando sink Pulse/PipeWire" >&2
    wait_for_pulse_sink 50 || \
        echo "Aviso: no se encontro un sink Pulse/PipeWire antes de iniciar RPCS3." >&2

    # WirePlumber recuerda un volumen bajo (40 %) en algunos equipos; se fija el
    # volumen de la salida por defecto y se quita el silencio.
    if [[ -n "$RPCS3_AUDIO_VOLUME" ]] && command -v wpctl >/dev/null 2>&1; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null 2>&1 || true
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$RPCS3_AUDIO_VOLUME" >/dev/null 2>&1 || true
    fi
}

find_rpcs3_bin() {
    if [[ -x /opt/RPCS3/AppRun ]]; then
        echo /opt/RPCS3/AppRun
    elif [[ -x /opt/RPCS3/usr/bin/rpcs3 ]]; then
        echo /opt/RPCS3/usr/bin/rpcs3
    fi
}

# Imprime lo que hay que pasarle a rpcs3 para lanzar el juego. Si
# RPCS3_GAME_PATH esta definida se usa tal cual; si no se busca, en orden:
#   1. Un .iso en la carpeta de juegos cuyo nombre contiene RPCS3_GAME_MATCH.
#   2. Un juego en carpeta (<juego>/PS3_GAME) en la carpeta de juegos o en
#      dev_hdd0/disc (volcados agregados desde la GUI), por el titulo del
#      PARAM.SFO.
#   3. Un juego instalado en dev_hdd0/game (solo si no hay disco: un paquete
#      de actualizacion como RB3DX tambien esta ahi y no arranca solo).
find_game() {
    local iso base sfo game_dir eboot pass
    local -a roots

    if [[ -n "$RPCS3_GAME_PATH" ]]; then
        [[ -e "$RPCS3_GAME_PATH" ]] && echo "$RPCS3_GAME_PATH"
        return 0
    fi

    while IFS= read -r iso; do
        base="${iso##*/}"
        if [[ "${base,,}" == *"${RPCS3_GAME_MATCH,,}"* ]]; then
            echo "$iso"
            return 0
        fi
    done < <(find "$RPCS3_GAMES_DIR" -maxdepth 2 -type f -iname '*.iso' 2>/dev/null | sort)

    for pass in disc installed; do
        if [[ "$pass" == "disc" ]]; then
            roots=("$RPCS3_GAMES_DIR" "$RPCS3_CONFIG_DIR/dev_hdd0/disc")
        else
            roots=("$RPCS3_CONFIG_DIR/dev_hdd0/game")
        fi

        while IFS= read -r sfo; do
            if grep -aqi -- "$RPCS3_GAME_MATCH" "$sfo" 2>/dev/null; then
                game_dir="$(dirname "$sfo")"
                eboot="$game_dir/USRDIR/EBOOT.BIN"
                if [[ -f "$eboot" ]]; then
                    echo "$eboot"
                    return 0
                fi
            fi
        done < <(find "${roots[@]}" -maxdepth 4 -name PARAM.SFO 2>/dev/null)
    done

    return 0
}

start_audio

while true; do
    RPCS3_BIN="$(find_rpcs3_bin)"
    open_gui=false

    if [[ -z "$RPCS3_BIN" ]]; then
        echo "No se encontro RPCS3 en /opt/RPCS3; abriendo menu de mantenimiento." >&2
    else
        GAME="$(find_game)"

        if [[ -f "$GUI_FLAG" ]]; then
            rm -f "$GUI_FLAG"
            open_gui=true
        elif [[ -z "$GAME" ]]; then
            echo "run-rpcs3: no se encontro el juego (\"$RPCS3_GAME_MATCH\"); abriendo la GUI de RPCS3 para configurarlo." >&2
            open_gui=true
        fi

        if [[ "$open_gui" == "true" ]]; then
            echo "Iniciando RPCS3 (GUI): $RPCS3_BIN" >&2
            /usr/bin/cage -- "$RPCS3_BIN" || \
                echo "Aviso: RPCS3/Cage termino con codigo $?" >&2
        else
            echo "Iniciando juego: $GAME" >&2
            /usr/bin/cage -- "$RPCS3_BIN" --no-gui "$GAME" || \
                echo "Aviso: RPCS3/Cage termino con codigo $?" >&2
        fi
    fi

    case "${RPCS3_EXIT_MENU,,}" in
        restart|relaunch|volver|rpcs3)
            echo "run-rpcs3: relanzando automaticamente" >&2
            sleep 1
            continue
            ;;
        never|off|false|no)
            echo "run-rpcs3: menu deshabilitado; saliendo" >&2
            exit 0
            ;;
    esac

    echo "run-rpcs3: abriendo menu de mantenimiento" >&2
    /usr/bin/cage -- /usr/bin/foot /usr/local/bin/kiosk-menu.sh || \
        echo "Aviso: menu de mantenimiento termino con codigo $?" >&2
done
TEMPLATE

install_rpcs3_update_script() {
    log "Instalando updater /usr/local/bin/update-rpcs3"

    mkdir -p /mnt/usr/local/bin
    rpcs3_render "$RPCS3_UPDATE_TEMPLATE" \
        "RPCS3_URL=$RPCS3_URL" \
        "RPCS3_API_URL=$RPCS3_API_URL" \
        "RPCS3_ASSET_REGEX=$RPCS3_ASSET_REGEX" \
        "OWNER=$KIOSK_USER" > /mnt/usr/local/bin/update-rpcs3
    chmod +x /mnt/usr/local/bin/update-rpcs3
}

install_rpcs3_cage_wrapper() {
    log "Creando menu de mantenimiento y wrapper /usr/local/bin/run-rpcs3.sh"

    mkdir -p /mnt/usr/local/bin

    printf '%s\n' "$RPCS3_MENU_TEMPLATE" > /mnt/usr/local/bin/kiosk-menu.sh
    chmod +x /mnt/usr/local/bin/kiosk-menu.sh

    rpcs3_render "$RPCS3_WRAPPER_TEMPLATE" \
        "RPCS3_GAMES_DIR=$RPCS3_GAMES_DIR" \
        "RPCS3_GAME_PATH=${RPCS3_GAME_PATH:-}" \
        "RPCS3_GAME_MATCH=$RPCS3_GAME_MATCH" \
        "RPCS3_EXIT_MENU=${RPCS3_EXIT_MENU:-always}" \
        "RPCS3_QT_PLATFORM=${RPCS3_QT_PLATFORM:-}" \
        "RPCS3_AUDIO_VOLUME=${RPCS3_AUDIO_VOLUME:-}" \
        "RPCS3_HOME=/home/$KIOSK_USER" > /mnt/usr/local/bin/run-rpcs3.sh
    chmod +x /mnt/usr/local/bin/run-rpcs3.sh
}

install_rpcs3_cage_service() {
    log "Creando servicio systemd cage-kiosk.service para RPCS3"

    local kiosk_uid
    if ! kiosk_uid=$(arch-chroot /mnt id -u "$KIOSK_USER"); then
        log_error "No se pudo resolver UID de $KIOSK_USER para cage-kiosk.service"
        return 1
    fi

    cat > /mnt/etc/systemd/system/cage-kiosk.service << EOF
[Unit]
Description=Kiosk RPCS3 con Cage
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
# RPCS3 pide fijar RLIMIT_MEMLOCK a 2 GiB; no depender de pam_limits.
LimitMEMLOCK=infinity
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$kiosk_uid
ExecStartPre=+/usr/bin/mkdir -p /run/user/$kiosk_uid
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire-pulse
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x wireplumber
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire
ExecStartPre=-/usr/bin/rm -f /run/user/$kiosk_uid/pipewire-0 /run/user/$kiosk_uid/pipewire-0.lock /run/user/$kiosk_uid/pulse/native
ExecStartPre=+/usr/bin/chown $KIOSK_USER:$KIOSK_USER /run/user/$kiosk_uid
ExecStartPre=+/usr/bin/chmod 700 /run/user/$kiosk_uid
ExecStart=/usr/bin/dbus-run-session -- /usr/local/bin/run-rpcs3.sh
ExecStopPost=-/usr/bin/pkill -u $KIOSK_USER -x pipewire-pulse
ExecStopPost=-/usr/bin/pkill -u $KIOSK_USER -x wireplumber
ExecStopPost=-/usr/bin/pkill -u $KIOSK_USER -x pipewire
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
