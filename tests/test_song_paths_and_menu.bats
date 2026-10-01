#!/usr/bin/env bats

@test "YARG usa home Songs como ruta canonica y /opt/YARG/Songs como enlace" {
    grep -Fq 'YARG_SONGS_DIR="${YARG_SONGS_DIR:-/home/$KIOSK_USER/Songs}"' install-cage-yarg.sh
    grep -Fq 'normalize_yarg_songs_dir()' lib/yarg.sh
    grep -Fq 'ensure_yarg_songs_symlink()' lib/yarg.sh
    grep -Fq 'ln -sfnT "$songs_dir" "$opt_songs"' lib/yarg.sh
    grep -Fq '"$YARG_SONGS_DIR"' lib/yarg.sh
    grep -Fq '"ShowAntiPiracyDialog": false' lib/yarg.sh
    grep -Fq '"ShowEngineInconsistencyDialog": false' lib/yarg.sh
    grep -Fq '"ShowExperimentalWarningDialog": false' lib/yarg.sh
    grep -Fq 'path = $songs_dir' lib/yarg.sh
}

@test "YARG no crea home Songs como enlace hacia /opt/YARG/Songs" {
    ! grep -Fq 'ln -sfnT "/opt/YARG/Songs" "/home/$KIOSK_USER/Songs"' lib/yarg.sh
    grep -Fq 'YARG_SONGS_DIR" != "/opt/YARG/Songs"' lib/yarg.sh
}

@test "Clone Hero mantiene home Songs fuera de /opt/CloneHero" {
    grep -Fq 'CLONEHERO_SONGS_DIR="${CLONEHERO_SONGS_DIR:-/home/$KIOSK_USER/Songs}"' install-cage-clonehero.sh
    grep -Fq 'normalize_clonehero_songs_dir()' lib/clonehero.sh
    grep -Fq 'arch-chroot /mnt ln -sfnT "$CLONEHERO_SONGS_DIR" "$CLONEHERO_DATA_DIR/Songs"' lib/clonehero.sh
    grep -Fq 'SONGS_DIR="$CLONEHERO_SONGS_DIR"' lib/clonehero.sh
    grep -Fq 'SONGS_DIR="${CLONEHERO_SONGS_DIR}"' lib/clonehero.sh
    grep -Fq 'path = $songs_dir' lib/clonehero.sh
    ! grep -Fq 'CLONEHERO_SONGS_DIR="${CLONEHERO_SONGS_DIR:-/opt/CloneHero' install-cage-clonehero.sh
}

@test "menus de mantenimiento tienen fallback si hostname no existe" {
    grep -Fq 'inetutils' lib/cage.sh
    grep -Fq 'show_hostname()' lib/cage.sh
    grep -Fq 'show_hostname_ips()' lib/cage.sh
    grep -Fq 'echo "Hostname: $(show_hostname)"' lib/cage.sh
    grep -Fq 'echo "IPs: $(show_hostname_ips)"' lib/cage.sh
    ! grep -Fq 'echo "Hostname: $(hostname)"' lib/cage.sh
    ! grep -Fq 'echo "IPs: $(hostname -I 2>/dev/null || true)"' lib/cage.sh

    grep -Fq 'show_hostname()' lib/clonehero.sh
    grep -Fq 'show_hostname_ips()' lib/clonehero.sh
    grep -Fq 'echo "Hostname: $(show_hostname)"' lib/clonehero.sh
    grep -Fq 'echo "IPs: $(show_hostname_ips)"' lib/clonehero.sh
    ! grep -Fq 'echo "Hostname: $(hostname)"' lib/clonehero.sh
    ! grep -Fq 'echo "IPs: $(hostname -I 2>/dev/null || true)"' lib/clonehero.sh
}

@test "menus de mantenimiento incluyen opcion para actualizar la app" {
    grep -Fq 'yarg_update_label="Actualizar YARG Stable"' lib/cage.sh
    grep -Fq 'yarg_update_label="Actualizar YARG Nightly"' lib/cage.sh
    grep -Fq 'UPDATE_COMMAND="/usr/local/bin/update-yarg"' lib/cage.sh
    grep -Fq '6) __KIOSK_UPDATE_LABEL__' lib/cage.sh
    grep -Fq 'update_kiosk_app' lib/cage.sh

    grep -Fq 'UPDATE_LABEL="Actualizar Clone Hero"' lib/clonehero.sh
    grep -Fq 'UPDATE_COMMAND="/usr/local/bin/update-clonehero"' lib/clonehero.sh
    grep -Fq '6) Actualizar Clone Hero' lib/clonehero.sh
    grep -Fq 'update_kiosk_app' lib/clonehero.sh
}

@test "update-clonehero actualiza sobre una instalacion existente con directorios _Data" {
    local work gen pkg
    work="$(mktemp -d)"
    gen="$work/update-clonehero"

    # Genera el updater real evaluando el heredoc de install_clonehero_update_script.
    export CLONEHERO_URL="https://example.invalid/CloneHero-linux-x64.tar.gz" CLONEHERO_RELEASE_CHANNEL=url \
        CLONEHERO_API_URL=unused CLONEHERO_ASSET_REGEX=unused \
        CLONEHERO_SONGS_DIR="$work/songs" KIOSK_USER="$(id -un)"
    awk '/cat > \/mnt\/usr\/local\/bin\/update-clonehero << EOF/{f=1;next} f&&/^EOF$/{exit} f' lib/clonehero.sh > "$work/body"
    eval "cat <<EOF
$(cat "$work/body")
EOF" > "$gen"

    sed -i -e "s#/opt/CloneHero#$work/opt#g" -e 's#if \[\[ \${EUID} -ne 0 \]\]#if false#' \
        -e "s#/tmp/CloneHero.download#$work/pkg.download#" -e "s#^chown -R .*#true#" "$gen"

    # Paquete nuevo: directorio raiz unico con un _Data y un binario.
    mkdir -p "$work/src/CloneHero/Clone Hero_Data/Managed"
    echo new > "$work/src/CloneHero/Clone Hero_Data/Managed/a.dll"
    echo bin > "$work/src/CloneHero/clonehero"
    tar -czf "$work/pkg.tar.gz" -C "$work/src" CloneHero

    # Instalacion previa con el mismo directorio _Data.
    mkdir -p "$work/opt/Clone Hero_Data/Managed"
    echo old > "$work/opt/Clone Hero_Data/Managed/a.dll"

    # curl de prueba: copia el paquete local en vez de descargar.
    mkdir -p "$work/bin"
    printf '#!/usr/bin/env bash
while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done
cp "%s" "$out"
' "$work/pkg.tar.gz" > "$work/bin/curl"
    chmod +x "$work/bin/curl"

    PATH="$work/bin:$PATH" run bash "$gen"
    [ "$status" -eq 0 ]
    [ "$(cat "$work/opt/Clone Hero_Data/Managed/a.dll")" = "new" ]
    [ -f "$work/opt/clonehero" ]
    [ ! -e "$work/opt/.new" ]
    rm -rf "$work"
}
