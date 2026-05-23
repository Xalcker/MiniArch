#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

################################################################################
# MÃ³dulo de Bootloader
#
# Este mÃ³dulo contiene funciones para instalar y configurar GRUB como gestor
# de arranque con soporte UEFI y configuraciÃ³n silenciosa para ocultar todos
# los mensajes durante el arranque.
#
# Funciones:
# - install_grub(): Instala GRUB con soporte UEFI
# - configure_grub_silent(): Configura GRUB para arranque silencioso
################################################################################

################################################################################
# install_grub()
#
# Instala GRUB y efibootmgr en el sistema, luego instala GRUB en la particiÃ³n
# ESP con soporte UEFI.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - La particiÃ³n ESP debe estar montada en /boot
#   - El sistema debe tener soporte UEFI
#
# Returns:
#   0 - Si la instalaciÃ³n fue exitosa
#   1 - Si hubo un error durante la instalaciÃ³n
################################################################################
bootloader_ensure_pacman_download_user() {
    if [[ ! -f /mnt/etc/pacman.conf ]]; then
        return 0
    fi

    if ! grep -Eq '^[[:space:]]*DownloadUser[[:space:]]*=' /mnt/etc/pacman.conf; then
        return 0
    fi

    if arch-chroot /mnt getent passwd alpm >/dev/null 2>&1; then
        return 0
    fi

    log "Creando usuario de sistema alpm requerido por pacman DownloadUser"
    arch-chroot /mnt groupadd -r alpm 2>/dev/null || true
    if ! arch-chroot /mnt useradd -r -g alpm -d /var/lib/pacman -s /usr/bin/nologin alpm; then
        log_error "No se pudo crear usuario alpm para pacman"
        return 1
    fi
}

install_grub() {
    local has_grub=0
    local has_efibootmgr=0

    bootloader_ensure_pacman_download_user || return 1

    if arch-chroot /mnt command -v grub-install >/dev/null 2>&1; then
        has_grub=1
    fi

    if arch-chroot /mnt command -v efibootmgr >/dev/null 2>&1; then
        has_efibootmgr=1
    fi

    if [[ $has_grub -eq 1 && $has_efibootmgr -eq 1 ]]; then
        log "GRUB y efibootmgr ya estan instalados en el sistema destino"
    else
        log "Instalando paquetes GRUB y efibootmgr"

        if ! run_quiet arch-chroot /mnt pacman -S --needed --noconfirm grub efibootmgr; then
            if arch-chroot /mnt command -v grub-install >/dev/null 2>&1 && \
               arch-chroot /mnt command -v efibootmgr >/dev/null 2>&1; then
                log "pacman reporto un fallo, pero GRUB y efibootmgr ya estan disponibles; continuando"
            else
                log_error "Fallo al instalar grub y efibootmgr"
                if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
                    echo "Ultimas lineas de $LOG_FILE:" >&2
                    tail -n 40 "$LOG_FILE" >&2 || true
                fi
                return 1
            fi
        fi
    fi

    if [[ ! -d /sys/firmware/efi ]]; then
        log_error "No se detecto arranque UEFI en /sys/firmware/efi. Arranque el ISO en modo UEFI."
        return 1
    fi

    if ! mountpoint -q /mnt/boot; then
        log_error "La particion ESP no esta montada en /mnt/boot"
        return 1
    fi

    log "Instalando GRUB en la particion ESP con soporte UEFI"

    if ! run_quiet arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB; then
        log_error "Fallo al instalar GRUB en la particion ESP"
        if [[ -n "${LOG_FILE:-}" && -f "$LOG_FILE" ]]; then
            echo "Ultimas lineas de $LOG_FILE:" >&2
            tail -n 40 "$LOG_FILE" >&2 || true
        fi
        return 1
    fi

    log "GRUB instalado exitosamente"
    return 0
}

################################################################################
# configure_grub_silent()
#
# Configura GRUB para arranque silencioso modificando /etc/default/grub con:
# - GRUB_TIMEOUT=0: Arranque inmediato sin menÃº
# - ParÃ¡metros del kernel: quiet, loglevel=3, rd.systemd.show_status=false,
#   rd.udev.log_level=3
# - GRUB_DISABLE_SUBMENU=y: Deshabilita submenÃºs
#
# Luego genera el archivo de configuraciÃ³n de GRUB.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - GRUB debe estar instalado
#
# Returns:
#   0 - Si la configuraciÃ³n fue exitosa
#   1 - Si hubo un error durante la configuraciÃ³n
################################################################################
configure_grub_silent() {
    local grub_config="/mnt/etc/default/grub"
    
    # Verificar que existe el archivo de configuraciÃ³n de GRUB
    if [[ ! -f "$grub_config" ]]; then
        log_error "El archivo $grub_config no existe. GRUB debe estar instalado primero."
        return 1
    fi
    
    log "Configurando GRUB para arranque silencioso"
    
    # Crear backup del archivo original
    cp "$grub_config" "${grub_config}.backup"
    
    # Modificar GRUB_TIMEOUT a 0
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
    
    # Modificar GRUB_CMDLINE_LINUX_DEFAULT para agregar parÃ¡metros silenciosos
    # Primero, eliminar la lÃ­nea existente
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
    
    # Agregar la nueva lÃ­nea con todos los parÃ¡metros
    # quiet: menos mensajes, loglevel=3: solo errores, rd.*: silencio en initramfs
    # vt.global_cursor_default=0: oculta el cursor de la terminal, fbcon=nodefer: evita retrasos en fb
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 vt.global_cursor_default=0 fbcon=nodefer"' >> "$grub_config"
    
    # Agregar o modificar GRUB_DISABLE_SUBMENU
    if grep -q "^GRUB_DISABLE_SUBMENU=" "$grub_config"; then
        sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
    else
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
    fi
    
    log "Generando archivo de configuraciÃ³n de GRUB"
    
    # Generar el archivo de configuraciÃ³n de GRUB
    if ! run_quiet arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        log_error "Fallo al generar el archivo de configuraciÃ³n de GRUB"
        return 1
    fi
    
    log "GRUB configurado exitosamente para arranque silencioso"
    return 0
}
