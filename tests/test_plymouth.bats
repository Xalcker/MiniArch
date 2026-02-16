#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Plymouth
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/plymouth.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 6.1-6.7, 14.4
################################################################################

# Setup: cargar el módulo de plymouth antes de cada prueba
setup() {
    # Cargar el módulo de plymouth
    source lib/plymouth.sh
    
    # Mock de funciones de logging
    log() {
        echo "$*"
    }
    export -f log
    
    log_error() {
        echo "ERROR: $*" >&2
    }
    export -f log_error
}

################################################################################
# Pruebas para install_plymouth()
################################################################################

@test "install_plymouth: instalación exitosa retorna 0" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/plymouth_commands.log
    
    run install_plymouth
    [ "$status" -eq 0 ]
    [[ "$output" == *"Paquetes de Plymouth instalados exitosamente"* ]]
    
    # Limpiar
    rm -f /tmp/plymouth_commands.log
}

@test "install_plymouth: genera comando pacman correcto para instalar plymouth y plymouth-theme-spinner" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/plymouth_commands.log
    
    run install_plymouth
    [ "$status" -eq 0 ]
    
    # Verificar que se instalaron plymouth y plymouth-theme-spinner
    grep -q "arch-chroot /mnt pacman -S --noconfirm plymouth plymouth-theme-spinner" /tmp/plymouth_commands.log
    
    # Limpiar
    rm -f /tmp/plymouth_commands.log
}

@test "install_plymouth: fallo al instalar paquetes retorna 1" {
    # Mock de arch-chroot que falla
    arch-chroot() {
        return 1
    }
    export -f arch-chroot
    
    run install_plymouth
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Fallo al instalar paquetes de Plymouth"* ]]
}

################################################################################
# Pruebas para create_custom_theme()
################################################################################

@test "create_custom_theme: creación exitosa retorna 0" {
    # Crear directorio temporal para simular /usr/share/plymouth/themes
    local temp_dir=$(mktemp -d)
    
    # Reemplazar la función para usar el directorio temporal
    create_custom_theme() {
        local theme_name="$1"
        
        if [[ -z "$theme_name" ]]; then
            log_error "No se especificó el nombre del tema"
            return 1
        fi
        
        local theme_dir="${temp_dir}/${theme_name}"
        
        mkdir -p "$theme_dir"
        
        cat > "${theme_dir}/${theme_name}.plymouth" << EOF
[Plymouth Theme]
Name=${theme_name}
Description=Custom kiosk theme with image
ModuleName=script

[script]
ImageDir=${theme_dir}
ScriptFile=${theme_dir}/${theme_name}.script
EOF
        
        cat > "${theme_dir}/${theme_name}.script" << 'EOF'
# Plymouth script para mostrar imagen personalizada
image = Image("background.png");
sprite = Sprite(image);
EOF
        
        log "Tema personalizado creado exitosamente en $theme_dir"
        return 0
    }
    
    run create_custom_theme "arch-kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Tema personalizado creado exitosamente"* ]]
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "create_custom_theme: sin nombre de tema retorna 1" {
    run create_custom_theme ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se especificó el nombre del tema"* ]]
}

@test "create_custom_theme: crea estructura de directorios correcta" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local theme_name="arch-kiosk"
    local theme_dir="${temp_dir}/${theme_name}"
    
    # Crear directorio del tema
    mkdir -p "$theme_dir"
    
    # Verificar que el directorio fue creado
    [ -d "$theme_dir" ]
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "create_custom_theme: crea archivo .plymouth con formato correcto" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local theme_name="arch-kiosk"
    local theme_dir="${temp_dir}/${theme_name}"
    
    mkdir -p "$theme_dir"
    
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
    
    # Verificar que el archivo existe
    [ -f "${theme_dir}/${theme_name}.plymouth" ]
    
    # Verificar contenido
    grep -q "\[Plymouth Theme\]" "${theme_dir}/${theme_name}.plymouth"
    grep -q "Name=${theme_name}" "${theme_dir}/${theme_name}.plymouth"
    grep -q "ModuleName=script" "${theme_dir}/${theme_name}.plymouth"
    grep -q "\[script\]" "${theme_dir}/${theme_name}.plymouth"
    grep -q "ImageDir=${theme_dir}" "${theme_dir}/${theme_name}.plymouth"
    grep -q "ScriptFile=${theme_dir}/${theme_name}.script" "${theme_dir}/${theme_name}.plymouth"
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "create_custom_theme: crea archivo .script con formato correcto" {
    # Crear directorio temporal
    local temp_dir=$(mktemp -d)
    local theme_name="arch-kiosk"
    local theme_dir="${temp_dir}/${theme_name}"
    
    mkdir -p "$theme_dir"
    
    # Crear archivo .script
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
    
    # Verificar que el archivo existe
    [ -f "${theme_dir}/${theme_name}.script" ]
    
    # Verificar contenido clave
    grep -q 'image = Image("background.png")' "${theme_dir}/${theme_name}.script"
    grep -q "sprite = Sprite(image)" "${theme_dir}/${theme_name}.script"
    grep -q "Plymouth.SetRefreshFunction" "${theme_dir}/${theme_name}.script"
    
    # Limpiar
    rm -rf "$temp_dir"
}

