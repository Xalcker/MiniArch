#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

################################################################################
# Módulo de Particionamiento
#
# Este módulo contiene funciones para particionar, formatear y montar el disco
# objetivo según el esquema definido:
# - Partición 1 (ESP): 512MB, FAT32, montada en /boot
# - Partición 2 (Root): 8GB, ext4, montada en /mnt
# - Partición 3 (Swap): 2GB, swap
# - Partición 4 (Home): Espacio restante, ext4, montada en /mnt/home
################################################################################

################################################################################
# get_partition_path()
#
# Devuelve la ruta correcta de una partición para dispositivos con distintos
# esquemas de nombres. Discos como /dev/sda usan /dev/sda1, mientras que NVMe y
# MMC usan un separador "p" (/dev/nvme0n1p1, /dev/mmcblk0p1).
#
# Parámetros:
#   $1 - Dispositivo de bloque base (ej: /dev/sda, /dev/nvme0n1)
#   $2 - Número de partición
#
# Retorna:
#   Ruta de la partición en stdout
################################################################################
get_partition_path() {
    local device="$1"
    local partition_number="$2"

    if [[ -z "$device" || -z "$partition_number" ]]; then
        log_error "Dispositivo o número de partición no especificado"
        return 1
    fi

    case "$device" in
        *[0-9]) echo "${device}p${partition_number}" ;;
        *) echo "${device}${partition_number}" ;;
    esac
}

################################################################################
# Función auxiliar para calcular el tamaño de la partición home
#
# Calcula el espacio restante del disco después de restar las particiones
# ESP (512MB), Root (8GB) y Swap (2GB)
#
# Parámetros:
#   $1 - Tamaño total del disco en GB
#
# Retorna:
#   Tamaño de la partición home en GB (stdout)
################################################################################
calculate_home_size() {
    local disk_size_gb="$1"

    # Convertir 512MB a GB (0.5GB)
    local esp_size_gb=0.5
    local root_size_gb=8
    local swap_size_gb=2

    # Calcular espacio restante: disk_size - (0.5 + 8 + 2) = disk_size - 10.5
    local home_size_gb=$(echo "$disk_size_gb - $esp_size_gb - $root_size_gb - $swap_size_gb" | bc)

    echo "$home_size_gb"
}

################################################################################
# Función para particionar el disco
#
# Crea una tabla de particiones GPT y 4 particiones según el esquema definido:
# 1. ESP: 512MB, tipo EFI System
# 2. Root: 8GB, tipo Linux filesystem
# 3. Swap: 2GB, tipo Linux swap
# 4. Home: Espacio restante, tipo Linux filesystem
#
# Parámetros:
#   $1 - Dispositivo de bloque (ej: /dev/sda)
#
# Retorna:
#   0 si éxito, 1 si error
################################################################################
partition_disk() {
    local device="$1"

    # Verificar que el dispositivo existe
    if [[ ! -b "$device" ]]; then
        log_error "El dispositivo $device no existe"
        return 1
    fi

    log "Creando tabla de particiones GPT en $device"

    # Crear tabla GPT
    if ! run_quiet parted -s "$device" mklabel gpt; then
        log_error "Fallo al crear tabla GPT en $device"
        return 1
    fi

    log "Creando partición ESP (512MB)"
    # Crear partición ESP: 1MB - 513MB
    if ! run_quiet parted -s "$device" mkpart ESP fat32 1MiB 513MiB; then
        log_error "Fallo al crear partición ESP"
        return 1
    fi

    # Marcar partición como ESP
    if ! run_quiet parted -s "$device" set 1 esp on; then
        log_error "Fallo al marcar partición como ESP"
        return 1
    fi

    log "Creando partición Root (8GB)"
    # Crear partición Root: 513MB - 8705MB (513 + 8192)
    if ! run_quiet parted -s "$device" mkpart primary ext4 513MiB 8705MiB; then
        log_error "Fallo al crear partición Root"
        return 1
    fi

    log "Creando partición Swap (2GB)"
    # Crear partición Swap: 8705MB - 10753MB (8705 + 2048)
    if ! run_quiet parted -s "$device" mkpart primary linux-swap 8705MiB 10753MiB; then
        log_error "Fallo al crear partición Swap"
        return 1
    fi

    log "Creando partición Home (espacio restante)"
    # Crear partición Home: 10753MB - 100%
    if ! run_quiet parted -s "$device" mkpart primary ext4 10753MiB 100%; then
        log_error "Fallo al crear partición Home"
        return 1
    fi

    log "Particionamiento completado exitosamente"
    return 0
}

