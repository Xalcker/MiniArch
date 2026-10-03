#!/usr/bin/env bats

# Pruebas de lib/kiosk_runtime.sh: prologo del wrapper, menu de mantenimiento y
# unidad systemd compartidos por los kioscos YARG, Clone Hero y RPCS3.

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    source lib/common.sh
    source lib/kiosk_runtime.sh
    STUBS="$BATS_TEST_TMPDIR/stubs"
    mkdir -p "$STUBS"
}

stub() { # nombre cuerpo
    printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUBS/$1"
    chmod +x "$STUBS/$1"
}

# --- prologo del wrapper -----------------------------------------------------

@test "el prologo es Bash valido, sin marcadores y usa la etiqueta de la app" {
    kiosk_wrapper_prelude run-yarg /home/k false > "$BATS_TEST_TMPDIR/p.sh"
    bash -n "$BATS_TEST_TMPDIR/p.sh"
    ! grep -q '__KIOSK_[A-Z]*__' "$BATS_TEST_TMPDIR/p.sh"
    grep -Fq 'echo "run-yarg: iniciado como' "$BATS_TEST_TMPDIR/p.sh"
    grep -Fq 'HOME="${HOME:-/home/k}"' "$BATS_TEST_TMPDIR/p.sh"
    ! grep -Fq 'run-rpcs3' "$BATS_TEST_TMPDIR/p.sh"
}

@test "el prologo activa el render por software solo cuando se pide" {
    kiosk_wrapper_prelude run-x /home/k true > "$BATS_TEST_TMPDIR/sw.sh"
    echo 'echo "$LIBGL_ALWAYS_SOFTWARE|$GALLIUM_DRIVER"' >> "$BATS_TEST_TMPDIR/sw.sh"
    DBUS_SESSION_BUS_ADDRESS="" KIOSK_DBUS_SESSION_STARTED=1 XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" \
        run bash "$BATS_TEST_TMPDIR/sw.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1|llvmpipe" ]]

    kiosk_wrapper_prelude run-x /home/k false > "$BATS_TEST_TMPDIR/nosw.sh"
    echo 'echo "[${LIBGL_ALWAYS_SOFTWARE:-}]"' >> "$BATS_TEST_TMPDIR/nosw.sh"
    DBUS_SESSION_BUS_ADDRESS="" KIOSK_DBUS_SESSION_STARTED=1 XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" \
        run bash "$BATS_TEST_TMPDIR/nosw.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"[]" ]]
}

@test "dbus_session_is_usable rechaza una direccion ausente o un socket inexistente" {
    eval "$(kiosk_wrapper_prelude run-x /home/k false | sed -n '/^dbus_session_is_usable() {/,/^}/p')"
    DBUS_SESSION_BUS_ADDRESS="" run dbus_session_is_usable
    [ "$status" -eq 1 ]
    DBUS_SESSION_BUS_ADDRESS="unix:path=$BATS_TEST_TMPDIR/no-existe,guid=1" run dbus_session_is_usable
    [ "$status" -eq 1 ]
}

@test "start_kiosk_audio arranca pipewire, wireplumber y pipewire-pulse en ese orden" {
    local order="$BATS_TEST_TMPDIR/order"
    stub pipewire "echo pipewire >> '$order'; touch \"\$XDG_RUNTIME_DIR/pipewire-0\"; sleep 3"
    stub wireplumber "echo wireplumber >> '$order'; sleep 3"
    stub pipewire-pulse "echo pipewire-pulse >> '$order'; sleep 3"
    stub pgrep 'exit 1'
    stub pactl 'echo "0 sink-falso"'

    {
        kiosk_wrapper_prelude run-x /home/k false
        echo 'start_kiosk_audio Prueba'
    } > "$BATS_TEST_TMPDIR/a.sh"

    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run timeout 20 bash "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 0 ]
    [ "$(cat "$order")" = $'pipewire\nwireplumber\npipewire-pulse' ]
}

@test "start_kiosk_audio avisa con el nombre de la app si no hay sink" {
    stub pgrep 'exit 0'
    stub pactl 'exit 0'
    {
        kiosk_wrapper_prelude run-x /home/k false
        echo 'wait_for_path() { return 0; }'
        echo 'wait_for_pulse_sink() { return 1; }'
        echo 'start_kiosk_audio "Clone Hero"'
    } > "$BATS_TEST_TMPDIR/a.sh"

    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run bash "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"antes de iniciar Clone Hero."* ]]
}

