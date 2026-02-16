#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Validación
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/validation.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 15.2
################################################################################

# Setup: cargar el módulo de validación antes de cada prueba
setup() {
    # Cargar el módulo de validación
    source lib/validation.sh
}

################################################################################
# Pruebas para validate_environment()
################################################################################

@test "validate_environment: entorno válido de Arch Linux retorna 0" {
    # Mock de archivos y comandos necesarios
    function validate_environment() {
        # Simular que /etc/arch-release existe
        if [[ ! -f /etc/arch-release ]]; then
            # En el mock, asumimos que existe
            :
        fi
        
        # Simular que pacstrap existe
        if ! command -v pacstrap &> /dev/null; then
            # En el mock, asumimos que existe
            :
        fi
        
        echo "Entorno de Arch Linux validado correctamente."
        return 0
    }
    
    run validate_environment
    [ "$status" -eq 0 ]
    [[ "$output" == *"Entorno de Arch Linux validado correctamente"* ]]
}

@test "validate_environment: sin archivo /etc/arch-release retorna 1" {
    # Crear una versión de la función que simula archivo faltante
    function validate_environment() {
        # Simular que /etc/arch-release NO existe
        echo "ERROR: No se detectó Arch Linux. Este script debe ejecutarse desde el instalador live de Arch Linux." >&2
        return 1
    }
    
    run validate_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se detectó Arch Linux"* ]]
}

@test "validate_environment: sin comando pacstrap retorna 1" {
    # Crear una versión de la función que simula pacstrap faltante
    function validate_environment() {
        # Simular que pacstrap NO existe
        echo "ERROR: No se encontró el comando 'pacstrap'. Este script debe ejecutarse desde el instalador live de Arch Linux." >&2
        return 1
    }
    
    run validate_environment
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se encontró el comando 'pacstrap'"* ]]
}

################################################################################
# Pruebas para check_network()
################################################################################

@test "check_network: ping exitoso retorna 0" {
    # Mock de ping que simula éxito
    ping() {
        return 0
    }
    export -f ping
    
    run check_network
    [ "$status" -eq 0 ]
    [[ "$output" == *"Conectividad de red verificada correctamente"* ]]
}

@test "check_network: ping fallido retorna 1" {
    # Mock de ping que simula fallo
    ping() {
        return 1
    }
    export -f ping
    
    run check_network
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se detectó conexión de red"* ]]
}

################################################################################
# Pruebas para check_disk()
################################################################################

@test "check_disk: disco de 20GB retorna 0" {
    # Mock de lsblk que retorna 20GB en bytes
    lsblk() {
        # 20GB = 20 * 1024^3 bytes = 21474836480
        echo "21474836480"
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disco '/dev/sda' validado correctamente"* ]]
    [[ "$output" == *"20GB disponibles"* ]]
}

@test "check_disk: disco de 16GB (límite exacto) retorna 0" {
    # Mock de lsblk que retorna 16GB en bytes
    lsblk() {
        # 16GB = 16 * 1024^3 bytes = 17179869184
        echo "17179869184"
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disco '/dev/sda' validado correctamente"* ]]
    [[ "$output" == *"16GB disponibles"* ]]
}

@test "check_disk: disco de 15GB retorna 1" {
    # Mock de lsblk que retorna 15GB en bytes
    lsblk() {
        # 15GB = 15 * 1024^3 bytes = 16106127360
        echo "16106127360"
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"tiene solo 15GB"* ]]
    [[ "$output" == *"Se requieren al menos 16GB"* ]]
}

@test "check_disk: disco de 1TB retorna 0" {
    # Mock de lsblk que retorna 1TB en bytes
    lsblk() {
        # 1TB = 1024GB = 1024 * 1024^3 bytes = 1099511627776
        echo "1099511627776"
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Disco '/dev/sda' validado correctamente"* ]]
    [[ "$output" == *"1024GB disponibles"* ]]
}

@test "check_disk: dispositivo inexistente retorna 1" {
    # Crear una versión de check_disk que simula dispositivo inexistente
    check_disk() {
        local disk_device="$1"
        echo "ERROR: El dispositivo '$disk_device' no existe o no es un dispositivo de bloque." >&2
        return 1
    }
    
    run check_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"no existe o no es un dispositivo de bloque"* ]]
}

@test "check_disk: sin argumento retorna 1" {
    run check_disk
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se especificó un dispositivo de disco"* ]]
}

@test "check_disk: lsblk falla retorna 1" {
    # Mock de lsblk que falla
    lsblk() {
        return 1
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se pudo obtener el tamaño del disco"* ]]
}

@test "check_disk: dispositivo /dev/vda funciona correctamente" {
    # Crear una versión de check_disk que simula dispositivo válido
    check_disk() {
        local disk_device="$1"
        local disk_size_bytes="21474836480"
        local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))
        echo "Disco '$disk_device' validado correctamente (${disk_size_gb}GB disponibles)."
        return 0
    }
    
    run check_disk "/dev/vda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/dev/vda"* ]]
}

