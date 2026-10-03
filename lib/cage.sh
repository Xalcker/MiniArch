#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Cage/Wayland helpers for install-cage-yarg.sh.

install_cage_base_system() {
    local packages=(
        base linux linux-firmware linux-headers
        sudo nano curl wget unzip git dbus file
        networkmanager grub efibootmgr samba cpupower inetutils
        mesa wayland xorg-xwayland cage foot
        xorg-xcursorgen
        ttf-dejavu
        vulkan-icd-loader egl-wayland
        vulkan-intel intel-media-driver
        vulkan-radeon xf86-video-amdgpu
        virglrenderer
        hidapi systemd-libs
        mc zram-generator
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

# Detecta las GPU NVIDIA con lspci y dice si nvidia-open puede manejarlas.
#
# nvidia-open solo soporta Turing (GTX 16xx / RTX 20xx) y posteriores. Con el
# driver 590, Arch dejo fuera Pascal (GTX 10xx) y anteriores: solo quedan en el
# AUR (nvidia-580xx-dkms), que un instalador desatendido no puede compilar.
#
# El nombre que lspci toma de pci.ids incluye el codigo del chip:
#   Turing y posteriores: TU (Turing), GA (Ampere), AD (Ada), GB (Blackwell), GH (Hopper)
#   Anteriores:           GV (Volta), GP (Pascal), GM (Maxwell), GK (Kepler),
#                         GF (Fermi), GT (Tesla), G80-G98, NV (Curie y anteriores)
#
# Imprime en stdout uno de:
#   none         no hay GPU NVIDIA
#   supported    todas las GPU NVIDIA son Turing o mas nuevas
#   unsupported  al menos una es anterior a Turing
#   unknown      no se pudo determinar (sin lspci o chip no reconocido)
detect_nvidia_support() {
    local lines modern_re legacy_re line has_modern=false has_legacy=false has_unknown=false

    if ! command -v lspci &> /dev/null; then
        echo "unknown"
        return 0
    fi

    lines=$(lspci -nn 2>/dev/null | grep -Ei 'VGA compatible|3D controller|Display controller' | grep -i 'nvidia' || true)
    if [[ -z "$lines" ]]; then
        echo "none"
        return 0
    fi

    modern_re='\b(TU|GA|AD|GB|GH)[0-9]{2,3}[A-Z]*\b'
    legacy_re='\b(GV|GP|GM|GK|GF|GT|G|NV|MCP)[0-9]{2,3}[A-Z]*\b'

    while IFS= read -r line; do
        if [[ "$line" =~ $modern_re ]]; then
            has_modern=true
        elif [[ "$line" =~ $legacy_re ]]; then
            has_legacy=true
        else
            has_unknown=true
        fi
    done <<< "$lines"

    if [[ "$has_legacy" == "true" ]]; then
        echo "unsupported"
    elif [[ "$has_unknown" == "true" ]]; then
        echo "unknown"
    elif [[ "$has_modern" == "true" ]]; then
        echo "supported"
    else
        echo "unknown"
    fi
}

# Decide si se instala el driver NVIDIA. Pregunta si INSTALL_NVIDIA esta vacio y,
# si se pidio instalarlo (por .env, pregunta o respuesta), evita instalar
# nvidia-open en una GPU anterior a Turing: dejaria el equipo sin video porque
# nvidia-utils pone nouveau en la lista negra. NVIDIA_SKIP_GPU_CHECK=true omite
# esa proteccion (falsos positivos, GPU en passthrough, etc.).
resolve_nvidia_choice() {
    local gpu_state answer

    gpu_state="$(detect_nvidia_support)"

    if [[ -z "${INSTALL_NVIDIA:-}" ]]; then
        case "$gpu_state" in
            supported)
                echo -e "${GREEN}Se detecto una GPU NVIDIA compatible con nvidia-open (Turing o mas nueva).${NC}"
                ;;
            unsupported)
                warn "Se detecto una GPU NVIDIA anterior a Turing (GTX 10xx o anterior): nvidia-open no la soporta. Lo recomendado es responder N y usar Mesa/nouveau."
                ;;
            none)
                echo "No se detecto ninguna GPU NVIDIA."
                ;;
            *)
                echo "No se pudo identificar la GPU NVIDIA. Recuerda que nvidia-open solo soporta Turing (GTX 16xx / RTX 20xx) o mas nuevas."
                ;;
        esac

        read -rp "$(echo -e "${BLUE}Instalar driver NVIDIA? (s/N): ${NC}")" answer
        INSTALL_NVIDIA=false
        [[ "${answer,,}" == "s" || "${answer,,}" == "y" ]] && INSTALL_NVIDIA=true
    fi

    if [[ "$INSTALL_NVIDIA" == "true" && "$gpu_state" == "unsupported" && "${NVIDIA_SKIP_GPU_CHECK:-false}" != "true" ]]; then
        warn "Se omite el driver NVIDIA: la GPU detectada es anterior a Turing y nvidia-open no la soporta."
        warn "Se usaran Mesa/nouveau. Para GTX 10xx y anteriores existe nvidia-580xx-dkms en el AUR (instalacion manual)."
        warn "Define NVIDIA_SKIP_GPU_CHECK=true si quieres instalar nvidia-open de todos modos."
        INSTALL_NVIDIA=false
    fi

    if [[ "$INSTALL_NVIDIA" == "true" ]]; then
        if [[ "$gpu_state" == "none" ]]; then
            warn "No se detecto una GPU NVIDIA, pero se instalara el driver porque INSTALL_NVIDIA=true."
        fi
        log "Se instalaran drivers NVIDIA (nvidia-open, nvidia-utils)"
    else
        warn "Driver NVIDIA omitido. Se instalaran Intel, AMD, Mesa y Vulkan base."
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

    local yarg_update_label="Actualizar YARG Stable"
    case "${YARG_RELEASE_CHANNEL,,}" in
        nightly)
            yarg_update_label="Actualizar YARG Nightly"
            ;;
    esac

    install_kiosk_menu "YARG" "Volver a YARG" "$yarg_update_label" "/usr/local/bin/update-yarg"

    {
        kiosk_wrapper_prelude "run-yarg" "/home/$KIOSK_USER" "${YARG_FORCE_SOFTWARE_RENDER:-false}" "${YARG_AUDIO_VOLUME-}" "${YARG_PIPEWIRE_QUANTUM-}"
        cat <<'WRAPPER'

YARG_SCREEN_WIDTH="__YARG_SCREEN_WIDTH__"
YARG_SCREEN_HEIGHT="__YARG_SCREEN_HEIGHT__"
YARG_EXIT_MENU="__YARG_EXIT_MENU__"

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

start_kiosk_exit_hotkey /opt/YARG/
start_kiosk_audio YARG

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
    } > /mnt/usr/local/bin/run-yarg.sh

    chmod +x /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_PERSISTENT_DATA_DIR__#$YARG_PERSISTENT_DATA_DIR#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_WIDTH__#${YARG_SCREEN_WIDTH:-}#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_SCREEN_HEIGHT__#${YARG_SCREEN_HEIGHT:-}#g" /mnt/usr/local/bin/run-yarg.sh
    sed -i "s#__YARG_EXIT_MENU__#${YARG_EXIT_MENU:-always}#g" /mnt/usr/local/bin/run-yarg.sh
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
