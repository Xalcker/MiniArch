#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Clone Hero download, configuration, Samba and updater helpers.

resolve_clonehero_download_url() {
    local api_url asset_regex release_json release_url

    if [[ "$CLONEHERO_RELEASE_CHANNEL" != "latest" ]]; then
        return 0
    fi

    api_url="$CLONEHERO_API_URL"
    asset_regex="$CLONEHERO_ASSET_REGEX"

    log "Resolviendo URL del release mas reciente de Clone Hero"
    if ! release_json=$(curl -fsSL "$api_url"); then
        log_error "Fallo al consultar $api_url"
        return 1
    fi

    release_url=$(printf '%s\n' "$release_json" \
        | grep -E '"browser_download_url":' \
        | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
        | grep -Ei "$asset_regex" \
        | head -n 1 || true)

    if [[ -z "$release_url" ]]; then
        release_url=$(printf '%s\n' "$release_json" \
            | grep -E '"browser_download_url":' \
            | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
            | grep -Ei 'linux.*\.(zip|tar\.xz|tar\.gz|appimage)$' \
            | head -n 1 || true)
    fi

    if [[ -z "$release_url" ]]; then
        log_error "No se encontro asset Linux para Clone Hero en el ultimo release"
        return 1
    fi

    CLONEHERO_URL="$release_url"
    log "Clone Hero seleccionado: $CLONEHERO_URL"
}

install_clonehero() {
    log "Descargando e instalando Clone Hero en /opt/CloneHero"

    local package_file="/mnt/root/CloneHero.download"
    local chroot_package_file="/root/CloneHero.download"

    mkdir -p /mnt/root /mnt/opt/CloneHero

    if ! run_quiet curl -fL --retry 3 --retry-delay 2 -o "$package_file" "$CLONEHERO_URL"; then
        log_error "Fallo al descargar Clone Hero"
        return 1
    fi

    if [[ ! -s "$package_file" ]]; then
        log_error "La descarga de Clone Hero quedo vacia en $package_file"
        return 1
    fi

    if ! arch-chroot /mnt test -s "$chroot_package_file"; then
        log_error "El paquete de Clone Hero no existe dentro del chroot"
        return 1
    fi

    run_quiet arch-chroot /mnt rm -rf /opt/CloneHero/.new
    run_quiet arch-chroot /mnt mkdir -p /opt/CloneHero/.new

    case "${CLONEHERO_URL,,}" in
        *.zip)
            if ! arch-chroot /mnt unzip -tq "$chroot_package_file" >/dev/null; then
                log_error "El ZIP descargado de Clone Hero no es valido"
                return 1
            fi
            if ! run_quiet arch-chroot /mnt unzip -o "$chroot_package_file" -d /opt/CloneHero/.new; then
                log_error "Fallo al descomprimir Clone Hero"
                return 1
            fi
            ;;
        *.tar.xz|*.txz|*.tar.gz|*.tgz)
            if ! run_quiet arch-chroot /mnt tar -xf "$chroot_package_file" -C /opt/CloneHero/.new; then
                log_error "Fallo al extraer Clone Hero"
                return 1
            fi
            ;;
        *.appimage)
            if ! run_quiet arch-chroot /mnt install -m 0755 "$chroot_package_file" /opt/CloneHero/.new/CloneHero.AppImage; then
                log_error "Fallo al instalar AppImage de Clone Hero"
                return 1
            fi
            ;;
        *)
            log_error "Formato de Clone Hero no soportado: $CLONEHERO_URL"
            return 1
            ;;
    esac

    run_quiet arch-chroot /mnt bash -c 'shopt -s dotglob nullglob; items=(/opt/CloneHero/.new/*); if [[ ${#items[@]} -eq 1 && -d ${items[0]} ]]; then mv "${items[0]}"/* /opt/CloneHero/; else mv /opt/CloneHero/.new/* /opt/CloneHero/; fi'
    run_quiet arch-chroot /mnt rm -rf /opt/CloneHero/.new
    run_quiet arch-chroot /mnt find /opt/CloneHero -maxdepth 2 -type f \( -iname 'Clone Hero*' -o -iname 'CloneHero*' -o -iname 'clonehero' -o -iname '*.AppImage' \) -exec chmod +x {} +
    run_quiet arch-chroot /mnt mkdir -p "$CLONEHERO_SONGS_DIR" "$CLONEHERO_DATA_DIR"
    run_quiet arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" /opt/CloneHero "$CLONEHERO_DATA_DIR"
    rm -f "$package_file"
}

