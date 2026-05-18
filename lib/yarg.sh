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
