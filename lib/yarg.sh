#!/bin/bash

# YARG download, configuration, Samba and updater helpers.

resolve_yarg_download_url() {
    if [[ "$YARG_RELEASE_CHANNEL" != "nightly" ]]; then
        return 0
    fi

    log "Resolviendo URL del nightly mas reciente de YARG"

    local release_json
    if ! release_json=$(curl -fsSL "$YARG_NIGHTLY_API_URL"); then
        log_error "Fallo al consultar $YARG_NIGHTLY_API_URL"
        return 1
    fi

    local nightly_url
    nightly_url=$(printf '%s\n' "$release_json" \
        | grep -E '"browser_download_url":' \
        | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
        | grep -Ei "$YARG_NIGHTLY_ASSET_REGEX" \
        | head -n 1 || true)

    if [[ -z "$nightly_url" ]]; then
        nightly_url=$(printf '%s\n' "$release_json" \
            | grep -E '"browser_download_url":' \
            | sed -E 's/.*"browser_download_url": "([^"]+)".*/\1/' \
            | grep -Ei 'linux.*\.zip' \
            | head -n 1 || true)
    fi

    if [[ -z "$nightly_url" ]]; then
        log_error "No se encontro asset Linux ZIP en el ultimo release nightly"
        return 1
    fi

    YARG_URL="$nightly_url"
    log "Nightly seleccionado: $YARG_URL"
}

install_yarg() {
    log "Descargando e instalando YARG en /opt/YARG"

    local yarg_zip="/mnt/root/YARG.zip"
    local chroot_yarg_zip="/root/YARG.zip"

    mkdir -p /mnt/root /mnt/opt/YARG

    if ! curl -fL --retry 3 --retry-delay 2 -o "$yarg_zip" "$YARG_URL"; then
        log_error "Fallo al descargar YARG"
        return 1
    fi

    if [[ ! -s "$yarg_zip" ]]; then
        log_error "La descarga de YARG no genero un ZIP valido en $yarg_zip"
        return 1
    fi

    if ! arch-chroot /mnt test -s "$chroot_yarg_zip"; then
        log_error "El ZIP de YARG no existe dentro del chroot en $chroot_yarg_zip"
        return 1
    fi

    if ! arch-chroot /mnt unzip -tq "$chroot_yarg_zip" >/dev/null; then
        log_error "El ZIP descargado de YARG no es valido"
        return 1
    fi

    if ! arch-chroot /mnt unzip -o "$chroot_yarg_zip" -d /opt/YARG; then
        log_error "Fallo al descomprimir YARG"
        return 1
    fi

    arch-chroot /mnt find /opt/YARG -maxdepth 1 -type f -name 'YARG*' -exec chmod +x {} +
    arch-chroot /mnt mkdir -p "$YARG_SONGS_DIR"
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" /opt/YARG
    rm -f "$yarg_zip"
}

configure_yarg_default_settings() {
    local settings_dir="/mnt${YARG_PERSISTENT_DATA_DIR}"
    local settings_file="$settings_dir/settings.json"

    log "Configurando ruta fija de canciones de YARG: $YARG_SONGS_DIR"

    mkdir -p "$settings_dir"

    cat > "$settings_file" << EOF
{
  "SongFolders": [
    "$YARG_SONGS_DIR"
  ]
}
EOF

    if ! arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$YARG_PERSISTENT_DATA_DIR"; then
        log_error "Fallo al asignar permisos de configuracion YARG"
        return 1
    fi
}

configure_yarg_samba_share() {
    local songs_dir="$YARG_SONGS_DIR"
    local smb_conf="/mnt/etc/samba/smb.conf"

    log "Configurando Samba para compartir canciones de YARG"

    mkdir -p /mnt/etc/samba /mnt/var/log/samba "/mnt${songs_dir}"
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
SONGS_DIR="$YARG_SONGS_DIR"
ZIP_FILE="/tmp/YARG_Linux.zip"
OWNER="$KIOSK_USER"

if [[ \${EUID} -ne 0 ]]; then
    echo "Este script debe ejecutarse como root." >&2
    exit 1
fi

curl -L -o "\$ZIP_FILE" "\$YARG_URL"
mkdir -p "\$SONGS_DIR"
unzip -o "\$ZIP_FILE" -d "\$INSTALL_DIR"
find "\$INSTALL_DIR" -maxdepth 1 -type f -name "YARG*" -exec chmod +x {} +
chown -R "\$OWNER:\$OWNER" "\$INSTALL_DIR"
chown -R "\$OWNER:\$OWNER" "\$SONGS_DIR"
rm -f "\$ZIP_FILE"

echo "YARG actualizado en \$INSTALL_DIR"
EOF

    chmod +x /mnt/usr/local/bin/update-yarg
}

install_yarg_song_download_script() {
    local user_home="/mnt/home/$KIOSK_USER"
    local script_path="$user_home/download-yarg-songs.sh"
    local links_target="$user_home/links.csv"
    local links_source="${SCRIPT_DIR:-.}/links.csv"

    log "Instalando descargador de canciones YARG en /home/$KIOSK_USER"

    mkdir -p "$user_home" "/mnt${YARG_SONGS_DIR}"

    if [[ -f "$links_source" ]]; then
        cp "$links_source" "$links_target"
    elif [[ ! -f "$links_target" ]]; then
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
                echo "No se pudo confirmar la descarga de Google Drive. Verifica que el enlace sea publico." >&2
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
    arch-chroot /mnt ln -sfnT "$YARG_SONGS_DIR" "/home/$KIOSK_USER/Songs"
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER"
    arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "$YARG_SONGS_DIR"
}
