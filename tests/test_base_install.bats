#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Instalación Base
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/base_install.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 4.1, 4.2, 4.3, 14.4
################################################################################

# Setup: cargar el módulo de instalación base antes de cada prueba
setup() {
    # Cargar el módulo de instalación base
    source lib/base_install.sh
    
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
# Pruebas para install_base_system()
################################################################################

@test "install_base_system: instalación exitosa con pacstrap retorna 0" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de pacstrap que registra los comandos
    pacstrap() {
        echo "pacstrap $*" >> /tmp/pacstrap_commands.log
        return 0
    }
    export -f pacstrap
    
    # Limpiar log de comandos
#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Instalación Base
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/base_install.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 4.1, 4.2, 4.3, 14.4
################################################################################

# Setup: cargar el módulo de instalación base antes de cada prueba
setup() {
    # Cargar el módulo de instalación base
    source lib/base_install.sh
    
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
# Pruebas para install_base_system()
################################################################################

@test "install_base_system: instalación exitosa con pacstrap retorna 0" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de pacstrap que registra los comandos
    pacstrap() {
        echo "pacstrap $*" >> /tmp/pacstrap_commands.log
        return 0
    }
    export -f pacstrap
    
    # Limpiar log de comandos
    rm -f /tmp/pacstrap_commands.log
    
    run install_base_system
    [ "$status" -eq 0 ]
    [[ "$output" == *"Sistema base instalado exitosamente"* ]]
    
    # Verificar que se llamó a pacstrap con los paquetes correctos
    grep -q "pacstrap /mnt base linux linux-firmware sudo wget curl unzip samba" /tmp/pacstrap_commands.log
    
    # Limpiar
    rm -f /tmp/pacstrap_commands.log
}

@test "install_base_system: comando pacstrap contiene exactamente base, linux, linux-firmware" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de pacstrap que registra los comandos
    pacstrap() {
        echo "pacstrap $*" >> /tmp/pacstrap_commands.log
        return 0
    }
    export -f pacstrap
    
    # Limpiar log de comandos
    rm -f /tmp/pacstrap_commands.log
    
    run install_base_system
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/pacstrap_commands.log)
    
    # Verificar que contiene exactamente los tres paquetes
    [[ "$command" == *"base"* ]]
    [[ "$command" == *"linux"* ]]
    [[ "$command" == *"linux-firmware"* ]]
    
    # Verificar que el comando es exactamente: pacstrap /mnt base linux linux-firmware sudo wget curl unzip samba
    [[ "$command" == "pacstrap /mnt base linux linux-firmware sudo wget curl unzip samba" ]]
    
    # Limpiar
    rm -f /tmp/pacstrap_commands.log
}

@test "install_base_system: /mnt no montado retorna 1" {
    # Mock de mountpoint que simula /mnt NO montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 1
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    run install_base_system
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"/mnt no está montado"* ]]
}

@test "install_base_system: fallo en pacstrap retorna 1" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de pacstrap que falla
    pacstrap() {
        return 1
    }
    export -f pacstrap
    
    run install_base_system
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar el sistema base con pacstrap"* ]]
}

################################################################################
# Pruebas para generate_fstab()
################################################################################

@test "generate_fstab: generación exitosa con genfstab -U retorna 0" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar directorio /mnt/etc
    test() {
        if [[ "$1" == "-d" && "$2" == "/mnt/etc" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de genfstab que registra los comandos
    genfstab() {
        echo "genfstab $*" >> /tmp/genfstab_commands.log
        return 0
    }
    export -f genfstab
    
    # Limpiar log de comandos
    rm -f /tmp/genfstab_commands.log
    
    run generate_fstab
    [ "$status" -eq 0 ]
    [[ "$output" == *"Archivo /etc/fstab generado exitosamente"* ]]
    
    # Verificar que se llamó a genfstab con opción -U
    grep -q "genfstab -U /mnt" /tmp/genfstab_commands.log
    
    # Limpiar
    rm -f /tmp/genfstab_commands.log
}

@test "generate_fstab: usa opción -U para UUIDs" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar directorio /mnt/etc
    test() {
        if [[ "$1" == "-d" && "$2" == "/mnt/etc" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de genfstab que registra los comandos
    genfstab() {
        echo "genfstab $*" >> /tmp/genfstab_commands.log
        return 0
    }
    export -f genfstab
    
    # Limpiar log de comandos
    rm -f /tmp/genfstab_commands.log
    
    run generate_fstab
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/genfstab_commands.log)
    
    # Verificar que contiene la opción -U
    [[ "$command" == *"-U"* ]]
    
    # Verificar que el comando es exactamente: genfstab -U /mnt
    [[ "$command" == "genfstab -U /mnt" ]]
    
    # Limpiar
    rm -f /tmp/genfstab_commands.log
}

@test "generate_fstab: /mnt no montado retorna 1" {
    # Mock de mountpoint que simula /mnt NO montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 1
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    run generate_fstab
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"/mnt no está montado"* ]]
}

@test "generate_fstab: directorio /mnt/etc no existe retorna 1" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar que /mnt/etc NO existe
    test() {
        if [[ "$1" == "-d" && "$2" == "/mnt/etc" ]]; then
            return 1
        fi
        command test "$@"
    }
    export -f test
    
    run generate_fstab
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"/mnt/etc no existe"* ]]
    [[ "$output" == *"sistema base debe estar instalado primero"* ]]
}

