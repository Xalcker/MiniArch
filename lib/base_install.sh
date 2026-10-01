#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

################################################################################
# Módulo de Instalación Base
#
# Este módulo contiene la función que genera el fstab del sistema instalado
#
# Funciones:
# - generate_fstab(): Genera el archivo /etc/fstab con UUIDs
################################################################################

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
    if ! genfstab -U /mnt >> /mnt/etc/fstab 2>> "$LOG_FILE"; then
        log_error "Fallo al generar /etc/fstab"
        return 1
    fi
    
    log "Archivo /etc/fstab generado exitosamente"
    return 0
}

