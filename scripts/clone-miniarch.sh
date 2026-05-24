#!/usr/bin/env bash
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
  sudo bash scripts/clone-miniarch.sh [disco-origen] [disco-destino]
  sudo bash scripts/clone-miniarch.sh --repair-fstab /dev/disco-clonado

Opciones:
  -h, --help       Mostrar esta ayuda.
  --repair-fstab  Reescribir /etc/fstab de un disco MiniArch ya clonado.
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
  pacman -Sy --needed gptfdisk e2fsprogs dosfstools arch-install-scripts parted util-linux

EOF
}

require_clone_commands() {
    require_command lsblk
    require_command awk
    require_command dd
    require_command sync
}

require_fstab_commands() {
    require_command lsblk
    require_command blkid
    require_command mount
    require_command umount
    require_command awk
}

require_uuid_commands() {
    local missing=false
    local command_name

    for command_name in sgdisk e2fsck tune2fs swaplabel uuidgen blkid mount umount; do
        if ! command -v "$command_name" >/dev/null 2>&1; then
            warn "Falta '$command_name'."
            missing=true
        fi
    done

    if [[ "$missing" == "true" ]]; then
        warn_missing_package_hint
        die "Faltan herramientas para cambiar UUIDs/GUIDs del clon."
    fi

    require_grub_commands
}

require_grub_commands() {
    if ! command -v arch-chroot >/dev/null 2>&1; then
        warn_missing_package_hint
        die "No se encontro 'arch-chroot' para regenerar GRUB."
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
        partprobe "$disk" || true
    elif command -v blockdev >/dev/null 2>&1; then
        blockdev --rereadpt "$disk" || true
    else
        warn "No se encontro partprobe ni blockdev; puede requerir reinicio para ver particiones nuevas."
    fi

    settle_devices
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-no}"
    local answer normalized suffix

    suffix="s/N"
    [[ "$default" == "yes" ]] && suffix="S/n"

    read -rp "$(echo -e "${BLUE}${prompt} (${suffix}): ${NC}")" answer </dev/tty
    answer="${answer:-$default}"
    normalized="${answer,,}"
    normalized="${normalized//$'\r'/}"
    normalized="${normalized//[[:space:]]/}"

    case "$normalized" in
        s|si|sí|y|yes) return 0 ;;
        n|no) return 1 ;;
        *) die "Respuesta invalida: $answer" ;;
    esac
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

disk_size_bytes() {
    lsblk -b -d -n -o SIZE "$1" 2>/dev/null | awk '{print $1}'
}

ensure_no_mounted_partitions() {
    local disk="$1"

    if lsblk -n -r -o MOUNTPOINT "$disk" | awk 'NF { found=1 } END { exit found ? 0 : 1 }'; then
        lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk" >&2
        die "Hay particiones montadas en $disk. Desmontelas antes de continuar."
    fi
}

confirm_clone() {
    local source_disk="$1"
    local target_disk="$2"
    local confirmation normalized

    echo ""
    echo "Origen:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$source_disk"
    echo ""
    echo "Destino:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$target_disk"
    echo ""
    warn "TODO el contenido de $target_disk sera destruido y reemplazado por $source_disk."
    read -rp "Para confirmar escriba CLONAR o clonar: " confirmation </dev/tty
    normalized="${confirmation,,}"
    normalized="${normalized//$'\r'/}"
    normalized="${normalized//[[:space:]]/}"
    [[ "$normalized" == "clonar" ]] || die "Operacion cancelada."
}

clone_disk() {
    local source_disk="$1"
    local target_disk="$2"
    local mapfile_path="/tmp/miniarch-ddrescue-$(basename "$source_disk")-to-$(basename "$target_disk").map"

    log "Clonando $source_disk hacia $target_disk..."
    if command -v ddrescue >/dev/null 2>&1; then
        ddrescue -f -n "$source_disk" "$target_disk" "$mapfile_path"
        ddrescue -f -r3 "$source_disk" "$target_disk" "$mapfile_path"
    else
        warn "ddrescue no esta instalado; usando dd."
        dd if="$source_disk" of="$target_disk" bs=4M status=progress conv=fsync
    fi

    sync
    reread_partition_table "$target_disk"
    log "Clonacion completada."
}

mount_clone() {
    local disk="$1"
    local mount_root="$2"
    local root_partition home_partition esp_partition

    root_partition=$(partition_path "$disk" 2)
    home_partition=$(partition_path "$disk" 4)
    esp_partition=$(partition_path "$disk" 1)

    mkdir -p "$mount_root"
    mount "$root_partition" "$mount_root"
    mkdir -p "$mount_root/home" "$mount_root/boot"

    if [[ -b "$home_partition" ]]; then
        mount "$home_partition" "$mount_root/home"
    fi

    if [[ -b "$esp_partition" ]]; then
        mount "$esp_partition" "$mount_root/boot"
    fi
}