@test "start_kiosk_audio fija el volumen con wpctl cuando el prologo lo recibe" {
    local calls="$BATS_TEST_TMPDIR/wpctl"
    stub pgrep 'exit 0'
    stub pactl 'echo "0 sink-falso"'
    stub wpctl "echo \"\$*\" >> '$calls'"
    {
        kiosk_wrapper_prelude run-x /home/k false 0.8
        echo 'wait_for_path() { return 0; }'
        echo 'start_kiosk_audio Prueba'
    } > "$BATS_TEST_TMPDIR/a.sh"

    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run bash "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 0 ]
    grep -q 'set-mute @DEFAULT_AUDIO_SINK@ 0' "$calls"
    grep -q 'set-volume @DEFAULT_AUDIO_SINK@ 0.8' "$calls"
}

@test "start_kiosk_audio no toca el volumen si el prologo no recibe uno" {
    local calls="$BATS_TEST_TMPDIR/wpctl"
    stub pgrep 'exit 0'
    stub pactl 'echo "0 sink-falso"'
    stub wpctl "echo llamado >> '$calls'"
    {
        kiosk_wrapper_prelude run-x /home/k false
        echo 'wait_for_path() { return 0; }'
        echo 'start_kiosk_audio Prueba'
    } > "$BATS_TEST_TMPDIR/a.sh"

    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run bash "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$calls" ]
}

@test "validate_kiosk_audio_volume acepta de 0 a 1 o vacio y rechaza el resto" {
    validate_kiosk_audio_volume V ""
    validate_kiosk_audio_volume V 1.0
    validate_kiosk_audio_volume V 0.5
    run validate_kiosk_audio_volume V 1.5
    [ "$status" -eq 1 ]
    run validate_kiosk_audio_volume V abc
    [ "$status" -eq 1 ]
}

@test "start_kiosk_audio fuerza el cuantum de PipeWire solo si el prologo recibe uno" {
    local calls="$BATS_TEST_TMPDIR/pwmeta"
    stub pgrep 'exit 0'
    stub pactl 'echo "0 sink-falso"'
    stub pw-metadata "echo \"\$*\" >> '$calls'"
    {
        kiosk_wrapper_prelude run-x /home/k false "" 128
        echo 'wait_for_path() { return 0; }'
        echo 'start_kiosk_audio Prueba'
    } > "$BATS_TEST_TMPDIR/a.sh"
    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run bash "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 0 ]
    grep -q 'settings 0 clock.force-quantum 128' "$calls"

    rm -f "$calls"
    {
        kiosk_wrapper_prelude run-x /home/k false "" ""
        echo 'wait_for_path() { return 0; }'
        echo 'start_kiosk_audio Prueba'
    } > "$BATS_TEST_TMPDIR/b.sh"
    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run bash "$BATS_TEST_TMPDIR/b.sh"
    [ "$status" -eq 0 ]
    [ ! -e "$calls" ]
}

@test "validate_kiosk_pipewire_quantum acepta de 32 a 2048 o vacio y rechaza el resto" {
    validate_kiosk_pipewire_quantum Q ""
    validate_kiosk_pipewire_quantum Q 128
    validate_kiosk_pipewire_quantum Q 32
    validate_kiosk_pipewire_quantum Q 2048
    run validate_kiosk_pipewire_quantum Q 16
    [ "$status" -eq 1 ]
    run validate_kiosk_pipewire_quantum Q 4096
    [ "$status" -eq 1 ]
    run validate_kiosk_pipewire_quantum Q abc
    [ "$status" -eq 1 ]
}

# --- atajo de salida compartido ----------------------------------------------

@test "install_kiosk_exit_hotkey no instala nada con false" {
    run install_kiosk_exit_hotkey false YARG
    [ "$status" -eq 0 ]
    [[ "$output" == *"omitido (YARG_EXIT_HOTKEY=false)"* ]]
}

@test "start_kiosk_exit_hotkey pasa los procesos objetivo al script" {
    local calls="$BATS_TEST_TMPDIR/hk"
    stub pgrep 'exit 1'
    stub python3 "echo \"\$*\" >> '$calls'"
    {
        kiosk_wrapper_prelude run-x /home/k false
        echo 'wait_for_path() { return 0; }'
        echo 'start_kiosk_exit_hotkey /opt/YARG/ proceso'
        echo 'wait'
    } > "$BATS_TEST_TMPDIR/a.sh"
    # El script solo arranca si existe: se sustituye la ruta fija por una de prueba.
    sed -i "s|/usr/local/bin/kiosk-exit-hotkey.py|$BATS_TEST_TMPDIR/kiosk-exit-hotkey.py|" "$BATS_TEST_TMPDIR/a.sh"
    touch "$BATS_TEST_TMPDIR/kiosk-exit-hotkey.py"

    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" KIOSK_DBUS_SESSION_STARTED=1 \
        run bash "$BATS_TEST_TMPDIR/a.sh"
    [ "$status" -eq 0 ]
    grep -q "kiosk-exit-hotkey.py /opt/YARG/ proceso" "$calls"
}

