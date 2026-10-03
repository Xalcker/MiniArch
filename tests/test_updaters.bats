#!/usr/bin/env bats

# Comportamiento de YARG y Clone Hero: resolucion de URLs contra un JSON de la
# API de GitHub y ejecucion real de los updaters generados (update-yarg y
# update-clonehero) con curl y unzip simulados. Nada toca la red ni /opt.

YARG_REGEX='linux.*(x86_64|x64|64).*\.zip'
CH_REGEX='linux.*(x86_64|x64|64|amd64).*(zip|tar\.xz|tar\.gz|appimage)$'

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    export W="$BATS_TEST_TMPDIR/w"
    mkdir -p "$W/bin" "$W/songs"
    printf 'zip falso' > "$W/pkg.zip"
    source lib/common.sh
    source lib/yarg.sh
    source lib/clonehero.sh
    # Los resolvers consultan la API a traves de github_api_get.
    github_api_get() { printf '%s\n' "$FAKE_JSON"; }
}

# JSON con la forma de la API de GitHub: el digest va antes de la URL del asset.
# Uso: make_json <digest-del-asset-linux> <nombre-del-asset-linux>
make_json() {
    cat <<EOF
{
  "assets": [
    {
      "name": "YARG_v1.0.0-Windows-x86_64.zip",
      "digest": "sha256:$(printf '1%.0s' {1..64})",
      "browser_download_url": "https://h/YARG_v1.0.0-Windows-x86_64.zip"
    },
    {
      "name": "$2",
      "digest": "sha256:$1",
      "browser_download_url": "https://h/$2"
    },
    {
      "name": "YARG_v1.0.0-MacOS.zip",
      "browser_download_url": "https://h/YARG_v1.0.0-MacOS.zip"
    }
  ]
}
EOF
}

# --- resolucion de URLs ------------------------------------------------------

@test "resolve_yarg_download_url elige el ZIP Linux y toma su digest" {
    local digest; digest="$(printf 'a%.0s' {1..64})"
    FAKE_JSON="$(make_json "$digest" YARG_v1.0.0-Linux-x86_64.zip)"
    YARG_RELEASE_CHANNEL=stable-latest
    YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX="$YARG_REGEX"
    YARG_URL=""
    resolve_yarg_download_url
    [ "$YARG_URL" = "https://h/YARG_v1.0.0-Linux-x86_64.zip" ]
    [ "$YARG_SHA256" = "$digest" ]
}

@test "resolve_yarg_download_url deja YARG_SHA256 vacio si el asset no publica digest" {
    FAKE_JSON='{
  "assets": [
    {
      "name": "YARG-Linux-x86_64.zip",
      "browser_download_url": "https://h/YARG-Linux-x86_64.zip"
    }
  ]
}'
    YARG_RELEASE_CHANNEL=nightly
    YARG_NIGHTLY_API_URL=https://api.invalid/n YARG_NIGHTLY_ASSET_REGEX="$YARG_REGEX"
    YARG_SHA256="viejo"
    resolve_yarg_download_url
    [ "$YARG_URL" = "https://h/YARG-Linux-x86_64.zip" ]
    [ -z "$YARG_SHA256" ]
}

@test "resolve_yarg_download_url usa el respaldo linux*.zip cuando el regex no coincide" {
    FAKE_JSON="$(make_json "$(printf 'b%.0s' {1..64})" YARG_v1.0.0-Linux-x86_64.zip)"
    YARG_RELEASE_CHANNEL=stable-latest
    YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX='nada-que-coincida'
    resolve_yarg_download_url
    [ "$YARG_URL" = "https://h/YARG_v1.0.0-Linux-x86_64.zip" ]
}

@test "resolve_yarg_download_url no elige un asset aarch64 aunque aparezca primero" {
    FAKE_JSON='{
  "assets": [
    {
      "name": "YARG-Linux-aarch64.zip",
      "browser_download_url": "https://h/YARG-Linux-aarch64.zip"
    },
    {
      "name": "YARG-Linux-arm64.zip",
      "browser_download_url": "https://h/YARG-Linux-arm64.zip"
    },
    {
      "name": "YARG-Linux-x86_64.zip",
      "browser_download_url": "https://h/YARG-Linux-x86_64.zip"
    }
  ]
}'
    YARG_RELEASE_CHANNEL=stable-latest
    YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX="$YARG_REGEX"
    resolve_yarg_download_url
    [ "$YARG_URL" = "https://h/YARG-Linux-x86_64.zip" ]
}

