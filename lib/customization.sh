#!/bin/bash

################################################################################
# Módulo de Personalización
#
# Este módulo contiene funciones para personalizar la apariencia y comportamiento
# del sistema, incluyendo ocultación de mensajes del sistema, instalación de
# cursor personalizado y aplicación de imagen de Plymouth.
#
# Funciones:
# - hide_system_messages(): Oculta todos los mensajes del sistema
# - install_custom_cursor(): Instala cursor personalizado
# - apply_plymouth_image(): Valida y copia imagen PNG para Plymouth
################################################################################

################################################################################
# hide_system_messages()
#
# Oculta todos los mensajes del sistema durante el inicio de sesión y arranque,
# incluyendo mensajes de login, MOTD, y mensajes de systemd.
#
# Arguments:
#   $1 - username: Nombre del usuario para el cual ocultar mensajes
#
# Returns:
#   0 - Si la configuración fue exitosa
#   1 - Si hubo algún error
################################################################################
hide_system_messages() {
    local username="$1"
    local user_home="/mnt/home/$username"
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided for hiding system messages"
        return 1
    fi
    
    log "Hiding system messages for user: $username"
    
    # Crear archivo .hushlogin para ocultar mensajes de login
    if ! touch "$user_home/.hushlogin"; then
        log_error "Failed to create .hushlogin file"
        return 1
    fi
    
    # Establecer permisos correctos para .hushlogin
    arch-chroot /mnt chown "$username:$username" "/home/$username/.hushlogin"
    
    # Vaciar o eliminar /etc/motd (Message Of The Day)
    if ! echo "" > /mnt/etc/motd; then
        log_error "Failed to clear /etc/motd"
        return 1
    fi
    
    # Configurar systemd para ocultar mensajes de servicios
    # Modificar /etc/systemd/system.conf
    if [[ ! -f /mnt/etc/systemd/system.conf ]]; then
        log_error "/etc/systemd/system.conf not found"
        return 1
    fi
    
    # Agregar o modificar ShowStatus=no en system.conf
    if grep -q "^#*ShowStatus=" /mnt/etc/systemd/system.conf; then
        sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' /mnt/etc/systemd/system.conf
    else
        echo "ShowStatus=no" >> /mnt/etc/systemd/system.conf
    fi
    
    # Configurar logind para deshabilitar VTs automáticos
    # Modificar /etc/systemd/logind.conf
    if [[ ! -f /mnt/etc/systemd/logind.conf ]]; then
        log_error "/etc/systemd/logind.conf not found"
        return 1
    fi
    
    # Agregar o modificar NAutoVTs=0 en logind.conf
    if grep -q "^#*NAutoVTs=" /mnt/etc/systemd/logind.conf; then
        sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' /mnt/etc/systemd/logind.conf
    else
        echo "NAutoVTs=0" >> /mnt/etc/systemd/logind.conf
    fi
    
    log "System messages hidden successfully"
    return 0
}

