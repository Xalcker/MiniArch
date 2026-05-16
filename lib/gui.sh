#!/bin/bash

# GUI Module - OpenBox and X Configuration
# Handles installation of X server, OpenBox window manager, user creation,
# and automatic login/X startup configuration

# Install X server and OpenBox window manager with system dialog support
# Returns: 0 on success, 1 on failure
install_openbox() {
    log "Installing X server, OpenBox, xterm, and system dialog components..."
    
    # Install required packages including XDG desktop portal for system dialogs and xterm
    if ! arch-chroot /mnt pacman -S --noconfirm xorg-server xorg-xinit openbox xterm xdg-desktop-portal xdg-desktop-portal-gtk gtk3; then
        log_error "Failed to install X server, OpenBox, xterm, and dialog components"
        return 1
    fi
    
    log "X server, OpenBox, xterm, and system dialog components installed successfully"
    return 0
}

# Create a system user with standard permissions
# Arguments:
#   $1 - username: Name of the user to create
# Returns: 0 on success, 1 on failure
create_user() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided"
        return 1
    fi
    
    log "Creating user: $username"
    
    # Create user with home directory
    if ! arch-chroot /mnt useradd -m -G wheel -s /bin/bash "$username"; then
        log_error "Failed to create user: $username"
        return 1
    fi
    
    # Set password for the user (using chpasswd)
    if ! echo "$username:$KIOSK_PASSWORD" | arch-chroot /mnt chpasswd; then
        log_error "Failed to set password for user: $username"
        return 1
    fi
    
    log "Configuring sudoers for group 'wheel'..."
    # Enable %wheel group in sudoers
    if ! arch-chroot /mnt bash -c "echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/10-wheel"; then
        log_error "Failed to configure sudoers for group 'wheel'"
        return 1
    fi
    
    log "User $username created successfully"
    return 0
}

# Configure automatic login for specified user on tty1
# Arguments:
#   $1 - username: Name of the user to auto-login
# Returns: 0 on success, 1 on failure
configure_autologin() {
    local username="$1"
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided for autologin configuration"
        return 1
    fi
    
    log "Configuring autologin for user: $username"
    
    # Create systemd override directory
    if ! mkdir -p /mnt/etc/systemd/system/getty@tty1.service.d; then
        log_error "Failed to create systemd override directory"
        return 1
    fi
    
    # Create autologin configuration file
    cat > /mnt/etc/systemd/system/getty@tty1.service.d/autologin.conf << EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty -o '-p -f -- \\\\u' --noclear --autologin $username %I \$TERM
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create autologin configuration file"
        return 1
    fi
    
    log "Autologin configured successfully for $username"
    return 0
}

# Configure automatic X startup for user
# Creates .xinitrc to start OpenBox and modifies .bash_profile to start X automatically
# Arguments:
#   $1 - username: Name of the user to configure
# Returns: 0 on success, 1 on failure
configure_autostart_x() {
    local username="$1"
    local user_home="/mnt/home/$username"
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided for X autostart configuration"
        return 1
    fi
    
    log "Configuring automatic X startup for user: $username"
    
    # Create .xinitrc to start OpenBox
    cat > "$user_home/.xinitrc" << 'EOF'
#!/bin/sh
exec openbox-session
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create .xinitrc"
        return 1
    fi
    
    # Make .xinitrc executable
    chmod +x "$user_home/.xinitrc"
    
    # Create or modify .bash_profile to start X automatically
    cat > "$user_home/.bash_profile" << 'EOF'
# Start X automatically on login to tty1
if [[ -z $DISPLAY ]] && [[ $(tty) = /dev/tty1 ]]; then
    exec startx
fi
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create .bash_profile"
        return 1
    fi
    
    # Set correct ownership for user files
    arch-chroot /mnt chown "$username:$username" "/home/$username/.xinitrc"
    arch-chroot /mnt chown "$username:$username" "/home/$username/.bash_profile"
    
    log "Automatic X startup configured successfully for $username"
    return 0
}

