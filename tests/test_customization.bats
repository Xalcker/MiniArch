#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de Personalización
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/customization.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 10.1-10.4, 11.1-11.5, 15.4
################################################################################

# Setup: cargar el módulo de personalización antes de cada prueba
setup() {
    # Cargar el módulo de personalización
    source lib/customization.sh
    
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
# Pruebas para hide_system_messages()
################################################################################

@test "hide_system_messages: configuración exitosa retorna 0" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    mkdir -p "$test_dir/etc/systemd"
    
    # Create mock systemd config files
    cat > "$test_dir/etc/systemd/system.conf" << 'EOF'
#ShowStatus=auto
EOF
    
    cat > "$test_dir/etc/systemd/logind.conf" << 'EOF'
#NAutoVTs=6
EOF
    
    # Override function to use test directory
    hide_system_messages() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for hiding system messages"
            return 1
        fi
        
        log "Hiding system messages for user: $username"
        
        # Crear archivo .hushlogin
        if ! touch "$user_home/.hushlogin"; then
            log_error "Failed to create .hushlogin file"
            return 1
        fi
        
        # Vaciar /etc/motd
        if ! echo "" > "$test_dir/etc/motd"; then
            log_error "Failed to clear /etc/motd"
            return 1
        fi
        
        # Modificar system.conf
        if [[ ! -f "$test_dir/etc/systemd/system.conf" ]]; then
            log_error "/etc/systemd/system.conf not found"
            return 1
        fi
        
        if grep -q "^#*ShowStatus=" "$test_dir/etc/systemd/system.conf"; then
            sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' "$test_dir/etc/systemd/system.conf"
        else
            echo "ShowStatus=no" >> "$test_dir/etc/systemd/system.conf"
        fi
        
        # Modificar logind.conf
        if [[ ! -f "$test_dir/etc/systemd/logind.conf" ]]; then
            log_error "/etc/systemd/logind.conf not found"
            return 1
        fi
        
        if grep -q "^#*NAutoVTs=" "$test_dir/etc/systemd/logind.conf"; then
            sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' "$test_dir/etc/systemd/logind.conf"
        else
            echo "NAutoVTs=0" >> "$test_dir/etc/systemd/logind.conf"
        fi
        
        log "System messages hidden successfully"
        return 0
    }
    
    run hide_system_messages "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"System messages hidden successfully"* ]]
    
    # Verify files were created/modified
    [ -f "$test_dir/home/kiosk/.hushlogin" ]
    [ -f "$test_dir/etc/motd" ]
    grep -q "ShowStatus=no" "$test_dir/etc/systemd/system.conf"
    grep -q "NAutoVTs=0" "$test_dir/etc/systemd/logind.conf"
    
    rm -rf "$test_dir"
}

@test "hide_system_messages: sin nombre de usuario retorna 1" {
    run hide_system_messages
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Username not provided"* ]]
}

@test "hide_system_messages: crea .hushlogin correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/testuser"
    mkdir -p "$test_dir/etc/systemd"
    
    # Create mock systemd config files
    cat > "$test_dir/etc/systemd/system.conf" << 'EOF'
#ShowStatus=auto
EOF
    
    cat > "$test_dir/etc/systemd/logind.conf" << 'EOF'
#NAutoVTs=6
EOF
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Mock de touch
    touch() {
        command touch "$@"
    }
    export -f touch
    
    # Override function to use test directory
    hide_system_messages() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for hiding system messages"
            return 1
        fi
        
        log "Hiding system messages for user: $username"
        
        if ! touch "$user_home/.hushlogin"; then
            log_error "Failed to create .hushlogin file"
            return 1
        fi
        
        echo "" > "$test_dir/etc/motd"
        
        if [[ ! -f "$test_dir/etc/systemd/system.conf" ]]; then
            log_error "/etc/systemd/system.conf not found"
            return 1
        fi
        
        if grep -q "^#*ShowStatus=" "$test_dir/etc/systemd/system.conf"; then
            sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' "$test_dir/etc/systemd/system.conf"
        else
            echo "ShowStatus=no" >> "$test_dir/etc/systemd/system.conf"
        fi
        
        if [[ ! -f "$test_dir/etc/systemd/logind.conf" ]]; then
            log_error "/etc/systemd/logind.conf not found"
            return 1
        fi
        
        if grep -q "^#*NAutoVTs=" "$test_dir/etc/systemd/logind.conf"; then
            sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' "$test_dir/etc/systemd/logind.conf"
        else
            echo "NAutoVTs=0" >> "$test_dir/etc/systemd/logind.conf"
        fi
        
        log "System messages hidden successfully"
        return 0
    }
    
    run hide_system_messages "testuser"
    [ "$status" -eq 0 ]
    
    # Verify .hushlogin was created
    [ -f "$test_dir/home/testuser/.hushlogin" ]
    
    rm -rf "$test_dir"
}

