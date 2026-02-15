#!/bin/bash

# Módulo de Finalización
# Funciones para configurar red y limpiar el sistema después de la instalación

# configure_network()
# Instala NetworkManager, lo habilita y configura la zona horaria
# Requirements: 12.1, 12.2, 12.3, 12.4
configure_network() {
    log "Configurando red y zona horaria..."
    
    # Instalar NetworkManager
    if ! arch-chroot /mnt pacman -S --noconfirm networkmanager; then
        log_error "Fallo al instalar NetworkManager"
        return 1
    fi
    
    # Habilitar NetworkManager para inicio automático
    if ! arch-chroot /mnt systemctl enable NetworkManager.service; then
        log_error "Fallo al habilitar NetworkManager.service"
        return 1
    fi
    
    log "Instalando y configurando SSH..."
    
    # Instalar OpenSSH
    if ! arch-chroot /mnt pacman -S --noconfirm openssh; then
        log_error "Fallo al instalar OpenSSH"
        return 1
    fi
    
    # Habilitar SSH para inicio automático
    if ! arch-chroot /mnt systemctl enable sshd.service; then
        log_error "Fallo al habilitar sshd.service"
        return 1
    fi
    
    log "SSH instalado y habilitado correctamente"
    
    # Configurar zona horaria
    if ! arch-chroot /mnt timedatectl set-timezone "${TIMEZONE:-America/Mexico_City}"; then
        log_error "Fallo al configurar zona horaria"
        return 1
    fi
    
    # Sincronizar reloj del hardware con el reloj del sistema
    if ! arch-chroot /mnt hwclock --systohc; then
        log_error "Fallo al sincronizar reloj del hardware"
        return 1
    fi
    
    log "Red, SSH y zona horaria configuradas correctamente"
    return 0
}

# cleanup_and_finish()
# Desmonta todas las particiones, desactiva swap y muestra mensajes de finalización
# Requirements: 13.1, 13.2, 13.3, 13.4, 13.5
cleanup_and_finish() {
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
    if swapon --show | grep -q "${DISK_DEVICE}3"; then
        if ! swapoff "${DISK_DEVICE}3"; then
            log_error "Fallo al desactivar swap"
            return 1
        fi
        log "Swap desactivado"
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
