#!/bin/bash

################################################################################
# Módulo de Plymouth
#
# Este módulo contiene funciones para instalar y configurar Plymouth, el
# sistema de arranque gráfico que muestra imágenes personalizadas durante
# el boot y shutdown, ocultando todos los mensajes del sistema.
#
# Funciones:
# - install_plymouth(): Instala paquetes de Plymouth
# - create_custom_theme(): Crea un tema personalizado de Plymouth
# - configure_plymouth(): Configura Plymouth en initramfs y GRUB
################################################################################

################################################################################
# install_plymouth()
#
# Instala los paquetes necesarios de Plymouth: plymouth y plymouth-theme-spinner.
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - Debe existir conexión de red activa
#
# Returns:
#   0 - Si la instalación fue exitosa
#   1 - Si hubo un error durante la instalación
################################################################################
install_plymouth() {
    log "Instalando paquetes de Plymouth"
    
    # Instalar plymouth y plymouth-theme-spinner
    if ! arch-chroot /mnt pacman -S --noconfirm plymouth plymouth-theme-spinner; then
        log_error "Fallo al instalar paquetes de Plymouth"
        return 1
    fi
    
    log "Paquetes de Plymouth instalados exitosamente"
    return 0
}

################################################################################
# create_custom_theme()
#
# Crea un tema personalizado de Plymouth que soporta imágenes PNG.
# Genera los archivos .plymouth y .script necesarios para el tema.
#
# Arguments:
#   $1 - Nombre del tema (ej: arch-kiosk)
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - Plymouth debe estar instalado
#
# Returns:
#   0 - Si el tema fue creado exitosamente
#   1 - Si hubo un error durante la creación
################################################################################
create_custom_theme() {
    local theme_name="$1"
    
    # Verificar que se proporcionó el nombre del tema
    if [[ -z "$theme_name" ]]; then
        log_error "No se especificó el nombre del tema"
        return 1
    fi
    
    local theme_dir="/usr/share/plymouth/themes/${theme_name}"
    
    log "Creando tema personalizado de Plymouth: $theme_name"
    
    # Crear directorio del tema
    if ! mkdir -p "$theme_dir"; then
        log_error "Fallo al crear directorio del tema: $theme_dir"
        return 1
    fi
    
    log "Generando archivo ${theme_name}.plymouth"
    
    # Crear archivo .plymouth
    cat > "${theme_dir}/${theme_name}.plymouth" << EOF
[Plymouth Theme]
Name=${theme_name}
Description=Custom kiosk theme with image
ModuleName=script

[script]
ImageDir=${theme_dir}
ScriptFile=${theme_dir}/${theme_name}.script
EOF
    
    if [[ ! -f "${theme_dir}/${theme_name}.plymouth" ]]; then
        log_error "Fallo al crear archivo ${theme_name}.plymouth"
        return 1
    fi
    
    log "Generando archivo ${theme_name}.script"
    
    # Crear archivo .script con soporte para imagen PNG
    cat > "${theme_dir}/${theme_name}.script" << 'EOF'
# Plymouth script para mostrar imagen personalizada

# Cargar la imagen
image = Image("background.png");
sprite = Sprite(image);

# Centrar la imagen en la pantalla
screen_width = Window.GetWidth();
screen_height = Window.GetHeight();
image_width = image.GetWidth();
image_height = image.GetHeight();

sprite.SetX((screen_width - image_width) / 2);
sprite.SetY((screen_height - image_height) / 2);

# Función de actualización (requerida por Plymouth)
fun refresh_callback() {
    # No se necesita actualización para imagen estática
}

Plymouth.SetRefreshFunction(refresh_callback);
EOF
    
    if [[ ! -f "${theme_dir}/${theme_name}.script" ]]; then
        log_error "Fallo al crear archivo ${theme_name}.script"
        return 1
    fi
    
    log "Tema personalizado creado exitosamente en $theme_dir"
    return 0
}

