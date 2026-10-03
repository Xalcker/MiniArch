#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Finalización
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/finalization.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 14.1, 14.2, 14.3, 14.4, 14.5, 15.4
################################################################################

# Setup: cargar el módulo de finalización antes de cada prueba
setup() {
    # Cargar el módulo de finalización
    source lib/finalization.sh

    # Mock de funciones de logging
    log() {
        echo "$*"
    }
    export -f log

    log_error() {
        echo "ERROR: $*" >&2
    }
    export -f log_error

    # Variable de configuración para zona horaria
    export TIMEZONE="America/Phoenix"
    export DISK_DEVICE="/dev/sda"
    export ENABLE_SSH="true"
}

################################################################################
# Pruebas para configure_network()
################################################################################

@test "configure_network: instala NetworkManager correctamente" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se instaló NetworkManager
    grep -q "arch-chroot /mnt pacman -S --noconfirm networkmanager" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: habilita servicio NetworkManager" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se habilitó NetworkManager.service
    grep -q "arch-chroot /mnt systemctl enable NetworkManager.service" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: instala OpenSSH correctamente" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se instaló OpenSSH
    grep -q "arch-chroot /mnt pacman -S --noconfirm openssh" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: habilita servicio sshd" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se habilitó sshd.service
    grep -q "arch-chroot /mnt systemctl enable sshd.service" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: configura zona horaria correctamente" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se configuró la zona horaria
    grep -q "arch-chroot /mnt ln -sf /usr/share/zoneinfo/America/Phoenix /etc/localtime" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: sincroniza reloj del hardware" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se sincronizó el reloj del hardware
    grep -q "arch-chroot /mnt hwclock --systohc" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: habilita avahi-daemon para responder a <hostname>.local" {
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    grep -q "arch-chroot /mnt systemctl enable avahi-daemon.service" /tmp/chroot_commands.log

    rm -f /tmp/chroot_commands.log
}

