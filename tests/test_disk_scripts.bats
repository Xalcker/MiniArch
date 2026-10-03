#!/usr/bin/env bats

# Comportamiento de scripts/expand-home.sh y scripts/clone-miniarch.sh.
# Los scripts terminan con `main "$@"`, asi que cada prueba carga sus funciones
# sin esa linea dentro de un bash aparte y con herramientas de disco simuladas:
# ninguna prueba toca discos reales.

setup() {
    W="$BATS_TEST_TMPDIR/w"
    STUBS="$W/stubs"
    CALLS="$W/calls.log"
    mkdir -p "$STUBS"
    : > "$CALLS"
    sed '/^main "\$@"$/d' scripts/expand-home.sh > "$W/expand.sh"
    sed '/^main "\$@"$/d' scripts/clone-miniarch.sh > "$W/clone.sh"
}

# Crea un ejecutable simulado que registra su nombre y argumentos en $CALLS.
# Uso: stub <nombre> [codigo-de-salida] [salida-estandar]
stub() {
    cat > "$STUBS/$1" <<SH
#!/bin/bash
echo "$1 \$*" >> "$CALLS"
[[ -n "${3:-}" ]] && printf '%s\n' "${3:-}"
exit ${2:-0}
SH
    chmod +x "$STUBS/$1"
}

# Ejecuta <script-cargado> y luego los comandos dados, solo con los stubs en PATH.
run_in() {
    local lib="$1"; shift
    run env PATH="$STUBS:/usr/bin:/bin" bash -c "source '$lib'; $*"
}

# --- expand-home.sh ----------------------------------------------------------

@test "expand-home: partition_path usa el sufijo p en nvme y mmcblk" {
    run_in "$W/expand.sh" 'partition_path /dev/sdb 4; partition_path /dev/nvme0n1 4; partition_path /dev/mmcblk0 4'
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "/dev/sdb4" ]
    [ "${lines[1]}" = "/dev/nvme0n1p4" ]
    [ "${lines[2]}" = "/dev/mmcblk0p4" ]
}

@test "expand-home: --help sale con 0 y describe la confirmacion" {
    run bash scripts/expand-home.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"EXPANDIR"* ]]
    [[ "$output" == *"--yes"* ]]
}

@test "expand-home: rechaza opciones desconocidas y mas de un disco" {
    run bash scripts/expand-home.sh --nada
    [ "$status" -eq 1 ]
    [[ "$output" == *"Opcion desconocida: --nada"* ]]

    run bash scripts/expand-home.sh /dev/sda /dev/sdb
    [ "$status" -eq 1 ]
    [[ "$output" == *"Solo se acepta un disco"* ]]
}

@test "expand-home: grow_home_partition repara GPT y usa growpart si funciona" {
    stub sgdisk; stub growpart; stub parted
    run_in "$W/expand.sh" 'grow_home_partition /dev/sdb'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$CALLS")" = "sgdisk -e /dev/sdb" ]
    grep -Fxq "growpart /dev/sdb 4" "$CALLS"
    ! grep -q '^parted' "$CALLS"
}

@test "expand-home: si growpart falla recurre a parted resizepart" {
    stub sgdisk; stub growpart 1; stub parted
    run_in "$W/expand.sh" 'grow_home_partition /dev/sdb'
    [ "$status" -eq 0 ]
    grep -Fxq "parted -s /dev/sdb resizepart 4 100%" "$CALLS"
}

@test "expand-home: sin growpart usa parted directamente" {
    stub sgdisk; stub parted
    # PATH solo con los stubs: un growpart real del sistema no debe interferir.
    run env PATH="$STUBS" /bin/bash -c "source '$W/expand.sh'; grow_home_partition /dev/sdb"
    [ "$status" -eq 0 ]
    grep -Fxq "parted -s /dev/sdb resizepart 4 100%" "$CALLS"
}

@test "expand-home: revisa el filesystem antes de redimensionarlo" {
    stub e2fsck; stub resize2fs
    run_in "$W/expand.sh" 'resize_home_filesystem /dev/sdb4'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$CALLS")" = "e2fsck -fy /dev/sdb4" ]
    [ "$(sed -n 2p "$CALLS")" = "resize2fs /dev/sdb4" ]
}