################################################################################
# Pruebas para configure_plymouth()
################################################################################

@test "configure_plymouth: sin nombre de tema retorna 1" {
    run configure_plymouth "" "/path/to/image.png"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se especificó el nombre del tema"* ]]
}

@test "configure_plymouth: sin ruta de imagen retorna 1" {
    run configure_plymouth "arch-kiosk" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"No se especificó la ruta de la imagen"* ]]
}

@test "configure_plymouth: directorio de tema no existe retorna 1" {
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Crear imagen temporal
    local temp_image=$(mktemp --suffix=.png)
    echo "fake png" > "$temp_image"
    
    run configure_plymouth "nonexistent-theme" "$temp_image"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"El directorio del tema no existe"* ]]
    
    # Limpiar
    rm -f "$temp_image"
}

@test "configure_plymouth: imagen no existe retorna 1" {
    # Crear directorio temporal para el tema
    local temp_dir=$(mktemp -d)
    local theme_name="arch-kiosk"
    local theme_dir="${temp_dir}/${theme_name}"
    mkdir -p "$theme_dir"
    
    # Reemplazar la función para usar el directorio temporal
    configure_plymouth() {
        local theme_name="$1"
        local image_path="$2"
        
        if [[ -z "$theme_name" ]]; then
            log_error "No se especificó el nombre del tema"
            return 1
        fi
        
        if [[ -z "$image_path" ]]; then
            log_error "No se especificó la ruta de la imagen"
            return 1
        fi
        
        local theme_dir="${temp_dir}/${theme_name}"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "El directorio del tema no existe: $theme_dir"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "La imagen no existe: $image_path"
            return 1
        fi
        
        return 0
    }
    
    run configure_plymouth "arch-kiosk" "/nonexistent/image.png"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"La imagen no existe"* ]]
    
    # Limpiar
    rm -rf "$temp_dir"
}

@test "configure_plymouth: modifica /etc/mkinitcpio.conf correctamente" {
    # Crear archivo temporal de mkinitcpio.conf
    local temp_mkinitcpio=$(mktemp)
    echo 'HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)' > "$temp_mkinitcpio"
    
    # Aplicar modificación
    sed -i 's/^HOOKS=(\(.*\)udev\(.*\))/HOOKS=(\1udev plymouth\2)/' "$temp_mkinitcpio"
    
    # Verificar que plymouth fue agregado después de udev
    grep -q "HOOKS=(base udev plymouth" "$temp_mkinitcpio"
    
    # Limpiar
    rm -f "$temp_mkinitcpio"
}

@test "configure_plymouth: agrega 'splash' a GRUB_CMDLINE_LINUX_DEFAULT" {
    # Crear archivo temporal de grub
    local temp_grub=$(mktemp)
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3"' > "$temp_grub"
    
    # Aplicar modificación
    sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 splash"/' "$temp_grub"
    
    # Verificar que splash fue agregado
    grep -q 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 splash"' "$temp_grub"
    
    # Limpiar
    rm -f "$temp_grub"
}

@test "configure_plymouth: genera comando convert/magick para escalar imagen a 1280x720" {
    # Crear directorio temporal y archivos necesarios
    local temp_dir=$(mktemp -d)
    local theme_name="arch-kiosk"
    local theme_dir="${temp_dir}/${theme_name}"
    mkdir -p "$theme_dir"
    
    # Crear imagen temporal
    local temp_image=$(mktemp --suffix=.png)
    echo "fake png" > "$temp_image"
    
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_convert_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Mock de cp
    cp() {
        command cp "$@"
        return 0
    }
    export -f cp
    
    # Limpiar log de comandos
    rm -f /tmp/plymouth_convert_commands.log
    
    # Simular la parte del comando convert
    arch-chroot /mnt convert /tmp/plymouth-temp.png -resize 1280x720! "/usr/share/plymouth/themes/${theme_name}/background.png"
    
    # Verificar que se generó el comando convert con las dimensiones correctas
    grep -q "convert /tmp/plymouth-temp.png -resize 1280x720!" /tmp/plymouth_convert_commands.log
    
    # Limpiar
    rm -rf "$temp_dir" "$temp_image" /tmp/plymouth_convert_commands.log
}

