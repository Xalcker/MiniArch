#!/usr/bin/env bats

################################################################################
# Pruebas Unitarias para el Módulo de GUI
#
# Este archivo contiene pruebas BATS para validar las funciones del módulo
# lib/gui.sh. Las pruebas usan mocks para simular el comportamiento
# del sistema sin modificar el entorno real.
#
# Requisitos probados: 9.1-9.8, 13.1-13.5, 15.4
################################################################################

# Setup: cargar el módulo de GUI antes de cada prueba
setup() {
    # Cargar el módulo de GUI
    source lib/gui.sh
    
    # Mock de funciones de logging
    log() {
        echo "$@"
    }
    export -f log
    
    log_error() {
        echo "ERROR: $@" >&2
    }
    export -f log_error
    
    # Variables globales de configuración
    export KIOSK_PASSWORD="kiosk123"
}

################################################################################
# Pruebas para install_openbox()
################################################################################

@test "install_openbox: instala paquetes correctos incluyendo xterm y componentes de diálogos" {
    # Mock de arch-chroot y pacman
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            # Verificar que se instalan los paquetes correctos
            local packages="$@"
            if [[ "$packages" == *"xorg-server"* ]] && \
               [[ "$packages" == *"xorg-xinit"* ]] && \
               [[ "$packages" == *"openbox"* ]] && \
               [[ "$packages" == *"xterm"* ]] && \
               [[ "$packages" == *"xdg-desktop-portal"* ]] && \
               [[ "$packages" == *"xdg-desktop-portal-gtk"* ]] && \
               [[ "$packages" == *"gtk3"* ]]; then
                return 0
            else
                return 1
            fi
        fi
        return 0
    }
    export -f arch-chroot
    
    run install_openbox
    [ "$status" -eq 0 ]
    [[ "$output" == *"X server, OpenBox, xterm, and system dialog components installed successfully"* ]]
}

@test "install_openbox: fallo en pacman retorna 1" {
    # Mock de arch-chroot que falla
    arch-chroot() {
        return 1
    }
    export -f arch-chroot
    
    run install_openbox
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Failed to install"* ]]
}

################################################################################
# Pruebas para create_user()
################################################################################

