#!/usr/bin/env bats

# Comportamiento de los wrappers run-yarg.sh y run-clonehero.sh: se generan con
# las funciones reales del instalador (apuntando /mnt a un directorio temporal)
# y se ejecutan con cage, PipeWire y aplay simulados.

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    export W="$BATS_TEST_TMPDIR/w"
    mkdir -p "$W/bin" "$W/mnt/usr/local/bin" "$W/run" "$W/opt/YARG" "$W/opt/CloneHero"
    : > "$W/run/pipewire-0"
    source lib/common.sh
    source lib/kiosk_runtime.sh
    source lib/cage.sh
    source lib/clonehero.sh
    install_kiosk_menu() { :; }

    export KIOSK_USER="$(id -un)" HOME="$W/home"
    export YARG_PERSISTENT_DATA_DIR="$W/data/yarg" CLONEHERO_DATA_DIR="$W/data/ch"
    export YARG_RELEASE_CHANNEL=stable YARG_SCREEN_WIDTH="" YARG_SCREEN_HEIGHT="" YARG_EXIT_MENU=never
    export CLONEHERO_SCREEN_WIDTH="" CLONEHERO_SCREEN_HEIGHT="" CLONEHERO_EXIT_MENU=never
    export YARG_FORCE_SOFTWARE_RENDER=false CLONEHERO_FORCE_SOFTWARE_RENDER=false
    unset YARG_AUDIO_VOLUME YARG_PIPEWIRE_QUANTUM CLONEHERO_AUDIO_VOLUME CLONEHERO_PIPEWIRE_QUANTUM
    fake_tools
}

# Herramientas simuladas. cage registra su invocacion y, en la segunda llamada a
# la app o en la primera al menu, mata al wrapper para cortar su bucle infinito.
fake_tools() {
    cat > "$W/bin/cage" <<'SH'
#!/bin/bash
echo "cage $*" >> "$W/cage.calls"
echo "env WLR=${WLR_RENDERER_ALLOW_SOFTWARE:-} GL=${LIBGL_ALWAYS_SOFTWARE:-}" >> "$W/cage.env"
case "$*" in
    *foot*) kill "$PPID" ;;
    *)
        n=$(( $(cat "$W/apps.count" 2>/dev/null || echo 0) + 1 ))
        echo "$n" > "$W/apps.count"
        [[ -n "${CAGE_STOP_AFTER:-}" && "$n" -ge "$CAGE_STOP_AFTER" ]] && kill "$PPID"
        ;;
esac
exit 0
SH
    printf '#!/bin/bash\necho "0 sink"\n' > "$W/bin/pactl"
    local t
    for t in pipewire wireplumber pipewire-pulse aplay; do
        printf '#!/bin/bash\nexit 0\n' > "$W/bin/$t"
    done
    chmod +x "$W/bin/"*
    : > "$W/cage.calls"
}

# Genera el wrapper con la funcion real del instalador y lo prepara para correr.
# Uso: gen_wrapper <funcion> <nombre> <dir-opt>
gen_wrapper() {
    local fn="$1" name="$2" opt="$3"
    # Solo reescribe /mnt precedido de espacio o comilla: es idempotente si la
    # funcion ya se reescribio en una llamada anterior.
    eval "$(declare -f "$fn" | sed "s#\([ \"]\)/mnt/#\1$W/mnt/#g")"
    "$fn"
    WRAPPER="$W/mnt/usr/local/bin/$name"
    [ -f "$WRAPPER" ]
    sed -i -e "s#/usr/bin/cage#$W/bin/cage#g" -e "s#$opt#$W$opt#g" "$WRAPPER"
}

run_wrapper() {
    run env PATH="$W/bin:$PATH" XDG_RUNTIME_DIR="$W/run" KIOSK_DBUS_SESSION_STARTED=1 \
        DBUS_SESSION_BUS_ADDRESS="" CAGE_STOP_AFTER="${CAGE_STOP_AFTER:-}" \
        timeout 60 bash "$WRAPPER"
}

make_yarg() {
    : > "$W/opt/YARG/YARG"
    chmod +x "$W/opt/YARG/YARG"
}

make_clonehero() {
    mkdir -p "$W/opt/CloneHero/sub"
    : > "$W/opt/CloneHero/sub/clonehero"
    chmod +x "$W/opt/CloneHero/sub/clonehero"
}

cage_app_calls() { grep -vc 'foot' "$W/cage.calls" || true; }

# --- run-yarg.sh -------------------------------------------------------------

@test "run-yarg.sh generado es Bash valido y no deja marcadores" {
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    bash -n "$WRAPPER"
    ! grep -q '__[A-Z_]*__' "$WRAPPER"
}

@test "run-yarg.sh lanza YARG con la carpeta de datos y sin resolucion si no se configura" {
    make_yarg
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    [ "$status" -eq 0 ]
    grep -Fq -- "cage -- $W/opt/YARG/YARG -persistent-data-path $W/data/yarg" "$W/cage.calls"
    ! grep -Fq -- "-screen-width" "$W/cage.calls"
}

