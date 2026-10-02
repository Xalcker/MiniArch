#!/bin/bash

if ! declare -F run_quiet >/dev/null; then
    run_quiet() { "$@"; }
fi

# Modulo de finalizacion.
# Configura red, servicios remotos opcionales, zona horaria y limpieza final.

# Copia las redes WiFi que iwd guardo en el live (/var/lib/iwd) al sistema
# instalado como perfiles de NetworkManager. Sin esto el kiosko arranca sin red la
# primera vez (el live usa iwd y el sistema instalado NetworkManager, que no
# comparten perfiles) y hay que configurar el WiFi desde el menu; ademas los
# servicios que esperan network-online.target, como nmb, fallan por tiempo de espera
# en ese primer arranque. Con cable no hay nada que copiar. Redes con ; \ o saltos
# de linea en el nombre se omiten con un aviso.
copy_live_wifi_profiles() {
    [[ "${COPY_LIVE_WIFI:-true}" == "true" ]] || return 0

    local iwd_dir="${IWD_STATE_DIR:-/var/lib/iwd}"
    local root="${INSTALL_ROOT:-/mnt}"
    local out_dir="$root/etc/NetworkManager/system-connections"
    local file base name ext ssid secret hex uuid out copied=0

    [[ -d "$iwd_dir" ]] || return 0

    for file in "$iwd_dir"/*.psk "$iwd_dir"/*.open; do
        [[ -f "$file" ]] || continue
        base="${file##*/}"
        ext="${base##*.}"
        name="${base%.*}"

        # iwd codifica el SSID con caracteres especiales como "=" + hex.
        if [[ "$name" == =* ]]; then
            hex="${name#=}"
            ssid="$(printf "$(printf '%s' "$hex" | sed 's/../\\x&/g')")"
        else
            ssid="$name"
        fi

        if [[ -z "$ssid" || "$ssid" == *\;* || "$ssid" == *\* || "$ssid" == *$'\n'* ]]; then
            log "Aviso: no se copia la red WiFi '$name' (nombre con caracteres no soportados)"
            continue
        fi

        secret=""
        if [[ "$ext" == "psk" ]]; then
            secret="$(sed -n 's/^Passphrase=//p' "$file" | head -n 1)"
            [[ -n "$secret" ]] || secret="$(sed -n 's/^PreSharedKey=//p' "$file" | head -n 1)"
            if [[ -z "$secret" ]]; then
                log "Aviso: no se copia la red WiFi '$ssid' (iwd no guardo su clave)"
                continue
            fi
            # En un archivo de claves de NetworkManager la barra invertida es el
            # caracter de escape: una suelta invalida el perfil.
            secret="${secret//\\/\\\\}"
        fi

        mkdir -p "$out_dir"
        uuid="$(cat /proc/sys/kernel/random/uuid)"
        out="$out_dir/miniarch-wifi-$((copied + 1)).nmconnection"

        {
            printf '[connection]\nid=%s\nuuid=%s\ntype=wifi\nautoconnect=true\n\n' "$ssid" "$uuid"
            printf '[wifi]\nmode=infrastructure\nssid=%s\n\n' "$ssid"
            if [[ "$ext" == "psk" ]]; then
                printf '[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n' "$secret"
            fi
            printf '[ipv4]\nmethod=auto\n\n[ipv6]\naddr-gen-mode=default\nmethod=auto\n'
        } > "$out"
        chmod 600 "$out"
        copied=$((copied + 1))
    done

    if (( copied > 0 )); then
        log "Redes WiFi del live copiadas al sistema instalado: $copied"
    fi
}

