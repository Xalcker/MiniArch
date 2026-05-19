#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

################################################################################
# Módulo de Bootloader
#
# Este módulo contiene funciones para instalar y configurar GRUB como gestor
# de arranque con soporte UEFI y configuración silenciosa para ocultar todos
# los mensajes durante el arranque.
#
# Funciones:
# - install_grub(): Instala GRUB con soporte UEFI
# - configure_grub_silent(): Configura GRUB para arranque silencioso
################################################################################

################################################################################
# install_grub()
#
# Instala GRUB y efibootmgr en el sistema, luego instala GRUB en la partición
# ESP con soporte UEFI.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - La partición ESP debe estar montada en /boot
#   - El sistema debe tener soporte UEFI
#
# Returns:
#   0 - Si la instalación fue exitosa
#   1 - Si hubo un error durante la instalación
################################################################################
install_grub() {
    log "Instalando paquetes GRUB y efibootmgr"
    
    # Instalar grub y efibootmgr
    if ! run_quiet arch-chroot /mnt pacman -S --noconfirm grub efibootmgr; then
        log_error "Fallo al instalar grub y efibootmgr"
        return 1
    fi
    
    # Verificar que /mnt/boot está montado
    if ! mountpoint -q /mnt/boot; then
        log_error "La partición ESP no está montada en /mnt/boot"
        return 1
    fi
    
    log "Instalando GRUB en la partición ESP con soporte UEFI"
    
    # Instalar GRUB con soporte UEFI
    if ! run_quiet arch-chroot /mnt grub-install --target=x86_64-efi --efi-directory=/boot --bootloader-id=GRUB; then
        log_error "Fallo al instalar GRUB en la partición ESP"
        return 1
    fi
    
    log "GRUB instalado exitosamente"
    return 0
}

################################################################################
# configure_grub_silent()
#
# Configura GRUB para arranque silencioso modificando /etc/default/grub con:
# - GRUB_TIMEOUT=0: Arranque inmediato sin menú
# - Parámetros del kernel: quiet, loglevel=3, rd.systemd.show_status=false,
#   rd.udev.log_level=3
# - GRUB_DISABLE_SUBMENU=y: Deshabilita submenús
#
# Luego genera el archivo de configuración de GRUB.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - GRUB debe estar instalado
#
# Returns:
#   0 - Si la configuración fue exitosa
#   1 - Si hubo un error durante la configuración
################################################################################
configure_grub_silent() {
    local grub_config="/mnt/etc/default/grub"
    
    # Verificar que existe el archivo de configuración de GRUB
    if [[ ! -f "$grub_config" ]]; then
        log_error "El archivo $grub_config no existe. GRUB debe estar instalado primero."
        return 1
    fi
    
    log "Configurando GRUB para arranque silencioso"
    
    # Crear backup del archivo original
    cp "$grub_config" "${grub_config}.backup"
    
    # Modificar GRUB_TIMEOUT a 0
    sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=0/' "$grub_config"
    
    # Modificar GRUB_CMDLINE_LINUX_DEFAULT para agregar parámetros silenciosos
    # Primero, eliminar la línea existente
    sed -i '/^GRUB_CMDLINE_LINUX_DEFAULT=/d' "$grub_config"
    
    # Agregar la nueva línea con todos los parámetros
    # quiet: menos mensajes, loglevel=3: solo errores, rd.*: silencio en initramfs
    # vt.global_cursor_default=0: oculta el cursor de la terminal, fbcon=nodefer: evita retrasos en fb
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3 vt.global_cursor_default=0 fbcon=nodefer"' >> "$grub_config"
    
    # Agregar o modificar GRUB_DISABLE_SUBMENU
    if grep -q "^GRUB_DISABLE_SUBMENU=" "$grub_config"; then
        sed -i 's/^GRUB_DISABLE_SUBMENU=.*/GRUB_DISABLE_SUBMENU=y/' "$grub_config"
    else
        echo 'GRUB_DISABLE_SUBMENU=y' >> "$grub_config"
    fi
    
    log "Generando archivo de configuración de GRUB"
    
    # Generar el archivo de configuración de GRUB
    if ! run_quiet arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        log_error "Fallo al generar el archivo de configuración de GRUB"
        return 1
    fi
    
    log "GRUB configurado exitosamente para arranque silencioso"
    return 0
}