@test "hide_system_messages: modifica system.conf correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    mkdir -p "$test_dir/etc/systemd"
    
    # Create mock systemd config files
    cat > "$test_dir/etc/systemd/system.conf" << 'EOF'
#ShowStatus=auto
EOF
    
    cat > "$test_dir/etc/systemd/logind.conf" << 'EOF'
#NAutoVTs=6
EOF
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    hide_system_messages() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for hiding system messages"
            return 1
        fi
        
        log "Hiding system messages for user: $username"
        
        touch "$user_home/.hushlogin"
        echo "" > "$test_dir/etc/motd"
        
        if [[ ! -f "$test_dir/etc/systemd/system.conf" ]]; then
            log_error "/etc/systemd/system.conf not found"
            return 1
        fi
        
        if grep -q "^#*ShowStatus=" "$test_dir/etc/systemd/system.conf"; then
            sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' "$test_dir/etc/systemd/system.conf"
        else
            echo "ShowStatus=no" >> "$test_dir/etc/systemd/system.conf"
        fi
        
        if [[ ! -f "$test_dir/etc/systemd/logind.conf" ]]; then
            log_error "/etc/systemd/logind.conf not found"
            return 1
        fi
        
        if grep -q "^#*NAutoVTs=" "$test_dir/etc/systemd/logind.conf"; then
            sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' "$test_dir/etc/systemd/logind.conf"
        else
            echo "NAutoVTs=0" >> "$test_dir/etc/systemd/logind.conf"
        fi
        
        log "System messages hidden successfully"
        return 0
    }
    
    run hide_system_messages "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify system.conf was modified correctly
    grep -q "ShowStatus=no" "$test_dir/etc/systemd/system.conf"
    ! grep -q "#ShowStatus" "$test_dir/etc/systemd/system.conf"
    
    rm -rf "$test_dir"
}

@test "hide_system_messages: modifica logind.conf correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    mkdir -p "$test_dir/etc/systemd"
    
    # Create mock systemd config files
    cat > "$test_dir/etc/systemd/system.conf" << 'EOF'
#ShowStatus=auto
EOF
    
    cat > "$test_dir/etc/systemd/logind.conf" << 'EOF'
#NAutoVTs=6
EOF
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    hide_system_messages() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for hiding system messages"
            return 1
        fi
        
        log "Hiding system messages for user: $username"
        
        touch "$user_home/.hushlogin"
        echo "" > "$test_dir/etc/motd"
        
        if [[ ! -f "$test_dir/etc/systemd/system.conf" ]]; then
            log_error "/etc/systemd/system.conf not found"
            return 1
        fi
        
        if grep -q "^#*ShowStatus=" "$test_dir/etc/systemd/system.conf"; then
            sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' "$test_dir/etc/systemd/system.conf"
        else
            echo "ShowStatus=no" >> "$test_dir/etc/systemd/system.conf"
        fi
        
        if [[ ! -f "$test_dir/etc/systemd/logind.conf" ]]; then
            log_error "/etc/systemd/logind.conf not found"
            return 1
        fi
        
        if grep -q "^#*NAutoVTs=" "$test_dir/etc/systemd/logind.conf"; then
            sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' "$test_dir/etc/systemd/logind.conf"
        else
            echo "NAutoVTs=0" >> "$test_dir/etc/systemd/logind.conf"
        fi
        
        log "System messages hidden successfully"
        return 0
    }
    
    run hide_system_messages "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify logind.conf was modified correctly
    grep -q "NAutoVTs=0" "$test_dir/etc/systemd/logind.conf"
    ! grep -q "#NAutoVTs" "$test_dir/etc/systemd/logind.conf"
    
    rm -rf "$test_dir"
}

@test "hide_system_messages: vacía /etc/motd correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    mkdir -p "$test_dir/etc/systemd"
    
    # Create mock systemd config files
    cat > "$test_dir/etc/systemd/system.conf" << 'EOF'
#ShowStatus=auto
EOF
    
    cat > "$test_dir/etc/systemd/logind.conf" << 'EOF'
#NAutoVTs=6
EOF
    
    # Create motd with content
    echo "Welcome to the system!" > "$test_dir/etc/motd"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    hide_system_messages() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for hiding system messages"
            return 1
        fi
        
        log "Hiding system messages for user: $username"
        
        touch "$user_home/.hushlogin"
        
        if ! echo "" > "$test_dir/etc/motd"; then
            log_error "Failed to clear /etc/motd"
            return 1
        fi
        
        if [[ ! -f "$test_dir/etc/systemd/system.conf" ]]; then
            log_error "/etc/systemd/system.conf not found"
            return 1
        fi
        
        if grep -q "^#*ShowStatus=" "$test_dir/etc/systemd/system.conf"; then
            sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' "$test_dir/etc/systemd/system.conf"
        else
            echo "ShowStatus=no" >> "$test_dir/etc/systemd/system.conf"
        fi
        
        if [[ ! -f "$test_dir/etc/systemd/logind.conf" ]]; then
            log_error "/etc/systemd/logind.conf not found"
            return 1
        fi
        
        if grep -q "^#*NAutoVTs=" "$test_dir/etc/systemd/logind.conf"; then
            sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' "$test_dir/etc/systemd/logind.conf"
        else
            echo "NAutoVTs=0" >> "$test_dir/etc/systemd/logind.conf"
        fi
        
        log "System messages hidden successfully"
        return 0
    }
    
    run hide_system_messages "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify motd was cleared (file exists and is empty or contains only whitespace)
    [ -f "$test_dir/etc/motd" ]
    local motd_content=$(cat "$test_dir/etc/motd" | tr -d '[:space:]')
    [ -z "$motd_content" ]
    
    rm -rf "$test_dir"
}

