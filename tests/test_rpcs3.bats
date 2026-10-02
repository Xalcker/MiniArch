#!/usr/bin/env bats

# Pruebas del camino Cage/RPCS3 (lib/rpcs3.sh e install-cage-rpcs3.sh).

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    source lib/common.sh
    source lib/rpcs3.sh
}

render_wrapper() {
    rpcs3_render "$RPCS3_WRAPPER_TEMPLATE" \
        "RPCS3_GAMES_DIR=$1" "RPCS3_GAME_PATH=${2:-}" \
        "RPCS3_GAME_MATCH=Rock Band 3" "RPCS3_EXIT_MENU=always" \
        "RPCS3_QT_PLATFORM=" "RPCS3_AUDIO_VOLUME=1.0" "RPCS3_HOME=$BATS_TEST_TMPDIR/home"
}

@test "rpcs3_render sustituye todas las apariciones sin interpretar & # \\ ni /" {
    run rpcs3_render "a=__A__ b=__B__ otra=__A__" 'A=https://x/y?a=1&b=2#f' 'B=linux.*\.AppImage$'
    [ "$status" -eq 0 ]
    [ "$output" = 'a=https://x/y?a=1&b=2#f b=linux.*\.AppImage$ otra=https://x/y?a=1&b=2#f' ]
}

@test "rpcs3_pick_asset_url elige el AppImage x86_64 y no el aarch64" {
    local json='{"assets":[
      {"browser_download_url": "https://h/rpcs3-v0.0.43-1_linux_aarch64.AppImage"},
      {"browser_download_url": "https://h/rpcs3-v0.0.43-1_linux64.AppImage"}]}'
    run rpcs3_pick_asset_url "$json" 'linux64.*\.AppImage$'
    [ "$output" = "https://h/rpcs3-v0.0.43-1_linux64.AppImage" ]
}

@test "resolve_rpcs3_download_url respeta RPCS3_URL y no consulta la API" {
    curl() { echo "no deberia llamarse" >&2; return 1; }
    RPCS3_URL="https://ejemplo/rpcs3.AppImage"
    run resolve_rpcs3_download_url
    [ "$status" -eq 0 ]
}

@test "resolve_rpcs3_download_url falla si el release no trae AppImage" {
    curl() { echo '{"assets":[{"browser_download_url": "https://h/notas.txt"}]}'; }
    RPCS3_URL="" RPCS3_API_URL="https://api" RPCS3_ASSET_REGEX='linux64.*\.AppImage$'
    run resolve_rpcs3_download_url
    [ "$status" -eq 1 ]
    [[ "$output" == *"No se encontro un AppImage"* ]]
}

# --- find_game del wrapper ---------------------------------------------------

# Carga find_game() desde la plantilla del wrapper, con rutas de prueba.
load_find_game() {
    local games="$1" game_path="${2:-}"
    render_wrapper "$games" "$game_path" > "$BATS_TEST_TMPDIR/wrapper.sh"
    RPCS3_GAMES_DIR="$games"
    RPCS3_GAME_PATH="$game_path"
    RPCS3_GAME_MATCH="Rock Band 3"
    RPCS3_CONFIG_DIR="$BATS_TEST_TMPDIR/cfg"
    eval "$(sed -n '/^find_game() {/,/^}/p' "$BATS_TEST_TMPDIR/wrapper.sh")"
}

make_game() { # dir titulo
    mkdir -p "$1/USRDIR"
    printf 'xx\0TITLE\0%s\0yy' "$2" > "$1/PARAM.SFO"
    : > "$1/USRDIR/EBOOT.BIN"
}

@test "find_game encuentra el juego de disco (PS3_GAME) por el titulo del PARAM.SFO" {
    local games="$BATS_TEST_TMPDIR/games"
    make_game "$games/Otro/PS3_GAME" "Guitar Hero"
    make_game "$games/RB3/PS3_GAME" "Rock Band 3"
    load_find_game "$games"
    run find_game
    [ "$output" = "$games/RB3/PS3_GAME/USRDIR/EBOOT.BIN" ]
}

