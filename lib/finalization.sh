#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Modulo de finalizacion.
# Configura red, servicios remotos opcionales, zona horaria y limpieza final.

configure_network() {
    log "Configurando red y zona horaria..."

    if ! run_quiet arch-chroot /mnt pacman -S --noconfirm networkmanager; then
        log_error "Fallo al instalar NetworkManager"
        return 1
    fi

    if ! run_quiet arch-chroot /mnt systemctl enable NetworkManager.service; then
        log_error "Fallo al habilitar NetworkManager.service"
        return 1
    fi

    if [[ "${ENABLE_SSH:-true}" == "true" ]]; then
        log "Instalando y configurando SSH..."

        if ! run_quiet arch-chroot /mnt pacman -S --noconfirm openssh; then
            log_error "Fallo al instalar OpenSSH"
            return 1
        fi

        if ! run_quiet arch-chroot /mnt systemctl enable sshd.service; then
            log_error "Fallo al habilitar sshd.service"
            return 1
        fi

        log "SSH instalado y habilitado correctamente"
    else
        log "SSH deshabilitado por configuracion (ENABLE_SSH=false)"
    fi

    local tz="${TIMEZONE:-America/Mexico_City}"
    log "Configurando zona horaria a $tz..."

    if ! run_quiet arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime; then
        log_error "Fallo al configurar zona horaria"
        return 1
    fi

    if ! run_quiet arch-chroot /mnt hwclock --systohc; then
        log_error "Fallo al sincronizar reloj del hardware"
        return 1
    fi

    log "Red, servicios remotos y zona horaria configurados correctamente"
}

cleanup_partition_path() {
    local device="$1"
    local partition_number="$2"

    if type get_partition_path &> /dev/null; then
        get_partition_path "$device" "$partition_number"
        return $?
    fi

    case "$device" in
        *[0-9]) echo "${device}p${partition_number}" ;;
        *) echo "${device}${partition_number}" ;;
    esac
}

cleanup_mounts() {
    local swap_partition
    swap_partition=$(cleanup_partition_path "${DISK_DEVICE:-/dev/sda}" 3) || return 1

    log "Iniciando limpieza y desmontaje..."

    if mountpoint -q /mnt/boot; then
        if ! run_quiet umount /mnt/boot; then
            log_error "Fallo al desmontar /mnt/boot"
            return 1
        fi
        log "Desmontado /mnt/boot"
    fi

    if mountpoint -q /mnt/home; then
        if ! run_quiet umount /mnt/home; then
            log_error "Fallo al desmontar /mnt/home"
            return 1
        fi
        log "Desmontado /mnt/home"
    fi

    if mountpoint -q /mnt; then
        if ! run_quiet umount /mnt; then
            log_error "Fallo al desmontar /mnt"
            return 1
        fi
        log "Desmontado /mnt"
    fi

    if swapon --show | grep -q "$swap_partition"; then
        if ! run_quiet swapoff "$swap_partition"; then
            log_error "Fallo al desactivar swap"
            return 1
        fi
        log "Swap desactivado"
    fi
}

cleanup_and_finish() {
    local system_message="${1:-El sistema Arch Linux en modo kiosko ha sido instalado correctamente.}"
    local boot_message="${2:-El sistema arrancara automaticamente en modo grafico con OpenBox.}"

    if ! cleanup_mounts; then
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "  INSTALACION COMPLETADA EXITOSAMENTE"
    echo "=========================================="
    echo ""
    echo "$system_message"
    echo ""
    echo "Puede reiniciar el sistema ejecutando: reboot"
    echo ""
    echo "$boot_message"
    echo "=========================================="
    echo ""

    log "Instalacion finalizada exitosamente"
}