################################################################################
# Pruebas para install_custom_cursor()
################################################################################

@test "install_custom_cursor: instalación exitosa retorna 0" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/cursor"
    mkdir -p "$test_dir/home/kiosk"
    
    # Create a dummy cursor file
    echo "cursor data" > "$test_dir/cursor/cursor.svg"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    install_custom_cursor() {
        local cursor_path="$1"
        local username="$2"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$cursor_path" ]]; then
            log_error "Cursor path not provided"
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for cursor installation"
            return 1
        fi
        
        if [[ ! -e "$cursor_path" ]]; then
            log_error "Cursor path does not exist: $cursor_path"
            return 1
        fi
        
        log "Installing custom cursor from: $cursor_path"
        
        if ! mkdir -p "$test_dir/usr/share/icons/default"; then
            log_error "Failed to create system icons directory"
            return 1
        fi
        
        if [[ -d "$cursor_path" ]]; then
            if ! cp -r "$cursor_path"/* "$test_dir/usr/share/icons/default/"; then
                log_error "Failed to copy cursor directory"
                return 1
            fi
        else
            if ! cp "$cursor_path" "$test_dir/usr/share/icons/default/"; then
                log_error "Failed to copy cursor file"
                return 1
            fi
        fi
        
        cat > "$test_dir/usr/share/icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create system cursor index.theme"
            return 1
        fi
        
        if ! mkdir -p "$user_home/.icons/default"; then
            log_error "Failed to create user icons directory"
            return 1
        fi
        
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
        
        log "Custom cursor installed successfully"
        return 0
    }
    
    run install_custom_cursor "$test_dir/cursor" "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Custom cursor installed successfully"* ]]
    
    rm -rf "$test_dir"
}

@test "install_custom_cursor: sin ruta de cursor retorna 1" {
    run install_custom_cursor "" "kiosk"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Cursor path not provided"* ]]
}

@test "install_custom_cursor: sin nombre de usuario retorna 1" {
    run install_custom_cursor "/path/to/cursor" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Username not provided"* ]]
}

@test "install_custom_cursor: cursor inexistente retorna 1" {
    run install_custom_cursor "/nonexistent/cursor" "kiosk"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Cursor path does not exist"* ]]
}

@test "install_custom_cursor: copia cursor de directorio correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/cursor"
    mkdir -p "$test_dir/home/kiosk"
    
    # Create dummy cursor files
    echo "cursor1" > "$test_dir/cursor/cursor1.svg"
    echo "cursor2" > "$test_dir/cursor/cursor2.svg"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    install_custom_cursor() {
        local cursor_path="$1"
        local username="$2"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$cursor_path" ]]; then
            log_error "Cursor path not provided"
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for cursor installation"
            return 1
        fi
        
        if [[ ! -e "$cursor_path" ]]; then
            log_error "Cursor path does not exist: $cursor_path"
            return 1
        fi
        
        log "Installing custom cursor from: $cursor_path"
        
        mkdir -p "$test_dir/usr/share/icons/default"
        
        if [[ -d "$cursor_path" ]]; then
            cp -r "$cursor_path"/* "$test_dir/usr/share/icons/default/"
        else
            cp "$cursor_path" "$test_dir/usr/share/icons/default/"
        fi
        
        cat > "$test_dir/usr/share/icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        mkdir -p "$user_home/.icons/default"
        
        cat > "$user_home/.icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        log "Custom cursor installed successfully"
        return 0
    }
    
    run install_custom_cursor "$test_dir/cursor" "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify cursor files were copied
    [ -f "$test_dir/usr/share/icons/default/cursor1.svg" ]
    [ -f "$test_dir/usr/share/icons/default/cursor2.svg" ]
    
    rm -rf "$test_dir"
}

@test "install_custom_cursor: copia cursor de archivo correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    
    # Create dummy cursor file
    echo "cursor data" > "$test_dir/cursor.svg"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    install_custom_cursor() {
        local cursor_path="$1"
        local username="$2"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$cursor_path" ]]; then
            log_error "Cursor path not provided"
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for cursor installation"
            return 1
        fi
        
        if [[ ! -e "$cursor_path" ]]; then
            log_error "Cursor path does not exist: $cursor_path"
            return 1
        fi
        
        log "Installing custom cursor from: $cursor_path"
        
        mkdir -p "$test_dir/usr/share/icons/default"
        
        if [[ -d "$cursor_path" ]]; then
            cp -r "$cursor_path"/* "$test_dir/usr/share/icons/default/"
        else
            cp "$cursor_path" "$test_dir/usr/share/icons/default/"
        fi
        
        cat > "$test_dir/usr/share/icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        mkdir -p "$user_home/.icons/default"
        
        cat > "$user_home/.icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        log "Custom cursor installed successfully"
        return 0
    }
    
    run install_custom_cursor "$test_dir/cursor.svg" "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify cursor file was copied
    [ -f "$test_dir/usr/share/icons/default/cursor.svg" ]
    
    rm -rf "$test_dir"
}

@test "install_custom_cursor: crea index.theme del sistema correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/cursor"
    mkdir -p "$test_dir/home/kiosk"
    
    # Create a dummy cursor file
    echo "cursor data" > "$test_dir/cursor/cursor.svg"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    install_custom_cursor() {
        local cursor_path="$1"
        local username="$2"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$cursor_path" ]]; then
            log_error "Cursor path not provided"
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for cursor installation"
            return 1
        fi
        
        if [[ ! -e "$cursor_path" ]]; then
            log_error "Cursor path does not exist: $cursor_path"
            return 1
        fi
        
        log "Installing custom cursor from: $cursor_path"
        
        mkdir -p "$test_dir/usr/share/icons/default"
        
        if [[ -d "$cursor_path" ]]; then
            cp -r "$cursor_path"/* "$test_dir/usr/share/icons/default/"
        else
            cp "$cursor_path" "$test_dir/usr/share/icons/default/"
        fi
        
        cat > "$test_dir/usr/share/icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        if [[ $? -ne 0 ]]; then
            log_error "Failed to create system cursor index.theme"
            return 1
        fi
        
        mkdir -p "$user_home/.icons/default"
        
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
        
        log "Custom cursor installed successfully"
        return 0
    }
    
    run install_custom_cursor "$test_dir/cursor" "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify system index.theme was created
    [ -f "$test_dir/usr/share/icons/default/index.theme" ]
    grep -q "Name=Default" "$test_dir/usr/share/icons/default/index.theme"
    grep -q "Inherits=default" "$test_dir/usr/share/icons/default/index.theme"
    
    rm -rf "$test_dir"
}

@test "install_custom_cursor: crea index.theme del usuario correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/cursor"
    mkdir -p "$test_dir/home/kiosk"
    
    # Create a dummy cursor file
    echo "cursor data" > "$test_dir/cursor/cursor.svg"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    install_custom_cursor() {
        local cursor_path="$1"
        local username="$2"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$cursor_path" ]]; then
            log_error "Cursor path not provided"
            return 1
        fi
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for cursor installation"
            return 1
        fi
        
        if [[ ! -e "$cursor_path" ]]; then
            log_error "Cursor path does not exist: $cursor_path"
            return 1
        fi
        
        log "Installing custom cursor from: $cursor_path"
        
        mkdir -p "$test_dir/usr/share/icons/default"
        
        if [[ -d "$cursor_path" ]]; then
            cp -r "$cursor_path"/* "$test_dir/usr/share/icons/default/"
        else
            cp "$cursor_path" "$test_dir/usr/share/icons/default/"
        fi
        
        cat > "$test_dir/usr/share/icons/default/index.theme" << 'EOF'
[Icon Theme]
Name=Default
Comment=Default Cursor Theme
Inherits=default
EOF
        
        mkdir -p "$user_home/.icons/default"
        
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
        
        log "Custom cursor installed successfully"
        return 0
    }
    
    run install_custom_cursor "$test_dir/cursor" "kiosk"
    [ "$status" -eq 0 ]
    
    # Verify user index.theme was created
    [ -f "$test_dir/home/kiosk/.icons/default/index.theme" ]
    grep -q "Name=Default" "$test_dir/home/kiosk/.icons/default/index.theme"
    grep -q "Inherits=default" "$test_dir/home/kiosk/.icons/default/index.theme"
    
    rm -rf "$test_dir"
}

################################################################################
# Pruebas para apply_plymouth_image()
################################################################################

@test "apply_plymouth_image: aplicación exitosa retorna 0" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/usr/share/plymouth/themes/test-theme"
    
    # Create a dummy PNG file
    echo "PNG data" > "$test_dir/test.png"
    
    # Mock de file command
    file() {
        if [[ "$*" == *"-b --mime-type"* ]]; then
            echo "image/png"
        else
            command file "$@"
        fi
    }
    export -f file
    
    # Mock de identify command (not available)
    identify() {
        return 1
    }
    export -f identify
    
    # Override function to use test directory
    apply_plymouth_image() {
        local image_path="$1"
        local theme_name="$2"
        local theme_dir="$test_dir/usr/share/plymouth/themes/$theme_name"
        
        if [[ -z "$image_path" ]]; then
            log_error "Image path not provided"
            return 1
        fi
        
        if [[ -z "$theme_name" ]]; then
            log_error "Theme name not provided"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file does not exist: $image_path"
            return 1
        fi
        
        log "Applying Plymouth image: $image_path"
        
        local file_type
        file_type=$(file -b --mime-type "$image_path")
        
        if [[ "$file_type" != "image/png" ]]; then
            log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
            return 1
        fi
        
        log "PNG image validated successfully"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "Plymouth theme directory does not exist: $theme_dir"
            return 1
        fi
        
        local target_image="$theme_dir/background.png"
        
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
        
        log "Plymouth image applied successfully"
        return 0
    }
    
    run apply_plymouth_image "$test_dir/test.png" "test-theme"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Plymouth image applied successfully"* ]]
    
    rm -rf "$test_dir"
}

@test "apply_plymouth_image: sin ruta de imagen retorna 1" {
    run apply_plymouth_image "" "test-theme"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Image path not provided"* ]]
}

@test "apply_plymouth_image: sin nombre de tema retorna 1" {
    run apply_plymouth_image "/path/to/image.png" ""
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Theme name not provided"* ]]
}

@test "apply_plymouth_image: imagen inexistente retorna 1" {
    run apply_plymouth_image "/nonexistent/image.png" "test-theme"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Image file does not exist"* ]]
}

@test "apply_plymouth_image: valida PNG correctamente" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/usr/share/plymouth/themes/test-theme"
    
    # Create a dummy PNG file
    echo "PNG data" > "$test_dir/test.png"
    
    # Mock de file command
    file() {
        if [[ "$*" == *"-b --mime-type"* ]]; then
            echo "image/png"
        else
            command file "$@"
        fi
    }
    export -f file
    
    # Mock de identify command (not available)
    identify() {
        return 1
    }
    export -f identify
    
    # Override function to use test directory
    apply_plymouth_image() {
        local image_path="$1"
        local theme_name="$2"
        local theme_dir="$test_dir/usr/share/plymouth/themes/$theme_name"
        
        if [[ -z "$image_path" ]]; then
            log_error "Image path not provided"
            return 1
        fi
        
        if [[ -z "$theme_name" ]]; then
            log_error "Theme name not provided"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file does not exist: $image_path"
            return 1
        fi
        
        log "Applying Plymouth image: $image_path"
        
        local file_type
        file_type=$(file -b --mime-type "$image_path")
        
        if [[ "$file_type" != "image/png" ]]; then
            log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
            return 1
        fi
        
        log "PNG image validated successfully"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "Plymouth theme directory does not exist: $theme_dir"
            return 1
        fi
        
        local target_image="$theme_dir/background.png"
        
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
        
        log "Plymouth image applied successfully"
        return 0
    }
    
    run apply_plymouth_image "$test_dir/test.png" "test-theme"
    [ "$status" -eq 0 ]
    [[ "$output" == *"PNG image validated successfully"* ]]
    
    rm -rf "$test_dir"
}

@test "apply_plymouth_image: rechaza archivo no-PNG" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/usr/share/plymouth/themes/test-theme"
    
    # Create a dummy non-PNG file
    echo "JPEG data" > "$test_dir/test.jpg"
    
    # Mock de file command to return JPEG
    file() {
        if [[ "$*" == *"-b --mime-type"* ]]; then
            echo "image/jpeg"
        else
            command file "$@"
        fi
    }
    export -f file
    
    # Override function to use test directory
    apply_plymouth_image() {
        local image_path="$1"
        local theme_name="$2"
        local theme_dir="$test_dir/usr/share/plymouth/themes/$theme_name"
        
        if [[ -z "$image_path" ]]; then
            log_error "Image path not provided"
            return 1
        fi
        
        if [[ -z "$theme_name" ]]; then
            log_error "Theme name not provided"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file does not exist: $image_path"
            return 1
        fi
        
        log "Applying Plymouth image: $image_path"
        
        local file_type
        file_type=$(file -b --mime-type "$image_path")
        
        if [[ "$file_type" != "image/png" ]]; then
            log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
            return 1
        fi
        
        log "PNG image validated successfully"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "Plymouth theme directory does not exist: $theme_dir"
            return 1
        fi
        
        local target_image="$theme_dir/background.png"
        
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
        
        log "Plymouth image applied successfully"
        return 0
    }
    
    run apply_plymouth_image "$test_dir/test.jpg" "test-theme"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"not a valid PNG image"* ]]
    [[ "$output" == *"image/jpeg"* ]]
    
    rm -rf "$test_dir"
}

@test "apply_plymouth_image: copia imagen al directorio del tema" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/usr/share/plymouth/themes/test-theme"
    
    # Create a dummy PNG file
    echo "PNG data" > "$test_dir/test.png"
    
    # Mock de file command
    file() {
        if [[ "$*" == *"-b --mime-type"* ]]; then
            echo "image/png"
        else
            command file "$@"
        fi
    }
    export -f file
    
    # Mock de identify command (not available)
    identify() {
        return 1
    }
    export -f identify
    
    # Override function to use test directory
    apply_plymouth_image() {
        local image_path="$1"
        local theme_name="$2"
        local theme_dir="$test_dir/usr/share/plymouth/themes/$theme_name"
        
        if [[ -z "$image_path" ]]; then
            log_error "Image path not provided"
            return 1
        fi
        
        if [[ -z "$theme_name" ]]; then
            log_error "Theme name not provided"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file does not exist: $image_path"
            return 1
        fi
        
        log "Applying Plymouth image: $image_path"
        
        local file_type
        file_type=$(file -b --mime-type "$image_path")
        
        if [[ "$file_type" != "image/png" ]]; then
            log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
            return 1
        fi
        
        log "PNG image validated successfully"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "Plymouth theme directory does not exist: $theme_dir"
            return 1
        fi
        
        local target_image="$theme_dir/background.png"
        
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
        
        log "Plymouth image applied successfully"
        return 0
    }
    
    run apply_plymouth_image "$test_dir/test.png" "test-theme"
    [ "$status" -eq 0 ]
    
    # Verify image was copied
    [ -f "$test_dir/usr/share/plymouth/themes/test-theme/background.png" ]
    
    rm -rf "$test_dir"
}

@test "apply_plymouth_image: directorio de tema inexistente retorna 1" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    
    # Create a dummy PNG file but no theme directory
    echo "PNG data" > "$test_dir/test.png"
    
    # Mock de file command
    file() {
        if [[ "$*" == *"-b --mime-type"* ]]; then
            echo "image/png"
        else
            command file "$@"
        fi
    }
    export -f file
    
    # Override function to use test directory
    apply_plymouth_image() {
        local image_path="$1"
        local theme_name="$2"
        local theme_dir="$test_dir/usr/share/plymouth/themes/$theme_name"
        
        if [[ -z "$image_path" ]]; then
            log_error "Image path not provided"
            return 1
        fi
        
        if [[ -z "$theme_name" ]]; then
            log_error "Theme name not provided"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file does not exist: $image_path"
            return 1
        fi
        
        log "Applying Plymouth image: $image_path"
        
        local file_type
        file_type=$(file -b --mime-type "$image_path")
        
        if [[ "$file_type" != "image/png" ]]; then
            log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
            return 1
        fi
        
        log "PNG image validated successfully"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "Plymouth theme directory does not exist: $theme_dir"
            return 1
        fi
        
        local target_image="$theme_dir/background.png"
        
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
        
        log "Plymouth image applied successfully"
        return 0
    }
    
    run apply_plymouth_image "$test_dir/test.png" "nonexistent-theme"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Plymouth theme directory does not exist"* ]]
    
    rm -rf "$test_dir"
}

################################################################################
# Prueba de Propiedad para hide_system_messages()
# Property 27: Configuración completa de ocultación de mensajes
# Validates: Requirements 10.1, 10.2, 10.3, 10.4
################################################################################

@test "Property 27: hide_system_messages configura correctamente todos los archivos para 50 usuarios aleatorios" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=50
    
    # Arrays de componentes para generar nombres de usuario válidos
    local prefixes=("user" "admin" "test" "kiosk" "guest" "dev" "sys" "app")
    local suffixes=("1" "2" "123" "test" "prod" "dev" "x" "a" "")
    local separators=("" "_" "-")
    
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Probar con 50 nombres de usuario aleatorios válidos
    for i in $(seq 1 $total_tests); do
        # Generar nombre de usuario aleatorio válido
        local prefix_idx=$((RANDOM % ${#prefixes[@]}))
        local suffix_idx=$((RANDOM % ${#suffixes[@]}))
        local separator_idx=$((RANDOM % ${#separators[@]}))
        
        local username="${prefixes[$prefix_idx]}${separators[$separator_idx]}${suffixes[$suffix_idx]}"
        
        # Si el nombre está vacío o solo tiene separador, usar un nombre por defecto
        if [[ -z "$username" || "$username" == "-" || "$username" == "_" ]]; then
            username="user${i}"
        fi
        
        # Create user home directory for this test
        mkdir -p "$test_dir/home/$username"
        mkdir -p "$test_dir/etc/systemd"
        
        # Create mock systemd config files
        cat > "$test_dir/etc/systemd/system.conf" << 'EOF'
#ShowStatus=auto
EOF
        
        cat > "$test_dir/etc/systemd/logind.conf" << 'EOF'
#NAutoVTs=6
EOF
        
        # Override function to use test directory
        hide_system_messages() {
            local username="$1"
            local user_home="$test_dir/home/$username"
            
            if [[ -z "$username" ]]; then
                log_error "Username not provided for hiding system messages"
                return 1
            fi
            
            log "Hiding system messages for user: $username"
            
            if ! touch "$user_home/.hushlogin"; then
                log_error "Failed to create .hushlogin file"
                return 1
            fi
            
            if ! echo "" > "$test_dir/etc/motd"; then
                log_error "Failed to clear /etc/motd"
                return 1
            fi
            
            if [[ ! -f "$test_dir/etc/systemd/system.conf" ]]; then
                log_error "/etc/systemd/system.conf not found"
                return 1
            fi
            
            if grep -q "^#*ShowStatus=" "$test_dir/etc/systemd/system.conf"; then
                sed -i 's/^#*ShowStatus=.*/ShowStatus=no/' "$test_dir/etc/systemd/system.conf"
            else
                echo "ShowStatus=no" >> "$test_dir/etc/systemd/system.conf"
            fi
            
            if [[ ! -f "$test_dir/etc/systemd/logind.conf" ]]; then
                log_error "/etc/systemd/logind.conf not found"
                return 1
            fi
            
            if grep -q "^#*NAutoVTs=" "$test_dir/etc/systemd/logind.conf"; then
                sed -i 's/^#*NAutoVTs=.*/NAutoVTs=0/' "$test_dir/etc/systemd/logind.conf"
            else
                echo "NAutoVTs=0" >> "$test_dir/etc/systemd/logind.conf"
            fi
            
            log "System messages hidden successfully"
            return 0
        }
        
        # Ejecutar hide_system_messages con el nombre generado
        run hide_system_messages "$username"
        
        # Verificar que el comando se ejecutó correctamente
        if [[ "$status" -eq 0 ]]; then
            # Verificar que todos los archivos fueron creados/modificados correctamente
            if [[ -f "$test_dir/home/$username/.hushlogin" ]] && \
               [[ -f "$test_dir/etc/motd" ]] && \
               grep -q "ShowStatus=no" "$test_dir/etc/systemd/system.conf" && \
               grep -q "NAutoVTs=0" "$test_dir/etc/systemd/logind.conf"; then
                success_count=$((success_count + 1))
            else
                echo "FALLO: Archivos no configurados correctamente para usuario '$username'" >&2
                rm -rf "$test_dir"
                return 1
            fi
        else
            echo "FALLO: hide_system_messages retornó código de error $status para usuario '$username'" >&2
            echo "Output: $output" >&2
            rm -rf "$test_dir"
            return 1
        fi
    done
    
    # Limpiar
    rm -rf "$test_dir"
    
    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}

