#!/bin/bash

################################################################################
# Módulo de Drivers
#
# Este módulo contiene funciones para instalar controladores gráficos y el
# sistema de audio PipeWire en el sistema Arch Linux.
#
# Funciones:
# - install_graphics_drivers(): Instala drivers para AMD, Intel, NVIDIA y Mesa
# - install_audio_system(): Instala y configura PipeWire completo
################################################################################

################################################################################
# install_graphics_drivers()
#
# Instala controladores gráficos para soportar diferentes configuraciones de
# hardware: AMD (xf86-video-amdgpu), Intel (xf86-video-intel), NVIDIA
# (nvidia-open), y Mesa para soporte OpenGL genérico.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - Debe existir conexión de red activa
#
# Returns:
#   0 - Si la instalación fue exitosa
#   1 - Si hubo un error durante la instalación
################################################################################
install_graphics_drivers() {
    log "Instalando controladores gráficos (AMD, Intel, NVIDIA, Mesa)"
    
    # Instalar todos los controladores gráficos
    if ! arch-chroot /mnt pacman -S --noconfirm xf86-video-amdgpu xf86-video-intel nvidia-open mesa; then
        log_error "Fallo al instalar controladores gráficos"
        return 1
    fi
    
    log "Controladores gráficos instalados exitosamente"
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
#   - Debe existir conexión de red activa
#
# Returns:
#   0 - Si la instalación y configuración fueron exitosas
#   1 - Si hubo un error durante la instalación o configuración
################################################################################
install_audio_system() {
    log "Instalando sistema de audio PipeWire y firmware de audio"
    
    # Instalar todos los componentes de PipeWire y firmware de audio
    if ! arch-chroot /mnt pacman -S --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack sof-firmware; then
        log_error "Fallo al instalar PipeWire y firmware de audio"
        return 1
    fi
    
    log "PipeWire y firmware de audio instalados exitosamente"
    log "Nota: Los servicios de PipeWire se habilitarán para el usuario del sistema después de su creación"
    
    return 0
}