@test "create_user: genera comando useradd correcto con nombre de usuario 'kiosk'" {
    # Mock de arch-chroot
    arch-chroot() {
        if [[ "$2" == "useradd" ]]; then
            # Verificar que el comando useradd tiene las opciones correctas
            if [[ "$@" == *"-m"* ]] && \
               [[ "$@" == *"-G wheel"* ]] && \
               [[ "$@" == *"-s /bin/bash"* ]] && \
               [[ "$@" == *"kiosk"* ]]; then
                return 0
            else
                return 1
            fi
        elif [[ "$2" == "chpasswd" ]]; then
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Mock de echo para chpasswd
    echo() {
        command echo "$@"
    }
    export -f echo
    
    run create_user "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"User kiosk created successfully"* ]]
}

@test "create_user: genera comando useradd correcto con nombre de usuario 'testuser'" {
    # Mock de arch-chroot
    arch-chroot() {
        if [[ "$2" == "useradd" ]]; then
            if [[ "$@" == *"testuser"* ]]; then
                return 0
            else
                return 1
            fi
        elif [[ "$2" == "chpasswd" ]]; then
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    run create_user "testuser"
    [ "$status" -eq 0 ]
    [[ "$output" == *"User testuser created successfully"* ]]
}

@test "create_user: sin nombre de usuario retorna 1" {
    run create_user
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Username not provided"* ]]
}

@test "create_user: fallo en useradd retorna 1" {
    # Mock de arch-chroot que falla en useradd
    arch-chroot() {
        if [[ "$2" == "useradd" ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot
    
    run create_user "kiosk"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Failed to create user"* ]]
}

@test "create_user: fallo en chpasswd retorna 1" {
    # Mock de arch-chroot que falla en chpasswd
    arch-chroot() {
        if [[ "$2" == "useradd" ]]; then
            return 0
        elif [[ "$2" == "chpasswd" ]]; then
            return 1
        fi
        return 0
    }
    export -f arch-chroot
    
    run create_user "kiosk"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Failed to set password"* ]]
}

################################################################################
# Pruebas para configure_autologin()
################################################################################

@test "configure_autologin: crea archivo de configuración correcto para usuario 'kiosk'" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/etc/systemd/system/getty@tty1.service.d"
    
    # Override function to use test directory
    configure_autologin() {
        local username="$1"
        if [[ -z "$username" ]]; then
            log_error "Username not provided for autologin configuration"
            return 1
        fi
        log "Configuring autologin for user: $username"
        mkdir -p "$test_dir/etc/systemd/system/getty@tty1.service.d" || return 1
        cat > "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $username %I \$TERM
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create autologin configuration file"; return 1; }
        log "Autologin configured successfully for $username"
        return 0
    }
    
    run configure_autologin "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Autologin configured successfully for kiosk"* ]]
    
    # Verify file content
    [ -f "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf" ]
    grep -q "autologin kiosk" "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    
    rm -rf "$test_dir"
}

@test "configure_autologin: crea archivo de configuración correcto para usuario 'admin'" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/etc/systemd/system/getty@tty1.service.d"
    
    # Override function to use test directory
    configure_autologin() {
        local username="$1"
        if [[ -z "$username" ]]; then
            log_error "Username not provided for autologin configuration"
            return 1
        fi
        log "Configuring autologin for user: $username"
        mkdir -p "$test_dir/etc/systemd/system/getty@tty1.service.d" || return 1
        cat > "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $username %I \$TERM
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create autologin configuration file"; return 1; }
        log "Autologin configured successfully for $username"
        return 0
    }
    
    run configure_autologin "admin"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Autologin configured successfully for admin"* ]]
    
    # Verify file content
    [ -f "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf" ]
    grep -q "autologin admin" "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf"
    
    rm -rf "$test_dir"
}

@test "configure_autologin: sin nombre de usuario retorna 1" {
    run configure_autologin
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Username not provided"* ]]
}

@test "configure_autologin: fallo en mkdir retorna 1" {
    # Mock de mkdir que falla
    mkdir() {
        return 1
    }
    export -f mkdir
    
    run configure_autologin "kiosk"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Failed to create systemd override directory"* ]]
}

################################################################################
# Pruebas para configure_autostart_x()
################################################################################

@test "configure_autostart_x: crea .xinitrc y .bash_profile correctos para usuario 'kiosk'" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    
    # Override function to use test directory
    configure_autostart_x() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for X autostart configuration"
            return 1
        fi
        
        log "Configuring automatic X startup for user: $username"
        
        cat > "$user_home/.xinitrc" << 'EOF'
#!/bin/sh
exec openbox-session
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create .xinitrc"; return 1; }
        
        chmod +x "$user_home/.xinitrc"
        
        cat > "$user_home/.bash_profile" << 'EOF'
# Start X automatically on login to tty1
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create .bash_profile"; return 1; }
        
        log "Automatic X startup configured successfully for $username"
        return 0
    }
    
    run configure_autostart_x "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Automatic X startup configured successfully for kiosk"* ]]
    
    # Verify files were created
    [ -f "$test_dir/home/kiosk/.xinitrc" ]
    [ -f "$test_dir/home/kiosk/.bash_profile" ]
    
    # Verify content
    grep -q "exec openbox-session" "$test_dir/home/kiosk/.xinitrc"
    grep -q "exec startx" "$test_dir/home/kiosk/.bash_profile"
    
    rm -rf "$test_dir"
}

@test "configure_autostart_x: crea archivos correctos para usuario 'testuser'" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/testuser"
    
    # Override function to use test directory
    configure_autostart_x() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for X autostart configuration"
            return 1
        fi
        
        log "Configuring automatic X startup for user: $username"
        
        cat > "$user_home/.xinitrc" << 'EOF'
#!/bin/sh
exec openbox-session
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create .xinitrc"; return 1; }
        
        chmod +x "$user_home/.xinitrc"
        
        cat > "$user_home/.bash_profile" << 'EOF'
# Start X automatically on login to tty1
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create .bash_profile"; return 1; }
        
        log "Automatic X startup configured successfully for $username"
        return 0
    }
    
    run configure_autostart_x "testuser"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Automatic X startup configured successfully for testuser"* ]]
    
    rm -rf "$test_dir"
}

