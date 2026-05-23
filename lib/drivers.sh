#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

################################################################################
# MÃ³dulo de Drivers
#
# Este mÃ³dulo contiene funciones para instalar controladores grÃ¡ficos y el
# sistema de audio PipeWire en el sistema Arch Linux.
#
# Funciones:
# - install_graphics_drivers(): Instala drivers para AMD, Intel, NVIDIA y Mesa
# - install_audio_system(): Instala y configura PipeWire completo
################################################################################

################################################################################
# install_graphics_drivers()
#
# Instala controladores grÃ¡ficos para soportar diferentes configuraciones de
# hardware: AMD (xf86-video-amdgpu), Intel (xf86-video-intel), NVIDIA
# (nvidia-open), y Mesa para soporte OpenGL genÃ©rico.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - Debe existir conexiÃ³n de red activa
#
# Returns:
#   0 - Si la instalaciÃ³n fue exitosa
#   1 - Si hubo un error durante la instalaciÃ³n
################################################################################
install_graphics_drivers() {
    log "Instalando controladores grÃ¡ficos (AMD, Intel, NVIDIA, Mesa)"
    
    # Instalar todos los controladores grÃ¡ficos
    if ! run_quiet arch-chroot /mnt pacman -S --noconfirm xf86-video-amdgpu xf86-video-intel nvidia-open mesa; then
        log_error "Fallo al instalar controladores grÃ¡ficos"
        return 1
    fi
    
    log "Controladores grÃ¡ficos instalados exitosamente"
    return 0
}

################################################################################
# install_audio_system()
#
# Instala el sistema de audio PipeWire completo con todos sus componentes:
# pipewire, pipewire-alsa, pipewire-pulse, pipewire-jack, y sof-firmware para
# soporte de audio en hardware Intel moderno. Luego habilita los servicios de
# PipeWire para el usuario del sistema.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - Debe existir conexiÃ³n de red activa
#
# Returns:
#   0 - Si la instalaciÃ³n y configuraciÃ³n fueron exitosas
#   1 - Si hubo un error durante la instalaciÃ³n o configuraciÃ³n
################################################################################
install_audio_system() {
    log "Instalando sistema de audio PipeWire y firmware de audio"
    

    if declare -F ensure_pacman_download_user >/dev/null; then
        ensure_pacman_download_user || return 1
    fi

    if declare -F repair_chroot_ca_certificates >/dev/null; then
        repair_chroot_ca_certificates || return 1
    fi
    # Instalar componentes de PipeWire, gestor de sesiÃ³n, cÃ³decs y utilidades de hardware
    # - pipewire-*: Audio moderno con compatibilidad ALSA/Pulse/JACK
    # - wireplumber: Gestor de sesiÃ³n indispensable para PipeWire
    # - ffmpeg/gst-*: CÃ³decs multimedia para decodificaciÃ³n de canciones (YARG)
    # - bluez*: Soporte para guitarras y perifÃ©ricos Bluetooth
    if ! run_quiet arch-chroot /mnt pacman -S --noconfirm \
        pipewire pipewire-alsa pipewire-pulse pipewire-jack wireplumber \
        libpulse alsa-plugins alsa-utils \
        ffmpeg gst-libav gst-plugins-good libvorbis opus \
        sof-firmware usbutils bluez bluez-utils; then
        log_error "Fallo al instalar PipeWire, cÃ³decs y utilidades de hardware"
        return 1
    fi

    log "Configurando ALSA default hacia PipeWire"
    cat > /mnt/etc/asound.conf << 'EOF'
pcm.!default {
    type pipewire
}

ctl.!default {
    type pipewire
}
EOF

    # Habilitar servicio de Bluetooth
    if ! arch-chroot /mnt systemctl enable bluetooth.service; then
        log_error "Fallo al habilitar bluetooth.service"
        return 1
    fi
    
    log "PipeWire y firmware de audio instalados exitosamente"
    log "Nota: Los servicios de PipeWire se habilitarÃ¡n para el usuario del sistema despuÃ©s de su creaciÃ³n"
    
    return 0
}
