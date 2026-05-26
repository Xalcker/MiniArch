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
