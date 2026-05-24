#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

ASSUME_YES=false

log() {
    echo -e "${GREEN}INFO:${NC} $*"
}

warn() {
    echo -e "${YELLOW}ADVERTENCIA:${NC} $*" >&2
}

die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}

usage() {
    cat <<'EOF'
Uso:
  sudo bash scripts/expand-home.sh [--yes] [/dev/disco]

Expande la particion 4, usada por /home en MiniArch, hasta el final del disco.

Ejemplos:
  sudo bash scripts/expand-home.sh
  sudo bash scripts/expand-home.sh /dev/sdb
  sudo bash scripts/expand-home.sh --yes /dev/nvme0n1

Opciones:
  -y, --yes   No pedir confirmacion EXPANDIR. Usar solo desde flujos ya confirmados.
  -h, --help  Mostrar esta ayuda.
EOF
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Ejecute este script como root."
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "No se encontro '$1'. Instale el paquete necesario y reintente."
}

warn_missing_package_hint() {
    cat >&2 <<'EOF'

En Arch live normalmente puedes instalar las herramientas faltantes con:
  pacman -Sy --needed gptfdisk e2fsprogs parted cloud-guest-utils

EOF
}

require_expand_commands() {
    local missing=false
    local command_name

    for command_name in lsblk awk sgdisk parted e2fsck resize2fs; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            warn "Falta '$command_name'."
            missing=true
        fi
    done

    if [[ "$missing" == "true" ]]; then
        warn_missing_package_hint
        die "Faltan herramientas para expandir /home."
    fi
}

settle_devices() {
    if command -v udevadm >/dev/null 2>&1; then
        udevadm settle || true
    fi
}

reread_partition_table() {
    local disk="$1"

    if command -v partprobe >/dev/null 2>&1; then
        partprobe "$disk" || warn "partprobe no pudo releer la tabla."
    elif command -v blockdev >/dev/null 2>&1; then
        blockdev --rereadpt "$disk" || warn "blockdev no pudo releer la tabla."
    else
        warn "No se encontro partprobe ni blockdev; puede requerir reinicio antes de resize2fs."
    fi

    settle_devices
}

partition_path() {
    local disk="$1"
    local number="$2"

    case "$disk" in
        *[0-9]) echo "${disk}p${number}" ;;
        *) echo "${disk}${number}" ;;
    esac
}

list_disks() {
    lsblk -d -n -p -e 7,11 -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" { print $1 }'
}

describe_disk() {
    local disk="$1"
    local size tran rm model label

    size=$(lsblk -d -n -o SIZE "$disk" 2>/dev/null | awk '{$1=$1; print}')
    tran=$(lsblk -d -n -o TRAN "$disk" 2>/dev/null | awk '{$1=$1; print}')
    rm=$(lsblk -d -n -o RM "$disk" 2>/dev/null | awk '{$1=$1; print}')
    model=$(lsblk -d -n -o MODEL "$disk" 2>/dev/null | awk '{$1=$1; print}')
    label=""

    if [[ "$tran" == "usb" || "$rm" == "1" ]]; then
        label=" [USB/removible]"
    fi

    printf "%-14s %-8s %-10s %s%s\n" "$disk" "${size:-?}" "${tran:-local}" "${model:-sin-modelo}" "$label"
}