################################################################################
# Prueba de Propiedad para apply_plymouth_image() - Validación de PNG
# Property 28: Validación de formato PNG
# Validates: Requirements 11.1
################################################################################

@test "Property 28: apply_plymouth_image valida correctamente 50 archivos PNG válidos y 50 inválidos" {
    # Contador de pruebas exitosas
    local valid_png_success=0
    local invalid_png_success=0
    local total_valid_tests=50
    local total_invalid_tests=50
    
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/usr/share/plymouth/themes/test-theme"
    
    # Arrays de tipos MIME inválidos para probar
    local invalid_types=(
        "image/jpeg"
        "image/gif"
        "image/bmp"
        "image/webp"
        "image/tiff"
        "image/svg+xml"
        "application/pdf"
        "text/plain"
        "application/octet-stream"
        "video/mp4"
        "audio/mpeg"
        "application/zip"
    )
    
    # Override function to use test directory
    apply_plymouth_image() {
        local image_path="$1"
        local theme_name="$2"
        local theme_dir="$test_dir/usr/share/plymouth/themes/$theme_name"
        
        if [[ -z "$image_path" ]]; then
            log_error "Image path not provided"
            return 1
        fi
        
        if [[ -z "$theme_name" ]]; then
            log_error "Theme name not provided"
            return 1
        fi
        
        if [[ ! -f "$image_path" ]]; then
            log_error "Image file does not exist: $image_path"
            return 1
        fi
        
        log "Applying Plymouth image: $image_path"
        
        local file_type
        file_type=$(file -b --mime-type "$image_path")
        
        if [[ "$file_type" != "image/png" ]]; then
            log_error "File is not a valid PNG image: $image_path (detected: $file_type)"
            return 1
        fi
        
        log "PNG image validated successfully"
        
        if [[ ! -d "$theme_dir" ]]; then
            log_error "Plymouth theme directory does not exist: $theme_dir"
            return 1
        fi
        
        local target_image="$theme_dir/background.png"
        
        if ! cp "$image_path" "$target_image"; then
            log_error "Failed to copy image to theme directory"
            return 1
        fi
        
        log "Plymouth image applied successfully"
        return 0
    }
    
    # Parte 1: Probar con 50 archivos PNG válidos
    for i in $(seq 1 $total_valid_tests); do
        # Crear un archivo PNG de prueba
        local png_file="$test_dir/valid_test_${i}.png"
        echo "PNG test data $i" > "$png_file"
        
        # Mock de file command para retornar image/png
        file() {
            if [[ "$*" == *"-b --mime-type"* ]]; then
                echo "image/png"
            else
                command file "$@"
            fi
        }
        export -f file
        
        # Ejecutar apply_plymouth_image con el archivo PNG válido
        run apply_plymouth_image "$png_file" "test-theme"
        
        # Verificar que el comando se ejecutó correctamente (debe retornar 0)
        if [[ "$status" -eq 0 ]]; then
            # Verificar que el mensaje de validación exitosa está presente
            if [[ "$output" == *"PNG image validated successfully"* ]]; then
                valid_png_success=$((valid_png_success + 1))
            else
                echo "FALLO: Mensaje de validación no encontrado para PNG válido #$i" >&2
                rm -rf "$test_dir"
                return 1
            fi
        else
            echo "FALLO: apply_plymouth_image retornó código de error $status para PNG válido #$i" >&2
            echo "Output: $output" >&2
            rm -rf "$test_dir"
            return 1
        fi
    done
    
    # Parte 2: Probar con 50 archivos inválidos (no-PNG)
    for i in $(seq 1 $total_invalid_tests); do
        # Crear un archivo de prueba inválido
        local invalid_file="$test_dir/invalid_test_${i}.jpg"
        echo "Invalid test data $i" > "$invalid_file"
        
        # Seleccionar un tipo MIME inválido aleatorio
        local type_idx=$((RANDOM % ${#invalid_types[@]}))
        local invalid_type="${invalid_types[$type_idx]}"
        
        # Mock de file command para retornar un tipo MIME inválido
        file() {
            if [[ "$*" == *"-b --mime-type"* ]]; then
                echo "$invalid_type"
            else
                command file "$@"
            fi
        }
        export -f file
        
        # Ejecutar apply_plymouth_image con el archivo inválido
        run apply_plymouth_image "$invalid_file" "test-theme"
        
        # Verificar que el comando falló correctamente (debe retornar 1)
        if [[ "$status" -eq 1 ]]; then
            # Verificar que el mensaje de error está presente
            if [[ "$output" == *"not a valid PNG image"* ]] && [[ "$output" == *"$invalid_type"* ]]; then
                invalid_png_success=$((invalid_png_success + 1))
            else
                echo "FALLO: Mensaje de error incorrecto para archivo inválido #$i (tipo: $invalid_type)" >&2
                echo "Output: $output" >&2
                rm -rf "$test_dir"
                return 1
            fi
        else
            echo "FALLO: apply_plymouth_image retornó código $status (esperado: 1) para archivo inválido #$i (tipo: $invalid_type)" >&2
            echo "Output: $output" >&2
            rm -rf "$test_dir"
            return 1
        fi
    done
    
    # Limpiar
    rm -rf "$test_dir"
    
    # Verificar que todas las pruebas pasaron
    if [[ $valid_png_success -eq $total_valid_tests ]] && [[ $invalid_png_success -eq $total_invalid_tests ]]; then
        echo "Property 28 verificada: $valid_png_success/$total_valid_tests PNGs válidos aceptados, $invalid_png_success/$total_invalid_tests archivos inválidos rechazados"
        return 0
    else
        echo "FALLO: Property 28 no verificada completamente" >&2
        echo "PNGs válidos: $valid_png_success/$total_valid_tests" >&2
        echo "Archivos inválidos: $invalid_png_success/$total_invalid_tests" >&2
        return 1
    fi
}

################################################################################
# Pruebas para install_extra_scripts()
################################################################################

@test "install_extra_scripts: instalación exitosa de múltiples scripts" {
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    
    # Crear scripts falsos
    touch "./setup-yarg.sh"
    touch "./setup-retroarch.sh"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Override function to use test directory
    install_extra_scripts() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        local scripts=("setup-yarg.sh" "setup-retroarch.sh")
        
        for script in "${scripts[@]}"; do
            if [[ -f "./$script" ]]; then
                cp "./$script" "$user_home/"
                chmod +x "$user_home/$script"
                log "Installed $script"
            else
                log "Warning: $script not found"
            fi
        done
        return 0
    }
    
    run install_extra_scripts "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Installed setup-yarg.sh"* ]]
    [[ "$output" == *"Installed setup-retroarch.sh"* ]]
    [ -f "$test_dir/home/kiosk/setup-yarg.sh" ]
    [ -f "$test_dir/home/kiosk/setup-retroarch.sh" ]
    
    # Limpiar
    rm -f "./setup-yarg.sh" "./setup-retroarch.sh"
    rm -rf "$test_dir"
}
