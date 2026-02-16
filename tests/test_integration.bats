#!/usr/bin/env bats

################################################################################
# Pruebas de Integración para el Instalador de Arch Linux Modo Kiosko
#
# Este archivo contiene pruebas BATS para validar la integración completa
# del script install-arch-kiosk.sh. Las pruebas usan mocks para simular
# todos los comandos del sistema y verifican que el flujo completo funciona
# correctamente.
#
# Requisitos probados: Todos los requisitos
################################################################################

# Setup: preparar el entorno de pruebas antes de cada prueba
setup() {
    # Crear directorio temporal para logs
    export TEST_LOG_DIR="/tmp/arch-kiosk-test-$$"
    mkdir -p "$TEST_LOG_DIR"
    
    # Archivo de log para comandos ejecutados
    export COMMANDS_LOG="$TEST_LOG_DIR/commands.log"
    touch "$COMMANDS_LOG"
    
    # Mock de funciones de logging
    log() {
        echo "[LOG] $*" >> "$COMMANDS_LOG"
    }
    export -f log
    
    log_error() {
        echo "[ERROR] $*" >> "$COMMANDS_LOG"
    }
    export -f log_error
    
    # Simular que somos root
    export EUID=0
}

# Teardown: limpiar después de cada prueba
teardown() {
    # Limpiar directorio temporal
    rm -rf "$TEST_LOG_DIR"
}

################################################################################
# Mocks de Comandos del Sistema
################################################################################