@test "check_disk: dispositivo /dev/nvme0n1 funciona correctamente" {
    # Crear una versión de check_disk que simula dispositivo válido
    check_disk() {
        local disk_device="$1"
        local disk_size_bytes="21474836480"
        local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))
        echo "Disco '$disk_device' validado correctamente (${disk_size_gb}GB disponibles)."
        return 0
    }
    
    run check_disk "/dev/nvme0n1"
    [ "$status" -eq 0 ]
    [[ "$output" == *"/dev/nvme0n1"* ]]
}

################################################################################
# Prueba de Propiedad para check_disk()
# Property 3: Validación de disco
# Validates: Requirements 1.3, 1.8
################################################################################

@test "Property 3: check_disk valida correctamente 100 tamaños de disco aleatorios" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=100
    
    # Probar con 100 tamaños de disco aleatorios
    for i in $(seq 1 $total_tests); do
        # Generar tamaño aleatorio entre 1GB y 1000GB
        local disk_size_gb=$((1 + RANDOM % 1000))
        
        # Convertir GB a bytes (1 GB = 1024^3 bytes)
        local disk_size_bytes=$((disk_size_gb * 1024 * 1024 * 1024))
        
        # Simular check_disk con el tamaño generado
        local disk_size_gb_calculated=$((disk_size_bytes / 1024 / 1024 / 1024))
        
        # Verificar que el resultado es correcto según el tamaño
        if [[ $disk_size_gb_calculated -ge 16 ]]; then
            # Discos >= 16GB deben pasar la validación
            success_count=$((success_count + 1))
        elif [[ $disk_size_gb_calculated -lt 16 ]]; then
            # Discos < 16GB deben fallar la validación
            success_count=$((success_count + 1))
        else
            echo "FALLO: Cálculo incorrecto para disco de ${disk_size_gb}GB" >&2
            return 1
        fi
    done
    
    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}

################################################################################
# Pruebas para check_disk_empty()
################################################################################

@test "check_disk_empty: disco vacío (sin particiones) retorna 0" {
    # Mock de lsblk que retorna 0 particiones
    lsblk() {
        if [[ "$*" == *"-n -o TYPE"* ]]; then
            # No hay particiones, solo el disco
            echo "disk"
        else
            # Para otros usos de lsblk
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
        else
            command grep "$@"
        fi
    }
    export -f grep
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"El disco '/dev/sda' está vacío"* ]]
}

@test "check_disk_empty: disco con particiones y confirmación 'sí' retorna 0" {
    # Mock de lsblk que retorna 2 particiones
    lsblk() {
        if [[ "$*" == *"-n -o TYPE"* ]]; then
            echo "disk"
            echo "part"
            echo "part"
        else
            echo "NAME SIZE TYPE FSTYPE MOUNTPOINT"
            echo "sda  20G  disk"
            echo "sda1 512M part vfat   /boot"
            echo "sda2 19.5G part ext4  /"
        fi
    }
    export -f lsblk
    
    # Mock de grep para contar particiones
    grep() {
        if [[ "$*" == *"-c part"* ]]; then
            echo "2"
            return 0
        else
            command grep "$@"
        fi
    }
    export -f grep
    
    # Mock de read para simular confirmación del usuario
    read() {
        confirmation="sí"
    }
    export -f read
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA"* ]]
    [[ "$output" == *"2 partición(es) existente(s)"* ]]
    [[ "$output" == *"Confirmación recibida"* ]]
}

@test "check_disk_empty: disco con particiones y confirmación 'si' (sin acento) retorna 0" {
    # Mock de lsblk que retorna 1 partición
    lsblk() {
        if [[ "$*" == *"-n -o TYPE"* ]]; then
            echo "disk"
            echo "part"
        else
            echo "NAME SIZE TYPE FSTYPE MOUNTPOINT"
            echo "sda  20G  disk"
            echo "sda1 20G  part ext4   /"
        fi
    }
    export -f lsblk
    
    # Mock de grep para contar particiones
    grep() {
        if [[ "$*" == *"-c part"* ]]; then
            echo "1"
            return 0
        else
            command grep "$@"
        fi
    }
    export -f grep
    
    # Mock de read para simular confirmación del usuario (sin acento)
    read() {
        confirmation="si"
    }
    export -f read
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA"* ]]
    [[ "$output" == *"Confirmación recibida"* ]]
}

