#!/usr/bin/env bats

# Seguridad del particionado: exclusion del medio live (live_boot_disk,
# select_disk_device) y limpieza previa del disco (prepare_disk_for_install).
# Todo se simula con funciones: ninguna prueba toca discos reales.

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    CALLS="$BATS_TEST_TMPDIR/calls.log"
    : > "$CALLS"
    source lib/common.sh
    source lib/validation.sh
    source lib/partitioning.sh

    is_block_device() { return 0; }
}

# --- live_boot_disk ----------------------------------------------------------

@test "live_boot_disk devuelve el disco padre de la particion de arranque del ISO" {
    findmnt() { echo "/dev/sdb1"; }
    lsblk() { echo "sdb"; }
    run live_boot_disk
    [ "$output" = "/dev/sdb" ]
}

@test "live_boot_disk ignora el sufijo [/subruta] de un bind mount" {
    findmnt() { echo "/dev/sdb1[/arch]"; }
    lsblk() { echo "sdb"; }
    run live_boot_disk
    [ "$output" = "/dev/sdb" ]
}

@test "live_boot_disk devuelve el propio dispositivo si no tiene disco padre (ej. un CD)" {
    findmnt() { echo "/dev/sr0"; }
    lsblk() { :; }
    run live_boot_disk
    [ "$output" = "/dev/sr0" ]
}

@test "live_boot_disk no devuelve nada si el ISO no esta montado" {
    findmnt() { return 1; }
    run live_boot_disk
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

# --- select_disk_device --------------------------------------------------------

mock_two_disks() {
    lsblk() {
        case "$*" in
            *"NAME,TYPE"*) printf '/dev/sda disk\n/dev/sdb disk\n' ;;
            *"-o SIZE"*) echo "64G" ;;
            *"-o TRAN"*) echo "sata" ;;
            *"-o RM"*) echo "0" ;;
            *"-o MODEL"*) echo "Disco" ;;
            *) echo "NAME SIZE TYPE" ;;
        esac
    }
}

@test "select_disk_device oculta el disco del ISO live y permite elegir otro" {
    mock_two_disks
    live_boot_disk() { echo "/dev/sdb"; }

    run select_disk_device ask <<< $'1\ninstalar'
    [ "$status" -eq 0 ]
    [[ "$output" == *"Se oculta /dev/sdb"* ]]
    [[ "$output" != *"2) /dev/sdb"* ]]
    [ "${lines[-1]}" = "/dev/sda" ]
}

@test "select_disk_device rechaza escribir a mano el disco del ISO live" {
    mock_two_disks
    live_boot_disk() { echo "/dev/sdb"; }

    run select_disk_device ask <<< $'/dev/sdb\ninstalar'
    [ "$status" -eq 1 ]
    [[ "$output" == *"medio de instalacion en uso"* ]]
}

@test "select_disk_device rechaza tambien las particiones del disco del ISO live" {
    mock_two_disks
    live_boot_disk() { echo "/dev/sdb"; }

    run select_disk_device ask <<< $'/dev/sdb1\ninstalar'
    [ "$status" -eq 1 ]
    [[ "$output" == *"medio de instalacion en uso"* ]]
}

@test "select_disk_device rechaza el disco live aunque venga fijado desde .env" {
    mock_two_disks
    live_boot_disk() { echo "/dev/sdb"; }

    run select_disk_device /dev/sdb <<< $'\ninstalar'
    [ "$status" -eq 1 ]
    [[ "$output" == *"medio de instalacion en uso"* ]]
}

@test "select_disk_device no oculta nada si no se detecta medio live" {
    mock_two_disks
    live_boot_disk() { :; }

    run select_disk_device ask <<< $'2\ninstalar'
    [ "$status" -eq 0 ]
    [[ "$output" == *"2) /dev/sdb"* ]]
    [[ "$output" != *"Se oculta"* ]]
    [ "${lines[-1]}" = "/dev/sdb" ]
}

# --- prepare_disk_for_install ---------------------------------------------------

