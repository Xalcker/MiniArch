#!/usr/bin/env bats

# Deteccion de la generacion de la GPU NVIDIA y decision de instalar nvidia-open
# (lib/cage.sh: detect_nvidia_support, resolve_nvidia_choice).

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    source lib/common.sh
    source lib/cage.sh
    unset NVIDIA_SKIP_GPU_CHECK
}

# Simula la salida de `lspci -nn` con las lineas dadas (una por argumento).
mock_lspci() {
    LSPCI_OUT=$(printf '%s\n' "$@")
    export LSPCI_OUT
    lspci() { printf '%s\n' "$LSPCI_OUT"; }
}

GPU_AMD='06:00.0 VGA compatible controller [0300]: Advanced Micro Devices, Inc. [AMD/ATI] Navi 23 [Radeon RX 6600] [1002:73ff]'
GPU_PASCAL='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP106 [GeForce GTX 1060 6GB] [10de:1c03] (rev a1)'
GPU_MAXWELL='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:13c2] (rev a1)'
GPU_KEPLER='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GK107 [GeForce GT 640] [10de:0fc1] (rev a1)'
GPU_VOLTA='01:00.0 3D controller [0302]: NVIDIA Corporation GV100GL [Tesla V100 PCIe 32GB] [10de:1db6]'
GPU_TESLA='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation G92 [GeForce 9800 GT] [10de:0605]'
GPU_TURING='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU106 [GeForce RTX 2060] [10de:1f08] (rev a1)'
GPU_TURING16='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation TU117 [GeForce GTX 1650] [10de:1f82] (rev a1)'
GPU_AMPERE='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GA104 [GeForce RTX 3070] [10de:2484] (rev a1)'
GPU_ADA='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation AD104 [GeForce RTX 4070] [10de:2786] (rev a1)'
GPU_BLACKWELL='01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GB203 [GeForce RTX 5080] [10de:2c02] (rev a1)'

# --- detect_nvidia_support ---------------------------------------------------

@test "detect_nvidia_support: Pascal, Maxwell, Kepler, Volta y Tesla son 'unsupported'" {
    local gpu
    for gpu in "$GPU_PASCAL" "$GPU_MAXWELL" "$GPU_KEPLER" "$GPU_VOLTA" "$GPU_TESLA"; do
        mock_lspci "$gpu"
        run detect_nvidia_support
        [ "$output" = "unsupported" ]
    done
}

@test "detect_nvidia_support: Turing, Ampere, Ada y Blackwell son 'supported'" {
    local gpu
    for gpu in "$GPU_TURING" "$GPU_TURING16" "$GPU_AMPERE" "$GPU_ADA" "$GPU_BLACKWELL"; do
        mock_lspci "$gpu"
        run detect_nvidia_support
        [ "$output" = "supported" ]
    done
}

@test "detect_nvidia_support: sin GPU NVIDIA devuelve 'none'" {
    mock_lspci "$GPU_AMD"
    run detect_nvidia_support
    [ "$output" = "none" ]
}

@test "detect_nvidia_support: sin lspci devuelve 'unknown'" {
    unset -f lspci
    PATH="$BATS_TEST_TMPDIR/vacio" run detect_nvidia_support
    [ "$output" = "unknown" ]
}

@test "detect_nvidia_support: un chip no reconocido devuelve 'unknown'" {
    mock_lspci '01:00.0 VGA compatible controller [0300]: NVIDIA Corporation Algo Nuevo [GeForce XYZ] [10de:ffff]'
    run detect_nvidia_support
    [ "$output" = "unknown" ]
}

@test "detect_nvidia_support: si hay una GPU moderna y una antigua marca 'unsupported'" {
    mock_lspci "$GPU_TURING" "$GPU_PASCAL"
    run detect_nvidia_support
    [ "$output" = "unsupported" ]
}

@test "detect_nvidia_support: ignora las GPU que no son NVIDIA" {
    mock_lspci "$GPU_AMD" "$GPU_AMPERE"
    run detect_nvidia_support
    [ "$output" = "supported" ]
}