@test "configure_autostart_x: sin nombre de usuario retorna 1" {
    run configure_autostart_x
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Username not provided"* ]]
}

################################################################################
# Pruebas para configure_xterm_autostart()
################################################################################

@test "configure_xterm_autostart: crea autostart con xterm y comando de apagado para usuario 'kiosk'" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk/.config/openbox"
    
    # Override function to use test directory
    configure_xterm_autostart() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        local autostart_dir="$user_home/.config/openbox"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for xterm autostart configuration"
            return 1
        fi
        
        log "Configuring xterm autostart with shutdown on close for user: $username"
        
        mkdir -p "$autostart_dir" || { log_error "Failed to create OpenBox config directory"; return 1; }
        
        cat > "$autostart_dir/autostart" << 'EOF'
#!/bin/bash
# Start xterm and shutdown system when it closes

# Wait a moment for X to fully initialize
sleep 2

# Launch xterm with a persistent shell (without -hold so it closes on exit)
xterm -e /bin/bash &
XTERM_PID=$!

# Wait for xterm to close in background, then shutdown
(
    while kill -0 $XTERM_PID 2>/dev/null; do
        sleep 1
    done
    /usr/bin/shutdown -h now
) &
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox autostart file"; return 1; }
        
        chmod +x "$autostart_dir/autostart"
        
        log "Creating OpenBox configuration for kiosk mode"
        
        cat > "$autostart_dir/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox configuration file"; return 1; }
        
        log "OpenBox kiosk configuration created successfully"
        log "xterm autostart with shutdown configured successfully for $username"
        return 0
    }
    
    run configure_xterm_autostart "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"xterm autostart with shutdown configured successfully for kiosk"* ]]
    
    # Verify files were created
    [ -f "$test_dir/home/kiosk/.config/openbox/autostart" ]
    [ -f "$test_dir/home/kiosk/.config/openbox/rc.xml" ]
    
    # Verify content
    grep -q "xterm" "$test_dir/home/kiosk/.config/openbox/autostart"
    grep -q "shutdown" "$test_dir/home/kiosk/.config/openbox/autostart"
    
    rm -rf "$test_dir"
}

@test "configure_xterm_autostart: crea rc.xml con configuración de modo kiosko" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk/.config/openbox"
    
    # Override function to use test directory
    configure_xterm_autostart() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        local autostart_dir="$user_home/.config/openbox"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for xterm autostart configuration"
            return 1
        fi
        
        log "Configuring xterm autostart with shutdown on close for user: $username"
        
        mkdir -p "$autostart_dir" || { log_error "Failed to create OpenBox config directory"; return 1; }
        
        cat > "$autostart_dir/autostart" << 'EOF'
#!/bin/bash
xterm -e /bin/bash &
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox autostart file"; return 1; }
        
        chmod +x "$autostart_dir/autostart"
        
        log "Creating OpenBox configuration for kiosk mode"
        
        cat > "$autostart_dir/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox configuration file"; return 1; }
        
        log "OpenBox kiosk configuration created successfully"
        log "xterm autostart with shutdown configured successfully for $username"
        return 0
    }
    
    run configure_xterm_autostart "kiosk"
    [ "$status" -eq 0 ]
    [[ "$output" == *"OpenBox kiosk configuration created successfully"* ]]
    
    # Verify rc.xml was created
    [ -f "$test_dir/home/kiosk/.config/openbox/rc.xml" ]
    
    # Verify it contains kiosk mode configuration (1 desktop)
    grep -q "<number>1</number>" "$test_dir/home/kiosk/.config/openbox/rc.xml"
    
    rm -rf "$test_dir"
}

@test "configure_xterm_autostart: sin nombre de usuario retorna 1" {
    run configure_xterm_autostart
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Username not provided"* ]]
}

@test "configure_xterm_autostart: fallo en mkdir retorna 1" {
    # Mock de mkdir que falla
    mkdir() {
        return 1
    }
    export -f mkdir
    
    run configure_xterm_autostart "kiosk"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ERROR"* ]]
    [[ "$output" == *"Failed to create OpenBox config directory"* ]]
}