@test "find_game encuentra el juego instalado en dev_hdd0/game" {
    local games="$BATS_TEST_TMPDIR/games"
    mkdir -p "$games"
    make_game "$BATS_TEST_TMPDIR/cfg/dev_hdd0/game/BLUS00000" "ROCK BAND 3"
    load_find_game "$games"
    run find_game
    [ "$output" = "$BATS_TEST_TMPDIR/cfg/dev_hdd0/game/BLUS00000/USRDIR/EBOOT.BIN" ]
}

@test "find_game no devuelve nada si no hay juego" {
    local games="$BATS_TEST_TMPDIR/games"
    make_game "$games/Otro/PS3_GAME" "Guitar Hero"
    load_find_game "$games"
    run find_game
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "find_game encuentra un .iso por nombre, sin distinguir mayusculas" {
    local games="$BATS_TEST_TMPDIR/games"
    mkdir -p "$games"
    : > "$games/Otro Juego.iso"
    : > "$games/rock band 3 (USA).DEC.ISO"
    load_find_game "$games"
    run find_game
    [ "$output" = "$games/rock band 3 (USA).DEC.ISO" ]
}

@test "find_game prefiere el .iso al paquete instalado en dev_hdd0/game (parche RB3DX)" {
    local games="$BATS_TEST_TMPDIR/games"
    mkdir -p "$games"
    : > "$games/Rock Band 3.iso"
    make_game "$BATS_TEST_TMPDIR/cfg/dev_hdd0/game/BLUS30463" "Rock Band 3"
    load_find_game "$games"
    run find_game
    [ "$output" = "$games/Rock Band 3.iso" ]
}

@test "find_game prefiere el juego en carpeta al instalado en dev_hdd0/game" {
    local games="$BATS_TEST_TMPDIR/games"
    make_game "$games/RB3/PS3_GAME" "Rock Band 3"
    make_game "$BATS_TEST_TMPDIR/cfg/dev_hdd0/game/BLUS30463" "Rock Band 3"
    load_find_game "$games"
    run find_game
    [ "$output" = "$games/RB3/PS3_GAME/USRDIR/EBOOT.BIN" ]
}

@test "find_game usa RPCS3_GAME_PATH si existe y lo ignora si no existe" {
    local games="$BATS_TEST_TMPDIR/games" f="$BATS_TEST_TMPDIR/EBOOT.BIN"
    mkdir -p "$games"; : > "$f"
    load_find_game "$games" "$f"
    run find_game
    [ "$output" = "$f" ]

    load_find_game "$games" "$BATS_TEST_TMPDIR/no-existe"
    run find_game
    [ -z "$output" ]
}

# --- updater -----------------------------------------------------------------

make_update_script() {
    local dir="$BATS_TEST_TMPDIR/upd"
    mkdir -p "$dir/bin"
    rpcs3_render "$RPCS3_UPDATE_TEMPLATE" \
        "RPCS3_URL=https://h/viejo_linux64.AppImage" \
        "RPCS3_API_URL=https://api" \
        'RPCS3_ASSET_REGEX=linux64.*\.AppImage$' \
        "OWNER=$(id -un)" > "$dir/update-rpcs3"
    sed -i -e "s#/opt/RPCS3#$dir/opt#g" -e 's#if \[\[ \${EUID} -ne 0 \]\]#if false#' \
        -e "s#/var/tmp/update-rpcs3#$dir/work#" -e 's#^chown -R .*#true#' "$dir/update-rpcs3"
    # curl de prueba: la API devuelve un release y la descarga copia un AppImage falso.
    cat > "$dir/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""
while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done
if [[ -n "$out" ]]; then
    cp "$APPIMAGE_FAKE" "$out"
else
    echo '{"assets":[{"browser_download_url": "https://h/nuevo_linux64.AppImage"}]}'
fi
SH
    chmod +x "$dir/bin/curl"
}

# $1: comandos que ejecuta el AppImage falso al recibir --appimage-extract
fake_appimage() {
    {
        echo '#!/usr/bin/env bash'
        echo 'if [[ "$1" == "--appimage-extract" ]]; then'
        echo "$1"
        echo 'fi'
    } > "$BATS_TEST_TMPDIR/fake.AppImage"
    export APPIMAGE_FAKE="$BATS_TEST_TMPDIR/fake.AppImage"
}

@test "update-rpcs3 reemplaza la instalacion con la version nueva" {
    make_update_script
    mkdir -p "$BATS_TEST_TMPDIR/upd/opt"
    echo viejo > "$BATS_TEST_TMPDIR/upd/opt/version"
    fake_appimage 'mkdir -p squashfs-root; printf "#!/bin/sh\n" > squashfs-root/AppRun; chmod +x squashfs-root/AppRun; echo nuevo > squashfs-root/version'
    PATH="$BATS_TEST_TMPDIR/upd/bin:$PATH" run bash "$BATS_TEST_TMPDIR/upd/update-rpcs3"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/upd/opt/version")" = "nuevo" ]
    [ ! -e "$BATS_TEST_TMPDIR/upd/opt.old" ]
}

