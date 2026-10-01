#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Indica si $1 es un dispositivo de bloque. Es una funcion (y no un [[ -b ]]
# directo) para que las pruebas puedan sustituirla sin depender de los discos
# reales del equipo que las corre.
if ! declare -F is_block_device >/dev/null; then
    is_block_device() { [[ -b "$1" ]]; }
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
# prepare_disk_for_install()
#
# Deja el disco destino listo para particionarlo desde cero:
#   - se niega a tocar el disco del que arranco el ISO live;
#   - desactiva swap y desmonta lo que este montado desde el disco;
#   - detiene volumenes LVM/cifrados/RAID heredados que lo estén usando;
#   - borra las firmas de sistemas de archivos, RAID, LVM, etc. (primero las
#     particiones y luego el disco) y la tabla de particiones.
# Sin esto, firmas viejas (mdraid, LVM, ZFS) pueden reactivarse solas en el live
# y hacer que parted o mkfs fallen con el disco ocupado.
#
# Parametros:
#   $1 - Dispositivo de bloque (ej: /dev/sda)
#
# Retorna:
#   0 si el disco quedo limpio, 1 si no se pudo liberar o es el medio live
################################################################################
prepare_disk_for_install() {
    local device="$1"
    local live_disk name type mountpoint

    if [[ -z "$device" ]] || ! is_block_device "$device"; then
        log_error "El dispositivo '$device' no existe"
        return 1
    fi

    live_disk=""
    if declare -F live_boot_disk >/dev/null; then
        live_disk="$(live_boot_disk)"
    fi
    if [[ -n "$live_disk" && "$device" == "$live_disk" ]]; then
        log_error "$device es el medio de instalacion en uso; no se puede instalar ahi"
        return 1
    fi

    log "Liberando y limpiando $device antes de particionar"

    # Swap activo en el disco.
    while IFS= read -r name; do
        [[ -n "$name" ]] || continue
        log "Desactivando swap en $name"
        run_quiet swapoff "$name" || log "No se pudo desactivar swap en $name; se continua"
    done < <(swapon --noheadings --raw --show=NAME 2>/dev/null | grep -E "^${device}(p?[0-9]+)?$" || true)

    # Montajes (los mas profundos primero).
    while read -r name mountpoint; do
        [[ -n "$mountpoint" ]] || continue
        log "Desmontando $mountpoint ($name)"
        if ! run_quiet umount -R "$mountpoint"; then
            log_error "No se pudo desmontar $mountpoint; no se puede limpiar $device"
            return 1
        fi
    done < <(lsblk -n -r -p -o NAME,MOUNTPOINT "$device" 2>/dev/null | awk 'NF >= 2 { print }' | tac)

    # LVM, cifrado y RAID heredados sobre el disco.
    while read -r name type; do
        case "$type" in
            lvm | crypt)
                run_quiet dmsetup remove --force "$name" || log "No se pudo quitar el volumen $name; se continua"
                ;;
            raid*)
                run_quiet mdadm --stop "$name" || log "No se pudo detener el RAID $name; se continua"
                ;;
        esac
    done < <(lsblk -n -r -p -o NAME,TYPE "$device" 2>/dev/null | tac)

    # Firmas: particiones primero, luego el disco completo.
    while read -r name type; do
        [[ "$type" == "part" ]] || continue
        if ! run_quiet wipefs --all --force "$name"; then
            log_error "Fallo al borrar las firmas de $name"
            return 1
        fi
    done < <(lsblk -n -r -p -o NAME,TYPE "$device" 2>/dev/null | tac)

    if ! run_quiet wipefs --all --force "$device"; then
        log_error "Fallo al borrar las firmas de $device"
        return 1
    fi

    if command -v sgdisk &> /dev/null; then
        run_quiet sgdisk --zap-all "$device" || log "sgdisk no pudo limpiar la tabla de particiones; se continua"
    fi

    if command -v partprobe &> /dev/null; then
        run_quiet partprobe "$device" || true
    fi
    if command -v udevadm &> /dev/null; then
        run_quiet udevadm settle || true
    fi

    log "Disco $device limpio"
    return 0
}