@test "run-yarg.sh pasa la resolucion a pantalla completa cuando esta configurada" {
    make_yarg
    export YARG_SCREEN_WIDTH=1920 YARG_SCREEN_HEIGHT=1080
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    [ "$status" -eq 0 ]
    grep -Fq -- "-screen-width 1920 -screen-height 1080 -screen-fullscreen 1" "$W/cage.calls"
}

@test "run-yarg.sh con menu 'never' sale tras cerrar YARG sin abrir el menu" {
    make_yarg
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    [ "$status" -eq 0 ]
    [[ "$output" == *"menu deshabilitado"* ]]
    [ "$(wc -l < "$W/cage.calls")" -eq 1 ]
}

@test "run-yarg.sh con menu 'always' abre el menu de mantenimiento tras cerrar YARG" {
    make_yarg
    export YARG_EXIT_MENU=always
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    [[ "$output" == *"abriendo menu de mantenimiento"* ]]
    grep -Fq -- "cage -- /usr/bin/foot /usr/local/bin/kiosk-menu.sh" "$W/cage.calls"
}

@test "run-yarg.sh con menu 'restart' relanza YARG en lugar de abrir el menu" {
    make_yarg
    export YARG_EXIT_MENU=restart CAGE_STOP_AFTER=2
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    [[ "$output" == *"relanzando YARG"* ]]
    [ "$(cage_app_calls)" -eq 2 ]
    ! grep -Fq foot "$W/cage.calls"
}

@test "run-yarg.sh sin YARG instalado avisa y abre el menu" {
    export YARG_EXIT_MENU=always
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    [[ "$output" == *"No se encontro YARG"* ]]
    [ "$(cage_app_calls)" -eq 0 ]
    grep -Fq foot "$W/cage.calls"
}

@test "run-yarg.sh activa el render por software solo si se pide" {
    make_yarg
    export YARG_FORCE_SOFTWARE_RENDER=true
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    grep -Fq "env WLR=1 GL=1" "$W/cage.env"
}

@test "run-yarg.sh espera el sink de audio antes de lanzar la app" {
    make_yarg
    gen_wrapper install_cage_wrapper run-yarg.sh /opt/YARG
    run_wrapper
    local sink app
    sink="$(echo "$output" | grep -n 'esperando sink' | head -1 | cut -d: -f1)"
    app="$(echo "$output" | grep -n 'Iniciando YARG' | head -1 | cut -d: -f1)"
    [ -n "$sink" ] && [ -n "$app" ]
    [ "$sink" -lt "$app" ]
}

# --- run-clonehero.sh --------------------------------------------------------

@test "run-clonehero.sh generado es Bash valido y no deja marcadores" {
    gen_wrapper install_clonehero_cage_wrapper run-clonehero.sh /opt/CloneHero
    bash -n "$WRAPPER"
    ! grep -q '__[A-Z_]*__' "$WRAPPER"
}

@test "run-clonehero.sh encuentra el binario en un subdirectorio y fija persistentDataPath" {
    make_clonehero
    gen_wrapper install_clonehero_cage_wrapper run-clonehero.sh /opt/CloneHero
    run_wrapper
    [ "$status" -eq 0 ]
    grep -Fq -- "cage -- $W/opt/CloneHero/sub/clonehero -persistentDataPath $W/data/ch" "$W/cage.calls"
}

@test "run-clonehero.sh pasa la resolucion cuando esta configurada" {
    make_clonehero
    export CLONEHERO_SCREEN_WIDTH=1280 CLONEHERO_SCREEN_HEIGHT=720
    gen_wrapper install_clonehero_cage_wrapper run-clonehero.sh /opt/CloneHero
    run_wrapper
    grep -Fq -- "-screen-width 1280 -screen-height 720 -screen-fullscreen 1" "$W/cage.calls"
}

@test "run-clonehero.sh respeta los modos de salida restart y always" {
    make_clonehero
    export CLONEHERO_EXIT_MENU=restart CAGE_STOP_AFTER=2
    gen_wrapper install_clonehero_cage_wrapper run-clonehero.sh /opt/CloneHero
    run_wrapper
    [[ "$output" == *"relanzando Clone Hero"* ]]
    [ "$(cage_app_calls)" -eq 2 ]

    : > "$W/cage.calls"; rm -f "$W/apps.count"
    export CLONEHERO_EXIT_MENU=always CAGE_STOP_AFTER=
    gen_wrapper install_clonehero_cage_wrapper run-clonehero.sh /opt/CloneHero
    run_wrapper
    grep -Fq foot "$W/cage.calls"
}

@test "run-clonehero.sh sin Clone Hero instalado avisa y abre el menu" {
    export CLONEHERO_EXIT_MENU=always
    gen_wrapper install_clonehero_cage_wrapper run-clonehero.sh /opt/CloneHero
    run_wrapper
    [[ "$output" == *"No se encontro Clone Hero"* ]]
    [ "$(cage_app_calls)" -eq 0 ]
}
