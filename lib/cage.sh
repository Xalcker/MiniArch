#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Cage/Wayland helpers for install-cage-yarg.sh.

install_cage_base_system() {
    local packages=(
        base linux linux-firmware linux-headers
        sudo nano curl wget unzip git dbus file
        networkmanager grub efibootmgr samba cpupower
        mesa wayland xorg-xwayland cage foot
        xorg-xcursorgen
        ttf-dejavu
        vulkan-icd-loader egl-wayland
        vulkan-intel intel-media-driver
        vulkan-radeon xf86-video-amdgpu
        virglrenderer
        hidapi systemd-libs
    )

    if ! mountpoint -q /mnt; then
        log_error "/mnt no esta montado. Ejecute mount_partitions primero."
        return 1
    fi

    log "Instalando sistema base y stack Cage/Wayland (${#packages[@]} paquetes)"
    if ! run_quiet pacstrap -K /mnt "${packages[@]}"; then
        log_error "Fallo pacstrap para sistema Cage/YARG"
        return 1
    fi
}

ensure_pacman_download_user() {
    if [[ ! -f /mnt/etc/pacman.conf ]]; then
        return 0
    fi

    if ! grep -Eq '^[[:space:]]*DownloadUser[[:space:]]*=' /mnt/etc/pacman.conf; then
        return 0
    fi

    if arch-chroot /mnt getent passwd alpm >/dev/null 2>&1; then
        return 0
    fi

    log "Creando usuario de sistema alpm requerido por pacman DownloadUser"
    arch-chroot /mnt groupadd -r alpm 2>/dev/null || true
    if ! arch-chroot /mnt useradd -r -g alpm -d /var/lib/pacman -s /usr/bin/nologin alpm; then
        log_error "No se pudo crear usuario alpm para pacman"
        return 1
    fi
}

repair_chroot_ca_certificates() {
    local source_bundle="/etc/ssl/certs/ca-certificates.crt"
    local target_bundle="/mnt/etc/ssl/certs/ca-certificates.crt"

    mkdir -p /mnt/etc/ssl/certs

    if [[ -s "$source_bundle" ]]; then
        cp "$source_bundle" "$target_bundle"
    fi

    if arch-chroot /mnt command -v update-ca-trust >/dev/null 2>&1; then
        run_quiet arch-chroot /mnt update-ca-trust || true
    fi

    if [[ ! -s "$target_bundle" ]]; then
        log_error "No existe un bundle de certificados valido en $target_bundle"
        return 1
    fi
}

configure_system_basics() {
    log "Configurando hostname, locale, zona horaria y root"

    echo "$KIOSK_HOSTNAME" > /mnt/etc/hostname
    echo "en_US.UTF-8 UTF-8" > /mnt/etc/locale.gen
    echo "LANG=en_US.UTF-8" > /mnt/etc/locale.conf

    if ! run_quiet arch-chroot /mnt locale-gen; then
        log_error "Fallo al generar locale"
        return 1
    fi

    if ! echo "root:$ROOT_PASSWORD" | arch-chroot /mnt chpasswd; then
        log_error "Fallo al configurar password de root"
        return 1
    fi
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

    if ! run_quiet arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        log_error "Fallo al regenerar GRUB con parametros NVIDIA"
        return 1
    fi
}

install_nvidia_drivers_if_requested() {
    if [[ "$INSTALL_NVIDIA" != "true" ]]; then
        return 0
    fi

    log "Instalando drivers NVIDIA despues del sistema base"
    ensure_pacman_download_user || return 1
    repair_chroot_ca_certificates || return 1

    if ! run_quiet arch-chroot /mnt pacman -S --needed --noconfirm nvidia-open nvidia-utils; then
        log_error "Fallo al instalar drivers NVIDIA"
        if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
            echo "Ultimas lineas de $LOG_FILE:" >&2
            tail -n 60 "$LOG_FILE" >&2 || true
        fi
        return 1
    fi
}

configure_cage_plymouth() {
    if [[ "$ENABLE_PLYMOUTH" != "true" ]]; then
        log "Plymouth deshabilitado por ENABLE_PLYMOUTH=$ENABLE_PLYMOUTH"
        return 0
    fi

    log "Instalando Plymouth"
    if ! install_plymouth; then
        warn "No se pudo instalar Plymouth; se continua sin pantalla de arranque personalizada."
        return 0
    fi

    log "Creando tema personalizado de Plymouth: $PLYMOUTH_THEME_NAME"
    if ! create_custom_theme "$PLYMOUTH_THEME_NAME"; then
        warn "No se pudo crear el tema Plymouth; se continua sin pantalla de arranque personalizada."
        return 0
    fi

    if [[ "$PLYMOUTH_ASSET_AVAILABLE" != "true" ]]; then
        warn "Plymouth instalado, pero sin imagen valida; se omite configuracion personalizada."
        return 0
    fi

    log "Configurando Plymouth con imagen personalizada"
    if ! configure_plymouth "$PLYMOUTH_THEME_NAME" "$PLYMOUTH_IMAGE_PATH" "${PLYMOUTH_TARGET_RESOLUTION:-1280x720}"; then
        warn "No se pudo configurar Plymouth; se continua sin pantalla de arranque personalizada."
        return 0
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
    ensure_pacman_download_user || return 1
    repair_chroot_ca_certificates || return 1

    if ! run_quiet arch-chroot /mnt pacman -Syu --noconfirm \
        lib32-pipewire lib32-alsa-plugins lib32-libpulse \
        hidapi systemd-libs alsa-plugins pipewire-alsa pulsemixer; then
        log_error "Fallo al instalar dependencias multilib/YARG"
        return 1
    fi

    log "Reafirmando ALSA default hacia PipeWire para YARG"
    cat > /mnt/etc/asound.conf << 'EOF'
pcm.!default {
    type pipewire
}

ctl.!default {
    type pipewire
}
EOF
}