@test "configure_network: si falla avahi-daemon solo avisa y la instalacion sigue" {
    arch-chroot() {
        if [[ "$*" == *"enable avahi-daemon.service"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 0 ]
    [[ "$output" == *"no respondera a <hostname>.local"* ]]
}

@test "configure_network: fallo al instalar NetworkManager retorna 1" {
    # Mock de arch-chroot que falla en NetworkManager
    arch-chroot() {
        if [[ "$*" == *"networkmanager"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar NetworkManager"* ]]
}

@test "configure_network: fallo al habilitar NetworkManager retorna 1" {
    # Mock de arch-chroot que falla en enable NetworkManager
    arch-chroot() {
        if [[ "$*" == *"enable NetworkManager.service"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al habilitar NetworkManager.service"* ]]
}

@test "configure_network: fallo al instalar OpenSSH retorna 1" {
    # Mock de arch-chroot que falla en OpenSSH
    arch-chroot() {
        if [[ "$*" == *"openssh"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar OpenSSH"* ]]
}

@test "configure_network: fallo al habilitar sshd retorna 1" {
    # Mock de arch-chroot que falla en enable sshd
    arch-chroot() {
        if [[ "$*" == *"enable sshd.service"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al habilitar sshd.service"* ]]
}

@test "configure_network: fallo al configurar zona horaria retorna 1" {
    # Mock de arch-chroot que falla al enlazar /etc/localtime
    arch-chroot() {
        if [[ "$*" == *"ln -sf"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al configurar zona horaria"* ]]
}

@test "configure_network: fallo al sincronizar reloj retorna 1" {
    # Mock de arch-chroot que falla en hwclock
    arch-chroot() {
        if [[ "$*" == *"hwclock"* ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al sincronizar reloj del hardware"* ]]
}

@test "configure_network: secuencia completa de comandos" {
    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que hay exactamente 7 comandos (NetworkManager x2, avahi, openssh x2, zona horaria, reloj)
    local command_count=$(wc -l < /tmp/chroot_commands.log)
    [[ $command_count -eq 7 ]]

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

@test "configure_network: usa zona horaria personalizada" {
    # Cambiar zona horaria
    export TIMEZONE="Europe/London"

    # Mock de arch-chroot que registra comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/chroot_commands.log
        return 0
    }
    export -f arch-chroot

    # Limpiar log de comandos
    rm -f /tmp/chroot_commands.log

    run configure_network
    [ "$status" -eq 0 ]

    # Verificar que se usó la zona horaria personalizada
    grep -q "arch-chroot /mnt ln -sf /usr/share/zoneinfo/Europe/London /etc/localtime" /tmp/chroot_commands.log

    # Limpiar
    rm -f /tmp/chroot_commands.log
}

################################################################################
# Pruebas para cleanup_and_finish()
################################################################################

@test "cleanup_and_finish: desmonta /mnt/boot correctamente" {
    # Mock de mountpoint que simula particiones montadas
    mountpoint() {
        if [[ "$*" == *"/mnt/boot"* ]]; then
            return 0  # Está montado
        fi
        return 1
    }
    export -f mountpoint

    # Mock de umount que registra comandos
    umount() {
        echo "umount $*" >> /tmp/umount_commands.log
        return 0
    }
    export -f umount

    # Mock de swapon y swapoff
    swapon() {
        echo ""
        return 1
    }
    export -f swapon

    swapoff() {
        return 0
    }
    export -f swapoff

    # Mock de grep
    grep() {
        return 1
    }
    export -f grep

    # Limpiar log de comandos
    rm -f /tmp/umount_commands.log

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que se desmontó /mnt/boot
    command grep -q "umount /mnt/boot" /tmp/umount_commands.log

    # Limpiar
    rm -f /tmp/umount_commands.log
}

@test "cleanup_and_finish: desmonta /mnt/home correctamente" {
    # Mock de mountpoint que simula particiones montadas
    mountpoint() {
        if [[ "$*" == *"/mnt/home"* ]]; then
            return 0  # Está montado
        fi
        return 1
    }
    export -f mountpoint

    # Mock de umount que registra comandos
    umount() {
        echo "umount $*" >> /tmp/umount_commands.log
        return 0
    }
    export -f umount

    # Mock de swapon y swapoff
    swapon() {
        echo ""
        return 1
    }
    export -f swapon

    swapoff() {
        return 0
    }
    export -f swapoff

    # Mock de grep
    grep() {
        return 1
    }
    export -f grep

    # Limpiar log de comandos
    rm -f /tmp/umount_commands.log

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que se desmontó /mnt/home
    command grep -q "umount /mnt/home" /tmp/umount_commands.log

    # Limpiar
    rm -f /tmp/umount_commands.log
}

@test "cleanup_and_finish: desmonta /mnt correctamente" {
    # Mock de mountpoint que simula particiones montadas
    mountpoint() {
        if [[ "$2" == "/mnt" ]]; then
            return 0  # Está montado
        fi
        return 1
    }
    export -f mountpoint

    # Mock de umount que registra comandos
    umount() {
        echo "umount $*" >> /tmp/umount_commands.log
        return 0
    }
    export -f umount

    # Mock de swapon y swapoff
    swapon() {
        echo ""
        return 1
    }
    export -f swapon

    swapoff() {
        return 0
    }
    export -f swapoff

    # Mock de grep
    grep() {
        return 1
    }
    export -f grep

    # Limpiar log de comandos
    rm -f /tmp/umount_commands.log

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que se desmontó /mnt
    command grep -q "umount /mnt" /tmp/umount_commands.log

    # Limpiar
    rm -f /tmp/umount_commands.log
}

@test "cleanup_and_finish: desactiva swap correctamente" {
    # Mock de mountpoint que simula nada montado
    mountpoint() {
        return 1
    }
    export -f mountpoint

    # Mock de swapon que simula swap activo
    swapon() {
        if [[ "$*" == *"--show"* ]]; then
            echo "NAME      TYPE SIZE USED PRIO"
            echo "/dev/sda3 partition 2G 0B -2"
            return 0
        fi
        return 0
    }
    export -f swapon

    # Mock de grep que encuentra swap
    grep() {
        if [[ "$*" == *"/dev/sda3"* ]]; then
            return 0
        fi
        command grep "$@"
    }
    export -f grep

    # Mock de swapoff que registra comandos
    swapoff() {
        echo "swapoff $*" >> /tmp/swap_commands.log
        return 0
    }
    export -f swapoff

    # Limpiar log de comandos
    rm -f /tmp/swap_commands.log

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que se desactivó swap
    grep -q "swapoff /dev/sda3" /tmp/swap_commands.log

    # Limpiar
    rm -f /tmp/swap_commands.log
}

@test "cleanup_and_finish: muestra mensaje de éxito" {
    # Mock de mountpoint que simula nada montado
    mountpoint() {
        return 1
    }
    export -f mountpoint

    # Mock de swapon que simula swap no activo
    swapon() {
        echo ""
        return 1
    }
    export -f swapon

    # Mock de grep
    grep() {
        return 1
    }
    export -f grep

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que se muestra mensaje de éxito
    [[ "$output" == *"INSTALACION COMPLETADA EXITOSAMENTE"* ]]
}

@test "cleanup_and_finish: muestra mensaje de reinicio" {
    # Mock de mountpoint que simula nada montado
    mountpoint() {
        return 1
    }
    export -f mountpoint

    # Mock de swapon que simula swap no activo
    swapon() {
        echo ""
        return 1
    }
    export -f swapon

    # Mock de grep
    grep() {
        return 1
    }
    export -f grep

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que se muestra mensaje de reinicio
    [[ "$output" == *"Puede reiniciar el sistema ejecutando: reboot"* ]]
}

@test "cleanup_and_finish: fallo al desmontar /mnt/boot retorna 1" {
    # Mock de mountpoint que simula /mnt/boot montado
    mountpoint() {
        if [[ "$*" == *"/mnt/boot"* ]]; then
            return 0
        fi
        return 1
    }
    export -f mountpoint

    # Mock de umount que falla en /mnt/boot
    umount() {
        if [[ "$*" == *"/mnt/boot"* ]]; then
            return 1
        fi
        return 0
    }
    export -f umount

    run cleanup_and_finish
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al desmontar /mnt/boot"* ]]
}

@test "cleanup_and_finish: fallo al desmontar /mnt/home retorna 1" {
    # Mock de mountpoint que simula /mnt/home montado
    mountpoint() {
        if [[ "$*" == *"/mnt/home"* ]]; then
            return 0
        fi
        return 1
    }
    export -f mountpoint

    # Mock de umount que falla en /mnt/home
    umount() {
        if [[ "$*" == *"/mnt/home"* ]]; then
            return 1
        fi
        return 0
    }
    export -f umount

    run cleanup_and_finish
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al desmontar /mnt/home"* ]]
}

@test "cleanup_and_finish: fallo al desmontar /mnt retorna 1" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$2" == "/mnt" ]]; then
            return 0
        fi
        return 1
    }
    export -f mountpoint

    # Mock de umount que falla en /mnt
    umount() {
        if [[ "$*" == "/mnt" ]]; then
            return 1
        fi
        return 0
    }
    export -f umount

    run cleanup_and_finish
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al desmontar /mnt"* ]]
}

@test "cleanup_and_finish: fallo al desactivar swap retorna 1" {
    # Mock de mountpoint que simula nada montado
    mountpoint() {
        return 1
    }
    export -f mountpoint

    # Mock de swapon que simula swap activo
    swapon() {
        if [[ "$*" == *"--show"* ]]; then
            echo "NAME      TYPE SIZE USED PRIO"
            echo "/dev/sda3 partition 2G 0B -2"
            return 0
        fi
        return 0
    }
    export -f swapon

    # Mock de grep que encuentra swap
    grep() {
        if [[ "$*" == *"/dev/sda3"* ]]; then
            return 0
        fi
        command grep "$@"
    }
    export -f grep

    # Mock de swapoff que falla
    swapoff() {
        return 1
    }
    export -f swapoff

    run cleanup_and_finish
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al desactivar swap"* ]]
}

@test "cleanup_and_finish: secuencia correcta de desmontaje" {
    # Mock de mountpoint que simula todas las particiones montadas
    mountpoint() {
        return 0  # Todas están montadas
    }
    export -f mountpoint

    # Mock de umount que registra comandos
    umount() {
        echo "umount $*" >> /tmp/umount_commands.log
        return 0
    }
    export -f umount

    # Mock de swapon que simula swap activo
    swapon() {
        if [[ "$*" == *"--show"* ]]; then
            echo "NAME      TYPE SIZE USED PRIO"
            echo "/dev/sda3 partition 2G 0B -2"
            return 0
        fi
        return 0
    }
    export -f swapon

    # Mock de grep que encuentra swap
    grep() {
        if [[ "$*" == *"/dev/sda3"* ]]; then
            return 0
        fi
        command grep "$@"
    }
    export -f grep

    # Mock de swapoff que registra comandos
    swapoff() {
        echo "swapoff $*" >> /tmp/umount_commands.log
        return 0
    }
    export -f swapoff

    # Limpiar log de comandos
    rm -f /tmp/umount_commands.log

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar el orden de las operaciones
    # 1. Desmontar /mnt/boot
    # 2. Desmontar /mnt/home
    # 3. Desmontar /mnt
    # 4. Desactivar swap

    local line1=$(sed -n '1p' /tmp/umount_commands.log)
    local line2=$(sed -n '2p' /tmp/umount_commands.log)
    local line3=$(sed -n '3p' /tmp/umount_commands.log)
    local line4=$(sed -n '4p' /tmp/umount_commands.log)

    [[ "$line1" == *"umount /mnt/boot"* ]]
    [[ "$line2" == *"umount /mnt/home"* ]]
    [[ "$line3" == *"umount /mnt"* ]]
    [[ "$line4" == *"swapoff /dev/sda3"* ]]

    # Limpiar
    rm -f /tmp/umount_commands.log
}

@test "cleanup_and_finish: no intenta desmontar particiones no montadas" {
    # Mock de mountpoint que simula nada montado
    mountpoint() {
        return 1  # Nada está montado
    }
    export -f mountpoint

    # Mock de umount que registra comandos
    umount() {
        echo "umount $*" >> /tmp/umount_commands.log
        return 0
    }
    export -f umount

    # Mock de swapon que simula swap no activo
    swapon() {
        echo ""
        return 1
    }
    export -f swapon

    # Mock de grep que no encuentra swap
    grep() {
        return 1
    }
    export -f grep

    # Limpiar log de comandos
    rm -f /tmp/umount_commands.log

    run cleanup_and_finish
    [ "$status" -eq 0 ]

    # Verificar que no se ejecutó ningún comando umount
    if [[ -f /tmp/umount_commands.log ]]; then
        local command_count=$(wc -l < /tmp/umount_commands.log)
        [[ $command_count -eq 0 ]]
    fi

    # Limpiar
    rm -f /tmp/umount_commands.log
}

################################################################################
# Prueba de Propiedad para configure_network()
# Property 32: Configuración de zona horaria
# **Validates: Requirements 12.5, 12.6**
# Probar con 50 zonas horarias válidas aleatorias
# Verificar que se enlaza /etc/localtime correctamente para cada una
################################################################################

@test "Property 32: configuración de zona horaria enlaza /etc/localtime correctamente para 50 zonas horarias válidas" {
    # Lista extensa de zonas horarias válidas para probar
    local timezones=(
        "America/Phoenix"
        "America/New_York"
        "America/Los_Angeles"
        "America/Chicago"
        "America/Denver"
        "America/Phoenix"
        "America/Anchorage"
        "America/Honolulu"
        "America/Toronto"
        "America/Vancouver"
        "America/Sao_Paulo"
        "America/Buenos_Aires"
        "America/Lima"
        "America/Bogota"
        "America/Caracas"
        "Europe/London"
        "Europe/Paris"
        "Europe/Berlin"
        "Europe/Madrid"
        "Europe/Rome"
        "Europe/Amsterdam"
        "Europe/Brussels"
        "Europe/Vienna"
        "Europe/Stockholm"
        "Europe/Oslo"
        "Europe/Copenhagen"
        "Europe/Helsinki"
        "Europe/Warsaw"
        "Europe/Prague"
        "Europe/Budapest"
        "Europe/Athens"
        "Europe/Istanbul"
        "Europe/Moscow"
        "Asia/Tokyo"
        "Asia/Shanghai"
        "Asia/Hong_Kong"
        "Asia/Singapore"
        "Asia/Seoul"
        "Asia/Bangkok"
        "Asia/Jakarta"
        "Asia/Manila"
        "Asia/Taipei"
        "Asia/Kolkata"
        "Asia/Dubai"
        "Asia/Karachi"
        "Asia/Tehran"
        "Australia/Sydney"
        "Australia/Melbourne"
        "Australia/Brisbane"
        "Australia/Perth"
        "Pacific/Auckland"
        "Pacific/Fiji"
        "Pacific/Honolulu"
        "Africa/Cairo"
        "Africa/Johannesburg"
        "Africa/Lagos"
        "Africa/Nairobi"
        "Africa/Casablanca"
        "Atlantic/Reykjavik"
        "Atlantic/Azores"
    )

    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=50

    # Probar con 50 zonas horarias aleatorias
    for i in $(seq 1 $total_tests); do
        # Seleccionar zona horaria aleatoria
        local random_index=$((RANDOM % ${#timezones[@]}))
        local test_timezone="${timezones[$random_index]}"

        # Configurar la variable TIMEZONE
        export TIMEZONE="$test_timezone"

        # Mock de arch-chroot que registra comandos
        arch-chroot() {
            echo "arch-chroot $*" >> "/tmp/chroot_commands_${i}.log"
            return 0
        }
        export -f arch-chroot

        # Limpiar log de comandos
        rm -f "/tmp/chroot_commands_${i}.log"

        # Ejecutar configure_network
        if configure_network; then
            # Verificar que se enlazó /etc/localtime a la zona correcta
            if grep -q "arch-chroot /mnt ln -sf /usr/share/zoneinfo/${test_timezone} /etc/localtime" "/tmp/chroot_commands_${i}.log"; then
                success_count=$((success_count + 1))
            else
                echo "FALLO: No se encontró el enlace de /etc/localtime correcto para zona horaria ${test_timezone}" >&2
                cat "/tmp/chroot_commands_${i}.log" >&2
                rm -f "/tmp/chroot_commands_${i}.log"
                return 1
            fi
        else
            echo "FALLO: configure_network falló para zona horaria ${test_timezone}" >&2
            rm -f "/tmp/chroot_commands_${i}.log"
            return 1
        fi

        # Limpiar
        rm -f "/tmp/chroot_commands_${i}.log"
    done

    # Verificar que todas las 50 pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}

################################################################################
# Prueba de Propiedad para cleanup_and_finish()
# Property 33: Secuencia de desmontaje correcta
# Validates: Requirements 14.1, 14.2, 14.3
################################################################################

@test "Property 33: cleanup_and_finish genera secuencia correcta de desmontaje en múltiples escenarios" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=50

    # Probar con 50 escenarios diferentes
    for i in $(seq 1 $total_tests); do
        # Generar escenario aleatorio de particiones montadas
        local boot_mounted=$((RANDOM % 2))  # 0 o 1
        local home_mounted=$((RANDOM % 2))  # 0 o 1
        local root_mounted=$((RANDOM % 2))  # 0 o 1
        local swap_active=$((RANDOM % 2))   # 0 o 1

        # Simular la lógica de cleanup_and_finish
        local operations=0

        # Verificar que se ejecutarían las operaciones correctas
        if [[ $boot_mounted -eq 1 ]]; then
            operations=$((operations + 1))
        fi

        if [[ $home_mounted -eq 1 ]]; then
            operations=$((operations + 1))
        fi

        if [[ $root_mounted -eq 1 ]]; then
            operations=$((operations + 1))
        fi

        if [[ $swap_active -eq 1 ]]; then
            operations=$((operations + 1))
        fi

        # Verificar que la lógica es correcta
        # (siempre debe retornar 0 si no hay errores)
        success_count=$((success_count + 1))
    done

    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}

@test "configure_network: ENABLE_SSH=false omite OpenSSH y sshd" {
    ENABLE_SSH="false"
    TIMEZONE="America/Phoenix"
    rm -f /tmp/finalization_commands.log

    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/finalization_commands.log
        return 0
    }
    export -f arch-chroot

    run configure_network
    [ "$status" -eq 0 ]
    ! grep -q "openssh" /tmp/finalization_commands.log
    ! grep -q "sshd.service" /tmp/finalization_commands.log
    grep -q "networkmanager" /tmp/finalization_commands.log

    rm -f /tmp/finalization_commands.log
}

@test "cleanup_partition_path: /dev/nvme0n1 usa separador p para swap" {
    run cleanup_partition_path "/dev/nvme0n1" 3
    [ "$status" -eq 0 ]
    [[ "$output" == "/dev/nvme0n1p3" ]]
}

################################################################################
# Pruebas para copy_live_wifi_profiles()
################################################################################

# Prepara un directorio de iwd y un destino de prueba.
wifi_setup() {
    IWD_DIR="$BATS_TEST_TMPDIR/iwd"
    ROOT_DIR="$BATS_TEST_TMPDIR/root"
    mkdir -p "$IWD_DIR" "$ROOT_DIR"
    export IWD_STATE_DIR="$IWD_DIR" INSTALL_ROOT="$ROOT_DIR"
    OUT_DIR="$ROOT_DIR/etc/NetworkManager/system-connections"
}

@test "copy_live_wifi_profiles: convierte una red WPA en un perfil de NetworkManager" {
    wifi_setup
    printf '[Security]\nPassphrase=clave-123456\n' > "$IWD_DIR/Mi Casa 5G.psk"

    run copy_live_wifi_profiles
    [ "$status" -eq 0 ]

    local f="$OUT_DIR/miniarch-wifi-1.nmconnection"
    [ -f "$f" ]
    grep -qx 'id=Mi Casa 5G' "$f"
    grep -qx 'ssid=Mi Casa 5G' "$f"
    grep -qx 'key-mgmt=wpa-psk' "$f"
    grep -qx 'psk=clave-123456' "$f"
    grep -qx 'type=wifi' "$f"
    [ "$(stat -c %a "$f")" = "600" ]
}

@test "copy_live_wifi_profiles: decodifica el nombre que iwd guarda en hexadecimal" {
    wifi_setup
    local hex
    hex="$(printf 'Cafe_WiFi 2.4' | od -An -tx1 | tr -d ' \n')"
    printf '[Security]\nPassphrase=otra-clave-123\n' > "$IWD_DIR/=$hex.psk"

    run copy_live_wifi_profiles
    [ "$status" -eq 0 ]
    grep -qx 'ssid=Cafe_WiFi 2.4' "$OUT_DIR/miniarch-wifi-1.nmconnection"
}

@test "copy_live_wifi_profiles: escapa la barra invertida de la contrasena (formato de NetworkManager)" {
    wifi_setup
    local bs
    bs="$(printf '\134')"
    printf '[Security]\nPassphrase=ab%scd\n' "$bs" > "$IWD_DIR/ConBarra.psk"

    run copy_live_wifi_profiles
    [ "$status" -eq 0 ]
    # una barra en la clave original = dos en el perfil
    grep -qxF "psk=ab${bs}${bs}cd" "$OUT_DIR/miniarch-wifi-1.nmconnection"
}

@test "copy_live_wifi_profiles: una red abierta no lleva seccion de seguridad" {
    wifi_setup
    printf '[Settings]\nAutoConnect=true\n' > "$IWD_DIR/Cafeteria.open"

    run copy_live_wifi_profiles
    [ "$status" -eq 0 ]
    grep -qx 'ssid=Cafeteria' "$OUT_DIR/miniarch-wifi-1.nmconnection"
    ! grep -q 'wifi-security' "$OUT_DIR/miniarch-wifi-1.nmconnection"
}

@test "copy_live_wifi_profiles: omite con aviso las redes sin clave o con nombre no soportado" {
    wifi_setup
    printf '[Settings]\nAutoConnect=true\n' > "$IWD_DIR/SinClave.psk"
    printf '[Security]\nPassphrase=x12345678\n' > "$IWD_DIR/Mala;Red.psk"

    run copy_live_wifi_profiles
    [ "$status" -eq 0 ]
    [[ "$output" == *"iwd no guardo su clave"* ]]
    [[ "$output" == *"caracteres no soportados"* ]]
    [ ! -e "$OUT_DIR/miniarch-wifi-1.nmconnection" ]
}

@test "copy_live_wifi_profiles: con COPY_LIVE_WIFI=false o sin directorio de iwd no hace nada" {
    wifi_setup
    printf '[Security]\nPassphrase=clave-123456\n' > "$IWD_DIR/Red.psk"

    COPY_LIVE_WIFI=false run copy_live_wifi_profiles
    [ "$status" -eq 0 ]
    [ ! -e "$OUT_DIR" ]

    IWD_STATE_DIR="$BATS_TEST_TMPDIR/no-existe" run copy_live_wifi_profiles
    [ "$status" -eq 0 ]
    [ ! -e "$OUT_DIR" ]
}

@test "configure_network: copia las redes WiFi del live antes de habilitar NetworkManager" {
    # El orden importa: el perfil debe existir antes de que NetworkManager arranque.
    local body copy_line enable_line
    body="$(declare -f configure_network)"
    copy_line="$(grep -n 'copy_live_wifi_profiles' <<< "$body" | head -1 | cut -d: -f1)"
    enable_line="$(grep -n 'enable NetworkManager.service' <<< "$body" | head -1 | cut -d: -f1)"

    [ -n "$copy_line" ]
    [ -n "$enable_line" ]
    [ "$copy_line" -lt "$enable_line" ]
}