@test "expand-home: ensure_not_mounted rechaza un disco con particiones montadas" {
    stub lsblk 0 "/home"
    run_in "$W/expand.sh" 'ensure_not_mounted /dev/sdb'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Hay particiones montadas en /dev/sdb"* ]]
}

@test "expand-home: ensure_not_mounted acepta un disco sin montajes" {
    stub lsblk 0 ""
    run_in "$W/expand.sh" 'ensure_not_mounted /dev/sdb'
    [ "$status" -eq 0 ]
}

@test "expand-home: ensure_whole_disk rechaza una particion" {
    stub lsblk 0 "part"
    run_in "$W/expand.sh" 'ensure_whole_disk /dev/sdb1'
    [ "$status" -eq 1 ]
    [[ "$output" == *"no parece ser un disco completo"* ]]
}

@test "expand-home: confirm_expand no pregunta con --yes" {
    run_in "$W/expand.sh" 'ASSUME_YES=true; confirm_expand /dev/sdb /dev/sdb4'
    [ "$status" -eq 0 ]
}

# --- clone-miniarch.sh -------------------------------------------------------

@test "clone-miniarch: partition_path usa el sufijo p en nvme y mmcblk" {
    run_in "$W/clone.sh" 'partition_path /dev/sdb 2; partition_path /dev/nvme1n1 2'
    [ "${lines[0]}" = "/dev/sdb2" ]
    [ "${lines[1]}" = "/dev/nvme1n1p2" ]
}

@test "clone-miniarch: --help sale con 0 y --repair-fstab exige un disco" {
    run bash scripts/clone-miniarch.sh --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"--repair-fstab"* ]]

    run bash scripts/clone-miniarch.sh --repair-fstab
    [ "$status" -eq 1 ]
    [[ "$output" == *"Falta el disco clonado"* ]]
}

@test "clone-miniarch: disk_size_bytes devuelve solo el numero de bytes" {
    stub lsblk 0 "  250059350016  "
    run_in "$W/clone.sh" 'disk_size_bytes /dev/sdb'
    [ "$output" = "250059350016" ]
}

@test "clone-miniarch: ensure_no_mounted_partitions rechaza discos montados" {
    stub lsblk 0 "/"
    run_in "$W/clone.sh" 'ensure_no_mounted_partitions /dev/sdb'
    [ "$status" -eq 1 ]
    [[ "$output" == *"Hay particiones montadas en /dev/sdb"* ]]
}

@test "clone-miniarch: require_partition_uuid falla si no hay UUID" {
    stub blkid 0 ""
    run_in "$W/clone.sh" 'require_partition_uuid /dev/sdb2 root'
    [ "$status" -eq 1 ]
    [[ "$output" == *"No se pudo leer UUID de root"* ]]
}

@test "clone-miniarch: refresh_fstab escribe los UUID actuales y respalda el fstab previo" {
    cat > "$STUBS/blkid" <<'SH'
#!/usr/bin/env bash
case "${*: -1}" in
    /dev/sdb1) echo "ESP1-UUID" ;;
    /dev/sdb2) echo "ROOT2-UUID" ;;
    /dev/sdb4) echo "HOME4-UUID" ;;
esac
SH
    chmod +x "$STUBS/blkid"
    mkdir -p "$W/root/etc"
    echo "UUID=viejo / ext4 defaults 0 1" > "$W/root/etc/fstab"

    run_in "$W/clone.sh" "
        mktemp() { echo '$W/root'; }
        mount_clone() { return 0; }
        unmount_clone() { :; }
        refresh_fstab /dev/sdb"
    [ "$status" -eq 0 ]
    grep -Fxq 'UUID=ROOT2-UUID / ext4 defaults,noatime 0 1' "$W/root/etc/fstab"
    grep -Fxq 'UUID=ESP1-UUID /boot vfat umask=0077 0 2' "$W/root/etc/fstab"
    grep -Fxq 'UUID=HOME4-UUID /home ext4 defaults,noatime 0 2' "$W/root/etc/fstab"
    ! grep -q 'swap' "$W/root/etc/fstab"
    ! grep -q 'viejo' "$W/root/etc/fstab"
    grep -Fxq 'UUID=viejo / ext4 defaults 0 1' "$W/root/etc/fstab.clone-backup"
}