@test "resolve_yarg_download_url falla si solo hay assets ARM" {
    FAKE_JSON='{"assets":[{"browser_download_url": "https://h/YARG-Linux-aarch64.zip"}]}'
    YARG_RELEASE_CHANNEL=stable-latest
    YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX="$YARG_REGEX"
    run resolve_yarg_download_url
    [ "$status" -eq 1 ]
}

@test "resolve_clonehero_download_url no elige un asset arm64" {
    FAKE_JSON='{
  "assets": [
    {
      "name": "clonehero-linux-arm64.tar.gz",
      "browser_download_url": "https://h/clonehero-linux-arm64.tar.gz"
    },
    {
      "name": "clonehero-linux-x64.tar.gz",
      "browser_download_url": "https://h/clonehero-linux-x64.tar.gz"
    }
  ]
}'
    CLONEHERO_RELEASE_CHANNEL=latest
    CLONEHERO_API_URL=https://api.invalid/ch CLONEHERO_ASSET_REGEX="$CH_REGEX"
    resolve_clonehero_download_url
    [ "$CLONEHERO_URL" = "https://h/clonehero-linux-x64.tar.gz" ]
}

@test "resolve_yarg_download_url falla sin asset Linux" {
    FAKE_JSON='{"assets":[{"browser_download_url": "https://h/YARG-Windows.zip"}]}'
    YARG_RELEASE_CHANNEL=stable-latest
    YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX="$YARG_REGEX"
    run resolve_yarg_download_url
    [ "$status" -eq 1 ]
    grep -Fq "No se encontro asset Linux ZIP" "$LOG_FILE"
}

@test "resolve_yarg_download_url no consulta la API en el canal stable" {
    github_api_get() { echo "no deberia llamarse" >&2; return 1; }
    YARG_RELEASE_CHANNEL=stable YARG_URL="https://h/fijo.zip"
    run resolve_yarg_download_url
    [ "$status" -eq 0 ]
    [ "$YARG_URL" = "https://h/fijo.zip" ]
}

@test "resolve_yarg_download_url propaga el fallo de la API" {
    github_api_get() { return 1; }
    YARG_RELEASE_CHANNEL=stable-latest
    YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX="$YARG_REGEX"
    run resolve_yarg_download_url
    [ "$status" -eq 1 ]
}

@test "resolve_clonehero_download_url prefiere el AppImage/paquete x64 y toma su digest" {
    local digest; digest="$(printf 'c%.0s' {1..64})"
    FAKE_JSON="$(make_json "$digest" clonehero-linux-x64.tar.gz)"
    CLONEHERO_RELEASE_CHANNEL=latest
    CLONEHERO_API_URL=https://api.invalid/ch CLONEHERO_ASSET_REGEX="$CH_REGEX"
    CLONEHERO_URL=""
    resolve_clonehero_download_url
    [ "$CLONEHERO_URL" = "https://h/clonehero-linux-x64.tar.gz" ]
    [ "$CLONEHERO_SHA256" = "$digest" ]
}

@test "resolve_clonehero_download_url no hace nada fuera del canal latest" {
    github_api_get() { echo "no deberia llamarse" >&2; return 1; }
    CLONEHERO_RELEASE_CHANNEL=url CLONEHERO_URL="https://h/ch.zip"
    run resolve_clonehero_download_url
    [ "$status" -eq 0 ]
}

# --- updaters generados ------------------------------------------------------