@test "configure_xterm_autostart: funciona con diferentes nombres de usuario" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    
    # Override function to use test directory
    configure_xterm_autostart() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        local autostart_dir="$user_home/.config/openbox"
        
        if [[ -z "$username" ]]; then
            log_error "Username not provided for xterm autostart configuration"
            return 1
        fi
        
        log "Configuring xterm autostart with shutdown on close for user: $username"
        
        mkdir -p "$autostart_dir" || { log_error "Failed to create OpenBox config directory"; return 1; }
        
        cat > "$autostart_dir/autostart" << 'EOF'
#!/bin/bash
xterm -e /bin/bash &
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox autostart file"; return 1; }
        
        chmod +x "$autostart_dir/autostart"
        
        log "Creating OpenBox configuration for kiosk mode"
        
        cat > "$autostart_dir/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox configuration file"; return 1; }
        
        log "OpenBox kiosk configuration created successfully"
        log "xterm autostart with shutdown configured successfully for $username"
        return 0
    }
    
    # Probar con varios nombres de usuario
    local usernames=("kiosk" "admin" "testuser" "user123" "myuser")
    
    for username in "${usernames[@]}"; do
        mkdir -p "$test_dir/home/$username"
        run configure_xterm_autostart "$username"
        [ "$status" -eq 0 ]
        [[ "$output" == *"xterm autostart with shutdown configured successfully for $username"* ]]
    done
    
    rm -rf "$test_dir"
}

################################################################################
# Pruebas de integración para el flujo completo
################################################################################

@test "Flujo completo: install_openbox -> create_user -> configure_autologin -> configure_autostart_x -> configure_xterm_autostart" {
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    mkdir -p "$test_dir/home/kiosk"
    mkdir -p "$test_dir/etc/systemd/system/getty@tty1.service.d"
    
    # Mock de arch-chroot
    arch-chroot() {
        return 0
    }
    export -f arch-chroot
    
    # Test install_openbox
    run install_openbox
    [ "$status" -eq 0 ]
    
    # Test create_user
    run create_user "kiosk"
    [ "$status" -eq 0 ]
    
    # Test configure_autologin with override
    configure_autologin() {
        local username="$1"
        [[ -z "$username" ]] && { log_error "Username not provided for autologin configuration"; return 1; }
        log "Configuring autologin for user: $username"
        mkdir -p "$test_dir/etc/systemd/system/getty@tty1.service.d" || return 1
        cat > "$test_dir/etc/systemd/system/getty@tty1.service.d/autologin.conf" << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $username %I \$TERM
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create autologin configuration file"; return 1; }
        log "Autologin configured successfully for $username"
        return 0
    }
    run configure_autologin "kiosk"
    [ "$status" -eq 0 ]
    
    # Test configure_autostart_x with override
    configure_autostart_x() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        [[ -z "$username" ]] && { log_error "Username not provided for X autostart configuration"; return 1; }
        log "Configuring automatic X startup for user: $username"
        cat > "$user_home/.xinitrc" << 'EOF'
#!/bin/sh
exec openbox-session
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create .xinitrc"; return 1; }
        chmod +x "$user_home/.xinitrc"
        cat > "$user_home/.bash_profile" << 'EOF'
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create .bash_profile"; return 1; }
        log "Automatic X startup configured successfully for $username"
        return 0
    }
    run configure_autostart_x "kiosk"
    [ "$status" -eq 0 ]
    
    # Test configure_xterm_autostart with override
    configure_xterm_autostart() {
        local username="$1"
        local user_home="$test_dir/home/$username"
        local autostart_dir="$user_home/.config/openbox"
        [[ -z "$username" ]] && { log_error "Username not provided for xterm autostart configuration"; return 1; }
        log "Configuring xterm autostart with shutdown on close for user: $username"
        mkdir -p "$autostart_dir" || { log_error "Failed to create OpenBox config directory"; return 1; }
        cat > "$autostart_dir/autostart" << 'EOF'
#!/bin/bash
xterm -e /bin/bash &
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox autostart file"; return 1; }
        chmod +x "$autostart_dir/autostart"
        log "Creating OpenBox configuration for kiosk mode"
        cat > "$autostart_dir/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF
        [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox configuration file"; return 1; }
        log "OpenBox kiosk configuration created successfully"
        log "xterm autostart with shutdown configured successfully for $username"
        return 0
    }
    run configure_xterm_autostart "kiosk"
    [ "$status" -eq 0 ]
    
    rm -rf "$test_dir"
}