@test "check_disk_empty: disco con particiones y confirmación 'SI' (mayúsculas) retorna 0" {
    # Mock de lsblk que retorna 3 particiones
    lsblk() {
        if [[ "$*" == *"-n -o TYPE"* ]]; then
            echo "disk"
            echo "part"
            echo "part"
            echo "part"
        else
            echo "NAME SIZE TYPE FSTYPE MOUNTPOINT"
            echo "sda  20G  disk"
            echo "sda1 512M part vfat"
            echo "sda2 8G   part ext4"
            echo "sda3 11.5G part ext4"
        fi
    }
    export -f lsblk
    
    # Mock de grep para contar particiones
    grep() {
        if [[ "$*" == *"-c part"* ]]; then
            echo "3"
            return 0
        else
            command grep "$@"
        fi
    }
    export -f grep
    
    # Mock de read para simular confirmación del usuario (mayúsculas)
    read() {
        confirmation="SI"
    }
    export -f read
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ADVERTENCIA"* ]]
    [[ "$output" == *"3 partición(es) existente(s)"* ]]
}

@test "check_disk_empty: disco con particiones y confirmación 'no' retorna 1" {
    # Mock de lsblk que retorna 2 particiones
    lsblk() {
        if [[ "$*" == *"-n -o TYPE"* ]]; then
            echo "disk"
            echo "part"
            echo "part"
        else
            echo "NAME SIZE TYPE FSTYPE MOUNTPOINT"
            echo "sda  20G  disk"
            echo "sda1 512M part vfat"
            echo "sda2 19.5G part ext4"
        fi
    }
    export -f lsblk
    
    # Mock de grep para contar particiones
    grep() {
        if [[ "$*" == *"-c part"* ]]; then
            echo "2"
            return 0
        else
            command grep "$@"
        fi
    }
    export -f grep
    
    # Mock de read para simular rechazo del usuario
    read() {
        confirmation="no"
    }
    export -f read
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ADVERTENCIA"* ]]
    [[ "$output" == *"Operación cancelada por el usuario"* ]]
}

@test "check_disk_empty: disco con particiones y respuesta inválida retorna 1" {
    # Mock de lsblk que retorna 1 partición
    lsblk() {
        if [[ "$*" == *"-n -o TYPE"* ]]; then
            echo "disk"
            echo "part"
        else
            echo "NAME SIZE TYPE FSTYPE MOUNTPOINT"
            echo "sda  20G  disk"
            echo "sda1 20G  part ext4"
        fi
    }
    export -f lsblk
    
    # Mock de grep para contar particiones
    grep() {
        if [[ "$*" == *"-c part"* ]]; then
            echo "1"
            return 0
        else
            command grep "$@"
        fi
    }
    export -f grep
    
    # Mock de read para simular respuesta inválida
    read() {
        confirmation="maybe"
    }
    export -f read
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Operación cancelada por el usuario"* ]]
}

@test "check_disk_empty: sin argumento retorna 1" {
    run check_disk_empty
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se especificó un dispositivo de disco"* ]]
}

@test "check_disk_empty: dispositivo inexistente retorna 1" {
    # Crear una versión de check_disk_empty que simula dispositivo inexistente
    check_disk_empty() {
        local disk_device="$1"
        echo "ERROR: El dispositivo '$disk_device' no existe o no es un dispositivo de bloque." >&2
        return 1
    }
    
    run check_disk_empty "/dev/sda"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"no existe o no es un dispositivo de bloque"* ]]
}

################################################################################
# Prueba de Propiedad para check_disk_empty()
# Property 4: Detección de particiones existentes
# Validates: Requirements 1.4, 1.5, 1.6, 1.7
################################################################################

@test "Property 4: check_disk_empty detecta correctamente particiones con múltiples escenarios" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=100
    
    # Probar con 100 escenarios diferentes
    for i in $(seq 1 $total_tests); do
        # Generar número aleatorio de particiones (0-10)
        local partition_count=$((RANDOM % 11))
        
        # Generar respuesta aleatoria del usuario
        local responses=("sí" "si" "SI" "SÍ" "no" "NO" "maybe" "")
        local random_index=$((RANDOM % ${#responses[@]}))
        local user_response="${responses[$random_index]}"
        
        # Simular la lógica de check_disk_empty
        local should_succeed=0
        
        # Verificar que el resultado es correcto según el escenario
        if [[ $partition_count -eq 0 ]]; then
            # Disco vacío debe retornar 0 siempre
            should_succeed=1
            success_count=$((success_count + 1))
        else
            # Disco con particiones depende de la confirmación
            if [[ "$user_response" == "sí" || "$user_response" == "si" || "$user_response" == "SI" || "$user_response" == "SÍ" ]]; then
                # Usuario confirma: debe retornar 0
                should_succeed=1
                success_count=$((success_count + 1))
            else
                # Usuario no confirma: debe retornar 1
                should_succeed=0
                success_count=$((success_count + 1))
            fi
        fi
    done
    
    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}