configure_clonehero_default_settings() {
    log "Configurando carpeta fija de canciones de Clone Hero: $CLONEHERO_SONGS_DIR"

    mkdir -p "/mnt${CLONEHERO_DATA_DIR}" "/mnt${CLONEHERO_SONGS_DIR}"
    arch-chroot /mnt ln -sfnT "$CLONEHERO_SONGS_DIR" "$CLONEHERO_DATA_DIR/Songs"
    arch-chroot /mnt ln -sfnT "$CLONEHERO_SONGS_DIR" "/home/$KIOSK_USER/Songs"

    if ! arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$CLONEHERO_DATA_DIR" "$CLONEHERO_SONGS_DIR" "/home/$KIOSK_USER"; then
        log_error "Fallo al asignar permisos de Clone Hero"
        return 1
    fi
}

configure_clonehero_samba_share() {
    local songs_dir="$CLONEHERO_SONGS_DIR"
    local smb_conf="/mnt/etc/samba/smb.conf"

    log "Configurando Samba para compartir canciones de Clone Hero"

    mkdir -p /mnt/etc/samba /mnt/var/log/samba "/mnt${songs_dir}"
    run_quiet arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$songs_dir"
    run_quiet arch-chroot /mnt chmod 775 "$songs_dir"

    if [[ ! -f "$smb_conf" ]] || ! grep -q '^\[global\]' "$smb_conf"; then
        cat > "$smb_conf" << EOF
[global]
   workgroup = WORKGROUP
   server string = Clone Hero Kiosk
   security = user
   map to guest = Bad User
   log file = /var/log/samba/%m.log
   max log size = 50
EOF
    fi

    if ! grep -q '^\[CloneHero-Songs\]' "$smb_conf"; then
        cat >> "$smb_conf" << EOF

[CloneHero-Songs]
   path = $songs_dir
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

configure_clonehero_performance() {
    log "Aplicando optimizaciones de rendimiento para Clone Hero"

    mkdir -p /mnt/etc/security/limits.d /mnt/etc/sysctl.d /mnt/etc/default

    cat > /mnt/etc/security/limits.d/99-clonehero.conf << EOF
$KIOSK_USER - rtprio 99
$KIOSK_USER - memlock unlimited
$KIOSK_USER - nice -20
EOF

    echo 'vm.swappiness=10' > /mnt/etc/sysctl.d/99-clonehero.conf

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

install_clonehero_update_script() {
    log "Instalando updater /usr/local/bin/update-clonehero"

    mkdir -p /mnt/usr/local/bin
    cat > /mnt/usr/local/bin/update-clonehero << EOF
#!/usr/bin/env bash
set -euo pipefail

CLONEHERO_URL="$CLONEHERO_URL"
CLONEHERO_RELEASE_CHANNEL="$CLONEHERO_RELEASE_CHANNEL"
CLONEHERO_API_URL="$CLONEHERO_API_URL"
CLONEHERO_ASSET_REGEX="$CLONEHERO_ASSET_REGEX"
INSTALL_DIR="/opt/CloneHero"
SONGS_DIR="$CLONEHERO_SONGS_DIR"
PACKAGE_FILE="/tmp/CloneHero.download"
OWNER="$KIOSK_USER"

if [[ \${EUID} -ne 0 ]]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi

resolve_latest_release_url() {
    local release_json release_url
    release_json="\$(curl -fsSL "\$CLONEHERO_API_URL")"
    release_url="\$(printf '%s\n' "\$release_json" \
        | grep -E '"browser_download_url":' \
        | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
        | grep -Ei "\$CLONEHERO_ASSET_REGEX" \
        | head -n 1 || true)"

    if [[ -z "\$release_url" ]]; then
        release_url="\$(printf '%s\n' "\$release_json" \
            | grep -E '"browser_download_url":' \
            | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
            | grep -Ei 'linux.*\.(zip|tar\.xz|tar\.gz|appimage)$' \
            | head -n 1 || true)"
    fi

    if [[ -z "\$release_url" ]]; then
        echo "No se encontro asset Linux para Clone Hero." >&2
        return 1
    fi

    printf '%s\n' "\$release_url"
}

if [[ "\$CLONEHERO_RELEASE_CHANNEL" == "latest" ]]; then
    echo "Resolviendo latest desde \$CLONEHERO_API_URL"
    CLONEHERO_URL="\$(resolve_latest_release_url)"
fi

echo "Descargando Clone Hero desde: \$CLONEHERO_URL"
curl -fsSL --retry 3 --retry-delay 2 -o "\$PACKAGE_FILE" "\$CLONEHERO_URL"
rm -rf "\$INSTALL_DIR/.new"
mkdir -p "\$INSTALL_DIR/.new" "\$SONGS_DIR"

case "\${CLONEHERO_URL,,}" in
    *.zip)
        unzip -tq "\$PACKAGE_FILE" >/dev/null
        unzip -o "\$PACKAGE_FILE" -d "\$INSTALL_DIR/.new" >/dev/null
        ;;
    *.tar.xz|*.txz|*.tar.gz|*.tgz)
        tar -xf "\$PACKAGE_FILE" -C "\$INSTALL_DIR/.new"
        ;;
    *.appimage)
        install -m 0755 "\$PACKAGE_FILE" "\$INSTALL_DIR/.new/CloneHero.AppImage"
        ;;
    *)
        echo "Formato no soportado: \$CLONEHERO_URL" >&2
        exit 1
        ;;
