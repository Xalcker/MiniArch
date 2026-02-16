#!/bin/bash

################################################################################
# Módulo de Validación
#
# Este módulo contiene funciones para validar el entorno de ejecución antes
# de comenzar la instalación de Arch Linux.
#
# Funciones:
# - validate_environment(): Verifica que se está ejecutando en Arch Linux
# - check_network(): Verifica conectividad de red
# - check_disk(): Valida que el disco existe y tiene suficiente espacio
################################################################################

################################################################################
# validate_environment()
#
# Verifica que el script se está ejecutando desde el instalador live de
# Arch Linux comprobando la existencia de archivos específicos del sistema.
#
# Returns:
#   0 - Si se está ejecutando en el instalador de Arch Linux
#   1 - Si no se está ejecutando en Arch Linux
################################################################################
validate_environment() {
    # Verificar que existe el archivo /etc/arch-release
    if [[ ! -f /etc/arch-release ]]; then
        echo "ERROR: No se detectó Arch Linux. Este script debe ejecutarse desde el instalador live de Arch Linux." >&2
        return 1
    fi
    
    # Verificar que existe el comando pacstrap (específico del instalador)
    if ! command -v pacstrap &> /dev/null; then
        echo "ERROR: No se encontró el comando 'pacstrap'. Este script debe ejecutarse desde el instalador live de Arch Linux." >&2
        return 1
    fi
    
    echo "Entorno de Arch Linux validado correctamente."
    return 0
}

################################################################################
# check_network()
#
# Verifica que existe conectividad de red activa intentando hacer ping a
# archlinux.org.
#
# Returns:
#   0 - Si hay conectividad de red
#   1 - Si no hay conectividad de red
################################################################################
check_network() {
    # Intentar hacer ping a archlinux.org (3 paquetes, timeout de 5 segundos)
    if ! ping -c 3 -W 5 archlinux.org &> /dev/null; then
        echo "ERROR: No se detectó conexión de red. Verifique su conexión a Internet." >&2
        return 1
    fi
    
    echo "Conectividad de red verificada correctamente."
    return 0
}

################################################################################
# check_disk()
#
# Verifica que el disco especificado existe y tiene al menos 16GB de capacidad.
#
# Arguments:
#   $1 - Ruta del dispositivo de disco (ej: /dev/sda)
#
# Returns:
#   0 - Si el disco existe y tiene >= 16GB
#   1 - Si el disco no existe o tiene < 16GB
################################################################################
check_disk() {
    local disk_device="$1"
    
    # Verificar que se proporcionó un argumento
    if [[ -z "$disk_device" ]]; then
        echo "ERROR: No se especificó un dispositivo de disco." >&2
        return 1
    fi
    
    # Verificar que el dispositivo existe
    if [[ ! -b "$disk_device" ]]; then
        echo "ERROR: El dispositivo '$disk_device' no existe o no es un dispositivo de bloque." >&2
        return 1
    fi
    
    # Obtener el tamaño del disco en GB usando lsblk
    local disk_size_bytes
    disk_size_bytes=$(lsblk -b -d -n -o SIZE "$disk_device" 2>/dev/null)
    
    if [[ -z "$disk_size_bytes" ]]; then
        echo "ERROR: No se pudo obtener el tamaño del disco '$disk_device'." >&2
        return 1
    fi
    
    # Convertir bytes a GB (1 GB = 1024^3 bytes)
    local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))
    
    # Verificar que el disco tiene al menos 16GB
    if [[ $disk_size_gb -lt 16 ]]; then
        echo "ERROR: El disco '$disk_device' tiene solo ${disk_size_gb}GB. Se requieren al menos 16GB." >&2
        return 1
    fi
    
    echo "Disco '$disk_device' validado correctamente (${disk_size_gb}GB disponibles)."
    return 0
}

################################################################################
# check_disk_empty()
#
# Verifica si el disco especificado tiene particiones existentes. Si las tiene,
# muestra una advertencia y solicita confirmación explícita del usuario antes
# de continuar.
#
# Arguments:
#   $1 - Ruta del dispositivo de disco (ej: /dev/sda)
#
# Returns:
#   0 - Si el disco está vacío o el usuario confirma la destrucción de datos
#   1 - Si el usuario cancela la operación
################################################################################
check_disk_empty() {
    local disk_device="$1"
    
    # Verificar que se proporcionó un argumento
    if [[ -z "$disk_device" ]]; then
        echo "ERROR: No se especificó un dispositivo de disco." >&2
        return 1
    fi
    
    # Verificar que el dispositivo existe
    if [[ ! -b "$disk_device" ]]; then
        echo "ERROR: El dispositivo '$disk_device' no existe o no es un dispositivo de bloque." >&2
        return 1
    fi
    
    # Verificar si el disco tiene particiones usando lsblk
    local partition_count
    partition_count=$(lsblk -n -o TYPE "$disk_device" 2>/dev/null | grep -c "part")
    
    # Si no hay particiones, el disco está vacío
    if [[ $partition_count -eq 0 ]]; then
        echo "El disco '$disk_device' está vacío. Continuando con la instalación."
        return 0
    fi
    
    # Si hay particiones, mostrar advertencia
    echo "⚠️  ADVERTENCIA: El disco '$disk_device' contiene $partition_count partición(es) existente(s)." >&2
    echo "⚠️  TODOS LOS DATOS EN ESTE DISCO SERÁN DESTRUIDOS." >&2
    echo "" >&2
    
    # Mostrar las particiones existentes
    echo "Particiones existentes:" >&2
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk_device" >&2
    echo "" >&2
    
    # Solicitar confirmación explícita del usuario
    echo -n "¿Está seguro de que desea continuar y destruir todos los datos? (sí/no): " >&2
    read -r confirmation
    
    # Verificar la respuesta del usuario
    if [[ "$confirmation" == "sí" || "$confirmation" == "si" || "$confirmation" == "SI" || "$confirmation" == "SÍ" ]]; then
        echo "Confirmación recibida. Continuando con la instalación."
        return 0
    else
        echo "Operación cancelada por el usuario. No se modificará el disco." >&2
        return 1
    fi
}