################################################################################
# Función para formatear las particiones
#
# Formatea las 4 particiones creadas con los sistemas de archivos apropiados:
# 1. partición 1: FAT32 (ESP)
# 2. partición 2: ext4 (Root)
# 3. partición 3: swap (Swap)
# 4. partición 4: ext4 (Home)
#
# Parámetros:
#   $1 - Dispositivo de bloque base (ej: /dev/sda, /dev/nvme0n1)
#
# Retorna:
#   0 si éxito, 1 si error
################################################################################
format_partitions() {
    local device="$1"
    local esp_partition
    local root_partition
    local swap_partition
    local home_partition

    esp_partition=$(get_partition_path "$device" 1) || return 1
    root_partition=$(get_partition_path "$device" 2) || return 1
    swap_partition=$(get_partition_path "$device" 3) || return 1
    home_partition=$(get_partition_path "$device" 4) || return 1

    log "Formateando partición ESP con FAT32"
    if ! run_quiet mkfs.fat -F32 "$esp_partition"; then
        log_error "Fallo al formatear partición ESP"
        return 1
    fi

    log "Formateando partición Root con ext4"
    if ! run_quiet mkfs.ext4 -F "$root_partition"; then
        log_error "Fallo al formatear partición Root"
        return 1
    fi

    log "Inicializando partición Swap"
    if ! run_quiet mkswap "$swap_partition"; then
        log_error "Fallo al inicializar partición Swap"
        return 1
    fi

    log "Formateando partición Home con ext4"
    if ! run_quiet mkfs.ext4 -F "$home_partition"; then
        log_error "Fallo al formatear partición Home"
        return 1
    fi

    log "Formateo completado exitosamente"
    return 0
}

################################################################################
# Función para montar las particiones
#
# Monta las particiones en el orden correcto para la instalación:
# 1. Monta Root en /mnt
# 2. Crea /mnt/boot y monta ESP
# 3. Crea /mnt/home y monta Home
# 4. Activa Swap
#
# Parámetros:
#   $1 - Dispositivo de bloque base (ej: /dev/sda, /dev/nvme0n1)
#
# Retorna:
#   0 si éxito, 1 si error
################################################################################
mount_partitions() {
    local device="$1"
    local esp_partition
    local root_partition
    local swap_partition
    local home_partition

    esp_partition=$(get_partition_path "$device" 1) || return 1
    root_partition=$(get_partition_path "$device" 2) || return 1
    swap_partition=$(get_partition_path "$device" 3) || return 1
    home_partition=$(get_partition_path "$device" 4) || return 1

    log "Montando partición Root en /mnt"
    if ! mount "$root_partition" /mnt; then
        log_error "Fallo al montar partición Root"
        return 1
    fi

    log "Creando directorio /mnt/boot"
    if ! mkdir -p /mnt/boot; then
        log_error "Fallo al crear directorio /mnt/boot"
        return 1
    fi

    log "Montando partición ESP en /mnt/boot"
    if ! mount "$esp_partition" /mnt/boot; then
        log_error "Fallo al montar partición ESP"
        return 1
    fi

    log "Creando directorio /mnt/home"
    if ! mkdir -p /mnt/home; then
        log_error "Fallo al crear directorio /mnt/home"
        return 1
    fi

    log "Montando partición Home en /mnt/home"
    if ! mount "$home_partition" /mnt/home; then
        log_error "Fallo al montar partición Home"
        return 1
    fi

    log "Activando partición Swap"
    if ! run_quiet swapon "$swap_partition"; then
        log_error "Fallo al activar partición Swap"
        return 1
    fi

    log "Montaje completado exitosamente"
    return 0
}