partition_uuid() {
    local partition="$1"

    blkid -s UUID -o value "$partition" 2>/dev/null | awk 'NF { print; exit }'
}

require_partition_uuid() {
    local partition="$1"
    local label="$2"
    local uuid

    uuid=$(partition_uuid "$partition")
    [[ -n "$uuid" ]] || die "No se pudo leer UUID de $label ($partition)."
    echo "$uuid"
}

unmount_clone() {
    local mount_root="$1"

    umount -R "$mount_root" 2>/dev/null || true
    rmdir "$mount_root" 2>/dev/null || true
}

refresh_fstab() {
    local disk="$1"
    local mount_root
    local esp_partition root_partition swap_partition home_partition
    local esp_uuid root_uuid swap_uuid home_uuid
    local backup_path

    mount_root=$(mktemp -d /mnt/miniarch-clone.XXXXXX)
    esp_partition=$(partition_path "$disk" 1)
    root_partition=$(partition_path "$disk" 2)
    swap_partition=$(partition_path "$disk" 3)
    home_partition=$(partition_path "$disk" 4)

    blkid -g || true

    root_uuid=$(require_partition_uuid "$root_partition" "root")
    esp_uuid=$(require_partition_uuid "$esp_partition" "EFI")
    home_uuid=$(require_partition_uuid "$home_partition" "home")
    swap_uuid=""
    if [[ -b "$swap_partition" ]]; then
        swap_uuid=$(partition_uuid "$swap_partition")
        [[ -n "$swap_uuid" ]] || warn "No se pudo leer UUID de swap ($swap_partition); no se escribira swap en fstab."
    fi

    if ! mount_clone "$disk" "$mount_root"; then
        unmount_clone "$mount_root"
        die "No se pudo montar el clon para regenerar fstab."
    fi

    if [[ -f "$mount_root/etc/fstab" ]]; then
        backup_path="$mount_root/etc/fstab.clone-backup"
        cp "$mount_root/etc/fstab" "$backup_path"
    fi

    cat > "$mount_root/etc/fstab" <<EOF
# /etc/fstab: static file system information.
# Generated by clone-miniarch.sh for MiniArch cloned layout.

UUID=$root_uuid / ext4 defaults,noatime 0 1
UUID=$esp_uuid /boot vfat umask=0077 0 2
EOF

    if [[ -n "$swap_uuid" ]]; then
        cat >> "$mount_root/etc/fstab" <<EOF
UUID=$swap_uuid none swap defaults 0 0
EOF
    fi

    cat >> "$mount_root/etc/fstab" <<EOF
UUID=$home_uuid /home ext4 defaults,noatime 0 2
EOF

    log "fstab escrito con UUIDs actuales:"
    sed 's/^/  /' "$mount_root/etc/fstab"

    unmount_clone "$mount_root"
}

refresh_grub() {
    local disk="$1"
    local mount_root

    require_grub_commands
    mount_root=$(mktemp -d /mnt/miniarch-clone.XXXXXX)

    if ! mount_clone "$disk" "$mount_root"; then
        unmount_clone "$mount_root"
        die "No se pudo montar el clon para regenerar GRUB."
    fi

    if [[ -x "$mount_root/usr/bin/grub-mkconfig" ]]; then
        if ! arch-chroot "$mount_root" grub-mkconfig -o /boot/grub/grub.cfg; then
            unmount_clone "$mount_root"
            die "No se pudo regenerar GRUB dentro del clon."
        fi
        log "GRUB regenerado con los UUIDs actuales."
    else
        warn "No se encontro grub-mkconfig dentro del clon; omitiendo regeneracion de GRUB."
    fi

    if [[ -x "$mount_root/usr/bin/grub-install" ]] && ask_yes_no "Instalar GRUB UEFI en modo removable en el clon" "yes"; then
        if ! arch-chroot "$mount_root" grub-install \
            --target=x86_64-efi \
            --efi-directory=/boot \
            --bootloader-id=MiniArch \
            --removable \
            --recheck; then
            unmount_clone "$mount_root"
            die "No se pudo instalar GRUB UEFI removable en el clon."
        fi
        log "GRUB UEFI removable instalado en el clon."
    fi

    unmount_clone "$mount_root"
}

