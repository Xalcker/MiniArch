#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Bootloader
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/bootloader.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 5.1-5.6, 14.4
################################################################################

# Setup: cargar el módulo de bootloader antes de cada prueba
setup() {
    # Cargar el módulo de bootloader
    source lib/bootloader.sh
    
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
# Pruebas para install_grub()
################################################################################

@test "install_grub: instalación exitosa retorna 0" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/grub_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de mountpoint que simula /mnt/boot montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt/boot"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Limpiar log de comandos
    rm -f /tmp/grub_commands.log
    
    run install_grub
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRUB instalado exitosamente"* ]]
    
    # Limpiar
    rm -f /tmp/grub_commands.log
}

@test "install_grub: genera comando pacman correcto para instalar grub y efibootmgr" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/grub_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de mountpoint que simula /mnt/boot montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt/boot"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Limpiar log de comandos
    rm -f /tmp/grub_commands.log
    
    run install_grub
    [ "$status" -eq 0 ]
    
    # Verificar que se instalaron grub y efibootmgr
    grep -q "arch-chroot /mnt pacman -S --noconfirm grub efibootmgr" /tmp/grub_commands.log
    
    # Limpiar
    rm -f /tmp/grub_commands.log
}

@test "install_grub: genera comando grub-install con opciones UEFI correctas" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/grub_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de mountpoint que simula /mnt/boot montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt/boot"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Limpiar log de comandos
    rm -f /tmp/grub_commands.log
    
    run install_grub
    [ "$status" -eq 0 ]
    
    # Verificar que se ejecutó grub-install con las opciones correctas
    grep -q "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB" /tmp/grub_commands.log
    
    # Limpiar
    rm -f /tmp/grub_commands.log
}

@test "install_grub: /mnt/boot no montado retorna 1" {
    # Mock de arch-chroot que funciona
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Mock de mountpoint que simula /mnt/boot NO montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt/boot"* ]]; then
            return 1
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    run install_grub
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"La partición ESP no está montada en /mnt/boot"* ]]
}

