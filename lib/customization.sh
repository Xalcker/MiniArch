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
        log_error "No se indicó el nombre de usuario para ocultar los mensajes del sistema"
        return 1
    fi
    
    log "Ocultando mensajes del sistema para el usuario: $username"
    
    # Crear archivo .hushlogin para ocultar mensajes de login
    if ! touch "$user_home/.hushlogin"; then
        log_error "Fallo al crear el archivo .hushlogin"
        return 1
    fi
    
    # Establecer permisos correctos para .hushlogin
    arch-chroot /mnt chown "$username:$username" "/home/$username/.hushlogin"
    
    # Vaciar o eliminar /etc/motd (Message Of The Day)
    if ! echo "" > /mnt/etc/motd; then
        log_error "Fallo al vaciar /etc/motd"
        return 1
    fi
    
    # Configurar systemd para ocultar mensajes de servicios
    # Modificar /etc/systemd/system.conf
    if [[ ! -f /mnt/etc/systemd/system.conf ]]; then
        log_error "No se encontró /etc/systemd/system.conf"
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
        log_error "No se encontró /etc/systemd/logind.conf"
        return 1
    fi
    
    # Agregar o modificar NAutoVTs=0 en logind.conf
    if grep -q "^#*NAutoVTs=" /mnt/etc/systemd/logind.conf; then
        sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' /mnt/etc/systemd/logind.conf
    else
        echo "NAutoVTs=0" >> /mnt/etc/systemd/logind.conf
    fi
    
    log "Mensajes del sistema ocultados exitosamente"
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
        log_error "No se indicó la ruta del cursor"
        return 1
    fi
    
    if [[ -z "$username" ]]; then
        log_error "No se indicó el nombre de usuario para instalar el cursor"
        return 1
    fi
    
    # Verificar que el cursor existe
    if [[ ! -e "$cursor_path" ]]; then
        log_error "La ruta del cursor no existe: $cursor_path"
        return 1
    fi
    
    log "Instalando cursor personalizado desde: $cursor_path"

    if [[ -d "$cursor_path" && -f "$cursor_path/guitar-pick-left.png" ]]; then
        png_source="$cursor_path/guitar-pick-left.png"
    elif [[ -f "$cursor_path" && "${cursor_path,,}" == *.png ]]; then
        png_source="$cursor_path"
    fi

    if [[ -n "$png_source" ]]; then
        if ! arch-chroot /mnt bash -lc 'command -v xcursorgen >/dev/null 2>&1'; then
            log_error "xcursorgen no está instalado en el sistema destino"
            return 1
        fi

        if ! mkdir -p "/mnt/usr/share/icons/$theme_name/cursors" /mnt/var/tmp "$user_home/.icons/default"; then
            log_error "Fallo al crear los directorios del tema de cursor"
            return 1
        fi

        if ! cp "$png_source" /mnt/var/tmp/miniarch-pick-cursor.png; then
            log_error "Fallo al copiar el PNG del cursor"
            return 1
        fi

        cat > /mnt/var/tmp/miniarch-pick-cursor.cfg <<'EOF'
64 23 8 miniarch-pick-cursor.png
EOF

        if ! arch-chroot /mnt bash -lc \
            'cd /var/tmp && xcursorgen miniarch-pick-cursor.cfg /usr/share/icons/MiniArchPick/cursors/default' \
            >> "${LOG_FILE:-/dev/null}" 2>&1; then
            log_error "Fallo al generar el cursor X11 desde el PNG. Revisa ${LOG_FILE:-el log del instalador} para ver los detalles de xcursorgen."
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

        rm -f /mnt/var/tmp/miniarch-pick-cursor.png /mnt/var/tmp/miniarch-pick-cursor.cfg
        arch-chroot /mnt chown -R "$username:$username" "/home/$username/.icons"

        log "Tema de cursor personalizado generado desde el PNG"
        return 0
    fi
    
    # Crear directorio de iconos del sistema si no existe
    if ! mkdir -p /mnt/usr/share/icons/default; then
        log_error "Fallo al crear el directorio de iconos del sistema"
        return 1
    fi
    
    # Copiar el cursor al directorio de iconos del sistema
    if [[ -d "$cursor_path" ]]; then
        # Si es un directorio, copiar todo el contenido
        if ! cp -r "$cursor_path"/* /mnt/usr/share/icons/default/; then
            log_error "Fallo al copiar el directorio del cursor"
            return 1
        fi
    else
        # Si es un archivo, copiarlo directamente
        if ! cp "$cursor_path" /mnt/usr/share/icons/default/; then
            log_error "Fallo al copiar el archivo del cursor"
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
        log_error "Fallo al crear el index.theme del cursor del sistema"
        return 1
    fi
    
    # Crear directorio de iconos del usuario
    if ! mkdir -p "$user_home/.icons/default"; then
        log_error "Fallo al crear el directorio de iconos del usuario"
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
        log_error "Fallo al crear el index.theme del cursor del usuario"
        return 1
    fi
    
    # Establecer permisos correctos
    arch-chroot /mnt chown -R "$username:$username" "/home/$username/.icons"
    
    log "Cursor personalizado instalado exitosamente"
    return 0
}

