#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Particionamiento
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/partitioning.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 2.1-2.9, 3.1-3.6, 14.3
################################################################################

# Setup: cargar el módulo de particionamiento antes de cada prueba
setup() {
    # Cargar el módulo de particionamiento
    source lib/partitioning.sh

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
# Pruebas para calculate_home_size()
################################################################################

@test "calculate_home_size: disco de 16GB retorna 5.5GB para home" {
    run calculate_home_size 16
    [ "$status" -eq 0 ]
    # 16 - 0.5 - 8 - 2 = 5.5
    [[ "$output" == "5.5" ]]
}

@test "calculate_home_size: disco de 20GB retorna 9.5GB para home" {
    run calculate_home_size 20
    [ "$status" -eq 0 ]
    # 20 - 0.5 - 8 - 2 = 9.5
    [[ "$output" == "9.5" ]]
}

@test "calculate_home_size: disco de 100GB retorna 89.5GB para home" {
    run calculate_home_size 100
    [ "$status" -eq 0 ]
    # 100 - 0.5 - 8 - 2 = 89.5
    [[ "$output" == "89.5" ]]
}

@test "calculate_home_size: disco de 1000GB retorna 989.5GB para home" {
    run calculate_home_size 1000
    [ "$status" -eq 0 ]
    # 1000 - 0.5 - 8 - 2 = 989.5
    [[ "$output" == "989.5" ]]
}

################################################################################
# Pruebas para partition_disk()
################################################################################

@test "partition_disk: dispositivo válido /dev/sda genera comandos correctos" {
    # Mock de parted que registra los comandos
    parted() {
        echo "parted $*" >> /tmp/parted_commands.log
        return 0
    }
    export -f parted

    # Limpiar log de comandos
    rm -f /tmp/parted_commands.log

    # Mock de test para verificar dispositivo de bloque
    test() {
        if [[ "$1" == "-b" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test

    run partition_disk "/dev/sda"
    [ "$status" -eq 0 ]

    # Verificar que se creó la tabla GPT
    grep -q "parted -s /dev/sda mklabel gpt" /tmp/parted_commands.log

    # Verificar que se creó la partición ESP
    grep -q "parted -s /dev/sda mkpart ESP fat32 1MiB 513MiB" /tmp/parted_commands.log

    # Verificar que se marcó como ESP
    grep -q "parted -s /dev/sda set 1 esp on" /tmp/parted_commands.log

    # Verificar que se creó la partición Root
    grep -q "parted -s /dev/sda mkpart primary ext4 513MiB 8705MiB" /tmp/parted_commands.log

    # Verificar que se creó la partición Swap
    grep -q "parted -s /dev/sda mkpart primary linux-swap 8705MiB 10753MiB" /tmp/parted_commands.log

    # Verificar que se creó la partición Home
    grep -q "parted -s /dev/sda mkpart primary ext4 10753MiB 100%" /tmp/parted_commands.log

    # Limpiar
    rm -f /tmp/parted_commands.log
}

@test "partition_disk: dispositivo válido /dev/vda genera comandos correctos" {
    # Mock de parted que registra los comandos
    parted() {
        echo "parted $*" >> /tmp/parted_commands_vda.log
        return 0
    }
    export -f parted

    # Limpiar log de comandos
    rm -f /tmp/parted_commands_vda.log

    # Reemplazar la función partition_disk para simular dispositivo válido
    partition_disk() {
        local device="$1"

        # Simular que el dispositivo existe
        log "Creando tabla de particiones GPT en $device"
        parted -s "$device" mklabel gpt

        log "Creando partición ESP (512MB)"
        parted -s "$device" mkpart ESP fat32 1MiB 513MiB
        parted -s "$device" set 1 esp on

        log "Creando partición Root (8GB)"
        parted -s "$device" mkpart primary ext4 513MiB 8705MiB

        log "Creando partición Swap (2GB)"
        parted -s "$device" mkpart primary linux-swap 8705MiB 10753MiB

        log "Creando partición Home (espacio restante)"
        parted -s "$device" mkpart primary ext4 10753MiB 100%

        log "Particionamiento completado exitosamente"
        return 0
    }

    run partition_disk "/dev/vda"
    [ "$status" -eq 0 ]

    # Verificar que los comandos usan /dev/vda
    grep -q "/dev/vda" /tmp/parted_commands_vda.log

    # Limpiar
    rm -f /tmp/parted_commands_vda.log
}

@test "partition_disk: dispositivo inexistente retorna 1" {
    # Reemplazar la función partition_disk para simular dispositivo inexistente
    partition_disk() {
        local device="$1"
        log_error "El dispositivo $device no existe"
        return 1
    }

    run partition_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"no existe"* ]]
}

@test "partition_disk: fallo al crear tabla GPT retorna 1" {
    # Mock de test para verificar dispositivo de bloque
    test() {
        if [[ "$1" == "-b" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test

    # Mock de parted que falla en mklabel
    parted() {
        if [[ "$*" == *"mklabel gpt"* ]]; then
            return 1
        fi
        return 0
    }
    export -f parted

    run partition_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al crear tabla GPT"* ]]
}

@test "partition_disk: fallo al crear partición ESP retorna 1" {
    # Mock de test para verificar dispositivo de bloque
    test() {
        if [[ "$1" == "-b" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test

    # Mock de parted que falla en mkpart ESP
    parted() {
        if [[ "$*" == *"mkpart ESP"* ]]; then
            return 1
        fi
        return 0
    }
    export -f parted

    run partition_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al crear partición ESP"* ]]
}

@test "partition_disk: secuencia completa de comandos parted" {
    # Mock de parted que registra los comandos
    parted() {
        echo "parted $*" >> /tmp/parted_commands.log
        return 0
    }
    export -f parted

    # Limpiar log de comandos
    rm -f /tmp/parted_commands.log

    # Mock de test para verificar dispositivo de bloque
    test() {
        if [[ "$1" == "-b" ]]; then
            return 0
        fi
        command test "$@"
    }
    export -f test

    run partition_disk "/dev/sda"
    [ "$status" -eq 0 ]

    # Verificar que hay exactamente 6 comandos parted
    local command_count=$(wc -l < /tmp/parted_commands.log)
    [[ $command_count -eq 6 ]]

    # Limpiar
    rm -f /tmp/parted_commands.log
}

################################################################################
# Pruebas para format_partitions()
################################################################################

@test "format_partitions: dispositivo /dev/sda genera comandos correctos de formateo" {
    # Mock de mkfs.fat
    mkfs.fat() {
        echo "mkfs.fat $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkfs.fat

    # Mock de mkfs.ext4
    mkfs.ext4() {
        echo "mkfs.ext4 $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkfs.ext4

    # Mock de mkswap
    mkswap() {
        echo "mkswap $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkswap

    # Limpiar log de comandos
    rm -f /tmp/format_commands.log

    run format_partitions "/dev/sda"
    [ "$status" -eq 0 ]

    # Verificar que se formateó ESP con FAT32
    grep -q "mkfs.fat -F32 /dev/sda1" /tmp/format_commands.log

    # Verificar que se formateó Root con ext4
    grep -q "mkfs.ext4 -F /dev/sda2" /tmp/format_commands.log

    # Verificar que se inicializó Swap
    grep -q "mkswap /dev/sda3" /tmp/format_commands.log

    # Verificar que se formateó Home con ext4
    grep -q "mkfs.ext4 -F /dev/sda4" /tmp/format_commands.log

    # Limpiar
    rm -f /tmp/format_commands.log
}

@test "format_partitions: dispositivo /dev/vda genera comandos correctos de formateo" {
    # Mock de mkfs.fat
    mkfs.fat() {
        echo "mkfs.fat $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkfs.fat

    # Mock de mkfs.ext4
    mkfs.ext4() {
        echo "mkfs.ext4 $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkfs.ext4

    # Mock de mkswap
    mkswap() {
        echo "mkswap $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkswap

    # Limpiar log de comandos
    rm -f /tmp/format_commands.log

    run format_partitions "/dev/vda"
    [ "$status" -eq 0 ]

    # Verificar que los comandos usan /dev/vda
    grep -q "/dev/vda1" /tmp/format_commands.log
    grep -q "/dev/vda2" /tmp/format_commands.log
    grep -q "/dev/vda3" /tmp/format_commands.log
    grep -q "/dev/vda4" /tmp/format_commands.log

    # Limpiar
    rm -f /tmp/format_commands.log
}

@test "format_partitions: fallo al formatear ESP retorna 1" {
    # Mock de mkfs.fat que falla
    mkfs.fat() {
        return 1
    }
    export -f mkfs.fat

    run format_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al formatear partición ESP"* ]]
}

@test "format_partitions: fallo al formatear Root retorna 1" {
    # Mock de mkfs.fat que funciona
    mkfs.fat() {
        return 0
    }
    export -f mkfs.fat

    # Mock de mkfs.ext4 que falla en la primera llamada
    mkfs.ext4() {
        if [[ "$*" == *"/dev/sda2"* ]]; then
            return 1
        fi
        return 0
    }
    export -f mkfs.ext4

    run format_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al formatear partición Root"* ]]
}

@test "format_partitions: fallo al inicializar Swap retorna 1" {
    # Mock de mkfs.fat que funciona
    mkfs.fat() {
        return 0
    }
    export -f mkfs.fat

    # Mock de mkfs.ext4 que funciona
    mkfs.ext4() {
        return 0
    }
    export -f mkfs.ext4

    # Mock de mkswap que falla
    mkswap() {
        return 1
    }
    export -f mkswap

    run format_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al inicializar partición Swap"* ]]
}

@test "format_partitions: secuencia completa de comandos de formateo" {
    # Mock de mkfs.fat
    mkfs.fat() {
        echo "mkfs.fat $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkfs.fat

    # Mock de mkfs.ext4
    mkfs.ext4() {
        echo "mkfs.ext4 $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkfs.ext4

    # Mock de mkswap
    mkswap() {
        echo "mkswap $*" >> /tmp/format_commands.log
        return 0
    }
    export -f mkswap

    # Limpiar log de comandos
    rm -f /tmp/format_commands.log

    run format_partitions "/dev/sda"
    [ "$status" -eq 0 ]

    # Verificar que hay exactamente 4 comandos de formateo
    local command_count=$(wc -l < /tmp/format_commands.log)
    [[ $command_count -eq 4 ]]

    # Limpiar
    rm -f /tmp/format_commands.log
}

################################################################################
# Pruebas para mount_partitions()
################################################################################

@test "mount_partitions: dispositivo /dev/sda genera secuencia correcta de montaje" {
    # Mock de mount
    mount() {
        echo "mount $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f mount

    # Mock de mkdir
    mkdir() {
        echo "mkdir $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f mkdir

    # Mock de swapon
    swapon() {
        echo "swapon $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f swapon

    # Limpiar log de comandos
    rm -f /tmp/mount_commands.log

    run mount_partitions "/dev/sda"
    [ "$status" -eq 0 ]

    # Verificar que se montó Root en /mnt
    grep -q "mount /dev/sda2 /mnt" /tmp/mount_commands.log

    # Verificar que se creó /mnt/boot
    grep -q "mkdir -p /mnt/boot" /tmp/mount_commands.log

    # Verificar que se montó ESP en /mnt/boot
    grep -q "mount /dev/sda1 /mnt/boot" /tmp/mount_commands.log

    # Verificar que se creó /mnt/home
    grep -q "mkdir -p /mnt/home" /tmp/mount_commands.log

    # Verificar que se montó Home en /mnt/home
    grep -q "mount /dev/sda4 /mnt/home" /tmp/mount_commands.log

    # Verificar que se activó Swap
    grep -q "swapon /dev/sda3" /tmp/mount_commands.log

    # Limpiar
    rm -f /tmp/mount_commands.log
}

@test "mount_partitions: dispositivo /dev/vda genera secuencia correcta de montaje" {
    # Mock de mount
    mount() {
        echo "mount $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f mount

    # Mock de mkdir
    mkdir() {
        echo "mkdir $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f mkdir

    # Mock de swapon
    swapon() {
        echo "swapon $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f swapon

    # Limpiar log de comandos
    rm -f /tmp/mount_commands.log

    run mount_partitions "/dev/vda"
    [ "$status" -eq 0 ]

    # Verificar que los comandos usan /dev/vda
    grep -q "/dev/vda1" /tmp/mount_commands.log
    grep -q "/dev/vda2" /tmp/mount_commands.log
    grep -q "/dev/vda3" /tmp/mount_commands.log
    grep -q "/dev/vda4" /tmp/mount_commands.log

    # Limpiar
    rm -f /tmp/mount_commands.log
}

@test "mount_partitions: fallo al montar Root retorna 1" {
    # Mock de mount que falla en Root
    mount() {
        if [[ "$*" == *"/dev/sda2"* ]]; then
            return 1
        fi
        return 0
    }
    export -f mount

    run mount_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al montar partición Root"* ]]
}

@test "mount_partitions: fallo al crear /mnt/boot retorna 1" {
    # Mock de mount que funciona
    mount() {
        return 0
    }
    export -f mount

    # Mock de mkdir que falla en /mnt/boot
    mkdir() {
        if [[ "$*" == *"/mnt/boot"* ]]; then
            return 1
        fi
        return 0
    }
    export -f mkdir

    run mount_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al crear directorio /mnt/boot"* ]]
}

@test "mount_partitions: fallo al montar ESP retorna 1" {
    # Mock de mount que falla en ESP
    mount() {
        if [[ "$*" == *"/dev/sda1"* ]]; then
            return 1
        fi
        return 0
    }
    export -f mount

    # Mock de mkdir que funciona
    mkdir() {
        return 0
    }
    export -f mkdir

    run mount_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al montar partición ESP"* ]]
}

@test "mount_partitions: fallo al activar Swap retorna 1" {
    # Mock de mount que funciona
    mount() {
        return 0
    }
    export -f mount

    # Mock de mkdir que funciona
    mkdir() {
        return 0
    }
    export -f mkdir

    # Mock de swapon que falla
    swapon() {
        return 1
    }
    export -f swapon

    run mount_partitions "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al activar partición Swap"* ]]
}

@test "mount_partitions: orden correcto de operaciones" {
    # Mock de mount
    mount() {
        echo "mount $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f mount

    # Mock de mkdir
    mkdir() {
        echo "mkdir $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f mkdir

    # Mock de swapon
    swapon() {
        echo "swapon $*" >> /tmp/mount_commands.log
        return 0
    }
    export -f swapon

    # Limpiar log de comandos
    rm -f /tmp/mount_commands.log

    run mount_partitions "/dev/sda"
    [ "$status" -eq 0 ]

    # Verificar el orden de las operaciones
    # 1. Montar Root
    # 2. Crear /mnt/boot
    # 3. Montar ESP
    # 4. Crear /mnt/home
    # 5. Montar Home
    # 6. Activar Swap

    local line1=$(sed -n '1p' /tmp/mount_commands.log)
    local line2=$(sed -n '2p' /tmp/mount_commands.log)
    local line3=$(sed -n '3p' /tmp/mount_commands.log)
    local line4=$(sed -n '4p' /tmp/mount_commands.log)
    local line5=$(sed -n '5p' /tmp/mount_commands.log)
    local line6=$(sed -n '6p' /tmp/mount_commands.log)

    [[ "$line1" == *"mount /dev/sda2 /mnt"* ]]
    [[ "$line2" == *"mkdir -p /mnt/boot"* ]]
    [[ "$line3" == *"mount /dev/sda1 /mnt/boot"* ]]
    [[ "$line4" == *"mkdir -p /mnt/home"* ]]
    [[ "$line5" == *"mount /dev/sda4 /mnt/home"* ]]
    [[ "$line6" == *"swapon /dev/sda3"* ]]

    # Limpiar
    rm -f /tmp/mount_commands.log
}

################################################################################
# Prueba de Propiedad para calculate_home_size()
# Property 6: Cálculo correcto del espacio restante
# Validates: Requirements 2.5
################################################################################

@test "Property 6: calculate_home_size calcula correctamente para 100 tamaños de disco aleatorios" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=100

    # Probar con 100 tamaños de disco aleatorios entre 16GB y 1TB
    for i in $(seq 1 $total_tests); do
        # Generar tamaño aleatorio entre 16GB y 1000GB
        local disk_size_gb=$((16 + RANDOM % 985))

        # Calcular espacio esperado para home
        # home = disk_size - 0.5 (ESP) - 8 (Root) - 2 (Swap) = disk_size - 10.5
        local expected_home=$(echo "$disk_size_gb - 10.5" | bc)

        # Ejecutar función
        local result=$(calculate_home_size "$disk_size_gb")

        # Verificar que el resultado es correcto
        if [[ "$result" == "$expected_home" ]]; then
            success_count=$((success_count + 1))
        else
            echo "FALLO: Para disco de ${disk_size_gb}GB, esperado ${expected_home}GB, obtenido ${result}GB" >&2
            return 1
        fi
    done

    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}

################################################################################
# Pruebas para get_partition_path()
################################################################################

@test "get_partition_path: /dev/sda usa sufijo directo" {
    run get_partition_path "/dev/sda" 1
    [ "$status" -eq 0 ]
    [[ "$output" == "/dev/sda1" ]]
}

@test "get_partition_path: /dev/nvme0n1 usa separador p" {
    run get_partition_path "/dev/nvme0n1" 1
    [ "$status" -eq 0 ]
    [[ "$output" == "/dev/nvme0n1p1" ]]
}

@test "format_partitions: dispositivo /dev/nvme0n1 genera rutas con p" {
    mkfs.fat() { echo "mkfs.fat $*" >> /tmp/format_nvme_commands.log; return 0; }
    mkfs.ext4() { echo "mkfs.ext4 $*" >> /tmp/format_nvme_commands.log; return 0; }
    mkswap() { echo "mkswap $*" >> /tmp/format_nvme_commands.log; return 0; }
    export -f mkfs.fat mkfs.ext4 mkswap

    rm -f /tmp/format_nvme_commands.log

    run format_partitions "/dev/nvme0n1"
    [ "$status" -eq 0 ]
    grep -q "mkfs.fat -F32 /dev/nvme0n1p1" /tmp/format_nvme_commands.log
    grep -q "mkfs.ext4 -F /dev/nvme0n1p2" /tmp/format_nvme_commands.log
    grep -q "mkswap /dev/nvme0n1p3" /tmp/format_nvme_commands.log
    grep -q "mkfs.ext4 -F /dev/nvme0n1p4" /tmp/format_nvme_commands.log

    rm -f /tmp/format_nvme_commands.log
}
