#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Módulo de Finalización
# Funciones para configurar red y limpiar el sistema después de la instalación

# configure_network()
# Instala NetworkManager, opcionalmente SSH, y configura la zona horaria
# Requirements: 12.1, 12.2, 12.3, 12.4
configure_network() {
    log "Configurando red y zona horaria..."

    # Instalar NetworkManager
    if ! run_quiet arch-chroot /mnt pacman -S --noconfirm networkmanager; then
        log_error "Fallo al instalar NetworkManager"
        return 1
    fi

    # Habilitar NetworkManager para inicio automático
    if ! arch-chroot /mnt systemctl enable NetworkManager.service; then
        log_error "Fallo al habilitar NetworkManager.service"
        return 1
    fi

    if [[ "${ENABLE_SSH:-true}" == "true" ]]; then
        log "Instalando y configurando SSH..."

        # Instalar OpenSSH
        if ! run_quiet arch-chroot /mnt pacman -S --noconfirm openssh; then
            log_error "Fallo al instalar OpenSSH"
            return 1
        fi

        # Habilitar SSH para inicio automático
        if ! arch-chroot /mnt systemctl enable sshd.service; then
            log_error "Fallo al habilitar sshd.service"
            return 1
        fi

        log "SSH instalado y habilitado correctamente"
    else
        log "SSH deshabilitado por configuración (ENABLE_SSH=false)"
    fi

    # Configurar zona horaria usando symlink (timedatectl no funciona en chroot)
    local tz="${TIMEZONE:-America/Mexico_City}"
    log "Configurando zona horaria a $tz..."
    if ! arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime; then
        log_error "Fallo al configurar zona horaria"
        return 1
    fi

    # Sincronizar reloj del hardware con el reloj del sistema
    if ! arch-chroot /mnt hwclock --systohc; then
        log_error "Fallo al sincronizar reloj del hardware"
        return 1
    fi

    log "Red, servicios remotos y zona horaria configurados correctamente"
    return 0
}

# cleanup_partition_path()
# Devuelve la ruta de partición para limpieza incluso si partitioning.sh no está cargado.
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

# cleanup_mounts()
# Desmonta todas las particiones y desactiva swap sin imprimir mensaje de éxito final.
cleanup_mounts() {
    local swap_partition
    swap_partition=$(cleanup_partition_path "${DISK_DEVICE:-/dev/sda}" 3) || return 1

    log "Iniciando limpieza y desmontaje..."

    # Desmontar /mnt/boot (ESP)
    if mountpoint -q /mnt/boot; then
        if ! umount /mnt/boot; then
            log_error "Fallo al desmontar /mnt/boot"
            return 1
        fi
        log "Desmontado /mnt/boot"
    fi

    # Desmontar /mnt/home
    if mountpoint -q /mnt/home; then
        if ! umount /mnt/home; then
            log_error "Fallo al desmontar /mnt/home"
            return 1
        fi
        log "Desmontado /mnt/home"
    fi

    # Desmontar /mnt (root)
    if mountpoint -q /mnt; then
        if ! umount /mnt; then
            log_error "Fallo al desmontar /mnt"
            return 1
        fi
        log "Desmontado /mnt"
    fi

    # Desactivar swap
    if swapon --show | grep -q "$swap_partition"; then
        if ! swapoff "$swap_partition"; then
            log_error "Fallo al desactivar swap"
            return 1
        fi
        log "Swap desactivado"
    fi

    return 0
}

# cleanup_and_finish()
# Desmonta todas las particiones, desactiva swap y muestra mensajes de finalización
# Requirements: 13.1, 13.2, 13.3, 13.4, 13.5
cleanup_and_finish() {
    if ! cleanup_mounts; then
        return 1
    fi

    # Mostrar mensaje de éxito
    echo ""
    echo "=========================================="
    echo "  INSTALACIÓN COMPLETADA EXITOSAMENTE"
    echo "=========================================="
    echo ""
    echo "El sistema Arch Linux en modo kiosko ha sido instalado correctamente."
    echo ""
    echo "Puede reiniciar el sistema ejecutando: reboot"
    echo ""
    echo "El sistema arrancará automáticamente en modo gráfico con OpenBox."
    echo "=========================================="
    echo ""

    log "Instalación finalizada exitosamente"
    return 0
}
