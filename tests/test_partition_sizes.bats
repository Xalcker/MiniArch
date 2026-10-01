#!/usr/bin/env bats

# Tamaños de particion configurables (ESP_SIZE, ROOT_SIZE, SWAP_SIZE) y
# coherencia de .env.example con el codigo.

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    source lib/common.sh
    source lib/partitioning.sh
    is_block_device() { return 0; }
    unset ESP_SIZE ROOT_SIZE SWAP_SIZE
    CALLS="$BATS_TEST_TMPDIR/parted.log"
    : > "$CALLS"
    parted() { echo "parted $*" >> "$CALLS"; }
}

# --- size_to_mib -------------------------------------------------------------

@test "size_to_mib convierte M y G (con o sin iB, sin distinguir mayusculas)" {
    [ "$(size_to_mib 512M)" = "512" ]
    [ "$(size_to_mib 8G)" = "8192" ]
    [ "$(size_to_mib 8GiB)" = "8192" ]
    [ "$(size_to_mib 512mib)" = "512" ]
    [ "$(size_to_mib 2gb)" = "2048" ]
    [ "$(size_to_mib 008G)" = "8192" ]
}

@test "size_to_mib rechaza formatos invalidos" {
    run size_to_mib "8"
    [ "$status" -eq 1 ]
    run size_to_mib "abc"
    [ "$status" -eq 1 ]
    run size_to_mib "8T"
    [ "$status" -eq 1 ]
    run size_to_mib ""
    [ "$status" -eq 1 ]
    run size_to_mib "-4G"
    [ "$status" -eq 1 ]
}

# --- resolve_partition_sizes ---------------------------------------------------

@test "resolve_partition_sizes usa 512M, 8G y 2G por defecto" {
    resolve_partition_sizes
    [ "$PARTITION_ESP_MIB" = "512" ]
    [ "$PARTITION_ROOT_MIB" = "8192" ]
    [ "$PARTITION_SWAP_MIB" = "2048" ]
}

@test "resolve_partition_sizes respeta ESP_SIZE, ROOT_SIZE y SWAP_SIZE" {
    ESP_SIZE=1G ROOT_SIZE=20G SWAP_SIZE=4G
    resolve_partition_sizes
    [ "$PARTITION_ESP_MIB" = "1024" ]
    [ "$PARTITION_ROOT_MIB" = "20480" ]
    [ "$PARTITION_SWAP_MIB" = "4096" ]
}

@test "resolve_partition_sizes rechaza valores invalidos o por debajo del minimo" {
    ROOT_SIZE=mucho
    run resolve_partition_sizes
    [ "$status" -eq 1 ]
    [[ "$output" == *"ROOT_SIZE invalido"* ]]
    unset ROOT_SIZE

    ESP_SIZE=100M
    run resolve_partition_sizes
    [ "$status" -eq 1 ]
    [[ "$output" == *"minimo de 256M"* ]]
    unset ESP_SIZE

    ROOT_SIZE=2G
    run resolve_partition_sizes
    [ "$status" -eq 1 ]
    [[ "$output" == *"minimo de 4G"* ]]
    unset ROOT_SIZE

    SWAP_SIZE=256M
    run resolve_partition_sizes
    [ "$status" -eq 1 ]
    [[ "$output" == *"minimo de 512M"* ]]
}

# --- partition_disk --------------------------------------------------------------

@test "partition_disk con los valores por defecto emite los mismos limites de siempre" {
    run partition_disk /dev/sda
    [ "$status" -eq 0 ]
    grep -Fxq "parted -s /dev/sda mkpart ESP fat32 1MiB 513MiB" "$CALLS"
    grep -Fxq "parted -s /dev/sda mkpart primary ext4 513MiB 8705MiB" "$CALLS"
    grep -Fxq "parted -s /dev/sda mkpart primary linux-swap 8705MiB 10753MiB" "$CALLS"
    grep -Fxq "parted -s /dev/sda mkpart primary ext4 10753MiB 100%" "$CALLS"
}