@test "update-rpcs3 conserva la instalacion si el AppImage nuevo no trae AppRun" {
    make_update_script
    mkdir -p "$BATS_TEST_TMPDIR/upd/opt"
    echo viejo > "$BATS_TEST_TMPDIR/upd/opt/version"
    fake_appimage 'mkdir -p squashfs-root; echo roto > squashfs-root/version'
    PATH="$BATS_TEST_TMPDIR/upd/bin:$PATH" run bash "$BATS_TEST_TMPDIR/upd/update-rpcs3"
    [ "$status" -ne 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/upd/opt/version")" = "viejo" ]
}

# --- wrapper y menu ----------------------------------------------------------

@test "el wrapper y el menu generados son Bash valido y sin marcadores sin sustituir" {
    render_wrapper "/home/k/Games" > "$BATS_TEST_TMPDIR/w.sh"
    bash -n "$BATS_TEST_TMPDIR/w.sh"
    ! grep -q '__[A-Z0-9_]*__' "$BATS_TEST_TMPDIR/w.sh"
    printf '%s\n' "$RPCS3_MENU_TEMPLATE" > "$BATS_TEST_TMPDIR/m.sh"
    bash -n "$BATS_TEST_TMPDIR/m.sh"
}

@test "el wrapper lanza el juego con --no-gui y abre la GUI cuando falta el juego o se pide" {
    render_wrapper "/home/k/Games" > "$BATS_TEST_TMPDIR/w.sh"
    grep -Fq -- '--no-gui "$GAME"' "$BATS_TEST_TMPDIR/w.sh"
    grep -Fq 'GUI_FLAG' "$BATS_TEST_TMPDIR/w.sh"
    grep -Fq 'rpcs3-open-gui' <<< "$RPCS3_MENU_TEMPLATE"
}

# --- instalador y validacion ---------------------------------------------------

@test "install-cage-rpcs3.sh carga common.sh y rpcs3.sh y exige el minimo de disco" {
    grep -Fq 'source "$SCRIPT_DIR/lib/common.sh"' install-cage-rpcs3.sh
    grep -Fq 'source "$SCRIPT_DIR/lib/rpcs3.sh"' install-cage-rpcs3.sh
    grep -Fq 'check_disk "$DISK_DEVICE" "$RPCS3_MIN_DISK_GB"' install-cage-rpcs3.sh
    grep -Fq 'RPCS3_MIN_DISK_GB="${RPCS3_MIN_DISK_GB:-32}"' install-cage-rpcs3.sh
    bash -n install-cage-rpcs3.sh
}

@test "check_disk acepta un minimo opcional y por defecto sigue pidiendo 16GB" {
    grep -Fq 'local min_gb="${2:-16}"' lib/validation.sh
    grep -Fq 'Se requieren al menos ${min_gb}GB' lib/validation.sh
}