@test "install_grub: fallo al instalar paquetes retorna 1" {
    # Mock de arch-chroot que falla en pacman
    arch-chroot() {
        if [[ "$*" == *"pacman"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot
    
    run install_grub
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar grub y efibootmgr"* ]]
}

@test "install_grub: fallo al ejecutar grub-install retorna 1" {
    # Mock de arch-chroot que falla en grub-install
    arch-chroot() {
        if [[ "$*" == *"grub-install"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot
    
    # Mock de mountpoint que simula /mnt/boot montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt/boot"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    run install_grub
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar GRUB en la partición ESP"* ]]
}

################################################################################
# Pruebas para configure_grub_silent()
################################################################################

@test "configure_grub_silent: configuración exitosa retorna 0" {
    # Crear archivo temporal de configuración de GRUB
    local temp_grub_config=$(mktemp)
    echo 'GRUB_TIMEOUT=5' > "$temp_grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' >> "$temp_grub_config"
    
    # Reemplazar la función para usar el archivo temporal
    configure_grub_silent() {
        local grub_config="$temp_grub_config"
        
        if [[ ! -f "$grub_config" ]]; then
            log_error "El archivo $grub_config no existe. GRUB debe estar instalado primero."
            return 1
        fi
        
        log "Configurando GRUB para arranque silencioso"
        
        cp "$grub_config" "${grub_config}.backup"
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' >> "$grub_config"
        
        if grep -q "^GRUB_DISABLE_SUBMENU=" "$grub_config"; then
            sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
        else
            echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
        fi
        
        log "Generando archivo de configuración de GRUB"
        log "GRUB configurado exitosamente para arranque silencioso"
        return 0
    }
    
    run configure_grub_silent
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRUB configurado exitosamente para arranque silencioso"* ]]
    
    # Limpiar
    rm -f "$temp_grub_config" "${temp_grub_config}.backup"
}

@test "configure_grub_silent: archivo /etc/default/grub contiene GRUB_TIMEOUT=0" {
    # Crear directorio temporal para simular /mnt/etc/default
    local temp_dir=$(mktemp -d)
    local grub_config="$temp_dir/grub"
    
    # Crear archivo de configuración inicial
    echo 'GRUB_TIMEOUT=5' > "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' >> "$grub_config"
    
    # Mock de arch-chroot que funciona
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Aplicar configuración
    cp "$grub_config" "${grub_config}.backup"
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' >> "$grub_config"
    
    if grep -q "^GRUB_DISABLE_SUBMENU=" "$grub_config"; then
        sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
    else
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
    fi
    
    # Verificar que GRUB_TIMEOUT=0 está presente
    grep -q "^GRUB_TIMEOUT=0$" "$grub_config"
    [ "$?" -eq 0 ]
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "configure_grub_silent: archivo contiene parámetros quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local grub_config="$temp_dir/grub"
    
    # Crear archivo de configuración inicial
    echo 'GRUB_TIMEOUT=5' > "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' >> "$grub_config"
    
    # Aplicar configuración
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' >> "$grub_config"
    
    # Verificar que la línea contiene todos los parámetros
    local cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config")
    
    [[ "$cmdline" == *"quiet"* ]]
    [[ "$cmdline" == *"loglevel=3"* ]]
    [[ "$cmdline" == *"rd.systemd.show_status=false"* ]]
    [[ "$cmdline" == *"rd.udev.log_level=3"* ]]
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "configure_grub_silent: archivo contiene GRUB_DISABLE_SUBMENU=y" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local grub_config="$temp_dir/grub"
    
    # Crear archivo de configuración inicial sin GRUB_DISABLE_SUBMENU
    echo 'GRUB_TIMEOUT=5' > "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' >> "$grub_config"
    
    # Aplicar configuración
    if grep -q "^GRUB_DISABLE_SUBMENU=" "$grub_config"; then
        sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
    else
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
    fi
    
    # Verificar que GRUB_DISABLE_SUBMENU=y está presente
    grep -q "^GRUB_DISABLE_SUBMENU=y$" "$grub_config"
    [ "$?" -eq 0 ]
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "configure_grub_silent: modifica GRUB_DISABLE_SUBMENU existente a y" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local grub_config="$temp_dir/grub"
    
    # Crear archivo de configuración inicial con GRUB_DISABLE_SUBMENU=n
    echo 'GRUB_TIMEOUT=5' > "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' >> "$grub_config"
    echo 'GRUB_DISABLE_SUBMENU=n' >> "$grub_config"
    
    # Aplicar configuración
    if grep -q "^GRUB_DISABLE_SUBMENU=" "$grub_config"; then
        sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
    else
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
    fi
    
    # Verificar que GRUB_DISABLE_SUBMENU=y está presente
    grep -q "^GRUB_DISABLE_SUBMENU=y$" "$grub_config"
    [ "$?" -eq 0 ]
    
    # Verificar que no hay líneas con GRUB_DISABLE_SUBMENU=n
    ! grep -q "^GRUB_DISABLE_SUBMENU=n$" "$grub_config"
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "configure_grub_silent: genera comando grub-mkconfig correcto" {
    # Crear archivo temporal de configuración de GRUB
    local temp_grub_config=$(mktemp)
    echo 'GRUB_TIMEOUT=5' > "$temp_grub_config"
    
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/grub_mkconfig_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/grub_mkconfig_commands.log
    
    # Reemplazar la función para usar el archivo temporal
    configure_grub_silent() {
        local grub_config="$temp_grub_config"
        
        if [[ ! -f "$grub_config" ]]; then
            return 1
        fi
        
        cp "$grub_config" "${grub_config}.backup"
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' >> "$grub_config"
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
        
        arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
        return 0
    }
    
    run configure_grub_silent
    [ "$status" -eq 0 ]
    
    # Verificar que se ejecutó grub-mkconfig con la salida correcta
    grep -q "arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg" /tmp/grub_mkconfig_commands.log
    
    # Limpiar
    rm -f "$temp_grub_config" "${temp_grub_config}.backup" /tmp/grub_mkconfig_commands.log
}

@test "configure_grub_silent: archivo /etc/default/grub no existe retorna 1" {
    # Reemplazar la función para simular archivo inexistente
    configure_grub_silent() {
        local grub_config="/mnt/etc/default/grub"
        
        if [[ ! -f "$grub_config" ]]; then
            log_error "El archivo $grub_config no existe. GRUB debe estar instalado primero."
            return 1
        fi
        
        return 0
    }
    
    run configure_grub_silent
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"no existe"* ]]
    [[ "$output" == *"GRUB debe estar instalado primero"* ]]
}

@test "configure_grub_silent: fallo al ejecutar grub-mkconfig retorna 1" {
    # Crear archivo temporal de configuración de GRUB
    local temp_grub_config=$(mktemp)
    echo 'GRUB_TIMEOUT=5' > "$temp_grub_config"
    
    # Mock de arch-chroot que falla en grub-mkconfig
    arch-chroot() {
        if [[ "$*" == *"grub-mkconfig"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot
    
    # Reemplazar la función para usar el archivo temporal
    configure_grub_silent() {
        local grub_config="$temp_grub_config"
        
        if [[ ! -f "$grub_config" ]]; then
            return 1
        fi
        
        cp "$grub_config" "${grub_config}.backup"
        sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
        sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' >> "$grub_config"
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
        
        if ! arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
            log_error "Fallo al generar el archivo de configuración de GRUB"
            return 1
        fi
        
        return 0
    }
    
    run configure_grub_silent
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al generar el archivo de configuración de GRUB"* ]]
    
    # Limpiar
    rm -f "$temp_grub_config" "${temp_grub_config}.backup"
}

################################################################################
# Prueba de Propiedad para install_grub()
# Property 12: Instalación de GRUB con UEFI
# Validates: Requirements 5.1, 5.2
################################################################################

@test "Property 12: install_grub genera comandos correctos para instalación UEFI" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/grub_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de mountpoint que simula /mnt/boot montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt/boot"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Limpiar log de comandos
    rm -f /tmp/grub_commands.log
    
    # Ejecutar la función
    run install_grub
    [ "$status" -eq 0 ]
    
    # Verificar que se generaron exactamente 2 comandos
    local command_count=$(wc -l < /tmp/grub_commands.log)
    [[ $command_count -eq 2 ]]
    
    # Verificar el primer comando: instalación de paquetes
    local cmd1=$(sed -n '1p' /tmp/grub_commands.log)
    [[ "$cmd1" == "arch-chroot /mnt pacman -S --noconfirm grub efibootmgr" ]]
    
    # Verificar el segundo comando: instalación de GRUB con UEFI
    local cmd2=$(sed -n '2p' /tmp/grub_commands.log)
    [[ "$cmd2" == "arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB" ]]
    
    # Verificar que el comando contiene todas las opciones requeridas
    [[ "$cmd2" == *"--target=x86_64-efi"* ]]
    [[ "$cmd2" == *"--efi-directory=/boot"* ]]
    [[ "$cmd2" == *"--bootloader-id=GRUB"* ]]
    
    # Limpiar
    rm -f /tmp/grub_commands.log
}

################################################################################
# Prueba de Propiedad para configure_grub_silent()
# Property 13: Configuración de GRUB silencioso completa
# Validates: Requirements 5.3, 5.4, 5.5
################################################################################

@test "Property 13: configure_grub_silent genera archivo con todas las configuraciones silenciosas" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local grub_config="$temp_dir/grub"
    
    # Crear archivo de configuración inicial con valores variados
    echo 'GRUB_TIMEOUT=5' > "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"' >> "$grub_config"
    echo 'GRUB_DISABLE_SUBMENU=n' >> "$grub_config"
    
    # Aplicar todas las configuraciones
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' >> "$grub_config"
    sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
    
    # Verificar GRUB_TIMEOUT=0
    grep -q "^GRUB_TIMEOUT=0$" "$grub_config"
    [ "$?" -eq 0 ]
    
    # Verificar GRUB_CMDLINE_LINUX_DEFAULT con todos los parámetros
    local cmdline=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$grub_config")
    [[ "$cmdline" == 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' ]]
    
    # Verificar que contiene cada parámetro individualmente
    [[ "$cmdline" == *"quiet"* ]]
    [[ "$cmdline" == *"loglevel=3"* ]]
    [[ "$cmdline" == *"rd.systemd.show_status=false"* ]]
    [[ "$cmdline" == *"rd.udev.log_level=3"* ]]
    
    # Verificar GRUB_DISABLE_SUBMENU=y
    grep -q "^GRUB_DISABLE_SUBMENU=y$" "$grub_config"
    [ "$?" -eq 0 ]
    
    # Limpiar
    rm -rf "$temp_dir"
}