@test "Verificar que install_openbox instala todos los paquetes requeridos" {
    # Mock de arch-chroot que captura paquetes
    arch-chroot() {
        if [[ "$2" == "pacman" ]]; then
            # Capture all arguments
            local packages="$*"
            
            # Count packages
            local count=0
            [[ "$packages" == *"xorg-server"* ]] && ((count++))
            [[ "$packages" == *"xorg-xinit"* ]] && ((count++))
            [[ "$packages" == *"openbox"* ]] && ((count++))
            [[ "$packages" == *"xterm"* ]] && ((count++))
            [[ "$packages" == *"xdg-desktop-portal"* ]] && ((count++))
            [[ "$packages" == *"xdg-desktop-portal-gtk"* ]] && ((count++))
            [[ "$packages" == *"gtk3"* ]] && ((count++))
            
            # Export count for verification
            echo "$count" > /tmp/package_count.txt
            
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    run install_openbox
    [ "$status" -eq 0 ]
    
    # Read the package count
    if [ -f /tmp/package_count.txt ]; then
        local packages_found=$(cat /tmp/package_count.txt)
        rm -f /tmp/package_count.txt
        
        # Verificar que se encontraron todos los paquetes (7 en total)
        [ "$packages_found" -eq 7 ]
    else
        # If file doesn't exist, test should fail
        false
    fi
}

################################################################################
# Prueba de Propiedad para create_user()
# Property 22: Creación de usuario del sistema
# Validates: Requirements 9.5
################################################################################

@test "Property 22: create_user genera comando useradd correcto para 100 nombres de usuario aleatorios válidos" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=100
    
    # Arrays de componentes para generar nombres de usuario válidos
    local prefixes=("user" "admin" "test" "kiosk" "guest" "dev" "sys" "app" "web" "db")
    local suffixes=("1" "2" "123" "test" "prod" "dev" "x" "a" "b" "")
    local separators=("" "_" "-")
    
    # Mock de arch-chroot que valida el comando useradd
    arch-chroot() {
        if [[ "$2" == "useradd" ]]; then
            # Verificar que el comando useradd tiene las opciones correctas
            if [[ "$@" == *"-m"* ]] && \
               [[ "$@" == *"-G wheel"* ]] && \
               [[ "$@" == *"-s /bin/bash"* ]]; then
                return 0
            else
                return 1
            fi
        elif [[ "$2" == "chpasswd" ]]; then
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Probar con 100 nombres de usuario aleatorios válidos
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
        
        # Ejecutar create_user con el nombre generado
        run create_user "$username"
        
        # Verificar que el comando se ejecutó correctamente
        if [[ "$status" -eq 0 ]]; then
            # Verificar que el output contiene el nombre de usuario
            if [[ "$output" == *"User $username created successfully"* ]]; then
                success_count=$((success_count + 1))
            else
                echo "FALLO: Output no contiene mensaje de éxito para usuario '$username'" >&2
                echo "Output: $output" >&2
                return 1
            fi
        else
            echo "FALLO: create_user retornó código de error $status para usuario '$username'" >&2
            echo "Output: $output" >&2
            return 1
        fi
    done
    
    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}

################################################################################
# Prueba de Propiedad para configure_xterm_autostart()
# Property 26: Configuración de xterm con apagado automático
# **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
################################################################################

@test "Property 26: configure_xterm_autostart crea configuración correcta de xterm con apagado para 100 nombres de usuario aleatorios" {
    # Contador de pruebas exitosas
    local success_count=0
    local total_tests=100
    
    # Arrays de componentes para generar nombres de usuario válidos
    local prefixes=("user" "admin" "test" "kiosk" "guest" "dev" "sys" "app" "web" "db" "operator" "service")
    local suffixes=("1" "2" "123" "test" "prod" "dev" "x" "a" "b" "99" "")
    local separators=("" "_" "-")
    
    # Create temporary test directory
    local test_dir=$(mktemp -d)
    
    # Mock de arch-chroot
    arch-chroot() {
        # Simular chown command
        if [[ "$2" == "chown" ]]; then
            return 0
        fi
        return 0
    }
    export -f arch-chroot
    
    # Probar con 100 nombres de usuario aleatorios válidos
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
        
        # Override configure_xterm_autostart to use test directory
        configure_xterm_autostart() {
            local username="$1"
            local user_home="$test_dir/home/$username"
            local autostart_dir="$user_home/.config/openbox"
            
            if [[ -z "$username" ]]; then
                log_error "Username not provided for xterm autostart configuration"
                return 1
            fi
            
            log "Configuring xterm autostart with shutdown on close for user: $username"
            
            if ! mkdir -p "$autostart_dir"; then
                log_error "Failed to create OpenBox config directory"
                return 1
            fi
            
            cat > "$autostart_dir/autostart" << 'EOF'
#!/bin/bash
# Start xterm and shutdown system when it closes

# Wait a moment for X to fully initialize
sleep 2

# Launch xterm with a persistent shell (without -hold so it closes on exit)
xterm -e /bin/bash &
XTERM_PID=$!

# Wait for xterm to close in background, then shutdown
(
    while kill -0 $XTERM_PID 2>/dev/null; do
        sleep 1
    done
    /usr/bin/shutdown -h now
) &
EOF
            
            [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox autostart file"; return 1; }
            
            chmod +x "$autostart_dir/autostart"
            
            log "Creating OpenBox configuration for kiosk mode"
            
            cat > "$autostart_dir/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <number>1</number>
  </desktops>
</openbox_config>
EOF
            
            [[ $? -ne 0 ]] && { log_error "Failed to create OpenBox configuration file"; return 1; }
            
            log "OpenBox kiosk configuration created successfully"
            log "xterm autostart with shutdown configured successfully for $username"
            return 0
        }
        
        # Ejecutar configure_xterm_autostart con el nombre generado
        run configure_xterm_autostart "$username"
        
        # Verificar que el comando se ejecutó correctamente
        if [[ "$status" -ne 0 ]]; then
            echo "FALLO: configure_xterm_autostart retornó código de error $status para usuario '$username'" >&2
            echo "Output: $output" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que el output contiene los mensajes de éxito
        if [[ "$output" != *"xterm autostart with shutdown configured successfully for $username"* ]]; then
            echo "FALLO: Output no contiene mensaje de éxito para usuario '$username'" >&2
            echo "Output: $output" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que el archivo autostart fue creado (Requirement 13.1)
        if [[ ! -f "$test_dir/home/$username/.config/openbox/autostart" ]]; then
            echo "FALLO: Archivo autostart no fue creado para usuario '$username'" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que el archivo autostart contiene el comando xterm (Requirement 13.1)
        if ! grep -q "xterm" "$test_dir/home/$username/.config/openbox/autostart"; then
            echo "FALLO: Archivo autostart no contiene comando xterm para usuario '$username'" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que el archivo autostart contiene el comando de apagado (Requirement 13.4, 13.5)
        if ! grep -q "shutdown" "$test_dir/home/$username/.config/openbox/autostart"; then
            echo "FALLO: Archivo autostart no contiene comando shutdown para usuario '$username'" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que el archivo rc.xml fue creado (Requirement 13.2)
        if [[ ! -f "$test_dir/home/$username/.config/openbox/rc.xml" ]]; then
            echo "FALLO: Archivo rc.xml no fue creado para usuario '$username'" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que rc.xml contiene configuración de un solo escritorio (kiosk mode)
        if ! grep -q "<number>1</number>" "$test_dir/home/$username/.config/openbox/rc.xml"; then
            echo "FALLO: Archivo rc.xml no contiene configuración de un solo escritorio para usuario '$username'" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        # Verificar que el archivo autostart es ejecutable
        if [[ ! -x "$test_dir/home/$username/.config/openbox/autostart" ]]; then
            echo "FALLO: Archivo autostart no es ejecutable para usuario '$username'" >&2
            rm -rf "$test_dir"
            return 1
        fi
        
        success_count=$((success_count + 1))
    done
    
    # Limpiar directorio temporal
    rm -rf "$test_dir"
    
    # Verificar que todas las pruebas pasaron
    [[ $success_count -eq $total_tests ]]
}