configure_hid_access() {
    log "Configurando acceso udev a dispositivos hidraw"

    mkdir -p /mnt/etc/udev/rules.d
    echo 'KERNEL=="hidraw*", TAG+="uaccess"' > /mnt/etc/udev/rules.d/69-hid.rules
    chmod 644 /mnt/etc/udev/rules.d/69-hid.rules
}

install_cage_wrapper() {
    log "Creando menu de mantenimiento y wrapper /usr/local/bin/run-yarg.sh"

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

    if command -v ip >/dev/null 2>&1; then
        ip -br addr show scope global || true
    fi

    echo ""
    if command -v nmcli >/dev/null 2>&1; then
        nmcli -t -f DEVICE,STATE,CONNECTION device status 2>/dev/null || true
    fi

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
Menu de mantenimiento YARG
==========================

1) Configurar sonido
2) Configurar WiFi
3) Ver direccion IP
4) Salir a Shell
5) Volver a YARG
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

    cat > /mnt/usr/local/bin/run-yarg.sh <<'WRAPPER'
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
if [[ -d /usr/share/icons/MiniArchPick ]]; then
    export XCURSOR_THEME=MiniArchPick
    export XCURSOR_SIZE=64
fi
if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
else
    unset WLR_XWAYLAND
fi
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
YARG_SCREEN_WIDTH="__YARG_SCREEN_WIDTH__"
YARG_SCREEN_HEIGHT="__YARG_SCREEN_HEIGHT__"
YARG_EXIT_MENU="__YARG_EXIT_MENU__"

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

build_yarg_args() {
    YARG_ARGS=(-persistent-data-path "__YARG_PERSISTENT_DATA_DIR__")

    if [[ -n "$YARG_SCREEN_WIDTH" && -n "$YARG_SCREEN_HEIGHT" ]]; then
        echo "run-yarg: resolucion YARG ${YARG_SCREEN_WIDTH}x${YARG_SCREEN_HEIGHT}" >&2
        YARG_ARGS+=(
            -screen-width "$YARG_SCREEN_WIDTH"
            -screen-height "$YARG_SCREEN_HEIGHT"
            -screen-fullscreen 1
        )
    fi
}

while true; do
    YARG_BIN=$(find /opt/YARG -maxdepth 1 -type f -name "YARG*" -executable -print -quit 2>/dev/null)

    if [[ -n "$YARG_BIN" ]]; then
        echo "Iniciando YARG: $YARG_BIN" >&2
        build_yarg_args
        /usr/bin/cage -- "$YARG_BIN" "${YARG_ARGS[@]}" || \
            echo "Aviso: YARG/Cage termino con codigo $?" >&2
    else
        echo "No se encontro YARG en /opt/YARG; abriendo menu de mantenimiento." >&2
    fi

    case "${YARG_EXIT_MENU,,}" in
        restart|relaunch|volver|yarg)
            echo "run-yarg: relanzando YARG automaticamente" >&2
            sleep 1
            continue
            ;;
        never|off|false|no)
            echo "run-yarg: menu deshabilitado; saliendo" >&2
            exit 0
            ;;
    esac

    echo "run-yarg: abriendo menu de mantenimiento" >&2
    /usr/bin/cage -- /usr/bin/foot /usr/local/bin/kiosk-menu.sh || \
        echo "Aviso: menu de mantenimiento termino con codigo $?" >&2
done
WRAPPER

    chmod +x /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_PERSISTENT_DATA_DIR__#$YARG_PERSISTENT_DATA_DIR#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_WIDTH__#${YARG_SCREEN_WIDTH:-}#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_HEIGHT__#${YARG_SCREEN_HEIGHT:-}#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_FORCE_SOFTWARE_RENDER__#${YARG_FORCE_SOFTWARE_RENDER:-false}#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_EXIT_MENU__#${YARG_EXIT_MENU:-always}#g" /mnt/usr/local/bin/run-yarg.sh
}

install_cage_service() {
    log "Creando servicio systemd cage-kiosk.service"

    local kiosk_uid
    if ! kiosk_uid=$(arch-chroot /mnt id -u "$KIOSK_USER"); then
        log_error "No se pudo resolver UID de $KIOSK_USER para cage-kiosk.service"
        return 1
    fi

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
Environment=XDG_RUNTIME_DIR=/run/user/$kiosk_uid
ExecStartPre=+/usr/bin/mkdir -p /run/user/$kiosk_uid
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire-pulse
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x wireplumber
ExecStartPre=-/usr/bin/pkill -u $KIOSK_USER -x pipewire
ExecStartPre=-/usr/bin/rm -f /run/user/$kiosk_uid/pipewire-0 /run/user/$kiosk_uid/pipewire-0.lock /run/user/$kiosk_uid/pulse/native
ExecStartPre=+/usr/bin/chown $KIOSK_USER:$KIOSK_USER /run/user/$kiosk_uid
ExecStartPre=+/usr/bin/chmod 700 /run/user/$kiosk_uid
ExecStart=/usr/bin/dbus-run-session -- /usr/local/bin/run-yarg.sh
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

configure_network_target() {
    if ! configure_network; then
        return 1
    fi

    if ! arch-chroot /mnt systemctl set-default graphical.target; then
        log_error "Fallo al configurar graphical.target"
        return 1
    fi
}