@test "find_game encuentra un volcado de disco agregado desde la GUI (dev_hdd0/disc)" {
    local games="$BATS_TEST_TMPDIR/games"
    mkdir -p "$games"
    make_game "$BATS_TEST_TMPDIR/cfg/dev_hdd0/disc/RockBand3/PS3_GAME" "Rock Band 3"
    load_find_game "$games"
    run find_game
    [ "$output" = "$BATS_TEST_TMPDIR/cfg/dev_hdd0/disc/RockBand3/PS3_GAME/USRDIR/EBOOT.BIN" ]
}

@test "el servicio fija LimitMEMLOCK=infinity para el requisito de 2 GiB de RPCS3" {
    grep -Fq 'LimitMEMLOCK=infinity' lib/rpcs3.sh
}

# --- atajo de salida ----------------------------------------------------------

@test "el wrapper arranca el atajo de salida" {
    run render_wrapper "$BATS_TEST_TMPDIR/games"
    [[ "$output" == *"start_exit_hotkey"* ]]
    [[ "$output" == *"rpcs3-exit-hotkey.py"* ]]
}

@test "el script del atajo de salida compila y detecta las combinaciones" {
    command -v python3 >/dev/null || skip "python3 no esta instalado"

    local script="$BATS_TEST_TMPDIR/rpcs3-exit-hotkey.py"
    printf '%s\n' "$RPCS3_EXIT_HOTKEY_TEMPLATE" > "$script"

    run python3 - "$script" <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("hotkey", sys.argv[1])
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
assert m.combo_pressed({"kbd"}, {29, 56, 16}) == "teclado"
assert m.combo_pressed({"kbd"}, {29, 16}) is None
assert m.combo_pressed({"pad"}, {316, 315}) == "control"
assert m.combo_pressed({"pad"}, {315}) is None
assert m.classify((1 << 316) | (1 << 315), "Xbox Controller") == {"pad"}
assert m.classify((1 << 316) | (1 << 315), "sanjay900 Santroller") == set()
PY
    [ "$status" -eq 0 ]
}

@test "install_rpcs3_exit_hotkey no instala nada con RPCS3_EXIT_HOTKEY=false" {
    RPCS3_EXIT_HOTKEY=false
    run install_rpcs3_exit_hotkey
    [ "$status" -eq 0 ]
    [[ "$output" == *"omitido"* ]]
}

# --- perfiles RB3DX -----------------------------------------------------------

@test "el adaptador de perfiles RB3DX reescribe rutas, Shader Mode y XAudio2 para Linux" {
    command -v python3 >/dev/null || skip "python3 no esta instalado"

    local fix="$BATS_TEST_TMPDIR/fix.py" zip="$BATS_TEST_TMPDIR/perfil.zip"
    printf '%s\n' "$RPCS3_PROFILE_FIX_TEMPLATE" > "$fix"

    python3 - "$zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("minimum/", "")
    z.writestr("minimum/config/custom_configs/config_BLUS30463.yml",
               "Video:\n  Renderer: Vulkan\n  Shader Mode: Async Shader Recompiler\nAudio:\n  Renderer: XAudio2\n")
    z.writestr("minimum/dev_hdd0/game/BLUS30463/USRDIR/dx_high_memory.dta", "(dx_high_memory 190000000)\n")
PY

    run python3 "$fix" "$zip"
    [ "$status" -eq 0 ]

    run python3 - "$zip" <<'PY'
import sys, zipfile
z = zipfile.ZipFile(sys.argv[1])
assert sorted(z.namelist()) == ["custom_configs/config_BLUS30463.yml", "dev_hdd0/game/BLUS30463/USRDIR/dx_high_memory.dta"], z.namelist()
yml = z.read("custom_configs/config_BLUS30463.yml").decode()
assert "Shader Mode: Async Recompiler with Shader Interpreter" in yml
assert "Renderer: Vulkan" in yml and "Renderer: Cubeb" in yml and "XAudio2" not in yml
PY
    [ "$status" -eq 0 ]
}

@test "install_rpcs3_dependencies instala python para el adaptador y el atajo de salida" {
    run grep -n "pulsemixer python" lib/rpcs3.sh
    [ "$status" -eq 0 ]
}