esac

shopt -s dotglob nullglob
items=("\$INSTALL_DIR/.new"/*)
if [[ \${#items[@]} -eq 1 && -d \${items[0]} ]]; then
    mv "\${items[0]}"/* "\$INSTALL_DIR/"
else
    mv "\$INSTALL_DIR/.new"/* "\$INSTALL_DIR/"
fi
rm -rf "\$INSTALL_DIR/.new"
find "\$INSTALL_DIR" -maxdepth 2 -type f \( -iname 'Clone Hero*' -o -iname 'CloneHero*' -o -iname 'clonehero' -o -iname '*.AppImage' \) -exec chmod +x {} +
chown -R "\$OWNER:\$OWNER" "\$INSTALL_DIR" "\$SONGS_DIR"
rm -f "\$PACKAGE_FILE"

echo "Clone Hero actualizado en \$INSTALL_DIR"
EOF

    chmod +x /mnt/usr/local/bin/update-clonehero
}

install_clonehero_song_download_script() {
    local user_home="/mnt/home/$KIOSK_USER"
    local script_path="$user_home/download-clonehero-songs.sh"
    local links_target="$user_home/links.csv"
    local links_source="${SCRIPT_DIR:-.}/links.csv"

    log "Instalando descargador de canciones Clone Hero en /home/$KIOSK_USER"

    mkdir -p "$user_home" "/mnt${CLONEHERO_SONGS_DIR}"

    if [[ -f "$links_source" ]]; then
        cp "$links_source" "$links_target"
    elif [[ ! -f "$links_target" ]]; then
        touch "$links_target"
    fi

    cat > "$script_path" << EOF
#!/usr/bin/env bash
set -euo pipefail

LINKS_FILE="\${1:-\$HOME/links.csv}"
SONGS_DIR="${CLONEHERO_SONGS_DIR}"

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
        local cookie_file confirm html_probe drive_url
        cookie_file="\$(mktemp)"
        html_probe="\$(mktemp)"

        curl -fL --retry 3 --retry-delay 2 -c "\$cookie_file" \
            -o "\$tmp_file" "https://drive.google.com/uc?export=download&id=\$drive_id"

        if grep -qiE 'confirm=|download_warning|Google Drive' "\$tmp_file"; then
            cp "\$tmp_file" "\$html_probe"
            confirm="\$(grep -Eo 'confirm=[0-9A-Za-z_-]+' "\$html_probe" | head -n 1 | cut -d= -f2)"
            drive_url="\$(grep -Eo 'https://drive\\.usercontent\\.google\\.com/download[^"]+' "\$html_probe" | head -n 1 | sed 's/&amp;/\\&/g')"
            if [[ -z "\$drive_url" ]]; then
                drive_url="\$(grep -Eo '/uc\\?export=download[^"]+' "\$html_probe" | head -n 1 | sed 's/&amp;/\\&/g')"
                [[ -n "\$drive_url" ]] && drive_url="https://drive.google.com\$drive_url"
            fi

            if [[ -n "\$drive_url" ]]; then
                curl -fL --retry 3 --retry-delay 2 -b "\$cookie_file" -o "\$tmp_file" "\$drive_url"
            else
                [[ -z "\$confirm" ]] && confirm="t"
                curl -fL --retry 3 --retry-delay 2 -b "\$cookie_file" \
                    -o "\$tmp_file" "https://drive.google.com/uc?export=download&confirm=\$confirm&id=\$drive_id"
            fi
        fi

        rm -f "\$cookie_file" "\$html_probe"
        return 0
    fi

    curl -fL --retry 3 --retry-delay 2 -o "\$tmp_file" "\$url"
}

download_link() {
    local url="\$1"
    local label="\$2"
    local drive_id tmp_file ext target unzip_answer

    drive_id="\$(google_drive_file_id "\$url")"
    tmp_file="\$(mktemp -p "\$SONGS_DIR" ".download.XXXXXX")"

    if ! download_to_temp "\$url" "\$tmp_file" "\$drive_id"; then
        rm -f "\$tmp_file"
        return 1
    fi

    if [[ ! -s "\$tmp_file" ]]; then
        rm -f "\$tmp_file"
        echo "La descarga quedo vacia: \$url" >&2
        return 1
    fi

    label="\$(sanitize_filename "\$label")"
    ext="\$(infer_extension "\$tmp_file")"

    if [[ "\$ext" == ".html" ]]; then
        rm -f "\$tmp_file"
        echo "La descarga devolvio HTML en vez del archivo. Revisa permisos del enlace." >&2
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
                echo "Guardado: \$target"
                ;;
        esac
    else
        echo "Guardado: \$target"
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
echo "Descargas revisadas. Carpeta Songs: \$SONGS_DIR"
EOF

    chmod +x "$script_path"
    arch-chroot /mnt ln -sfnT "$CLONEHERO_SONGS_DIR" "/home/$KIOSK_USER/Songs"
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER"
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$CLONEHERO_SONGS_DIR"
}

install_clonehero_cage_wrapper() {
    log "Creando menu de mantenimiento y wrapper /usr/local/bin/run-clonehero.sh"

    mkdir -p /mnt/usr/local/bin
    cat > /mnt/usr/local/bin/kiosk-menu.sh <<'MENU'
#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"

pause_menu() {
    echo ""
    read -r -p "Presione Enter para volver al menu..."
}

show_ip_addresses() {
    clear
    echo "Direcciones IP"
    echo "=============="
    echo ""
    command -v ip >/dev/null 2>&1 && ip -br addr show scope global || true
    echo ""
    command -v nmcli >/dev/null 2>&1 && nmcli -t -f DEVICE,STATE,CONNECTION device status 2>/dev/null || true
    echo ""
    echo "Hostname: $(hostname)"
    echo "IPs: $(hostname -I 2>/dev/null || true)"
    pause_menu
}

open_shell() {
    clear
    echo "Shell de mantenimiento"
    echo "Escriba 'exit' para volver al menu."
    echo ""
    "${SHELL:-/bin/bash}"
}

while true; do
    clear
    cat <<'EOF'
Menu de mantenimiento Clone Hero
================================

1) Configurar sonido
2) Configurar WiFi
3) Ver direccion IP
4) Salir a Shell
5) Volver a Clone Hero
6) Reiniciar Kiosko
7) Apagar Kiosko

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
            elif command -v nmcli >/dev/null 2>&1; then
                nmcli device wifi list || true
                echo ""
                read -r -p "SSID: " ssid
                read -r -s -p "Password (vacio para red abierta): " password
                echo ""
                if [[ -n "$password" ]]; then
                    nmcli device wifi connect "$ssid" password "$password" || true
                else
                    nmcli device wifi connect "$ssid" || true
                fi
                pause_menu
            else
                echo "NetworkManager/nmcli no esta disponible."
                pause_menu
            fi
            ;;
        3) show_ip_addresses ;;
        4) open_shell ;;
        5) exit 0 ;;
        6)
            echo "Reiniciando servicio cage-kiosk..."
            sudo systemctl restart cage-kiosk.service
            exit 0
            ;;
        7)
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
MENU
    chmod +x /mnt/usr/local/bin/kiosk-menu.sh

    cat > /mnt/usr/local/bin/run-clonehero.sh <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

echo "run-clonehero: iniciado como $(id -un) pid=$$" >&2

CLONEHERO_FORCE_SOFTWARE_RENDER="__CLONEHERO_FORCE_SOFTWARE_RENDER__"

case "${CLONEHERO_FORCE_SOFTWARE_RENDER,,}" in
    true|yes|si|1)
        echo "run-clonehero: usando render por software por configuracion" >&2
        export WLR_RENDERER_ALLOW_SOFTWARE=1
        export WLR_NO_HARDWARE_CURSORS=1
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        ;;
esac

export HOME="${HOME:-__CLONEHERO_HOME__}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"

if [[ -d /usr/share/icons/MiniArchPick ]]; then
    export XCURSOR_THEME=MiniArchPick
    export XCURSOR_SIZE=64
fi
if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
else
    unset WLR_XWAYLAND
fi

CLONEHERO_SCREEN_WIDTH="__CLONEHERO_SCREEN_WIDTH__"
CLONEHERO_SCREEN_HEIGHT="__CLONEHERO_SCREEN_HEIGHT__"
CLONEHERO_EXIT_MENU="__CLONEHERO_EXIT_MENU__"
CLONEHERO_DATA_DIR="__CLONEHERO_DATA_DIR__"

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
    echo "run-clonehero: DBus de sesion ausente o invalido" >&2
    unset DBUS_SESSION_BUS_ADDRESS
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -z "${CLONEHERO_DBUS_SESSION_STARTED:-}" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        echo "run-clonehero: iniciando DBus de sesion" >&2
        export CLONEHERO_DBUS_SESSION_STARTED=1
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

if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
    echo "run-clonehero: iniciando pipewire" >&2
    pipewire 2>&1 | sed 's/^/[pipewire] /' &
fi

wait_for_path "$XDG_RUNTIME_DIR/pipewire-0" 100 || \
    echo "Aviso: PipeWire no creo $XDG_RUNTIME_DIR/pipewire-0 a tiempo." >&2

if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
    echo "run-clonehero: iniciando wireplumber" >&2
    wireplumber 2>&1 | sed 's/^/[wireplumber] /' &
fi

sleep 1

if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
    echo "run-clonehero: iniciando pipewire-pulse" >&2
    pipewire-pulse 2>&1 | sed 's/^/[pipewire-pulse] /' &
fi

echo "run-clonehero: esperando sink Pulse/PipeWire" >&2
wait_for_pulse_sink 50 || \
    echo "Aviso: no se encontro un sink Pulse/PipeWire antes de iniciar Clone Hero." >&2

find_clonehero_bin() {
    find /opt/CloneHero -maxdepth 2 -type f \( -iname 'Clone Hero*' -o -iname 'CloneHero*' -o -iname 'clonehero' -o -iname '*.AppImage' \) -executable -print -quit 2>/dev/null
}

build_clonehero_args() {
    CLONEHERO_ARGS=("-persistentDataPath" "$CLONEHERO_DATA_DIR")

    if [[ -n "$CLONEHERO_SCREEN_WIDTH" && -n "$CLONEHERO_SCREEN_HEIGHT" ]]; then
        echo "run-clonehero: resolucion ${CLONEHERO_SCREEN_WIDTH}x${CLONEHERO_SCREEN_HEIGHT}" >&2
        CLONEHERO_ARGS+=(
            -screen-width "$CLONEHERO_SCREEN_WIDTH"
            -screen-height "$CLONEHERO_SCREEN_HEIGHT"
            -screen-fullscreen 1
        )
    fi
}

while true; do
    CLONEHERO_BIN="$(find_clonehero_bin)"

    if [[ -n "$CLONEHERO_BIN" ]]; then
        echo "Iniciando Clone Hero: $CLONEHERO_BIN" >&2
        build_clonehero_args
        /usr/bin/cage -- "$CLONEHERO_BIN" "${CLONEHERO_ARGS[@]}" || \
            echo "Aviso: Clone Hero/Cage termino con codigo $?" >&2
    else
        echo "No se encontro Clone Hero en /opt/CloneHero; abriendo menu de mantenimiento." >&2
    fi

    case "${CLONEHERO_EXIT_MENU,,}" in
        restart|relaunch|volver|clonehero)
            echo "run-clonehero: relanzando Clone Hero automaticamente" >&2
            sleep 1
            continue
            ;;
        never|off|false|no)
            echo "run-clonehero: menu deshabilitado; saliendo" >&2
            exit 0
            ;;
    esac

    echo "run-clonehero: abriendo menu de mantenimiento" >&2
    /usr/bin/cage -- /usr/bin/foot /usr/local/bin/kiosk-menu.sh || \
        echo "Aviso: menu de mantenimiento termino con codigo $?" >&2
done
WRAPPER

    chmod +x /mnt/usr/local/bin/run-clonehero.sh
    sed -i "s#__CLONEHERO_HOME__#/home/$KIOSK_USER#g" /mnt/usr/local/bin/run-clonehero.sh
    sed -i "s#__CLONEHERO_DATA_DIR__#$CLONEHERO_DATA_DIR#g" /mnt/usr/local/bin/run-clonehero.sh
    sed -i "s#__CLONEHERO_SCREEN_WIDTH__#${CLONEHERO_SCREEN_WIDTH:-}#g" /mnt/usr/local/bin/run-clonehero.sh
    sed -i "s#__CLONEHERO_SCREEN_HEIGHT__#${CLONEHERO_SCREEN_HEIGHT:-}#g" /mnt/usr/local/bin/run-clonehero.sh
    sed -i "s#__CLONEHERO_FORCE_SOFTWARE_RENDER__#${CLONEHERO_FORCE_SOFTWARE_RENDER:-false}#g" /mnt/usr/local/bin/run-clonehero.sh
    sed -i "s#__CLONEHERO_EXIT_MENU__#${CLONEHERO_EXIT_MENU:-always}#g" /mnt/usr/local/bin/run-clonehero.sh
}

install_clonehero_cage_service() {
    log "Creando servicio systemd cage-kiosk.service para Clone Hero"

    local kiosk_uid
    if ! kiosk_uid=$(arch-chroot /mnt id -u "$KIOSK_USER"); then
        log_error "No se pudo resolver UID de $KIOSK_USER para cage-kiosk.service"
        return 1
    fi

    cat > /mnt/etc/systemd/system/cage-kiosk.service << EOF
[Unit]
Description=Kiosk Clone Hero con Cage
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
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire-pulse
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x wireplumber
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire
ExecStartPre=-/usr/bin/rm -f /run/user/$kiosk_uid/pipewire-0 /run/user/$kiosk_uid/pipewire-0.lock /run/user/$kiosk_uid/pulse/native
ExecStartPre=+/usr/bin/chown $KIOSK_USER:$KIOSK_USER /run/user/$kiosk_uid
ExecStartPre=+/usr/bin/chmod 700 /run/user/$kiosk_uid
ExecStart=/usr/bin/dbus-run-session -- /usr/local/bin/run-clonehero.sh
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