# Genera el updater real evaluando el heredoc del instalador y lo adapta para
# correr en un directorio temporal. Uso: gen_updater <lib> <nombre> <dir-opt>
gen_updater() {
    local lib="$1" name="$2" opt="$3"
    awk -v m="cat > /mnt/usr/local/bin/$name << EOF" 'index($0, m) { f = 1; next } f && /^EOF$/ { exit } f' "$lib" > "$W/body"
    [ -s "$W/body" ]
    eval "cat <<EOF
$(cat "$W/body")
EOF" > "$W/$name"
    sed -i -e "s#/opt/#$W/opt/#g" -e 's#if \[\[ \${EUID} -ne 0 \]\]#if false#' -e 's#^chown .*#true#' "$W/$name"
    bash -n "$W/$name"
}

# curl y unzip de prueba. Las consultas a api.* devuelven $FAKE_JSON con el
# codigo $FAKE_CODE; el resto de descargas copia $FAKE_PKG.
fake_tools() {
    cat > "$W/bin/curl" <<'SH'
#!/usr/bin/env bash
out=""; wcode=false; url=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -o) out="$2"; shift ;;
        -w) wcode=true; shift ;;
        -H|--retry|--retry-delay) shift ;;
        -*) ;;
        *) url="$1" ;;
    esac
    shift
done
echo "$url" >> "$W/curl.calls"
if [[ "$url" == https://api.* ]]; then
    printf '%s' "$FAKE_JSON" > "$out"
    $wcode && printf '%s' "${FAKE_CODE:-200}"
    exit 0
fi
cp "$FAKE_PKG" "$out"
SH
    cat > "$W/bin/unzip" <<'SH'
#!/usr/bin/env bash
# unzip -tq <zip> | unzip -o <zip> -d <dir>
if [[ "$1" == "-o" ]]; then
    mkdir -p "$4"
    : > "$4/YARG"
fi
exit 0
SH
    chmod +x "$W/bin/curl" "$W/bin/unzip"
    export PATH="$W/bin:$PATH"
    : > "$W/curl.calls"
}

yarg_env() {
    export YARG_RELEASE_CHANNEL="${1:-stable-latest}" YARG_URL="https://h/fijo.zip" \
        YARG_STABLE_API_URL=https://api.invalid/yarg YARG_STABLE_ASSET_REGEX="$YARG_REGEX" \
        YARG_NIGHTLY_API_URL=https://api.invalid/n YARG_NIGHTLY_ASSET_REGEX="$YARG_REGEX" \
        YARG_SONGS_DIR="$W/songs" KIOSK_USER="$(id -un)" YARG_SHA256="${2:-}"
}

downloads() { grep -vc '^https://api\.' "$W/curl.calls" || true; }

prepare_yarg() {
    # $1 = digest que anuncia la API para el ZIP Linux
    export FAKE_PKG="$W/pkg.zip"
    export FAKE_JSON="$(make_json "$1" YARG_v1.0.0-Linux-x86_64.zip)"
    fake_tools
    yarg_env
    gen_updater lib/yarg.sh update-yarg opt/YARG
}

@test "update-yarg instala la ultima release cuando el digest de la API coincide" {
    prepare_yarg "$(sha256sum "$W/pkg.zip" | cut -d' ' -f1)"
    run bash "$W/update-yarg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sha256 verificado"* ]]
    [ -f "$W/opt/YARG/YARG" ]
    [ "$(cat "$W/opt/YARG/.install-url")" = "https://h/YARG_v1.0.0-Linux-x86_64.zip" ]
}

@test "update-yarg aborta sin instalar si el digest de la API no coincide" {
    prepare_yarg "$(printf 'f%.0s' {1..64})"
    run bash "$W/update-yarg"
    [ "$status" -ne 0 ]
    [[ "$output" == *"sha256 no coincide"* ]]
    [ ! -e "$W/opt/YARG/YARG" ]
    [ ! -e "$W/opt/YARG/.install-url" ]
}

@test "update-yarg no descarga si ya esta la ultima version y --force reinstala" {
    prepare_yarg "$(sha256sum "$W/pkg.zip" | cut -d' ' -f1)"
    run bash "$W/update-yarg"
    [ "$status" -eq 0 ]
    [ "$(downloads)" -eq 1 ]

    run bash "$W/update-yarg"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ya esta en la ultima version"* ]]
    [ "$(downloads)" -eq 1 ]

    run bash "$W/update-yarg" --force
    [ "$status" -eq 0 ]
    [ "$(downloads)" -eq 2 ]
}

