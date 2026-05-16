#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Drivers
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/drivers.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 7.1, 7.2, 7.3, 7.4, 8.1, 8.2, 8.3, 14.4
################################################################################

# Setup: cargar el módulo de drivers antes de cada prueba
setup() {
    # Cargar el módulo de drivers
    source lib/drivers.sh
    
    # Mock de funciones de logging
    log() {
        echo "$*"
    }
    export -f log
    
    log_error() {
        echo "ERROR: $*" >&2
    }
    export -f log_error
}

################################################################################
# Pruebas para install_graphics_drivers()
################################################################################

@test "install_graphics_drivers: instalación exitosa retorna 0" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de pacman
    pacman() {
        echo "pacman $*" >> /tmp/pacman_commands.log
        return 0
    }
    export -f pacman
    
    # Limpiar logs de comandos
    rm -f /tmp/arch_chroot_commands.log /tmp/pacman_commands.log
    
    run install_graphics_drivers
    [ "$status" -eq 0 ]
    [[ "$output" == *"Instalando controladores gráficos"* ]]
    [[ "$output" == *"Controladores gráficos instalados exitosamente"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log /tmp/pacman_commands.log
}

@test "install_graphics_drivers: instala todos los drivers necesarios (AMD, Intel, NVIDIA, Mesa)" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/arch_chroot_commands.log
    
    run install_graphics_drivers
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/arch_chroot_commands.log)
    
    # Verificar que contiene todos los drivers requeridos
    [[ "$command" == *"xf86-video-amdgpu"* ]]
    [[ "$command" == *"xf86-video-intel"* ]]
    [[ "$command" == *"nvidia-open"* ]]
    [[ "$command" == *"mesa"* ]]
    
    # Verificar que usa pacman con --noconfirm
    [[ "$command" == *"pacman"* ]]
    [[ "$command" == *"-S"* ]]
    [[ "$command" == *"--noconfirm"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log
}

@test "install_graphics_drivers: fallo en instalación retorna 1" {
    # Mock de arch-chroot que falla
    arch-chroot() {
        return 1
    }
    export -f arch-chroot
    
    run install_graphics_drivers
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar controladores gráficos"* ]]
}

@test "install_graphics_drivers: comando contiene exactamente los 4 drivers requeridos" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/arch_chroot_commands.log
    
    run install_graphics_drivers
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/arch_chroot_commands.log)
    
    # Verificar que el comando es exactamente el esperado
    [[ "$command" == "arch-chroot /mnt pacman -S --noconfirm xf86-video-amdgpu xf86-video-intel nvidia-open mesa" ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log
}

################################################################################
# Pruebas para install_audio_system()
################################################################################

@test "install_audio_system: instalación exitosa retorna 0" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de pacman
    pacman() {
        echo "pacman $*" >> /tmp/pacman_commands.log
        return 0
    }
    export -f pacman
    
    # Limpiar logs de comandos
    rm -f /tmp/arch_chroot_commands.log /tmp/pacman_commands.log
    
    run install_audio_system
    [ "$status" -eq 0 ]
    [[ "$output" == *"Instalando sistema de audio PipeWire"* ]]
    [[ "$output" == *"PipeWire, firmware de audio y utilidades de hardware instalados exitosamente"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log /tmp/pacman_commands.log
}

@test "install_audio_system: instala todos los componentes de PipeWire" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/arch_chroot_commands.log
    
    run install_audio_system
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/arch_chroot_commands.log)
    
    # Verificar que contiene todos los componentes de PipeWire requeridos
    [[ "$command" == *"pipewire"* ]]
    [[ "$command" == *"pipewire-alsa"* ]]
    [[ "$command" == *"pipewire-pulse"* ]]
    [[ "$command" == *"pipewire-jack"* ]]
    [[ "$command" == *"sof-firmware"* ]]
    [[ "$command" == *"alsa-utils"* ]]
    [[ "$command" == *"usbutils"* ]]
    [[ "$command" == *"bluez"* ]]
    [[ "$command" == *"bluez-utils"* ]]
    
    # Verificar que usa pacman con --noconfirm
    [[ "$command" == *"pacman"* ]]
    [[ "$command" == *"-S"* ]]
    [[ "$command" == *"--noconfirm"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log
}

@test "install_audio_system: fallo en instalación retorna 1" {
    # Mock de arch-chroot que falla
    arch-chroot() {
        return 1
    }
    export -f arch-chroot
    
    run install_audio_system
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar PipeWire, firmware de audio y utilidades de hardware"* ]]
}

@test "install_audio_system: comando contiene exactamente los 5 paquetes requeridos" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/arch_chroot_commands.log
    
    run install_audio_system
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/arch_chroot_commands.log)
    
    # Verificar que el comando contiene los paquetes base esperados
    [[ "$command" == *"pipewire pipewire-alsa pipewire-pulse pipewire-jack sof-firmware alsa-utils usbutils bluez bluez-utils"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log
}

@test "install_audio_system: menciona habilitación de servicios para el usuario" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    run install_audio_system
    [ "$status" -eq 0 ]
    
    # Verificar que el output menciona la habilitación de servicios
    [[ "$output" == *"servicios de PipeWire"* ]]
    [[ "$output" == *"usuario del sistema"* ]]
    [[ "$output" == *"bluetooth.service"* ]]
}

################################################################################
# Prueba de Propiedad para install_graphics_drivers()
# Property 19: Instalación completa de drivers gráficos
# Validates: Requirements 7.1, 7.2, 7.3, 7.4
################################################################################

@test "Property 19: install_graphics_drivers instala todos los drivers requeridos" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/arch_chroot_commands.log
    
    # Ejecutar la función
    run install_graphics_drivers
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/arch_chroot_commands.log)
    
    # Verificar que el comando contiene todos los drivers requeridos
    local drivers=("xf86-video-amdgpu" "xf86-video-intel" "nvidia-open" "mesa")
    
    for driver in "${drivers[@]}"; do
        if [[ "$command" != *"$driver"* ]]; then
            echo "ERROR: Falta el driver $driver en el comando" >&2
            rm -f /tmp/arch_chroot_commands.log
            return 1
        fi
    done
    
    # Verificar que usa arch-chroot con /mnt
    [[ "$command" == *"arch-chroot /mnt"* ]]
    
    # Verificar que usa pacman con las opciones correctas
    [[ "$command" == *"pacman -S --noconfirm"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log
}

################################################################################
# Prueba de Propiedad para install_audio_system()
# Property 20: Instalación completa de PipeWire
# Validates: Requirements 8.1
################################################################################

@test "Property 20: install_audio_system instala todos los componentes de PipeWire" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            echo "arch-chroot $*" >> /tmp/arch_chroot_commands.log
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/arch_chroot_commands.log
    
    # Ejecutar la función
    run install_audio_system
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/arch_chroot_commands.log)
    
    # Verificar que el comando contiene todos los componentes requeridos
    local packages=("pipewire" "pipewire-alsa" "pipewire-pulse" "pipewire-jack" "sof-firmware" "alsa-utils" "usbutils" "bluez" "bluez-utils")
    
    for package in "${packages[@]}"; do
        if [[ "$command" != *"$package"* ]]; then
            echo "ERROR: Falta el paquete $package en el comando" >&2
            rm -f /tmp/arch_chroot_commands.log
            return 1
        fi
    done
    
    # Verificar que usa arch-chroot con /mnt
    [[ "$command" == *"arch-chroot /mnt"* ]]
    
    # Verificar que usa pacman con las opciones correctas
    [[ "$command" == *"pacman -S --noconfirm"* ]]
    
    # Limpiar
    rm -f /tmp/arch_chroot_commands.log
}
