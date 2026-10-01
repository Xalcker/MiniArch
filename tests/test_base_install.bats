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

    # generate_fstab usa 2>> "$LOG_FILE"; sin esta variable la redireccion falla.
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    
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
# Pruebas para generate_fstab()
################################################################################

@test "generate_fstab: generación exitosa con genfstab -U retorna 0" {
    [[ -d /mnt/etc ]] || skip "requiere /mnt/etc real (el codigo usa [[ -d ]], no mockeable); ejecutar en el live ISO"
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
    [[ -d /mnt/etc ]] || skip "requiere /mnt/etc real (el codigo usa [[ -d ]], no mockeable); ejecutar en el live ISO"
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
    [[ -d /mnt/etc ]] || skip "requiere /mnt/etc real (el codigo usa [[ -d ]], no mockeable); ejecutar en el live ISO"
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