@test "update-yarg explica el limite de GitHub ante un 403" {
    prepare_yarg "$(printf 'a%.0s' {1..64})"
    export FAKE_CODE=403
    run bash "$W/update-yarg"
    [ "$status" -ne 0 ]
    [[ "$output" == *"HTTP 403"* ]]
    [[ "$output" == *"GITHUB_TOKEN"* ]]
    [ "$(downloads)" -eq 0 ]
}

@test "update-yarg en canal stable verifica YARG_SHA256 de la URL fija" {
    export FAKE_PKG="$W/pkg.zip" FAKE_JSON="{}"
    fake_tools
    yarg_env stable "$(printf '0%.0s' {1..64})"
    gen_updater lib/yarg.sh update-yarg opt/YARG
    run bash "$W/update-yarg"
    [ "$status" -ne 0 ]
    [[ "$output" == *"sha256 no coincide"* ]]

    yarg_env stable "$(sha256sum "$W/pkg.zip" | cut -d' ' -f1)"
    gen_updater lib/yarg.sh update-yarg opt/YARG
    run bash "$W/update-yarg"
    [ "$status" -eq 0 ]
    [ "$(cat "$W/opt/YARG/.install-url")" = "https://h/fijo.zip" ]
}

@test "update-yarg no deja temporales en /var/tmp" {
    prepare_yarg "$(sha256sum "$W/pkg.zip" | cut -d' ' -f1)"
    local antes; antes="$(ls /var/tmp | grep -c '^update-yarg\.' || true)"
    run bash "$W/update-yarg"
    [ "$status" -eq 0 ]
    run bash "$W/update-yarg" --force
    [ "$(ls /var/tmp | grep -c '^update-yarg\.' || true)" -eq "$antes" ]
}

prepare_clonehero() {
    # $1 = canal; $2 = sha256 esperado para la URL fija
    mkdir -p "$W/src/CloneHero"
    echo bin > "$W/src/CloneHero/clonehero"
    tar -czf "$W/pkg.tar.gz" -C "$W/src" CloneHero
    export FAKE_PKG="$W/pkg.tar.gz"
    export FAKE_JSON="$(make_json "$(sha256sum "$W/pkg.tar.gz" | cut -d' ' -f1)" clonehero-linux-x64.tar.gz)"
    fake_tools
    export CLONEHERO_RELEASE_CHANNEL="$1" CLONEHERO_URL="https://h/CloneHero-linux-x64.tar.gz" \
        CLONEHERO_API_URL=https://api.invalid/ch CLONEHERO_ASSET_REGEX="$CH_REGEX" \
        CLONEHERO_SONGS_DIR="$W/songs" KIOSK_USER="$(id -un)" CLONEHERO_SHA256="${2:-}"
    gen_updater lib/clonehero.sh update-clonehero opt/CloneHero
}

@test "update-clonehero en canal latest verifica el digest de la API e instala" {
    prepare_clonehero latest
    run bash "$W/update-clonehero"
    [ "$status" -eq 0 ]
    [[ "$output" == *"sha256 verificado"* ]]
    [ -f "$W/opt/CloneHero/clonehero" ]
    [ "$(cat "$W/opt/CloneHero/.install-url")" = "https://h/clonehero-linux-x64.tar.gz" ]
}

@test "update-clonehero aborta si CLONEHERO_SHA256 no coincide con la URL fija" {
    prepare_clonehero url "$(printf '0%.0s' {1..64})"
    run bash "$W/update-clonehero"
    [ "$status" -ne 0 ]
    [[ "$output" == *"sha256 no coincide"* ]]
    [ ! -e "$W/opt/CloneHero/clonehero" ]
}

@test "update-clonehero no descarga dos veces la misma version" {
    prepare_clonehero latest
    run bash "$W/update-clonehero"
    [ "$status" -eq 0 ]
    run bash "$W/update-clonehero"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ya esta en la ultima version"* ]]
    [ "$(downloads)" -eq 1 ]
}