################################################################################
# install_custom_cursor()
#
# Instala un cursor personalizado en el sistema y lo configura como predeterminado
# para el usuario especificado.
#
# Arguments:
#   $1 - cursor_path: Ruta al directorio o archivo del cursor
#   $2 - username: Nombre del usuario para el cual configurar el cursor
#
# Returns:
#   0 - Si la instalación fue exitosa
#   1 - Si hubo algún error
################################################################################
install_custom_cursor() {
    local cursor_path="$1"
    local username="$2"
    local user_home="/mnt/home/$username"
    
    if [[ -z "$cursor_path" ]]; then
        log_error "Cursor path not provided"
        return 1
    fi
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided for cursor installation"
        return 1
    fi
    
    # Verificar que el cursor existe
    if [[ ! -e "$cursor_path" ]]; then
        log_error "Cursor path does not exist: $cursor_path"
        return 1
    fi
    
    log "Installing custom cursor from: $cursor_path"
    
    # Crear directorio de iconos del sistema si no existe
    if ! mkdir -p /mnt/usr/share/icons/default; then
        log_error "Failed to create system icons directory"
        return 1
    fi
    
    # Copiar el cursor al directorio de iconos del sistema
    if [[ -d "$cursor_path" ]]; then
        # Si es un directorio, copiar todo el contenido
        if ! cp -r "$cursor_path"/* /mnt/usr/share/icons/default/; then
            log_error "Failed to copy cursor directory"
            return 1
        fi
    else
        # Si es un archivo, copiarlo directamente
        if ! cp "$cursor_path" /mnt/usr/share/icons/default/; then
            log_error "Failed to copy cursor file"
            return 1
        fi
    fi
    
    # Crear archivo index.theme para el cursor predeterminado del sistema
    cat > /mnt/usr/share/icons/default/index.theme << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create system cursor index.theme"
        return 1
    fi
    
    # Crear directorio de iconos del usuario
    if ! mkdir -p "$user_home/.icons/default"; then
        log_error "Failed to create user icons directory"
        return 1
    fi
    
    # Crear archivo index.theme para el usuario
    cat > "$user_home/.icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create user cursor index.theme"
        return 1
    fi
    
    # Establecer permisos correctos
    arch-chroot /mnt chown -R "$username:$username" "/home/$username/.icons"
    
    log "Custom cursor installed successfully"
    return 0
}

################################################################################
# apply_plymouth_image()
#
# Valida que un archivo es una imagen PNG válida y la copia al directorio
# del tema de Plymouth. Si la imagen tiene dimensiones diferentes a 1280x720,
# la escala a esa resolución.
#
# Arguments:
#   $1 - image_path: Ruta a la imagen PNG
#   $2 - theme_name: Nombre del tema de Plymouth
#
# Returns:
#   0 - Si la imagen fue aplicada exitosamente
#   1 - Si hubo algún error
################################################################################
apply_plymouth_image() {
    local image_path="$1"
    local theme_name="$2"
    local theme_dir="/mnt/usr/share/plymouth/themes/$theme_name"
    
    if [[ -z "$image_path" ]]; then
        log_error "Image path not provided"
        return 1
    fi
    
    if [[ -z "$theme_name" ]]; then
        log_error "Theme name not provided"
        return 1
    fi
    
    # Verificar que la imagen existe
    if [[ ! -f "$image_path" ]]; then
        log_error "Image file does not exist: $image_path"
        return 1
    fi
    
    log "Applying Plymouth image: $image_path"
    
    # Validar que el archivo es un PNG válido usando el comando file
    local file_type
    file_type=$(file -b --mime-type "$image_path")
    
    if [[ "$file_type" != "image/png" ]]; then
        log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
        return 1
    fi
    
    log "PNG image validated successfully"
    
    # Verificar que el directorio del tema existe
    if [[ ! -d "$theme_dir" ]]; then
        log_error "Plymouth theme directory does not exist: $theme_dir"
        return 1
    fi
    
    # Obtener dimensiones de la imagen
    local image_info
    if command -v identify &> /dev/null; then
        image_info=$(identify -format "%wx%h" "$image_path" 2>/dev/null)
    else
        log "ImageMagick not available, skipping dimension check"
        image_info=""
    fi
    
    # Copiar y escalar la imagen si es necesario
    local target_image="$theme_dir/background.png"
    
    if [[ "$image_info" == "1280x720" ]]; then
        # La imagen ya tiene las dimensiones correctas, copiar directamente
        log "Image already has correct dimensions (1280x720), copying..."
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
    elif [[ -n "$image_info" ]]; then
        # La imagen tiene dimensiones diferentes, escalar a 1280x720
        log "Scaling image from $image_info to 1280x720..."
        
        # Intentar usar convert (ImageMagick) o magick
        if command -v convert &> /dev/null; then
            if ! convert "$image_path" -resize 1280x720! "$target_image"; then
                log_error "Failed to scale image using convert"
                return 1
            fi
        elif command -v magick &> /dev/null; then
            if ! magick "$image_path" -resize 1280x720! "$target_image"; then
                log_error "Failed to scale image using magick"
                return 1
            fi
        else
            log "ImageMagick not available, copying image without scaling"
            if ! cp "$image_path" "$target_image"; then
                log_error "Failed to copy image to theme directory"
                return 1
            fi
        fi
    else
        # No se pudo obtener información de dimensiones, copiar sin escalar
        log "Could not determine image dimensions, copying without scaling"
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
    fi
    
    log "Plymouth image applied successfully"
    return 0
}

################################################################################
# install_extra_scripts()
#
# Copia scripts adicionales útiles (como el de instalación de YARG) al directorio
# home del usuario kiosko y les da permisos de ejecución.
#
# Arguments:
#   $1 - username: Nombre del usuario para el cual instalar scripts
#
# Returns:
#   0 - Si la instalación fue exitosa
#   1 - Si hubo algún error
################################################################################
install_extra_scripts() {
    local username="$1"
    local user_home="/mnt/home/$username"
    local script_name="setup-yarg.sh"
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided for extra scripts installation"
        return 1
    fi
    
    log "Installing extra scripts for user: $username"
    
    # Lista de scripts a copiar
    local scripts=("setup-yarg.sh" "setup-retroarch.sh" "setup-web.sh")
    
    for script in "${scripts[@]}"; do
        if [[ -f "./$script" ]]; then
            log "Copying $script to $user_home"
            if cp "./$script" "$user_home/"; then
                chmod +x "$user_home/$script"
                arch-chroot /mnt chown "$username:$username" "/home/$username/$script"
            else
                log_error "Failed to copy $script"
            fi
        else
            log "Warning: $script not found, skipping"
        fi
    done
    
    return 0
}