################################################################################
# configure_plymouth()
#
# Configura Plymouth para usar el tema personalizado:
# - Copia y escala la imagen proporcionada a 1280x720
# - Actualiza /etc/mkinitcpio.conf para agregar el hook de Plymouth
# - Regenera el initramfs
# - Activa el tema personalizado
# - Actualiza GRUB para agregar "splash" al kernel
#
# Arguments:
#   $1 - Nombre del tema (ej: arch-kiosk)
#   $2 - Ruta de la imagen PNG proporcionada por el usuario
#
# Precondiciones:
#   - Debe ejecutarse dentro de arch-chroot
#   - Plymouth debe estar instalado
#   - El tema personalizado debe estar creado
#   - ImageMagick debe estar instalado para escalado de imagen
#
# Returns:
#   0 - Si la configuración fue exitosa
#   1 - Si hubo un error durante la configuración
################################################################################
configure_plymouth() {
    local theme_name="$1"
    local image_path="$2"
    
    # Verificar argumentos
    if [[ -z "$theme_name" ]]; then
        log_error "No se especificó el nombre del tema"
        return 1
    fi
    
    if [[ -z "$image_path" ]]; then
        log_error "No se especificó la ruta de la imagen"
        return 1
    fi
    
    local theme_dir="/usr/share/plymouth/themes/${theme_name}"
    
    # Verificar que el directorio del tema existe
    if [[ ! -d "$theme_dir" ]]; then
        log_error "El directorio del tema no existe: $theme_dir"
        return 1
    fi
    
    # Verificar que la imagen existe
    if [[ ! -f "$image_path" ]]; then
        log_error "La imagen no existe: $image_path"
        return 1
    fi
    
    log "Instalando ImageMagick para escalado de imagen"
    
    # Instalar ImageMagick para escalado
    if ! arch-chroot /mnt pacman -S --noconfirm imagemagick; then
        log_error "Fallo al instalar ImageMagick"
        return 1
    fi
    
    log "Copiando imagen al sistema instalado"
    
    # Copiar la imagen al directorio temporal en el chroot
    local temp_image="/mnt/tmp/plymouth-temp.png"
    if ! cp "$image_path" "$temp_image"; then
        log_error "Fallo al copiar imagen al sistema instalado"
        return 1
    fi
    
    log "Escalando imagen a 1280x720"
    
    # Escalar la imagen a 1280x720 y copiarla al directorio del tema
    if ! arch-chroot /mnt convert /tmp/plymouth-temp.png -resize 1280x720! "/usr/share/plymouth/themes/${theme_name}/background.png"; then
        log_error "Fallo al escalar y copiar la imagen"
        # Limpiar archivo temporal
        rm -f "$temp_image"
        return 1
    fi
    
    # Limpiar archivo temporal
    rm -f "$temp_image"
    
    log "Actualizando /etc/mkinitcpio.conf para habilitar KMS y Plymouth"
    
    # Backup del archivo original
    cp /mnt/etc/mkinitcpio.conf /mnt/etc/mkinitcpio.conf.backup
    
    # Habilitar KMS (Kernel Mode Setting) agregando drivers de video a MODULES
    # Esto es crucial para que Plymouth se muestre temprano en Proxmox y otros entornos
    sed -i 's/^MODULES=(\(.*\))/MODULES=(\1 i915 amdgpu nouveau virtio_gpu qxl bochs_drm)/' /mnt/etc/mkinitcpio.conf
    
    # Agregar plymouth hook después de udev de forma más robusta
    if grep -q "plymouth" /mnt/etc/mkinitcpio.conf; then
        log "El hook de Plymouth ya está presente en mkinitcpio.conf"
    else
        # Intentar insertar después de udev
        sed -i 's/\budev\b/& plymouth/' /mnt/etc/mkinitcpio.conf
    fi
    
    log "Regenerando initramfs con mkinitcpio"
    
    # Regenerar initramfs
    if ! arch-chroot /mnt mkinitcpio -P; then
        log_error "Fallo al regenerar initramfs"
        return 1
    fi
    
    log "Activando tema de Plymouth: $theme_name"
    
    # Activar el tema personalizado
    if ! arch-chroot /mnt plymouth-set-default-theme -R "$theme_name"; then
        log_error "Fallo al activar tema de Plymouth"
        return 1
    fi
    
    log "Actualizando GRUB para agregar 'splash' al kernel"
    
    local grub_config="/mnt/etc/default/grub"
    
    # Verificar que existe el archivo de configuración de GRUB
    if [[ ! -f "$grub_config" ]]; then
        log_error "El archivo $grub_config no existe"
        return 1
    fi
    
    # Agregar "splash" si no está presente
    if ! grep -q "splash" "$grub_config"; then
        sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 splash"/' "$grub_config"
    fi
    
    log "Regenerando configuración de GRUB"
    
    # Regenerar configuración de GRUB
    if ! arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg; then
        log_error "Fallo al regenerar configuración de GRUB"
        return 1
    fi
    
    log "Plymouth configurado exitosamente"
    return 0
}
