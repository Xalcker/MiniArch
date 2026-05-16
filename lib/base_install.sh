#!/bin/bash

################################################################################
# Módulo de Instalación Base
#
# Este módulo contiene funciones para instalar el sistema base de Arch Linux,
# generar el archivo fstab, y preparar el entorno chroot para la configuración
# posterior del sistema.
#
# Funciones:
# - install_base_system(): Instala el sistema base usando pacstrap
# - generate_fstab(): Genera el archivo /etc/fstab con UUIDs
# - configure_chroot(): Prepara el entorno chroot para configuración
################################################################################

################################################################################
# install_base_system()
#
# Instala el sistema base de Arch Linux en /mnt usando pacstrap con los
# paquetes esenciales: base, linux, linux-firmware, y utilidades (nano, git, wpa_supplicant).
#
# Precondiciones:
#   - Las particiones deben estar montadas en /mnt
#   - Debe existir conexión de red activa
#
# Returns:
#   0 - Si la instalación fue exitosa
#   1 - Si hubo un error durante la instalación
################################################################################
install_base_system() {
    # Verificar que /mnt está montado
    if ! mountpoint -q /mnt; then
        log_error "El directorio /mnt no está montado. Ejecute mount_partitions primero."
        return 1
    fi
    
    log "Instalando sistema base con pacstrap (base, linux, linux-firmware)"
    
    # Ejecutar pacstrap para instalar el sistema base y utilidades esenciales
    if ! pacstrap /mnt base linux linux-firmware sudo wget curl unzip samba nano git wpa_supplicant; then
        log_error "Fallo al instalar el sistema base y utilidades (sudo, wget, curl, unzip, samba, nano, git, wpa_supplicant) con pacstrap"
        return 1
    fi
    
    log "Sistema base instalado exitosamente"
    return 0
}

################################################################################
# generate_fstab()
#
# Genera el archivo /etc/fstab en el sistema instalado usando genfstab con
# UUIDs para identificar las particiones de forma persistente.
#
# Precondiciones:
#   - El sistema base debe estar instalado en /mnt
#   - Las particiones deben estar montadas correctamente
#
# Returns:
#   0 - Si el fstab fue generado exitosamente
#   1 - Si hubo un error durante la generación
################################################################################
generate_fstab() {
    # Verificar que /mnt está montado
    if ! mountpoint -q /mnt; then
        log_error "El directorio /mnt no está montado"
        return 1
    fi
    
    # Verificar que existe el directorio /mnt/etc
    if [[ ! -d /mnt/etc ]]; then
        log_error "El directorio /mnt/etc no existe. El sistema base debe estar instalado primero."
        return 1
    fi
    
    log "Generando archivo /etc/fstab con UUIDs"
    
    # Generar fstab usando genfstab con opción -U (UUIDs)
    if ! genfstab -U /mnt >> /mnt/etc/fstab; then
        log_error "Fallo al generar /etc/fstab"
        return 1
    fi
    
    log "Archivo /etc/fstab generado exitosamente"
    return 0
}

################################################################################
# configure_chroot()
#
# Prepara el entorno chroot para ejecutar configuraciones adicionales dentro
# del sistema instalado. Esta función verifica que el sistema está listo para
# entrar en chroot.
#
# Precondiciones:
#   - El sistema base debe estar instalado en /mnt
#   - El archivo /etc/fstab debe estar generado
#
# Returns:
#   0 - Si el entorno chroot está listo
#   1 - Si hay un error en la preparación
#
# Nota:
#   Esta función solo verifica que el entorno está listo. La ejecución real
#   de comandos en chroot debe hacerse con: arch-chroot /mnt <comando>
################################################################################
configure_chroot() {
    # Verificar que /mnt está montado
    if ! mountpoint -q /mnt; then
        log_error "El directorio /mnt no está montado"
        return 1
    fi
    
    # Verificar que existe el sistema base instalado
    if [[ ! -f /mnt/etc/fstab ]]; then
        log_error "El archivo /mnt/etc/fstab no existe. Ejecute generate_fstab primero."
        return 1
    fi
    
    # Verificar que existe el comando arch-chroot
    if ! command -v arch-chroot &> /dev/null; then
        log_error "El comando arch-chroot no está disponible"
        return 1
    fi
    
    log "Entorno chroot preparado y listo para configuración"
    log "Use 'arch-chroot /mnt' para entrar al entorno chroot"
    
    return 0
}