reformat_esp_uuid() {
    local disk="$1"
    local esp_partition
    local tmp_mount backup_dir

    esp_partition=$(partition_path "$disk" 1)
    [[ -b "$esp_partition" ]] || return 0

    if ! command -v mkfs.fat >/dev/null 2>&1; then
        warn_missing_package_hint
        die "No se encontro 'mkfs.fat' para cambiar el UUID FAT de la particion EFI."
    fi

    tmp_mount=$(mktemp -d /mnt/miniarch-esp.XXXXXX)
    backup_dir=$(mktemp -d /tmp/miniarch-esp-backup.XXXXXX)

    mount "$esp_partition" "$tmp_mount"
    cp -a "$tmp_mount"/. "$backup_dir"/
    umount "$tmp_mount"

    mkfs.fat -F32 "$esp_partition"
    mount "$esp_partition" "$tmp_mount"
    cp -a "$backup_dir"/. "$tmp_mount"/
    sync
    umount "$tmp_mount"

    rmdir "$tmp_mount"
    rm -rf "$backup_dir"
}

randomize_clone_ids() {
    local disk="$1"
    local root_partition swap_partition home_partition

    require_uuid_commands

    root_partition=$(partition_path "$disk" 2)
    swap_partition=$(partition_path "$disk" 3)
    home_partition=$(partition_path "$disk" 4)

    ensure_no_mounted_partitions "$disk"

    log "Cambiando GUIDs GPT del disco y particiones..."
    sgdisk -G "$disk"
    reread_partition_table "$disk"

    log "Cambiando UUID de root ext4..."
    e2fsck -fy "$root_partition"
    tune2fs -U random "$root_partition"

    if [[ -b "$swap_partition" ]]; then
        log "Cambiando UUID de swap..."
        swaplabel -U "$(uuidgen)" "$swap_partition"
    fi

    if [[ -b "$home_partition" ]]; then
        log "Cambiando UUID de home ext4..."
        e2fsck -fy "$home_partition"
        tune2fs -U random "$home_partition"
    fi

    if ! command -v mkfs.fat >/dev/null 2>&1; then
        warn "No se encontro mkfs.fat; se conservara el UUID FAT de la particion EFI."
    elif ask_yes_no "Cambiar tambien el UUID FAT de la particion EFI reformateandola y restaurando su contenido" "yes"; then
        reformat_esp_uuid "$disk"
    else
        warn "La particion EFI conservara su UUID FAT actual."
    fi

    blkid -g || true
    refresh_fstab "$disk"
    refresh_grub "$disk"
}

repair_fstab_only() {
    local disk="$1"

    require_root
    require_fstab_commands
    [[ -b "$disk" ]] || die "El disco no existe: $disk"
    ensure_no_mounted_partitions "$disk"

    refresh_fstab "$disk"

    if command -v arch-chroot >/dev/null 2>&1 && ask_yes_no "Regenerar GRUB tambien" "yes"; then
        refresh_grub "$disk"
    else
        warn "GRUB no fue regenerado. Si cambiaste UUID de root, conviene regenerarlo despues."
    fi
}

main() {
    local source_disk="${1:-}"
    local target_disk="${2:-}"
    local source_size target_size

    case "${1:-}" in
        -h|--help)
            usage
            exit 0
            ;;
        --repair-fstab)
            [[ -n "${2:-}" ]] || die "Falta el disco clonado. Ejemplo: --repair-fstab /dev/sdb"
            repair_fstab_only "$2"
            exit 0
            ;;
    esac

    require_root
    require_clone_commands

    if [[ -z "$source_disk" ]]; then
        source_disk=$(select_disk "Disco origen (numero o ruta)")
    fi

    if [[ -z "$target_disk" ]]; then
        target_disk=$(select_disk "Disco destino (numero o ruta)")
    fi

    [[ -b "$source_disk" ]] || die "El disco origen no existe: $source_disk"
    [[ -b "$target_disk" ]] || die "El disco destino no existe: $target_disk"
    [[ "$source_disk" != "$target_disk" ]] || die "Origen y destino no pueden ser el mismo disco."

    source_size=$(disk_size_bytes "$source_disk")
    target_size=$(disk_size_bytes "$target_disk")
    [[ -n "$source_size" && -n "$target_size" ]] || die "No se pudo leer el tamano de los discos."
    (( target_size >= source_size )) || die "El destino es mas pequeno que el origen."

    ensure_no_mounted_partitions "$source_disk"
    ensure_no_mounted_partitions "$target_disk"
    confirm_clone "$source_disk" "$target_disk"
    clone_disk "$source_disk" "$target_disk"

    if ask_yes_no "Cambiar UUIDs/GUIDs del disco clonado y regenerar fstab" "yes"; then
        randomize_clone_ids "$target_disk"
    fi

    if ask_yes_no "Expandir /home del disco clonado al espacio disponible" "yes"; then
        [[ -f "$SCRIPT_DIR/expand-home.sh" ]] || die "No se encontro $SCRIPT_DIR/expand-home.sh"
        bash "$SCRIPT_DIR/expand-home.sh" --yes "$target_disk"
    fi

    echo ""
    log "Proceso terminado."
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$target_disk"
}

main "$@"
