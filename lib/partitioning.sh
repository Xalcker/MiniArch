#!/bin/bash

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
    if ! parted -s "$device" mklabel gpt; then
        log_error "Fallo al crear tabla GPT en $device"
        return 1
    fi
    
    log "Creando partición ESP (512MB)"
    # Crear partición ESP: 1MB - 513MB
    if ! parted -s "$device" mkpart ESP fat32 1MiB 513MiB; then
        log_error "Fallo al crear partición ESP"
        return 1
    fi
    
    # Marcar partición como ESP
    if ! parted -s "$device" set 1 esp on; then
        log_error "Fallo al marcar partición como ESP"
        return 1
    fi
    
    log "Creando partición Root (8GB)"
    # Crear partición Root: 513MB - 8705MB (513 + 8192)
    if ! parted -s "$device" mkpart primary ext4 513MiB 8705MiB; then
        log_error "Fallo al crear partición Root"
        return 1
    fi
    
    log "Creando partición Swap (2GB)"
    # Crear partición Swap: 8705MB - 10753MB (8705 + 2048)
    if ! parted -s "$device" mkpart primary linux-swap 8705MiB 10753MiB; then
        log_error "Fallo al crear partición Swap"
        return 1
    fi
    
    log "Creando partición Home (espacio restante)"
    # Crear partición Home: 10753MB - 100%
    if ! parted -s "$device" mkpart primary ext4 10753MiB 100%; then
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
# 1. ${device}1: FAT32 (ESP)
# 2. ${device}2: ext4 (Root)
# 3. ${device}3: swap (Swap)
# 4. ${device}4: ext4 (Home)
#
# Parámetros:
#   $1 - Dispositivo de bloque base (ej: /dev/sda)
#
# Retorna:
#   0 si éxito, 1 si error
################################################################################
format_partitions() {
    local device="$1"
    
    log "Formateando partición ESP con FAT32"
    if ! mkfs.fat -F32 "${device}1"; then
        log_error "Fallo al formatear partición ESP"
        return 1
    fi
    
    log "Formateando partición Root con ext4"
    if ! mkfs.ext4 -F "${device}2"; then
        log_error "Fallo al formatear partición Root"
        return 1
    fi
    
    log "Inicializando partición Swap"
    if ! mkswap "${device}3"; then
        log_error "Fallo al inicializar partición Swap"
        return 1
    fi
    
    log "Formateando partición Home con ext4"
    if ! mkfs.ext4 -F "${device}4"; then
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
#   $1 - Dispositivo de bloque base (ej: /dev/sda)
#
# Retorna:
#   0 si éxito, 1 si error
################################################################################
mount_partitions() {
    local device="$1"
    
    log "Montando partición Root en /mnt"
    if ! mount "${device}2" /mnt; then
        log_error "Fallo al montar partición Root"
        return 1
    fi
    
    log "Creando directorio /mnt/boot"
    if ! mkdir -p /mnt/boot; then
        log_error "Fallo al crear directorio /mnt/boot"
        return 1
    fi
    
    log "Montando partición ESP en /mnt/boot"
    if ! mount "${device}1" /mnt/boot; then
        log_error "Fallo al montar partición ESP"
        return 1
    fi
    
    log "Creando directorio /mnt/home"
    if ! mkdir -p /mnt/home; then
        log_error "Fallo al crear directorio /mnt/home"
        return 1
    fi
    
    log "Montando partición Home en /mnt/home"
    if ! mount "${device}4" /mnt/home; then
        log_error "Fallo al montar partición Home"
        return 1
    fi
    
    log "Activando partición Swap"
    if ! swapon "${device}3"; then
        log_error "Fallo al activar partición Swap"
        return 1
    fi
    
    log "Montaje completado exitosamente"
    return 0
}