@test "generate_fstab: fallo en genfstab retorna 1" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar directorio /mnt/etc
    test() {
        if [[ "$1" == "-d" && "$2" == "/mnt/etc" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de genfstab que falla
    genfstab() {
        return 1
    }
    export -f genfstab
    
    run generate_fstab
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al generar /etc/fstab"* ]]
}

################################################################################
# Pruebas para configure_chroot()
################################################################################

@test "configure_chroot: configuración exitosa retorna 0" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar archivo /mnt/etc/fstab
    test() {
        if [[ "$1" == "-f" && "$2" == "/mnt/etc/fstab" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de command para verificar arch-chroot
    command() {
        if [[ "$1" == "-v" && "$2" == "arch-chroot" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    export -f command
    
    run configure_chroot
    [ "$status" -eq 0 ]
    [[ "$output" == *"Entorno chroot preparado y listo para configuración"* ]]
    [[ "$output" == *"arch-chroot /mnt"* ]]
}

@test "configure_chroot: genera comando arch-chroot correcto" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar archivo /mnt/etc/fstab
    test() {
        if [[ "$1" == "-f" && "$2" == "/mnt/etc/fstab" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de command para verificar arch-chroot
    command() {
        if [[ "$1" == "-v" && "$2" == "arch-chroot" ]]; then
            return 0
        fi
        builtin command "$@"
    }
    export -f command
    
    run configure_chroot
    [ "$status" -eq 0 ]
    
    # Verificar que el output menciona el comando correcto
    [[ "$output" == *"arch-chroot /mnt"* ]]
}

@test "configure_chroot: /mnt no montado retorna 1" {
    # Mock de mountpoint que simula /mnt NO montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 1
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    run configure_chroot
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"/mnt no está montado"* ]]
}

@test "configure_chroot: archivo /mnt/etc/fstab no existe retorna 1" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar que /mnt/etc/fstab NO existe
    test() {
        if [[ "$1" == "-f" && "$2" == "/mnt/etc/fstab" ]]; then
            return 1
        fi
        command test "$@"
    }
    export -f test
    
    run configure_chroot
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"/mnt/etc/fstab no existe"* ]]
    [[ "$output" == *"Ejecute generate_fstab primero"* ]]
}

@test "configure_chroot: comando arch-chroot no disponible retorna 1" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de test para verificar archivo /mnt/etc/fstab
    test() {
        if [[ "$1" == "-f" && "$2" == "/mnt/etc/fstab" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test
    
    # Mock de command para simular que arch-chroot NO está disponible
    command() {
        if [[ "$1" == "-v" && "$2" == "arch-chroot" ]]; then
            return 1
        fi
        builtin command "$@"
    }
    export -f command
    
    run configure_chroot
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"arch-chroot no está disponible"* ]]
}

################################################################################
# Prueba de Propiedad para install_base_system()
# Property 9: Comando pacstrap correcto
# Validates: Requirements 4.1
################################################################################

@test "Property 9: install_base_system genera comando pacstrap con paquetes correctos" {
    # Mock de mountpoint que simula /mnt montado
    mountpoint() {
        if [[ "$*" == *"-q /mnt"* ]]; then
            return 0
        fi
        command mountpoint "$@"
    }
    export -f mountpoint
    
    # Mock de pacstrap que registra los comandos
    pacstrap() {
        echo "pacstrap $*" >> /tmp/pacstrap_commands.log
        return 0
    }
    export -f pacstrap
    
    # Limpiar log de comandos
    rm -f /tmp/pacstrap_commands.log
    
    # Ejecutar la función
    run install_base_system
    [ "$status" -eq 0 ]
    
    # Leer el comando ejecutado
    local command=$(cat /tmp/pacstrap_commands.log)
    
    # Verificar que el comando contiene exactamente los paquetes requeridos
    # y que están en el orden correcto
    [[ "$command" == "pacstrap /mnt base linux linux-firmware sudo wget curl unzip samba" ]]
    
    # Verificar que contiene cada paquete individualmente
    [[ "$command" == *"base"* ]]
    [[ "$command" == *"linux"* ]]
    [[ "$command" == *"linux-firmware"* ]]
    
    # Verificar que no contiene paquetes inesperados (total: pacstrap + /mnt + base + linux + linux-firmware + sudo + wget + curl + unzip + samba = 10 palabras)
    local word_count=$(echo "$command" | wc -w)
    [[ $word_count -eq 10 ]]
    
    # Limpiar
    rm -f /tmp/pacstrap_commands.log
}