configure_network() {
    log "Configurando red y zona horaria..."

    if declare -F ensure_pacman_download_user >/dev/null; then
        ensure_pacman_download_user || return 1
    fi

    if declare -F repair_chroot_ca_certificates >/dev/null; then
        repair_chroot_ca_certificates || return 1
    fi

    if ! run_quiet arch-chroot /mnt pacman -S --noconfirm networkmanager; then
        log_error "Fallo al instalar NetworkManager"
        return 1
    fi

    copy_live_wifi_profiles

    if ! run_quiet arch-chroot /mnt systemctl enable NetworkManager.service; then
        log_error "Fallo al habilitar NetworkManager.service"
        return 1
    fi

    # Nombre <hostname>.local por mDNS: avahi (dependencia de pipewire-pulse, ya
    # instalada) responde a esa consulta, asi que el kiosko se encuentra por nombre
    # aunque el router no registre el hostname del DHCP. Si no esta, solo se avisa.
    if ! run_quiet arch-chroot /mnt systemctl enable avahi-daemon.service; then
        log "Aviso: no se pudo habilitar avahi-daemon; el kiosko no respondera a <hostname>.local"
    fi

    if [[ "${ENABLE_SSH:-true}" == "true" ]]; then
        log "Instalando y configurando SSH..."

        if ! run_quiet arch-chroot /mnt pacman -S --noconfirm openssh; then
            log_error "Fallo al instalar OpenSSH"
            return 1
        fi

        if ! run_quiet arch-chroot /mnt systemctl enable sshd.service; then
            log_error "Fallo al habilitar sshd.service"
            return 1
        fi

        log "SSH instalado y habilitado correctamente"
    else
        log "SSH deshabilitado por configuracion (ENABLE_SSH=false)"
    fi

    local tz="${TIMEZONE:-America/Phoenix}"
    log "Configurando zona horaria a $tz..."

    if ! run_quiet arch-chroot /mnt ln -sf "/usr/share/zoneinfo/$tz" /etc/localtime; then
        log_error "Fallo al configurar zona horaria"
        return 1
    fi

    if ! run_quiet arch-chroot /mnt hwclock --systohc; then
        log_error "Fallo al sincronizar reloj del hardware"
        return 1
    fi

    log "Red, servicios remotos y zona horaria configurados correctamente"
}

cleanup_partition_path() {
    local device="$1"
    local partition_number="$2"

    if type get_partition_path &> /dev/null; then
        get_partition_path "$device" "$partition_number"
        return $?
    fi

    case "$device" in
        *[0-9]) echo "${device}p${partition_number}" ;;
        *) echo "${device}${partition_number}" ;;
    esac
}

cleanup_mounts() {
    local swap_partition
    swap_partition=$(cleanup_partition_path "${DISK_DEVICE:-/dev/sda}" 3) || return 1

    log "Iniciando limpieza y desmontaje..."

    if mountpoint -q /mnt/boot; then
        if ! run_quiet umount /mnt/boot; then
            log_error "Fallo al desmontar /mnt/boot"
            return 1
        fi
        log "Desmontado /mnt/boot"
    fi

    if mountpoint -q /mnt/home; then
        if ! run_quiet umount /mnt/home; then
            log_error "Fallo al desmontar /mnt/home"
            return 1
        fi
        log "Desmontado /mnt/home"
    fi

    if mountpoint -q /mnt; then
        if ! run_quiet umount /mnt; then
            log_error "Fallo al desmontar /mnt"
            return 1
        fi
        log "Desmontado /mnt"
    fi

    if swapon --show | grep -q "$swap_partition"; then
        if ! run_quiet swapoff "$swap_partition"; then
            log_error "Fallo al desactivar swap"
            return 1
        fi
        log "Swap desactivado"
    fi
}

cleanup_and_finish() {
    local system_message="${1:-El sistema Arch Linux en modo kiosko ha sido instalado correctamente.}"
    local boot_message="${2:-El sistema arrancara automaticamente en modo grafico con Cage.}"

    if ! cleanup_mounts; then
        return 1
    fi

    echo ""
    echo "=========================================="
    echo "  INSTALACION COMPLETADA EXITOSAMENTE"
    echo "=========================================="
    echo ""
    echo "$system_message"
    echo ""
    echo "Puede reiniciar el sistema ejecutando: reboot"
    echo ""
    echo "$boot_message"
    echo "=========================================="
    echo ""

    log "Instalacion finalizada exitosamente"
}