@test "partition_disk calcula los limites con tamanos personalizados" {
    ESP_SIZE=1G ROOT_SIZE=20G SWAP_SIZE=4G
    run partition_disk /dev/sda
    [ "$status" -eq 0 ]
    grep -Fxq "parted -s /dev/sda mkpart ESP fat32 1MiB 1025MiB" "$CALLS"
    grep -Fxq "parted -s /dev/sda mkpart primary ext4 1025MiB 21505MiB" "$CALLS"
    grep -Fxq "parted -s /dev/sda mkpart primary linux-swap 21505MiB 25601MiB" "$CALLS"
    grep -Fxq "parted -s /dev/sda mkpart primary ext4 25601MiB 100%" "$CALLS"
}

@test "partition_disk no toca el disco si un tamano es invalido" {
    SWAP_SIZE=x
    run partition_disk /dev/sda
    [ "$status" -eq 1 ]
    [ ! -s "$CALLS" ]
}

# --- validate_partition_plan -------------------------------------------------------

disk_of() { # GiB
    local bytes=$(($1 * 1024 * 1024 * 1024))
    eval "lsblk() { echo $bytes; }"
}

@test "validate_partition_plan acepta un disco de 16 GiB y muestra el esquema" {
    disk_of 16
    run validate_partition_plan /dev/sda
    [ "$status" -eq 0 ]
    [[ "$output" == *"ESP 512MiB, root 8192MiB, swap 2048MiB, /home ~5GiB"* ]]
}

@test "validate_partition_plan rechaza un esquema que deja menos de 2 GiB para /home" {
    disk_of 12
    run validate_partition_plan /dev/sda
    [ "$status" -eq 1 ]
    [[ "$output" == *"para /home"* ]]
}

@test "validate_partition_plan permite agrandar root si el disco lo permite" {
    disk_of 64
    ROOT_SIZE=30G
    run validate_partition_plan /dev/sda
    [ "$status" -eq 0 ]
    [[ "$output" == *"root 30720MiB"* ]]
}

@test "validate_partition_plan falla si no puede leer el tamano del disco" {
    lsblk() { :; }
    run validate_partition_plan /dev/sda
    [ "$status" -eq 1 ]
}

@test "los instaladores validan el esquema antes de pedir confirmacion de borrado" {
    local f v c
    for f in install-cage-yarg.sh install-cage-clonehero.sh install-cage-rpcs3.sh install-cage-kiosk.sh; do
        v=$(grep -n 'validate_partition_plan "\$DISK_DEVICE"' "$f" | head -n 1 | cut -d: -f1)
        c=$(grep -n 'check_disk_empty "\$DISK_DEVICE"' "$f" | head -n 1 | cut -d: -f1)
        [ -n "$v" ] && [ -n "$c" ]
        [ "$v" -lt "$c" ]
    done
}

# --- .env.example -----------------------------------------------------------------

@test ".env.example no define variables que ningun script lea" {
    local key
    for key in $(tr -d '\r' < .env.example | grep -oE '^#?[A-Z][A-Z0-9_]*=' | tr -d '#='); do
        grep -rqw "$key" install-cage-*.sh lib scripts
    done
}

@test ".env.example no apunta las canciones a /opt (el default real es el home del usuario)" {
    ! grep -Eq '^(YARG|CLONEHERO)_SONGS_DIR=/opt' .env.example
}

@test "el fallback de zona horaria de lib/finalization.sh coincide con el de los instaladores" {
    local installer_default
    installer_default=$(grep -ho 'TIMEZONE="\${TIMEZONE:-[^}]*}"' install-cage-yarg.sh | sed 's/.*:-//; s/}".*//')
    [ -n "$installer_default" ]
    grep -Fq "\${TIMEZONE:-$installer_default}" lib/finalization.sh
}