mock_disk_commands() {
    live_boot_disk() { :; }
    swapon() { printf '/dev/sda3\n/dev/sdb2\n'; }
    swapoff() { echo "swapoff $*" >> "$CALLS"; }
    umount() { echo "umount $*" >> "$CALLS"; }
    wipefs() { echo "wipefs $*" >> "$CALLS"; }
    sgdisk() { echo "sgdisk $*" >> "$CALLS"; }
    dmsetup() { echo "dmsetup $*" >> "$CALLS"; }
    mdadm() { echo "mdadm $*" >> "$CALLS"; }
    lsblk() {
        case "$*" in
            *"NAME,MOUNTPOINT"*)
                printf '/dev/sda\n/dev/sda1 /boot\n/dev/sda2 /mnt\n'
                ;;
            *"NAME,TYPE"*)
                printf '/dev/sda disk\n/dev/sda1 part\n/dev/sda2 part\n/dev/mapper/vg-root lvm\n/dev/md0 raid1\n'
                ;;
        esac
    }
}

line_of() { grep -n -F -- "$1" "$CALLS" | head -n 1 | cut -d: -f1; }

@test "prepare_disk_for_install desactiva solo el swap del disco destino" {
    mock_disk_commands
    run prepare_disk_for_install /dev/sda
    [ "$status" -eq 0 ]
    grep -Fq "swapoff /dev/sda3" "$CALLS"
    ! grep -Fq "swapoff /dev/sdb2" "$CALLS"
}

@test "prepare_disk_for_install desmonta lo montado desde el disco" {
    mock_disk_commands
    run prepare_disk_for_install /dev/sda
    [ "$status" -eq 0 ]
    grep -Fq "umount -R /boot" "$CALLS"
    grep -Fq "umount -R /mnt" "$CALLS"
}

@test "prepare_disk_for_install detiene LVM y RAID heredados" {
    mock_disk_commands
    run prepare_disk_for_install /dev/sda
    grep -Fq "dmsetup remove --force /dev/mapper/vg-root" "$CALLS"
    grep -Fq "mdadm --stop /dev/md0" "$CALLS"
}

@test "prepare_disk_for_install borra firmas de las particiones antes que las del disco" {
    mock_disk_commands
    run prepare_disk_for_install /dev/sda
    [ "$status" -eq 0 ]
    local p1 p2 disk zap
    p1=$(line_of "wipefs --all --force /dev/sda1")
    p2=$(line_of "wipefs --all --force /dev/sda2")
    disk=$(grep -n -x -F "wipefs --all --force /dev/sda" "$CALLS" | head -n 1 | cut -d: -f1)
    zap=$(line_of "sgdisk --zap-all /dev/sda")
    [ -n "$p1" ] && [ -n "$p2" ] && [ -n "$disk" ] && [ -n "$zap" ]
    [ "$p1" -lt "$disk" ]
    [ "$p2" -lt "$disk" ]
    [ "$disk" -lt "$zap" ]
}

@test "prepare_disk_for_install se niega a tocar el disco del ISO live" {
    mock_disk_commands
    live_boot_disk() { echo "/dev/sda"; }
    run prepare_disk_for_install /dev/sda
    [ "$status" -eq 1 ]
    [[ "$output" == *"medio de instalacion en uso"* ]]
    [ ! -s "$CALLS" ]
}

@test "prepare_disk_for_install falla sin borrar nada si no se puede desmontar" {
    mock_disk_commands
    umount() { return 1; }
    run prepare_disk_for_install /dev/sda
    [ "$status" -eq 1 ]
    [[ "$output" == *"No se pudo desmontar"* ]]
    ! grep -Fq "wipefs" "$CALLS"
}

@test "prepare_disk_for_install falla si wipefs no puede borrar las firmas" {
    mock_disk_commands
    wipefs() { return 1; }
    run prepare_disk_for_install /dev/sda
    [ "$status" -eq 1 ]
    [[ "$output" == *"Fallo al borrar las firmas"* ]]
}

@test "prepare_disk_for_install rechaza un dispositivo que no existe" {
    mock_disk_commands
    is_block_device() { return 1; }
    run prepare_disk_for_install /dev/no-existe
    [ "$status" -eq 1 ]
}

@test "los instaladores limpian el disco antes de particionarlo" {
    local f p w
    for f in install-cage-yarg.sh install-cage-clonehero.sh install-cage-rpcs3.sh install-cage-kiosk.sh; do
        p=$(grep -n 'prepare_disk_for_install "\$DISK_DEVICE"' "$f" | head -n 1 | cut -d: -f1)
        w=$(grep -n 'partition_disk "\$DISK_DEVICE"' "$f" | head -n 1 | cut -d: -f1)
        [ -n "$p" ] && [ -n "$w" ]
        [ "$p" -lt "$w" ]
    done
}
