#!/bin/bash

# Cage/Wayland helpers for install-arch-cage.sh.

install_cage_base_system() {
    local packages=(
        base linux linux-firmware linux-headers
        sudo nano curl wget unzip git dbus file
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
    if ! configure_plymouth "$PLYMOUTH_THEME_NAME" "$PLYMOUTH_IMAGE_PATH"; then
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

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

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
    unset DBUS_SESSION_BUS_ADDRESS
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -z "${YARG_DBUS_SESSION_STARTED:-}" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        export YARG_DBUS_SESSION_STARTED=1
        exec dbus-run-session -- "$0"
    fi

    echo "Aviso: dbus-run-session no esta disponible; continuando sin DBus de sesion." >&2
fi

export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export WLR_XWAYLAND=1
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"

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

if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
    pipewire 2>&1 | sed 's/^/[pipewire] /' &
fi

wait_for_path "$XDG_RUNTIME_DIR/pipewire-0" 100 || \
    echo "Aviso: PipeWire no creo $XDG_RUNTIME_DIR/pipewire-0 a tiempo." >&2

if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
    wireplumber 2>&1 | sed 's/^/[wireplumber] /' &
fi

sleep 1

if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
    pipewire-pulse 2>&1 | sed 's/^/[pipewire-pulse] /' &
fi

wait_for_pulse_sink 50 || \
    echo "Aviso: no se encontro un sink Pulse/PipeWire antes de iniciar YARG." >&2

YARG_BIN=$(find /opt/YARG -maxdepth 1 -type f -name "YARG*" -executable -print -quit 2>/dev/null)

if [[ -n "$YARG_BIN" ]]; then
    echo "Iniciando YARG: $YARG_BIN" >&2
    exec /usr/bin/cage -- "$YARG_BIN" -persistent-data-path "__YARG_PERSISTENT_DATA_DIR__"
fi

echo "No se encontro YARG en /opt/YARG; abriendo foot." >&2
exec /usr/bin/cage /usr/bin/foot
WRAPPER

    chmod +x /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_PERSISTENT_DATA_DIR__#$YARG_PERSISTENT_DATA_DIR#g" /mnt/usr/local/bin/run-yarg.sh
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