# --- adaptador de dos microfonos -----------------------------------------------

@test "el wrapper asigna los microfonos USB por jugador antes de cada arranque" {
    run render_wrapper "$BATS_TEST_TMPDIR/games"
    [[ "$output" == *"setup_mics"* ]]
    [[ "$output" == *"module-remap-source"* ]]
    [[ "$output" == *"source_name=mic_p"* && "$output" == *"device.description=Mic_P"* ]]
}

# Ejecuta setup_mics() del wrapper con un pactl simulado; devuelve en $output
# los comandos pactl que habria ejecutado.
run_setup_mics() {
    local sources="$1" log="$BATS_TEST_TMPDIR/pactl.log"
    : > "$log"
    render_wrapper "$BATS_TEST_TMPDIR/games" > "$BATS_TEST_TMPDIR/wrapper.sh"
    run bash -c '
        SOURCES="$1"; LOG="$2"
        RPCS3_MIC_SINGLE_MATCH=Logitech; RPCS3_MIC_SPLIT_MATCH="USBMIC|SingStar"
        RPCS3_MIC_VOLUME=35%; RPCS3_MIC_SINGLE_VOLUME=75%; XDG_RUNTIME_DIR="$3"
        pactl() {
            if [[ "$1 $2" == "list short" ]]; then
                [[ "$3" == sources ]] && printf "%s\n" "$SOURCES"
                return 0
            fi
            echo "pactl $*" >> "$LOG"
        }
        eval "$(sed -n "/^setup_mics() {/,/^}/p" "$4")"
        setup_mics
        cat "$LOG"
    ' _ "$sources" "$log" "$BATS_TEST_TMPDIR" "$BATS_TEST_TMPDIR/wrapper.sh"
}

HD_SRC=$'54\talsa_input.pci-0000_0b_00.6.analog-stereo\tPipeWire\ts32le 2ch 48000Hz\tSUSPENDED'
SS_SRC=$'51\talsa_input.usb-Nam_Tai_E_E_Products_Ltd._USBMIC_Serial__1-00.analog-stereo\tPipeWire\ts16le 2ch 48000Hz\tSUSPENDED'
LG_SRC=$'123\talsa_input.usb-Logitech_Logitech_USB_Microphone-00.mono-fallback\tPipeWire\ts16le 1ch 48000Hz\tSUSPENDED'

@test "setup_mics: Logitech = P1 y el SingStar azul/rojo = P2/P3" {
    run_setup_mics "$HD_SRC"$'\n'"$SS_SRC"$'\n'"$LG_SRC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"set-source-volume alsa_input.usb-Logitech"*" 75%"* ]]
    [[ "$output" == *"set-source-volume alsa_input.usb-Nam_Tai"*" 35%"* ]]
    [[ "$output" == *"master=alsa_input.usb-Logitech"*"source_name=mic_p1"*"master_channel_map=mono"*"description=Mic_P1"* ]]
    [[ "$output" == *"source_name=mic_p2"*"master_channel_map=front-left"*"description=Mic_P2"* ]]
    [[ "$output" == *"source_name=mic_p3"*"master_channel_map=front-right"*"description=Mic_P3"* ]]
}

@test "setup_mics: solo el SingStar queda como P1 (izquierdo) y P2 (derecho)" {
    run_setup_mics "$HD_SRC"$'\n'"$SS_SRC"
    [ "$status" -eq 0 ]
    [[ "$output" == *"source_name=mic_p1"*"master_channel_map=front-left"* ]]
    [[ "$output" == *"source_name=mic_p2"*"master_channel_map=front-right"* ]]
    [[ "$output" != *"mic_p3"* ]]
}

