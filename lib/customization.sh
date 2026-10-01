#!/bin/bash

################################################################################
# Módulo de Personalización
#
# Este módulo contiene funciones para personalizar la apariencia y comportamiento
# del sistema, incluyendo ocultación de mensajes del sistema, instalación de
# cursor personalizado.
#
# Funciones:
# - hide_system_messages(): Oculta todos los mensajes del sistema
# - install_custom_cursor(): Instala cursor personalizado
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
    local theme_name="MiniArchPick"
    local png_source=""
    
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

    if [[ -d "$cursor_path" && -f "$cursor_path/guitar-pick-left.png" ]]; then
        png_source="$cursor_path/guitar-pick-left.png"
    elif [[ -f "$cursor_path" && "${cursor_path,,}" == *.png ]]; then
        png_source="$cursor_path"
    fi

    if [[ -n "$png_source" ]]; then
        if ! arch-chroot /mnt bash -lc 'command -v xcursorgen >/dev/null 2>&1'; then
            log_error "xcursorgen is not installed in target system"
            return 1
        fi

        if ! mkdir -p "/mnt/usr/share/icons/$theme_name/cursors" /mnt/tmp "$user_home/.icons/default"; then
            log_error "Failed to create cursor theme directories"
            return 1
        fi

        if ! cp "$png_source" /mnt/tmp/miniarch-pick-cursor.png; then
            log_error "Failed to copy cursor PNG"
            return 1
        fi

        cat > /mnt/tmp/miniarch-pick-cursor.cfg <<'EOF'
64 23 8 miniarch-pick-cursor.png
EOF

        if ! arch-chroot /mnt bash -lc \
            'cd /tmp && xcursorgen miniarch-pick-cursor.cfg /usr/share/icons/MiniArchPick/cursors/default' \
            >> "${LOG_FILE:-/dev/null}" 2>&1; then
            log_error "Failed to generate X11 cursor from PNG. Check ${LOG_FILE:-installer log} for xcursorgen details."
            return 1
        fi

        cp "/mnt/usr/share/icons/$theme_name/cursors/default" "/mnt/usr/share/icons/$theme_name/cursors/left_ptr"
        cp "/mnt/usr/share/icons/$theme_name/cursors/default" "/mnt/usr/share/icons/$theme_name/cursors/pointer"
        cp "/mnt/usr/share/icons/$theme_name/cursors/default" "/mnt/usr/share/icons/$theme_name/cursors/hand"

        cat > "/mnt/usr/share/icons/$theme_name/index.theme" <<EOF
[Icon Theme]
Name=$theme_name
Comment=MiniArch guitar pick cursor
Example=default
EOF

        cat > /mnt/usr/share/icons/default/index.theme <<EOF
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=$theme_name
EOF

        cat > "$user_home/.icons/default/index.theme" <<EOF
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=$theme_name
EOF

        rm -f /mnt/tmp/miniarch-pick-cursor.png /mnt/tmp/miniarch-pick-cursor.cfg
        arch-chroot /mnt chown -R "$username:$username" "/home/$username/.icons"

        log "Custom cursor theme generated from PNG"
        return 0
    fi
    
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