@test "el atajo de salida distingue rutas (-f con prefijo) de nombres exactos (-x)" {
    command -v python3 >/dev/null || skip "python3 no esta instalado"
    local script="$BATS_TEST_TMPDIR/kiosk-exit-hotkey.py"
    printf '%s\n' "$KIOSK_EXIT_HOTKEY_TEMPLATE" > "$script"

    run python3 - "$script" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hotkey", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.match_args("/opt/YARG/") == ["-f", "^/opt/YARG/"]
assert m.match_args("rpcs3") == ["-x", "rpcs3"]
PY
    [ "$status" -eq 0 ]
}

# --- rendimiento y updaters compartidos -----------------------------------------

@test "las tres rutas usan configure_kiosk_performance y no quedan copias propias" {
    grep -Fq 'configure_kiosk_performance YARG' install-cage-yarg.sh
    grep -Fq 'configure_kiosk_performance "Clone Hero"' install-cage-clonehero.sh
    grep -Fq 'configure_kiosk_performance RPCS3' install-cage-rpcs3.sh
    run grep -rn 'configure_yarg_performance\|configure_clonehero_performance\|configure_rpcs3_performance' lib install-cage-*.sh
    [ "$status" -ne 0 ]
}

@test "update-yarg y update-clonehero no descargan si ya esta la ultima version y aceptan --force" {
    for f in lib/yarg.sh lib/clonehero.sh; do
        grep -Fq 'URL_MARK=' "$f"
        grep -Fq '[[ "\${1:-}" == "--force" ]]' "$f"
        grep -Fq '.install-url' "$f"
    done
}

@test "YARG y Clone Hero exigen un disco minimo configurable" {
    grep -Fq 'check_disk "$DISK_DEVICE" "$YARG_MIN_DISK_GB"' install-cage-yarg.sh
    grep -Fq 'check_disk "$DISK_DEVICE" "$CLONEHERO_MIN_DISK_GB"' install-cage-clonehero.sh
    grep -q '^YARG_MIN_DISK_GB=' .env.example
    grep -q '^CLONEHERO_MIN_DISK_GB=' .env.example
}

# --- menu de mantenimiento ---------------------------------------------------

@test "el menu es Bash valido, sin marcadores, con titulo y subrayado del mismo largo" {
    kiosk_menu_script "Clone Hero" "Volver a Clone Hero" "Actualizar Clone Hero" /usr/local/bin/update-clonehero \
        > "$BATS_TEST_TMPDIR/m.sh"
    bash -n "$BATS_TEST_TMPDIR/m.sh"
    ! grep -q '__KIOSK_[A-Z_]*__' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq 'Menu de mantenimiento Clone Hero' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '================================' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '5) Volver a Clone Hero' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '6) Actualizar Clone Hero' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '7) Reiniciar Kiosko' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '8) Apagar Kiosko' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fq 'UPDATE_COMMAND="/usr/local/bin/update-clonehero"' "$BATS_TEST_TMPDIR/m.sh"
}

@test "una opcion extra desplaza actualizar, reiniciar y apagar" {
    kiosk_menu_script RPCS3 "Volver al juego" "Actualizar RPCS3" /usr/local/bin/update-rpcs3 \
        --extra-label "Abrir RPCS3" --extra-code '            echo extra' > "$BATS_TEST_TMPDIR/m.sh"
    bash -n "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '6) Abrir RPCS3' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '7) Actualizar RPCS3' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '8) Reiniciar Kiosko' "$BATS_TEST_TMPDIR/m.sh"
    grep -Fxq '9) Apagar Kiosko' "$BATS_TEST_TMPDIR/m.sh"
}

@test "kiosk_menu_script rechaza opciones desconocidas" {
    run kiosk_menu_script A B C D --nada x
    [ "$status" -eq 1 ]
}