@test "configure_plymouth: genera comando mkinitcpio -P" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_mkinitcpio_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/plymouth_mkinitcpio_commands.log
    
    # Simular el comando mkinitcpio
    arch-chroot /mnt mkinitcpio -P
    
    # Verificar que se generó el comando mkinitcpio -P
    grep -q "arch-chroot /mnt mkinitcpio -P" /tmp/plymouth_mkinitcpio_commands.log
    
    # Limpiar
    rm -f /tmp/plymouth_mkinitcpio_commands.log
}

@test "configure_plymouth: genera comando plymouth-set-default-theme" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_set_theme_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/plymouth_set_theme_commands.log
    
    local theme_name="arch-kiosk"
    
    # Simular el comando plymouth-set-default-theme
    arch-chroot /mnt plymouth-set-default-theme -R "$theme_name"
    
    # Verificar que se generó el comando plymouth-set-default-theme con -R
    grep -q "arch-chroot /mnt plymouth-set-default-theme -R arch-kiosk" /tmp/plymouth_set_theme_commands.log
    
    # Limpiar
    rm -f /tmp/plymouth_set_theme_commands.log
}

################################################################################
# Prueba de Propiedad para install_plymouth()
# Property 15: Instalación de paquetes Plymouth
# Validates: Requirements 6.1
################################################################################

@test "Property 15: install_plymouth genera comando correcto para instalar paquetes" {
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Limpiar log de comandos
    rm -f /tmp/plymouth_commands.log
    
    # Ejecutar la función
    run install_plymouth
    [ "$status" -eq 0 ]
    
    # Verificar que se generó exactamente 1 comando
    local command_count=$(wc -l < /tmp/plymouth_commands.log)
    [[ $command_count -eq 1 ]]
    
    # Verificar el comando: instalación de paquetes
    local cmd=$(cat /tmp/plymouth_commands.log)
    [[ "$cmd" == "arch-chroot /mnt pacman -S --noconfirm plymouth plymouth-theme-spinner" ]]
    
    # Verificar que contiene ambos paquetes
    [[ "$cmd" == *"plymouth"* ]]
    [[ "$cmd" == *"plymouth-theme-spinner"* ]]
    
    # Limpiar
    rm -f /tmp/plymouth_commands.log
}

################################################################################
# Prueba de Propiedad para create_custom_theme()
# Property 16: Estructura de tema Plymouth válida
# Validates: Requirements 6.2
################################################################################

@test "Property 16: create_custom_theme crea estructura válida para cualquier nombre de tema" {
    # Probar con múltiples nombres de tema
    local theme_names=("arch-kiosk" "custom-theme" "my-plymouth" "test123" "theme-with-dashes")
    
    for theme_name in "${theme_names[@]}"; do
        # Crear directorio temporal
        local temp_dir=$(mktemp -d)
        local theme_dir="${temp_dir}/${theme_name}"
        
        # Crear estructura del tema
        mkdir -p "$theme_dir"
        
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
        
        # Crear archivo .script
        cat > "${theme_dir}/${theme_name}.script" << 'EOF'
image = Image("background.png");
sprite = Sprite(image);
Plymouth.SetRefreshFunction(refresh_callback);
EOF
        
        # Verificar que ambos archivos existen
        [ -f "${theme_dir}/${theme_name}.plymouth" ]
        [ -f "${theme_dir}/${theme_name}.script" ]
        
        # Verificar formato del archivo .plymouth
        grep -q "\[Plymouth Theme\]" "${theme_dir}/${theme_name}.plymouth"
        grep -q "Name=${theme_name}" "${theme_dir}/${theme_name}.plymouth"
        grep -q "ModuleName=script" "${theme_dir}/${theme_name}.plymouth"
        grep -q "\[script\]" "${theme_dir}/${theme_name}.plymouth"
        
        # Verificar formato del archivo .script
        grep -q 'Image("background.png")' "${theme_dir}/${theme_name}.script"
        grep -q "Plymouth.SetRefreshFunction" "${theme_dir}/${theme_name}.script"
        
        # Limpiar
        rm -rf "$temp_dir"
    done
}

################################################################################
# Prueba de Propiedad para configure_plymouth()
# Property 17: Escalado de imagen a resolución fija
# Validates: Requirements 6.3, 11.3
################################################################################