# --- resolve_nvidia_choice ---------------------------------------------------------

@test "INSTALL_NVIDIA=true en una GPU Pascal se desactiva con advertencia (no instala nvidia-open)" {
    mock_lspci "$GPU_PASCAL"
    INSTALL_NVIDIA=true
    resolve_nvidia_choice > "$BATS_TEST_TMPDIR/out.txt"
    [ "$INSTALL_NVIDIA" = "false" ]
    grep -Fq "anterior a Turing" "$BATS_TEST_TMPDIR/out.txt"
    grep -Fq "nvidia-580xx-dkms" "$BATS_TEST_TMPDIR/out.txt"
}

@test "INSTALL_NVIDIA=true en una GPU Turing o posterior se conserva" {
    mock_lspci "$GPU_AMPERE"
    INSTALL_NVIDIA=true
    resolve_nvidia_choice > "$BATS_TEST_TMPDIR/out.txt"
    [ "$INSTALL_NVIDIA" = "true" ]
    grep -Fq "nvidia-open, nvidia-utils" "$BATS_TEST_TMPDIR/out.txt"
}

@test "NVIDIA_SKIP_GPU_CHECK=true permite instalar nvidia-open aunque la GPU sea antigua" {
    mock_lspci "$GPU_PASCAL"
    INSTALL_NVIDIA=true NVIDIA_SKIP_GPU_CHECK=true
    resolve_nvidia_choice > /dev/null
    [ "$INSTALL_NVIDIA" = "true" ]
}

@test "INSTALL_NVIDIA=true sin GPU NVIDIA detectada avisa pero respeta la orden" {
    mock_lspci "$GPU_AMD"
    INSTALL_NVIDIA=true
    resolve_nvidia_choice > "$BATS_TEST_TMPDIR/out.txt"
    [ "$INSTALL_NVIDIA" = "true" ]
    grep -Fq "No se detecto una GPU NVIDIA" "$BATS_TEST_TMPDIR/out.txt"
}

@test "INSTALL_NVIDIA=false no instala y lo informa" {
    mock_lspci "$GPU_AMPERE"
    INSTALL_NVIDIA=false
    resolve_nvidia_choice > "$BATS_TEST_TMPDIR/out.txt"
    [ "$INSTALL_NVIDIA" = "false" ]
    grep -Fq "Driver NVIDIA omitido" "$BATS_TEST_TMPDIR/out.txt"
}

@test "al preguntar, muestra la deteccion y respeta la respuesta (GPU compatible)" {
    mock_lspci "$GPU_ADA"
    INSTALL_NVIDIA=""
    resolve_nvidia_choice <<< "s" > "$BATS_TEST_TMPDIR/out.txt"
    [ "$INSTALL_NVIDIA" = "true" ]
    grep -Fq "compatible con nvidia-open" "$BATS_TEST_TMPDIR/out.txt"
}

@test "al preguntar con GPU antigua, aunque se responda 's' no se instala" {
    mock_lspci "$GPU_MAXWELL"
    INSTALL_NVIDIA=""
    resolve_nvidia_choice <<< "s" > "$BATS_TEST_TMPDIR/out.txt"
    [ "$INSTALL_NVIDIA" = "false" ]
    grep -Fq "anterior a Turing" "$BATS_TEST_TMPDIR/out.txt"
}

@test "al preguntar, Enter (por defecto) no instala el driver" {
    mock_lspci "$GPU_ADA"
    INSTALL_NVIDIA=""
    resolve_nvidia_choice <<< "" > /dev/null
    [ "$INSTALL_NVIDIA" = "false" ]
}

# --- instaladores y documentacion ---------------------------------------------------

@test "los instaladores usan resolve_nvidia_choice y ya no mencionan nvidia-dkms" {
    local f
    for f in install-cage-yarg.sh install-cage-clonehero.sh install-cage-rpcs3.sh; do
        grep -Fq 'resolve_nvidia_choice' "$f"
        ! grep -Fq 'nvidia-dkms' "$f"
    done
}
