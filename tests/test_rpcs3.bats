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
        "RPCS3_QT_PLATFORM=" "RPCS3_HOME=$BATS_TEST_TMPDIR/home"
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