################################################################################
# size_to_mib()
#
# Convierte un tamaño como 512M, 8G, 512MiB o 8GiB a MiB (entero) en stdout.
#
# Retorna:
#   0 si el formato es valido, 1 en caso contrario
################################################################################
size_to_mib() {
    local text="${1,,}"
    local amount

    if [[ "$text" =~ ^([0-9]+)(m|g)(ib|b)?$ ]]; then
        amount=$((10#${BASH_REMATCH[1]}))
        if [[ "${BASH_REMATCH[2]}" == "g" ]]; then
            amount=$((amount * 1024))
        fi
        echo "$amount"
        return 0
    fi

    return 1
}

################################################################################
# resolve_partition_sizes()
#
# Lee ESP_SIZE, ROOT_SIZE y SWAP_SIZE (por defecto 512M, 8G y 2G), los valida y
# deja los valores en MiB en PARTITION_ESP_MIB, PARTITION_ROOT_MIB y
# PARTITION_SWAP_MIB. /home siempre ocupa el resto del disco.
#
# Minimos: ESP 256M, root 4G, swap 512M.
#
# Retorna:
#   0 si los tres tamaños son validos, 1 en caso contrario
################################################################################
resolve_partition_sizes() {
    local esp_text="${ESP_SIZE:-512M}"
    local root_text="${ROOT_SIZE:-8G}"
    local swap_text="${SWAP_SIZE:-2G}"

    if ! PARTITION_ESP_MIB=$(size_to_mib "$esp_text"); then
        log_error "ESP_SIZE invalido: '$esp_text'. Use un numero con M o G (ej: 512M)."
        return 1
    fi
    if ! PARTITION_ROOT_MIB=$(size_to_mib "$root_text"); then
        log_error "ROOT_SIZE invalido: '$root_text'. Use un numero con M o G (ej: 8G)."
        return 1
    fi
    if ! PARTITION_SWAP_MIB=$(size_to_mib "$swap_text"); then
        log_error "SWAP_SIZE invalido: '$swap_text'. Use un numero con M o G (ej: 2G)."
        return 1
    fi

    if ((PARTITION_ESP_MIB < 256)); then
        log_error "ESP_SIZE ($esp_text) es menor al minimo de 256M"
        return 1
    fi
    if ((PARTITION_ROOT_MIB < 4096)); then
        log_error "ROOT_SIZE ($root_text) es menor al minimo de 4G"
        return 1
    fi
    if ((PARTITION_SWAP_MIB < 512)); then
        log_error "SWAP_SIZE ($swap_text) es menor al minimo de 512M"
        return 1
    fi

    export PARTITION_ESP_MIB PARTITION_ROOT_MIB PARTITION_SWAP_MIB
}

################################################################################
# validate_partition_plan()
#
# Comprueba, antes de tocar el disco, que el esquema elegido (ESP + root + swap)
# deja al menos 2 GiB para /home, y muestra el esquema resultante.
#
# Parametros:
#   $1 - Dispositivo de bloque (ej: /dev/sda)
#
# Retorna:
#   0 si el esquema cabe, 1 si no cabe o no se pudo leer el tamaño del disco
################################################################################
validate_partition_plan() {
    local device="$1"
    local disk_bytes disk_mib used_mib home_mib
    local min_home_mib=2048

    resolve_partition_sizes || return 1

    disk_bytes=$(lsblk -b -d -n -o SIZE "$device" 2>/dev/null | awk '{print $1}')
    if [[ -z "$disk_bytes" ]]; then
        log_error "No se pudo leer el tamaño de $device para validar el esquema de particiones"
        return 1
    fi

    disk_mib=$((disk_bytes / 1024 / 1024))
    # 1 MiB inicial de alineacion; el resto del disco es /home.
    used_mib=$((1 + PARTITION_ESP_MIB + PARTITION_ROOT_MIB + PARTITION_SWAP_MIB))
    home_mib=$((disk_mib - used_mib))

    if ((home_mib < min_home_mib)); then
        log_error "El esquema (ESP $((PARTITION_ESP_MIB))M + root $((PARTITION_ROOT_MIB))M + swap $((PARTITION_SWAP_MIB))M) deja solo ${home_mib}MiB para /home en un disco de ${disk_mib}MiB; se requieren al menos ${min_home_mib}MiB."
        return 1
    fi

    log "Esquema de particiones: ESP ${PARTITION_ESP_MIB}MiB, root ${PARTITION_ROOT_MIB}MiB, swap ${PARTITION_SWAP_MIB}MiB, /home ~$((home_mib / 1024))GiB (resto del disco)"
}

################################################################################
# Función para particionar el disco
#
# Crea una tabla de particiones GPT y 4 particiones según el esquema definido:
# 1. ESP: ESP_SIZE (512M por defecto), tipo EFI System
# 2. Root: ROOT_SIZE (8G por defecto), tipo Linux filesystem
# 3. Swap: SWAP_SIZE (2G por defecto), tipo Linux swap
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
    local esp_end root_end swap_end

    # Verificar que el dispositivo existe
    if ! is_block_device "$device"; then
        log_error "El dispositivo $device no existe"
        return 1
    fi

    resolve_partition_sizes || return 1
    esp_end=$((1 + PARTITION_ESP_MIB))
    root_end=$((esp_end + PARTITION_ROOT_MIB))
    swap_end=$((root_end + PARTITION_SWAP_MIB))

    log "Creando tabla de particiones GPT en $device"

    # Crear tabla GPT
    if ! run_quiet parted -s "$device" mklabel gpt; then
        log_error "Fallo al crear tabla GPT en $device"
        return 1
    fi

    log "Creando partición ESP (${PARTITION_ESP_MIB}MiB)"
    # Crear partición ESP: 1MiB - esp_end (513MiB con el tamaño por defecto)
    if ! run_quiet parted -s "$device" mkpart ESP fat32 1MiB "${esp_end}MiB"; then
        log_error "Fallo al crear partición ESP"
        return 1
    fi

    # Marcar partición como ESP
    if ! run_quiet parted -s "$device" set 1 esp on; then
        log_error "Fallo al marcar partición como ESP"
        return 1
    fi

    log "Creando partición Root (${PARTITION_ROOT_MIB}MiB)"
    # Crear partición Root: esp_end - root_end (513MiB - 8705MiB por defecto)
    if ! run_quiet parted -s "$device" mkpart primary ext4 "${esp_end}MiB" "${root_end}MiB"; then
        log_error "Fallo al crear partición Root"
        return 1
    fi

    log "Creando partición Swap (${PARTITION_SWAP_MIB}MiB)"
    # Crear partición Swap: root_end - swap_end (8705MiB - 10753MiB por defecto)
    if ! run_quiet parted -s "$device" mkpart primary linux-swap "${root_end}MiB" "${swap_end}MiB"; then
        log_error "Fallo al crear partición Swap"
        return 1
    fi

    log "Creando partición Home (espacio restante)"
    # Crear partición Home: swap_end - 100%
    if ! run_quiet parted -s "$device" mkpart primary ext4 "${swap_end}MiB" 100%; then
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