@test "setup_mics: sin microfonos USB no hace nada" {
    run_setup_mics "$HD_SRC"
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "el adaptador de perfiles con --mics fija Microphone Type Standard y las dos fuentes" {
    command -v python3 >/dev/null || skip "python3 no esta instalado"

    local fix="$BATS_TEST_TMPDIR/fix.py" zip="$BATS_TEST_TMPDIR/perfil.zip"
    printf '%s\n' "$RPCS3_PROFILE_FIX_TEMPLATE" > "$fix"

    python3 - "$zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("p/config/custom_configs/config_BLUS30463.yml",
               "Audio:\n  Microphone Type: Null\n  Microphone Devices: \"@@@@@@@@@@@@\"\n")
PY

    run python3 "$fix" "$zip" --mics
    [ "$status" -eq 0 ]

    run python3 - "$zip" <<'PY'
import sys, zipfile
yml = zipfile.ZipFile(sys.argv[1]).read("custom_configs/config_BLUS30463.yml").decode()
assert "Microphone Type: Standard" in yml
assert 'Microphone Devices: "Mic_P1@@@Mic_P2@@@Mic_P3@@@@@@"' in yml
PY
    [ "$status" -eq 0 ]
}

# --- bateria electronica MIDI ---------------------------------------------------

@test "el wrapper detecta la bateria MIDI antes de cada arranque" {
    run render_wrapper "$BATS_TEST_TMPDIR/games"
    [[ "$output" == *"setup_midi_drums"* ]]
}

# Ejecuta setup_midi_drums() del wrapper con un aconnect simulado ($1 = salida de
# "aconnect -l") sobre una configuracion de juego de prueba.
run_setup_midi_drums() {
    local cfg_dir="$BATS_TEST_TMPDIR/rpcs3" ac="$BATS_TEST_TMPDIR/aconnect.out"
    mkdir -p "$cfg_dir/custom_configs"
    printf '%s\n' "$1" > "$ac"
    if [[ ! -f "$cfg_dir/custom_configs/config_BLUS30463.yml" ]]; then
        printf 'Input/Output:\n  Emulated Midi devices: Keyboardßßß@@@Keyboardßßß@@@Keyboardßßß@@@\n  Otro: 1\n' \
            > "$cfg_dir/custom_configs/config_BLUS30463.yml"
    fi
    render_wrapper "$BATS_TEST_TMPDIR/games" > "$BATS_TEST_TMPDIR/wrapper.sh"
    run bash -c '
        RPCS3_MIDI_DRUMS=true; RPCS3_CONFIG_DIR="$1"; AC="$2"
        aconnect() { cat "$AC"; }
        eval "$(sed -n "/^setup_midi_drums() {/,/^}/p" "$3")"
        setup_midi_drums
        grep "Emulated Midi" "$1/custom_configs/config_BLUS30463.yml"
    ' _ "$cfg_dir" "$ac" "$BATS_TEST_TMPDIR/wrapper.sh"
}

ACONNECT_NITRO="client 0: 'System' [type=kernel]
    0 'Timer           '
client 14: 'Midi Through' [type=kernel]
    0 'Midi Through Port-0'
client 32: 'Alesis Nitro' [type=kernel,card=4]
    0 'Alesis Nitro MIDI 1'
client 142: 'PipeWire-System' [type=user,pid=638]
    0 'input           '"

@test "setup_midi_drums escribe el puerto del e-kit como Drums con su numero de cliente" {
    run_setup_midi_drums "$ACONNECT_NITRO"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Emulated Midi devices: Drumsßßß"* ]]
    [[ "$output" == *"Drumsßßß""Alesis Nitro:Alesis Nitro MIDI 1 32:0@@@Keyboardßßß@@@Keyboardßßß@@@"* ]]
}

@test "setup_midi_drums sigue al e-kit si cambia su numero de cliente" {
    run_setup_midi_drums "$ACONNECT_NITRO"
    run_setup_midi_drums "${ACONNECT_NITRO//client 32:/client 36:}"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Alesis Nitro MIDI 1 36:0@@@"* ]]
}

@test "setup_midi_drums no toca la configuracion si no hay dispositivo MIDI de tarjeta" {
    run_setup_midi_drums "client 14: 'Midi Through' [type=kernel]
    0 'Midi Through Port-0'"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Emulated Midi devices: Keyboardßßß@@@Keyboardßßß@@@Keyboardßßß@@@"* ]]
}