# Ejecuta el menu generado con una opcion y registra los comandos con sudo.
run_menu() { # opcion [args de kiosk_menu_script...]
    local option="$1"
    shift
    kiosk_menu_script "$@" > "$BATS_TEST_TMPDIR/m.sh"
    stub clear 'true'
    stub sudo 'echo "sudo $*" >> "$BATS_TEST_TMPDIR/calls"'
    : > "$BATS_TEST_TMPDIR/calls"
    PATH="$STUBS:$PATH" XDG_RUNTIME_DIR="$BATS_TEST_TMPDIR" BATS_TEST_TMPDIR="$BATS_TEST_TMPDIR" \
        run bash "$BATS_TEST_TMPDIR/m.sh" <<< "$option"
}

@test "el menu reinicia el servicio con la opcion 7 y apaga con la 8" {
    run_menu 7 YARG "Volver a YARG" "Actualizar YARG Stable" /usr/local/bin/update-yarg
    [ "$status" -eq 0 ]
    grep -Fxq 'sudo systemctl restart cage-kiosk.service' "$BATS_TEST_TMPDIR/calls"

    run_menu 8 YARG "Volver a YARG" "Actualizar YARG Stable" /usr/local/bin/update-yarg
    [ "$status" -eq 0 ]
    grep -Fxq 'sudo systemctl poweroff' "$BATS_TEST_TMPDIR/calls"
}

@test "la opcion de actualizar llama al comando indicado" {
    stub update-app 'exit 0'
    # 6 = actualizar, Enter para la pausa y 5 para volver.
    run_menu $'6\n\n5' App "Volver" "Actualizar App" "$STUBS/update-app"
    [ "$status" -eq 0 ]
    grep -Fxq "sudo $STUBS/update-app" "$BATS_TEST_TMPDIR/calls"
}

@test "la opcion extra y su setup se ejecutan en el menu" {
    run_menu 6 RPCS3 "Volver al juego" "Actualizar RPCS3" /usr/local/bin/update-rpcs3 \
        --setup 'GUI_FLAG="$XDG_RUNTIME_DIR/gui-flag"' \
        --extra-label "Abrir RPCS3" --extra-code '            touch "$GUI_FLAG"
            exit 0'
    [ "$status" -eq 0 ]
    [ -e "$BATS_TEST_TMPDIR/gui-flag" ]
}

# --- servicio systemd --------------------------------------------------------

@test "la unidad de cage-kiosk.service usa usuario, uid y wrapper indicados" {
    run kiosk_service_unit "Kiosk YARG con Cage" /usr/local/bin/run-yarg.sh player 1001
    [ "$status" -eq 0 ]
    [[ "$output" == *"Description=Kiosk YARG con Cage"* ]]
    [[ "$output" == *"User=player"* ]]
    [[ "$output" == *"Environment=XDG_RUNTIME_DIR=/run/user/1001"* ]]
    [[ "$output" == *"ExecStart=/usr/bin/dbus-run-session -- /usr/local/bin/run-yarg.sh"* ]]
    [[ "$output" == *"ExecStartPre=+/usr/bin/chown player:player /run/user/1001"* ]]
    [[ "$output" != *"LimitMEMLOCK"* ]]
}

@test "las lineas extra de la unidad quedan dentro de [Service]" {
    kiosk_service_unit "Kiosk RPCS3 con Cage" /usr/local/bin/run-rpcs3.sh k 1000 "LimitMEMLOCK=infinity" \
        > "$BATS_TEST_TMPDIR/u"
    local service_line extra_line install_line
    service_line=$(grep -n '^\[Service\]' "$BATS_TEST_TMPDIR/u" | cut -d: -f1)
    extra_line=$(grep -n '^LimitMEMLOCK=infinity$' "$BATS_TEST_TMPDIR/u" | cut -d: -f1)
    install_line=$(grep -n '^\[Install\]' "$BATS_TEST_TMPDIR/u" | cut -d: -f1)
    [ "$service_line" -lt "$extra_line" ]
    [ "$extra_line" -lt "$install_line" ]
}

@test "los instaladores cargan kiosk_runtime.sh y ningun modulo redefine el servicio" {
    local s
    for s in yarg clonehero rpcs3; do
        grep -Fq 'source "$SCRIPT_DIR/lib/kiosk_runtime.sh"' install-cage-$s.sh
        bash -n install-cage-$s.sh
    done
    ! grep -Fq 'cat > /mnt/etc/systemd/system/cage-kiosk.service' lib/cage.sh lib/clonehero.sh lib/rpcs3.sh
}