# Mock de comandos de validación
mock_validation_commands() {
    # Mock de test para verificar archivos y dispositivos
    test() {
        if [[ "$1" == "-f" && "$2" == "/etc/arch-release" ]]; then
            return 0
        elif [[ "$1" == "-b" ]]; then
            return 0
        elif [[ "$1" == "-d" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de command para verificar comandos disponibles
    command() {
        if [[ "$1" == "-v" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    export -f command
    
    # Mock de ping
    ping() {
        echo "[MOCK] ping $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f ping
    
    # Mock de lsblk para tamaño de disco
    lsblk() {
        if [[ "$*" == *"-b -d -n -o SIZE"* ]]; then
            # 20GB en bytes
            echo "21474836480"
        elif [[ "$*" == *"-n -o TYPE"* ]]; then
            echo "disk"
        else
            echo "NAME SIZE TYPE FSTYPE MOUNTPOINT"
            echo "sda  20G  disk"
        fi
    }
    export -f lsblk
    
    # Mock de grep para contar particiones
    grep() {
        if [[ "$*" == *"-c part"* ]]; then
            echo "0"
            return 0
        fi
        command grep "$@"
    }
    export -f grep
    
    # Mock de mountpoint
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
}

# Mock de comandos de particionamiento
mock_partitioning_commands() {
    # Mock de parted
    parted() {
        echo "[MOCK] parted $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f parted
    
    # Mock de mkfs.fat
    mkfs.fat() {
        echo "[MOCK] mkfs.fat $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f mkfs.fat
    
    # Mock de mkfs.ext4
    mkfs.ext4() {
        echo "[MOCK] mkfs.ext4 $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f mkfs.ext4
    
    # Mock de mkswap
    mkswap() {
        echo "[MOCK] mkswap $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f mkswap
    
    # Mock de mount
    mount() {
        echo "[MOCK] mount $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f mount
    
    # Mock de mkdir
    mkdir() {
        if [[ "$*" != *"-p $TEST_LOG_DIR"* ]]; then
            echo "[MOCK] mkdir $*" >> "$COMMANDS_LOG"
        fi
        command mkdir "$@"
    }
    export -f mkdir
    
    # Mock de swapon
    swapon() {
        echo "[MOCK] swapon $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f swapon
}

# Mock de comandos de instalación base
mock_base_install_commands() {
    # Mock de pacstrap
    pacstrap() {
        echo "[MOCK] pacstrap $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f pacstrap
    
    # Mock de genfstab
    genfstab() {
        echo "[MOCK] genfstab $*" >> "$COMMANDS_LOG"
        echo "# /etc/fstab: static file system information"
        return 0
    }
    export -f genfstab
    
    # Mock de arch-chroot
    arch-chroot() {
        echo "[MOCK] arch-chroot $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f arch-chroot
}

# Mock de comandos de bootloader
mock_bootloader_commands() {
    # Mock de pacman
    pacman() {
        echo "[MOCK] pacman $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f pacman
    
    # Mock de grub-install
    grub-install() {
        echo "[MOCK] grub-install $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f grub-install
    
    # Mock de grub-mkconfig
    grub-mkconfig() {
        echo "[MOCK] grub-mkconfig $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f grub-mkconfig
    
    # Mock de sed para modificar archivos
    sed() {
        echo "[MOCK] sed $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f sed
}

# Mock de comandos de Plymouth
mock_plymouth_commands() {
    # Mock de convert (ImageMagick)
    convert() {
        echo "[MOCK] convert $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f convert
    
    # Mock de mkinitcpio
    mkinitcpio() {
        echo "[MOCK] mkinitcpio $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f mkinitcpio
    
    # Mock de plymouth-set-default-theme
    plymouth-set-default-theme() {
        echo "[MOCK] plymouth-set-default-theme $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f plymouth-set-default-theme
    
    # Mock de file para validar PNG
    file() {
        if [[ "$*" == *"--mime-type"* ]]; then
            echo "image/png"
        else
            echo "PNG image data"
        fi
    }
    export -f file
}

# Mock de comandos de GUI
mock_gui_commands() {
    # Mock de useradd
    useradd() {
        echo "[MOCK] useradd $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f useradd
    
    # Mock de passwd
    passwd() {
        echo "[MOCK] passwd $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f passwd
    
    # Mock de chown
    chown() {
        echo "[MOCK] chown $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f chown
    
    # Mock de chmod
    chmod() {
        echo "[MOCK] chmod $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f chmod
}

# Mock de comandos de finalización
mock_finalization_commands() {
    # Mock de systemctl
    systemctl() {
        echo "[MOCK] systemctl $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f systemctl
    
    # Mock de timedatectl
    timedatectl() {
        echo "[MOCK] timedatectl $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f timedatectl
    
    # Mock de hwclock
    hwclock() {
        echo "[MOCK] hwclock $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f hwclock
    
    # Mock de umount
    umount() {
        echo "[MOCK] umount $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f umount
    
    # Mock de swapoff
    swapoff() {
        echo "[MOCK] swapoff $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f swapoff
}

# Mock de comandos de escritura de archivos
mock_file_operations() {
    # Mock de tee
    tee() {
        if [[ "$*" == *"-a"* ]]; then
            cat >> /dev/null
        else
            cat > /dev/null
        fi
    }
    export -f tee
    
    # Mock de touch
    touch() {
        if [[ "$*" != *"$COMMANDS_LOG"* ]]; then
            echo "[MOCK] touch $*" >> "$COMMANDS_LOG"
        fi
        command touch "$@"
    }
    export -f touch
    
    # Mock de echo para redirecciones
    # (echo funciona normalmente, solo registramos cuando se usa con >)
    
    # Mock de cp
    cp() {
        echo "[MOCK] cp $*" >> "$COMMANDS_LOG"
        return 0
    }
    export -f cp
    
    # Mock de cat
    cat() {
        if [[ "$*" == "/etc/arch-release" ]]; then
            echo "Arch Linux"
        else
            command cat "$@"
        fi
    }
    export -f cat
}

################################################################################
# Pruebas de Integración
################################################################################

@test "Integración: script completo ejecuta todas las fases en orden correcto (dry-run)" {
    # Activar todos los mocks
    mock_validation_commands
    mock_partitioning_commands
    mock_base_install_commands
    mock_bootloader_commands
    mock_plymouth_commands
    mock_gui_commands
    mock_finalization_commands
    mock_file_operations
    
    # Cargar todos los módulos
    source lib/validation.sh
    source lib/partitioning.sh
    source lib/base_install.sh
    source lib/bootloader.sh
    source lib/plymouth.sh
    source lib/drivers.sh
    source lib/gui.sh
    source lib/customization.sh
    source lib/finalization.sh
    
    # Ejecutar validación
    run validate_environment
    [ "$status" -eq 0 ]
    
    run check_network
    [ "$status" -eq 0 ]
    
    run check_disk "/dev/sda"
    [ "$status" -eq 0 ]
    
    # Ejecutar particionamiento
    run partition_disk "/dev/sda"
    [ "$status" -eq 0 ]
    
    run format_partitions "/dev/sda"
    [ "$status" -eq 0 ]
    
    run mount_partitions "/dev/sda"
    [ "$status" -eq 0 ]
    
    # Ejecutar instalación base
    run install_base_system
    [ "$status" -eq 0 ]
    
    run generate_fstab
    [ "$status" -eq 0 ]
    
    # Verificar que se ejecutaron los comandos clave
    grep -q "pacstrap /mnt base linux linux-firmware" "$COMMANDS_LOG"
    grep -q "genfstab -U /mnt" "$COMMANDS_LOG"
}

@test "Integración: todas las funciones de validación se ejecutan correctamente" {
    # Activar mocks de validación
    mock_validation_commands
    mock_file_operations
    
    # Cargar módulo de validación
    source lib/validation.sh
    
    # Ejecutar todas las funciones de validación
    run validate_environment
    [ "$status" -eq 0 ]
    [[ "$output" == *"Entorno de Arch Linux validado correctamente"* ]]
    
    run check_network
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conectividad de red verificada correctamente"* ]]
    
    run check_disk "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disco '/dev/sda' validado correctamente"* ]]
    
    # Verificar que se registraron los comandos
    grep -q "ping" "$COMMANDS_LOG"
}

@test "Integración: secuencia completa de particionamiento funciona correctamente" {
    # Activar mocks de particionamiento
    mock_partitioning_commands
    mock_file_operations
    
    # Cargar módulo de particionamiento
    source lib/partitioning.sh
    
    # Ejecutar secuencia completa
    run partition_disk "/dev/sda"
    [ "$status" -eq 0 ]
    
    run format_partitions "/dev/sda"
    [ "$status" -eq 0 ]
    
    run mount_partitions "/dev/sda"
    [ "$status" -eq 0 ]
    
    # Verificar que se ejecutaron todos los comandos de particionamiento
    grep -q "parted -s /dev/sda mklabel gpt" "$COMMANDS_LOG"
    grep -q "mkfs.fat -F32 /dev/sda1" "$COMMANDS_LOG"
    grep -q "mkfs.ext4 -F /dev/sda2" "$COMMANDS_LOG"
    grep -q "mkswap /dev/sda3" "$COMMANDS_LOG"
    grep -q "mount /dev/sda2 /mnt" "$COMMANDS_LOG"
    grep -q "swapon /dev/sda3" "$COMMANDS_LOG"
}

@test "Integración: instalación base y generación de fstab funcionan correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_base_install_commands
    mock_file_operations
    
    # Cargar módulo de instalación base
    source lib/base_install.sh
    
    # Ejecutar instalación base
    run install_base_system
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sistema base instalado exitosamente"* ]]
    
    # Ejecutar generación de fstab
    run generate_fstab
    [ "$status" -eq 0 ]
    [[ "$output" == *"Archivo /etc/fstab generado exitosamente"* ]]
    
    # Verificar comandos ejecutados
    grep -q "pacstrap /mnt base linux linux-firmware" "$COMMANDS_LOG"
    grep -q "genfstab -U /mnt" "$COMMANDS_LOG"
}

@test "Integración: instalación y configuración de GRUB funcionan correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_bootloader_commands
    mock_file_operations
    
    # Cargar módulo de bootloader
    source lib/bootloader.sh
    
    # Ejecutar instalación de GRUB
    run install_grub
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRUB instalado exitosamente"* ]]
    
    # Ejecutar configuración de GRUB
    run configure_grub_silent
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRUB configurado para arranque silencioso"* ]]
    
    # Verificar comandos ejecutados
    grep -q "pacman -S --noconfirm grub efibootmgr" "$COMMANDS_LOG"
    grep -q "grub-install" "$COMMANDS_LOG"
    grep -q "grub-mkconfig" "$COMMANDS_LOG"
}

@test "Integración: instalación y configuración de Plymouth funcionan correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_bootloader_commands
    mock_plymouth_commands
    mock_file_operations
    
    # Cargar módulos necesarios
    source lib/plymouth.sh
    
    # Ejecutar instalación de Plymouth
    run install_plymouth
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plymouth instalado exitosamente"* ]]
    
    # Ejecutar creación de tema
    run create_custom_theme "arch-kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tema personalizado 'arch-kiosk' creado exitosamente"* ]]
    
    # Verificar comandos ejecutados
    grep -q "pacman -S --noconfirm plymouth" "$COMMANDS_LOG"
}

@test "Integración: instalación de drivers gráficos y audio funciona correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_bootloader_commands
    mock_file_operations
    
    # Cargar módulo de drivers
    source lib/drivers.sh
    
    # Ejecutar instalación de drivers gráficos
    run install_graphics_drivers
    [ "$status" -eq 0 ]
    [[ "$output" == *"Drivers gráficos instalados exitosamente"* ]]
    
    # Ejecutar instalación de sistema de audio
    run install_audio_system
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sistema de audio PipeWire instalado exitosamente"* ]]
    
    # Verificar comandos ejecutados
    grep -q "pacman -S --noconfirm xf86-video-amdgpu xf86-video-intel nvidia-open mesa" "$COMMANDS_LOG"
    grep -q "pacman -S --noconfirm pipewire pipewire-alsa pipewire-pulse pipewire-jack sof-firmware" "$COMMANDS_LOG"
}

@test "Integración: instalación y configuración de OpenBox funcionan correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_bootloader_commands
    mock_gui_commands
    mock_file_operations
    
    # Cargar módulo de GUI
    source lib/gui.sh
    
    # Ejecutar instalación de OpenBox
    run install_openbox
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenBox y servidor X instalados exitosamente"* ]]
    
    # Ejecutar creación de usuario
    run create_user "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Usuario 'kiosk' creado exitosamente"* ]]
    
    # Ejecutar configuración de autologin
    run configure_autologin "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Autologin configurado para usuario 'kiosk'"* ]]
    
    # Verificar comandos ejecutados
    grep -q "pacman -S --noconfirm xorg-server xorg-xinit openbox xterm" "$COMMANDS_LOG"
    grep -q "useradd" "$COMMANDS_LOG"
}

@test "Integración: configuración de xterm con apagado automático funciona correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_gui_commands
    mock_file_operations
    
    # Cargar módulo de GUI
    source lib/gui.sh
    
    # Ejecutar configuración de xterm autostart
    run configure_xterm_autostart "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"xterm con apagado automático configurado para usuario 'kiosk'"* ]]
}

@test "Integración: ocultación de mensajes del sistema funciona correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_file_operations
    
    # Cargar módulo de personalización
    source lib/customization.sh
    
    # Ejecutar ocultación de mensajes
    run hide_system_messages "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Mensajes del sistema ocultados para usuario 'kiosk'"* ]]
    
    # Verificar que se registraron las operaciones
    grep -q "touch" "$COMMANDS_LOG"
}

@test "Integración: configuración de red y finalización funcionan correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_bootloader_commands
    mock_finalization_commands
    mock_file_operations
    
    # Cargar módulo de finalización
    source lib/finalization.sh
    
    # Ejecutar configuración de red
    run configure_network
    [ "$status" -eq 0 ]
    [[ "$output" == *"NetworkManager, SSH y zona horaria configurados exitosamente"* ]]
    
    # Verificar comandos ejecutados
    grep -q "pacman -S --noconfirm networkmanager openssh" "$COMMANDS_LOG"
    grep -q "systemctl enable NetworkManager" "$COMMANDS_LOG"
    grep -q "systemctl enable sshd" "$COMMANDS_LOG"
    grep -q "timedatectl set-timezone" "$COMMANDS_LOG"
}

@test "Integración: limpieza y desmontaje funcionan correctamente" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_finalization_commands
    mock_file_operations
    
    # Cargar módulo de finalización
    source lib/finalization.sh
    
    # Ejecutar limpieza
    run cleanup_and_finish
    [ "$status" -eq 0 ]
    [[ "$output" == *"Limpieza completada exitosamente"* ]]
    [[ "$output" == *"puede reiniciar el sistema"* ]]
    
    # Verificar comandos de desmontaje
    grep -q "umount" "$COMMANDS_LOG"
    grep -q "swapoff" "$COMMANDS_LOG"
}

################################################################################
# Pruebas de Manejo de Errores
################################################################################

@test "Integración: error en validación de entorno detiene la ejecución" {
    # Mock que simula fallo en validación
    validate_environment() {
        log_error "No se detectó Arch Linux"
        return 1
    }
    export -f validate_environment
    
    mock_file_operations
    source lib/validation.sh
    
    run validate_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "Integración: error en particionamiento detiene la ejecución" {
    # Mock que simula fallo en particionamiento
    partition_disk() {
        log_error "Fallo al crear tabla GPT"
        return 1
    }
    export -f partition_disk
    
    mock_file_operations
    source lib/partitioning.sh
    
    run partition_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "Integración: error en instalación base detiene la ejecución" {
    # Mock que simula fallo en pacstrap
    pacstrap() {
        return 1
    }
    export -f pacstrap
    
    mock_validation_commands
    mock_file_operations
    source lib/base_install.sh
    
    run install_base_system
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

@test "Integración: error en instalación de GRUB detiene la ejecución" {
    # Mock que simula fallo en grub-install
    grub-install() {
        return 1
    }
    export -f grub-install
    
    pacman() {
        return 0
    }
    export -f pacman
    
    mock_validation_commands
    mock_file_operations
    source lib/bootloader.sh
    
    run install_grub
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
}

################################################################################
# Pruebas de Orden de Ejecución
################################################################################

@test "Integración: las funciones se ejecutan en el orden correcto" {
    # Activar todos los mocks
    mock_validation_commands
    mock_partitioning_commands
    mock_base_install_commands
    mock_bootloader_commands
    mock_plymouth_commands
    mock_gui_commands
    mock_finalization_commands
    mock_file_operations
    
    # Cargar todos los módulos
    source lib/validation.sh
    source lib/partitioning.sh
    source lib/base_install.sh
    source lib/bootloader.sh
    source lib/plymouth.sh
    source lib/drivers.sh
    source lib/gui.sh
    source lib/customization.sh
    source lib/finalization.sh
    
    # Ejecutar funciones en orden
    validate_environment
    check_network
    check_disk "/dev/sda"
    partition_disk "/dev/sda"
    format_partitions "/dev/sda"
    mount_partitions "/dev/sda"
    install_base_system
    generate_fstab
    
    # Verificar que los comandos se ejecutaron en el orden correcto
    # 1. Validación (ping)
    # 2. Particionamiento (parted)
    # 3. Formateo (mkfs)
    # 4. Montaje (mount)
    # 5. Instalación (pacstrap)
    # 6. Fstab (genfstab)
    
    local line_ping=$(grep -n "ping" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_parted=$(grep -n "parted" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_mkfs=$(grep -n "mkfs" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_mount=$(grep -n "mount" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_pacstrap=$(grep -n "pacstrap" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_genfstab=$(grep -n "genfstab" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    
    # Verificar orden: ping < parted < mkfs < mount < pacstrap < genfstab
    [[ $line_ping -lt $line_parted ]]
    [[ $line_parted -lt $line_mkfs ]]
    [[ $line_mkfs -lt $line_mount ]]
    [[ $line_mount -lt $line_pacstrap ]]
    [[ $line_pacstrap -lt $line_genfstab ]]
}

@test "Integración: configuración de GRUB se ejecuta después de instalación base" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_base_install_commands
    mock_bootloader_commands
    mock_file_operations
    
    # Cargar módulos
    source lib/base_install.sh
    source lib/bootloader.sh
    
    # Ejecutar en orden
    install_base_system
    generate_fstab
    install_grub
    configure_grub_silent
    
    # Verificar orden: pacstrap < genfstab < grub-install < grub-mkconfig
    local line_pacstrap=$(grep -n "pacstrap" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_genfstab=$(grep -n "genfstab" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_grub_install=$(grep -n "grub-install" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_grub_mkconfig=$(grep -n "grub-mkconfig" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    
    [[ $line_pacstrap -lt $line_genfstab ]]
    [[ $line_genfstab -lt $line_grub_install ]]
    [[ $line_grub_install -lt $line_grub_mkconfig ]]
}

@test "Integración: desmontaje se ejecuta al final de todo" {
    # Activar mocks necesarios
    mock_validation_commands
    mock_partitioning_commands
    mock_base_install_commands
    mock_finalization_commands
    mock_file_operations
    
    # Cargar módulos
    source lib/partitioning.sh
    source lib/base_install.sh
    source lib/finalization.sh
    
    # Ejecutar secuencia
    mount_partitions "/dev/sda"
    install_base_system
    cleanup_and_finish
    
    # Verificar que umount se ejecuta después de todo
    local line_mount=$(grep -n "mount /dev/sda2 /mnt" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_pacstrap=$(grep -n "pacstrap" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    local line_umount=$(grep -n "umount" "$COMMANDS_LOG" | head -1 | cut -d: -f1)
    
    [[ $line_mount -lt $line_pacstrap ]]
    [[ $line_pacstrap -lt $line_umount ]]
}