@test "install_rpcs3_midi_config no hace nada sin RPCS3_MIDI_NOTE_OVERRIDE" {
    RPCS3_MIDI_NOTE_OVERRIDE=""
    run install_rpcs3_midi_config
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "el adaptador de perfiles con --audio-buffer fija Desired Audio Buffer Duration" {
    command -v python3 >/dev/null || skip "python3 no esta instalado"

    local fix="$BATS_TEST_TMPDIR/fix.py" zip="$BATS_TEST_TMPDIR/perfil.zip"
    printf '%s\n' "$RPCS3_PROFILE_FIX_TEMPLATE" > "$fix"

    python3 - "$zip" <<'PY'
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "w") as z:
    z.writestr("p/config/custom_configs/config_BLUS30463.yml",
               "Audio:\n  Enable Buffering: true\n  Desired Audio Buffer Duration: 100\n")
PY

    run python3 "$fix" "$zip" --audio-buffer=32
    [ "$status" -eq 0 ]

    run python3 - "$zip" <<'PY'
import sys, zipfile
yml = zipfile.ZipFile(sys.argv[1]).read("custom_configs/config_BLUS30463.yml").decode()
assert "Desired Audio Buffer Duration: 32" in yml
assert "Enable Buffering: true" in yml
PY
    [ "$status" -eq 0 ]
}

# --- control del jugador 1 --------------------------------------------------------

@test "la plantilla de entrada deja el jugador 1 en SDL y los demas en Null" {
    [ -f assets/rpcs3-input-Default.yml ]
    run grep -nE '^  (Handler|Device):' assets/rpcs3-input-Default.yml
    [ "${lines[0]}" = "2:  Handler: SDL" ]
    [ "${lines[1]}" = "3:  Device: Xbox Series X Controller 1" ]
    [[ "${lines[2]}" == *'Handler: "Null"'* ]]
}

@test "install_rpcs3_input_config no hace nada con RPCS3_PAD_CONFIG=false" {
    RPCS3_PAD_CONFIG=false
    run install_rpcs3_input_config
    [ "$status" -eq 0 ]
    [[ "$output" == *"omitida"* ]]
}

@test "install_rpcs3_input_config escribe el dispositivo indicado sin interpretar caracteres especiales" {
    local dest="$BATS_TEST_TMPDIR/root"
    mkdir -p "$dest"

    # La funcion escribe bajo /mnt; se ejecuta una copia apuntando a un directorio de prueba.
    local fn
    fn="$(declare -f install_rpcs3_input_config)"
    fn="${fn//\/mnt\//$dest/}"
    fn="${fn//arch-chroot \/mnt/true}"
    eval "$fn"
    run_quiet() { :; }

    SCRIPT_DIR="$PWD" KIOSK_USER=kiosk RPCS3_PAD_DEVICE="Xbox Series S|X Controller & Co/1" \
        install_rpcs3_input_config

    local yml="$dest/home/kiosk/.config/rpcs3/input_configs/global/Default.yml"
    grep -qxF '  Device: Xbox Series S|X Controller & Co/1' "$yml"
    grep -qxF 'Active Configurations:' "$dest/home/kiosk/.config/rpcs3/input_configs/active_input_configurations.yml"
}

@test "install_rpcs3_input_config no pisa una configuracion existente" {
    local dest="$BATS_TEST_TMPDIR/root"
    mkdir -p "$dest/home/kiosk/.config/rpcs3/input_configs/global"
    echo "mio" > "$dest/home/kiosk/.config/rpcs3/input_configs/global/Default.yml"

    local fn
    fn="$(declare -f install_rpcs3_input_config)"
    fn="${fn//\/mnt\//$dest/}"
    fn="${fn//arch-chroot \/mnt/true}"
    eval "$fn"
    run_quiet() { :; }

    SCRIPT_DIR="$PWD" KIOSK_USER=kiosk install_rpcs3_input_config

    [ "$(cat "$dest/home/kiosk/.config/rpcs3/input_configs/global/Default.yml")" = "mio" ]
}