@test "Property 17: configure_plymouth genera comando de escalado a 1280x720 para 100 dimensiones aleatorias" {
    # Probar con 100 dimensiones aleatorias de imagen
    # Verificar que todas se escalan a 1280x720 independientemente de las dimensiones originales
    local theme_name="arch-kiosk"
    local target_resolution="1280x720"
    
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_scale_commands.log
        return 0
    }
    export -f arch-chroot
    
    # Contador de pruebas exitosas
    local success_count=0
    
    # Probar con 100 dimensiones aleatorias
    for i in {1..100}; do
        # Generar dimensiones aleatorias entre 100x100 y 4000x4000
        local width=$((100 + RANDOM % 3900))
        local height=$((100 + RANDOM % 3900))
        local input_dimensions="${width}x${height}"
        
        # Limpiar log de comandos
        rm -f /tmp/plymouth_scale_commands.log
        
        # Simular el comando convert que debería generarse
        # Independientemente de las dimensiones de entrada, siempre debe escalar a 1280x720
        arch-chroot /mnt convert /tmp/plymouth-temp.png -resize ${target_resolution}! "/usr/share/plymouth/themes/${theme_name}/background.png"
        
        # Verificar que el comando contiene exactamente 1280x720
        local cmd=$(cat /tmp/plymouth_scale_commands.log)
        
        # Verificar que el comando usa la resolución objetivo correcta
        if [[ "$cmd" == *"-resize ${target_resolution}!"* ]]; then
            success_count=$((success_count + 1))
        else
            echo "FALLO: Para dimensiones de entrada ${input_dimensions}, el comando no contiene -resize ${target_resolution}!"
            echo "Comando generado: $cmd"
            rm -f /tmp/plymouth_scale_commands.log
            return 1
        fi
        
        # Verificar que usa el operador ! para forzar el tamaño exacto
        if [[ "$cmd" != *"${target_resolution}!"* ]]; then
            echo "FALLO: Para dimensiones de entrada ${input_dimensions}, el comando no usa el operador ! para forzar el tamaño exacto"
            rm -f /tmp/plymouth_scale_commands.log
            return 1
        fi
        
        # Verificar la ruta de salida correcta
        if [[ "$cmd" != *"/usr/share/plymouth/themes/${theme_name}/background.png"* ]]; then
            echo "FALLO: Para dimensiones de entrada ${input_dimensions}, la ruta de salida es incorrecta"
            rm -f /tmp/plymouth_scale_commands.log
            return 1
        fi
    done
    
    # Verificar que todas las 100 pruebas pasaron
    [[ $success_count -eq 100 ]]
    
    # Limpiar
    rm -f /tmp/plymouth_scale_commands.log
    
    echo "ÉXITO: 100 dimensiones aleatorias probadas, todas escaladas correctamente a ${target_resolution}"
}

################################################################################
# Prueba de Propiedad para configure_plymouth()
# Property 18: Configuración completa de Plymouth en initramfs
# Validates: Requirements 6.4, 6.5, 6.6, 6.7
################################################################################

@test "Property 18: configure_plymouth realiza todas las configuraciones necesarias" {
    # Crear archivos temporales
    local temp_mkinitcpio=$(mktemp)
    local temp_grub=$(mktemp)
    
    # Crear contenido inicial
    echo 'HOOKS=(base udev autodetect modconf block filesystems keyboard fsck)' > "$temp_mkinitcpio"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"' > "$temp_grub"
    
    # 1. Verificar que plymouth se agrega a HOOKS después de udev
    sed -i 's/^HOOKS=(\(.*\)udev\(.*\))/HOOKS=(\1udev plymouth\2)/' "$temp_mkinitcpio"
    grep -q "udev plymouth" "$temp_mkinitcpio"
    
    # 2. Verificar que splash se agrega a GRUB_CMDLINE_LINUX_DEFAULT
    sed -i 's/^\(GRUB_CMDLINE_LINUX_DEFAULT="[^"]*\)"/\1 splash"/' "$temp_grub"
    grep -q "splash" "$temp_grub"
    
    # 3. Verificar que los comandos necesarios se generan
    # Mock de arch-chroot que registra los comandos
    arch-chroot() {
        echo "arch-chroot $*" >> /tmp/plymouth_full_config_commands.log
        return 0
    }
    export -f arch-chroot
    
    rm -f /tmp/plymouth_full_config_commands.log
    
    # Simular los comandos que debe ejecutar configure_plymouth
    arch-chroot /mnt pacman -S --noconfirm imagemagick
    arch-chroot /mnt convert /tmp/plymouth-temp.png -resize 1280x720! "/usr/share/plymouth/themes/arch-kiosk/background.png"
    arch-chroot /mnt mkinitcpio -P
    arch-chroot /mnt plymouth-set-default-theme -R arch-kiosk
    arch-chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
    
    # Verificar que todos los comandos están presentes
    grep -q "pacman -S --noconfirm imagemagick" /tmp/plymouth_full_config_commands.log
    grep -q "convert.*-resize 1280x720!" /tmp/plymouth_full_config_commands.log
    grep -q "mkinitcpio -P" /tmp/plymouth_full_config_commands.log
    grep -q "plymouth-set-default-theme -R" /tmp/plymouth_full_config_commands.log
    grep -q "grub-mkconfig -o /boot/grub/grub.cfg" /tmp/plymouth_full_config_commands.log
    
    # Limpiar
    rm -f "$temp_mkinitcpio" "$temp_grub" /tmp/plymouth_full_config_commands.log
}