select_disk() {
    local prompt="$1"
    local -a disks=()
    local disk answer selected index

    mapfile -t disks < <(list_disks)
    [[ ${#disks[@]} -gt 0 ]] || die "No se detectaron discos."

    echo "" >&2
    echo "Discos detectados:" >&2
    index=1
    for disk in "${disks[@]}"; do
        printf "  %d) " "$index" >&2
        describe_disk "$disk" >&2
        index=$((index + 1))
    done
    echo "" >&2

    read -rp "$(echo -e "${BLUE}${prompt}: ${NC}")" answer </dev/tty
    [[ -n "$answer" ]] || die "No se selecciono ningun disco."

    if [[ "$answer" =~ ^[0-9]+$ ]]; then
        (( answer >= 1 && answer <= ${#disks[@]} )) || die "Seleccion fuera de rango: $answer"
        selected="${disks[$((answer - 1))]}"
    else
        selected="$answer"
    fi

    [[ -b "$selected" ]] || die "El dispositivo '$selected' no existe o no es un bloque."
    echo "$selected"
}

ensure_whole_disk() {
    local disk="$1"
    local type

    type=$(lsblk -d -n -o TYPE "$disk" 2>/dev/null | awk '{print $1}')
    [[ "$type" == "disk" ]] || die "$disk no parece ser un disco completo. Use /dev/sdX, /dev/nvme0n1 o similar."
}

ensure_not_mounted() {
    local disk="$1"

    if lsblk -n -r -o MOUNTPOINT "$disk" | awk 'NF { found=1 } END { exit found ? 0 : 1 }'; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk" >&2
        die "Hay particiones montadas en $disk. Desmontelas antes de expandir."
    fi
}

ensure_home_partition() {
    local home_partition="$1"
    local fstype

    [[ -b "$home_partition" ]] || die "No existe la particion home esperada: $home_partition"

    fstype=$(lsblk -n -o FSTYPE "$home_partition" 2>/dev/null | awk '{print $1}')
    [[ "$fstype" == "ext4" ]] || die "$home_partition usa FSTYPE='${fstype:-desconocido}', se esperaba ext4."
}

show_layout() {
    local disk="$1"

    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$disk"
}

confirm_expand() {
    local disk="$1"
    local home_partition="$2"
    local confirmation

    [[ "$ASSUME_YES" == "true" ]] && return 0

    echo ""
    echo "Disco seleccionado para expandir /home:"
    show_layout "$disk"
    echo ""
    warn "Se expandira la particion 4 ($home_partition) hasta el final de $disk."
    read -rp "Para confirmar escriba EXPANDIR: " confirmation
    [[ "$confirmation" == "EXPANDIR" ]] || die "Operacion cancelada."
}

grow_home_partition() {
    local disk="$1"

    log "Reparando GPT si el disco crecio despues de clonar..."
    sgdisk -e "$disk"

    log "Expandiendo particion 4 hasta el final del disco..."
    if command -v growpart >/dev/null 2>&1; then
        if ! growpart "$disk" 4; then
            warn "growpart no pudo expandir la particion; intentando con parted."
            parted -s "$disk" resizepart 4 100%
        fi
    else
        parted -s "$disk" resizepart 4 100%
    fi

    reread_partition_table "$disk"
}

resize_home_filesystem() {
    local home_partition="$1"

    log "Revisando filesystem ext4 en $home_partition..."
    e2fsck -fy "$home_partition"

    log "Expandiendo filesystem ext4 en $home_partition..."
    resize2fs "$home_partition"
}

expand_home() {
    local disk="$1"
    local home_partition

    ensure_whole_disk "$disk"
    home_partition=$(partition_path "$disk" 4)
    ensure_home_partition "$home_partition"
    ensure_not_mounted "$disk"
    confirm_expand "$disk" "$home_partition"

    echo ""
    log "Estado antes de expandir:"
    show_layout "$disk"

    grow_home_partition "$disk"
    resize_home_filesystem "$home_partition"

    echo ""
    log "Expansion completada."
    show_layout "$disk"
}

main() {
    local disk=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--yes)
                ASSUME_YES=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "Opcion desconocida: $1"
                ;;
            *)
                [[ -z "$disk" ]] || die "Solo se acepta un disco."
                disk="$1"
                shift
                ;;
        esac
    done

    require_root
    require_expand_commands

    if [[ -z "$disk" ]]; then
        disk=$(select_disk "Disco clonado donde expandir /home (numero o ruta)")
    fi

    expand_home "$disk"
}

main "$@"