# Configure kiosk application to start automatically and shutdown system on close
# Arguments:
#   $1 - username: Name of the user to configure
# Returns: 0 on success, 1 on failure
configure_kiosk_autostart() {
    local username="$1"
    local user_home="/mnt/home/$username"
    local autostart_dir="$user_home/.config/openbox"
    
    if [[ -z "$username" ]]; then
        log_error "Username not provided for kiosk autostart configuration"
        return 1
    fi
    
    log "Configuring kiosk autostart (YARG/xterm) with shutdown on close for user: $username"
    
    # Create OpenBox config directory
    if ! mkdir -p "$autostart_dir"; then
        log_error "Failed to create OpenBox config directory"
        return 1
    fi
    
    # Create autostart file that launches YARG (if exists) or xterm and shuts down on close
    cat > "$autostart_dir/autostart" << 'EOF'
#!/bin/bash
# Start kiosk application and shutdown system when it closes

# Wait a moment for X to fully initialize
sleep 2

# Determine which application to start (Priority: YARG > RetroArch > Web > xterm)
if [ -f "\$HOME/YARG/YARG" ]; then
    echo "Starting YARG..."
    "\$HOME/YARG/YARG" &
    APP_PID=\$!
elif command -v retroarch &> /dev/null; then
    echo "Starting RetroArch..."
    retroarch --fullscreen &
    APP_PID=\$!
elif [ -f "\$HOME/kiosk_url" ]; then
    URL=\$(cat "\$HOME/kiosk_url")
    echo "Starting Web Kiosk at \$URL..."
    chromium --kiosk --no-first-run --disable-infobars --window-position=0,0 "\$URL" &
    APP_PID=\$!
else
    echo "No game found. Starting xterm for maintenance..."
    xterm -e /bin/bash &
    APP_PID=\$!
fi

# Wait for application to close in background, then shutdown
(
    wait \$APP_PID
    EXIT_STATUS=\$?
    if [ \$EXIT_STATUS -ne 0 ]; then
        echo "Application failed with status \$EXIT_STATUS. Rebooting..."
        /usr/bin/sudo /usr/bin/reboot
    else
        echo "Application closed normally. Shutting down system..."
        /usr/bin/sudo /usr/bin/shutdown -h now
    fi
) &
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create OpenBox autostart file"
        return 1
    fi
    
    # Make autostart executable
    chmod +x "$autostart_dir/autostart"
    
    log "Creating OpenBox configuration for kiosk mode"
    
    # Create OpenBox rc.xml configuration for kiosk mode
    cat > "$autostart_dir/rc.xml" << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<openbox_config xmlns="http://openbox.org/3.4/rc" xmlns:xi="http://www.w3.org/2001/XInclude">
  <desktops>
    <!-- Use only 1 desktop for kiosk mode -->
    <number>1</number>
    <firstdesk>1</firstdesk>
    <names>
      <name>Kiosk</name>
    </names>
    <popupTime>0</popupTime>
  </desktops>
  
  <mouse>
    <context name="Desktop">
      <!-- Disable desktop switching with mouse wheel -->
      <mousebind button="Up" action="Click"/>
      <mousebind button="Down" action="Click"/>
    </context>
    <context name="Root">
      <!-- Disable desktop switching with mouse wheel on root window -->
      <mousebind button="Up" action="Click"/>
      <mousebind button="Down" action="Click"/>
    </context>
  </mouse>
  
  <keyboard>
    <!-- Disable desktop switching keyboard shortcuts -->
    <keybind key="C-A-Left"/>
    <keybind key="C-A-Right"/>
    <keybind key="C-A-Up"/>
    <keybind key="C-A-Down"/>
  </keyboard>
</openbox_config>
EOF
    
    if [[ $? -ne 0 ]]; then
        log_error "Failed to create OpenBox configuration file"
        return 1
    fi
    
    log "OpenBox kiosk configuration created successfully"
    
    # Set correct ownership for user files
    arch-chroot /mnt chown -R "$username:$username" "/home/$username/.config"
    
    log "Kiosk autostart (YARG/xterm) with shutdown configured successfully for $username"
    return 0
}
