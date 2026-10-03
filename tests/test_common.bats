#!/usr/bin/env bats

# Pruebas de lib/common.sh: utilidades compartidas por los instaladores.

setup() {
    export LOG_FILE="$(mktemp)"
    source lib/common.sh
}

teardown() {
    rm -f "$LOG_FILE"
}

@test "log escribe en consola y en LOG_FILE" {
    run log "mensaje de prueba"
    [ "$status" -eq 0 ]
    [[ "$output" == *"mensaje de prueba"* ]]
    grep -q "mensaje de prueba" "$LOG_FILE"
}

@test "log_error escribe en LOG_FILE" {
    run log_error "algo fallo"
    grep -q "ERROR" "$LOG_FILE"
    grep -q "algo fallo" "$LOG_FILE"
}

@test "run_quiet manda la salida al log y conserva el codigo de salida" {
    VERBOSE_INSTALL=false
    run run_quiet bash -c 'echo ruido; exit 3'
    [ "$status" -eq 3 ]
    [ -z "$output" ]
    grep -q "ruido" "$LOG_FILE"
}

@test "run_quiet muestra la salida con VERBOSE_INSTALL=true" {
    VERBOSE_INSTALL=true
    run run_quiet echo visible
    [ "$status" -eq 0 ]
    [[ "$output" == "visible" ]]
}

@test "prompt_value no pregunta si .env ya definio la variable" {
    ENV_FILE_LOADED=true
    MI_VAR=desde-env
    run prompt_value MI_VAR "Etiqueta" "default" </dev/null
    [ "$status" -eq 0 ]
    [ -z "$output" ]
}

@test "prompt_value usa el valor ingresado" {
    ENV_FILE_LOADED=false
    MI_VAR=""
    prompt_value MI_VAR "Etiqueta" "default" <<< "escrito"
    [ "$MI_VAR" = "escrito" ]
}

@test "prompt_value usa el default con Enter" {
    ENV_FILE_LOADED=false
    MI_VAR=""
    prompt_value MI_VAR "Etiqueta" "default" <<< ""
    [ "$MI_VAR" = "default" ]
}

@test "prompt_bool normaliza s/n a true/false" {
    ENV_FILE_LOADED=false
    B=""
    prompt_bool B "Etiqueta" "false" <<< "s"
    [ "$B" = "true" ]
    prompt_bool B "Etiqueta" "true" <<< "n"
    [ "$B" = "false" ]
}

@test "prompt_password acepta una contrasena confirmada" {
    ENV_FILE_LOADED=false
    PW=""
    prompt_password PW "Password" <<< $'secreto\nsecreto'
    [ "$PW" = "secreto" ]
}

@test "cleanup_on_exit no limpia montajes si la instalacion termino bien" {
    cleanup_mounts() { echo "limpiando"; }
    INSTALL_SUCCESS=1
    run cleanup_on_exit
    [ "$status" -eq 0 ]
    [[ "$output" != *limpiando* ]]
}

@test "los instaladores cargan lib/common.sh y no redefinen sus funciones" {
    local script fn
    for script in install-cage-yarg.sh install-cage-clonehero.sh install-cage-kiosk.sh; do
        grep -Fq 'source "$SCRIPT_DIR/lib/common.sh"' "$script"
        for fn in log log_error warn run_quiet cleanup_on_exit; do
            ! grep -Eq "^${fn}\(\) \{" "$script"
        done
    done
}

# curl de prueba: escribe $FAKE_BODY en -o e imprime $FAKE_CODE como http_code.
# Guarda los argumentos recibidos en $BATS_TEST_TMPDIR/curl.args.
fake_curl() {
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    cat > "$BATS_TEST_TMPDIR/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$BATS_TEST_TMPDIR/curl.args"
while [[ $# -gt 0 ]]; do [[ "$1" == "-o" ]] && out="$2"; shift; done
printf '%s' "$FAKE_BODY" > "$out"
printf '%s' "$FAKE_CODE"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/curl"
    export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "github_api_get devuelve el JSON con HTTP 200 y envia el token si existe" {
    fake_curl
    export FAKE_BODY='{"ok":true}' FAKE_CODE=200 GITHUB_TOKEN=abc123
    run github_api_get "https://api.github.com/x"
    [ "$status" -eq 0 ]
    [ "$output" = '{"ok":true}' ]
    grep -Fq 'Authorization: Bearer abc123' "$BATS_TEST_TMPDIR/curl.args"
}

@test "github_api_get no envia Authorization sin token" {
    fake_curl
    export FAKE_BODY='{}' FAKE_CODE=200
    unset GITHUB_TOKEN
    run github_api_get "https://api.github.com/x"
    [ "$status" -eq 0 ]
    ! grep -Fq 'Authorization' "$BATS_TEST_TMPDIR/curl.args"
}

@test "github_api_get explica el limite de peticiones ante 403 y 429" {
    fake_curl
    local code
    for code in 403 429; do
        export FAKE_BODY='rate limit' FAKE_CODE=$code
        run github_api_get "https://api.github.com/x"
        [ "$status" -eq 1 ]
        grep -Fq "HTTP $code" "$LOG_FILE"
        grep -Fq "GITHUB_TOKEN" "$LOG_FILE"
    done
}

@test "github_api_get falla con otros codigos HTTP" {
    fake_curl
    export FAKE_BODY='' FAKE_CODE=500
    run github_api_get "https://api.github.com/x"
    [ "$status" -eq 1 ]
    grep -Fq "HTTP 500" "$LOG_FILE"
}

@test "github_asset_sha256 extrae el digest del asset correcto" {
    local json
    json='{"assets":[
      {"name":"a.zip","digest": "sha256:'"$(printf 'a%.0s' {1..64})"'",
       "browser_download_url": "https://x/a.zip"},
      {"name":"b.zip","browser_download_url": "https://x/b.zip"},
      {"name":"c.zip","digest": "sha256:'"$(printf 'c%.0s' {1..64})"'",
       "browser_download_url": "https://x/c.zip"}]}'
    run github_asset_sha256 "$(printf '%s' "$json" | sed 's/,\s*"browser/,\n"browser/;s/{"name/\n{"name/')" "https://x/c.zip"
    [ "$output" = "$(printf 'c%.0s' {1..64})" ]
    # b.zip no publica digest: no debe heredar el de a.zip
    run github_asset_sha256 "$(printf '%s' "$json" | sed 's/,\s*"browser/,\n"browser/;s/{"name/\n{"name/')" "https://x/b.zip"
    [ -z "$output" ]
}

@test "verify_sha256 acepta hash correcto, vacio, y rechaza uno distinto" {
    local f="$BATS_TEST_TMPDIR/f"
    printf 'hola' > "$f"
    local h; h="$(sha256sum "$f" | cut -d' ' -f1)"
    run verify_sha256 "$f" "$h"
    [ "$status" -eq 0 ]
    run verify_sha256 "$f" "${h^^}"
    [ "$status" -eq 0 ]
    run verify_sha256 "$f" ""
    [ "$status" -eq 0 ]
    run verify_sha256 "$f" "$(printf '0%.0s' {1..64})"
    [ "$status" -eq 1 ]
    grep -Fq "sha256 no coincide" "$LOG_FILE"
}

@test "write_samba_share por defecto deja el share con guest y SMB2 minimo" {
    export SAMBA_CONF="$BATS_TEST_TMPDIR/smb.conf" KIOSK_USER=kiosk
    unset SAMBA_GUEST SAMBA_HOSTS_ALLOW
    write_samba_share "Test Kiosk" "Songs" "/srv/songs"
    grep -Fq 'server string = Test Kiosk' "$SAMBA_CONF"
    grep -Fq 'server min protocol = SMB2' "$SAMBA_CONF"
    grep -Fq 'map to guest = Bad User' "$SAMBA_CONF"
    grep -Fq 'guest ok = yes' "$SAMBA_CONF"
    grep -Fq 'force user = kiosk' "$SAMBA_CONF"
    ! grep -Fq 'hosts allow' "$SAMBA_CONF"
    ! grep -Fq 'valid users' "$SAMBA_CONF"
}

@test "write_samba_share con SAMBA_GUEST=false exige usuario y aplica hosts allow" {
    export SAMBA_CONF="$BATS_TEST_TMPDIR/smb.conf" KIOSK_USER=kiosk \
        SAMBA_GUEST=false SAMBA_HOSTS_ALLOW="192.168.0.0/16 127."
    write_samba_share "Test Kiosk" "Songs" "/srv/songs"
    ! grep -Fq 'guest ok' "$SAMBA_CONF"
    ! grep -Fq 'map to guest' "$SAMBA_CONF"
    grep -Fq 'valid users = kiosk' "$SAMBA_CONF"
    grep -Fq 'hosts allow = 192.168.0.0/16 127.' "$SAMBA_CONF"
}

@test "write_samba_share agrega varios shares sin duplicar [global] ni el mismo share" {
    export SAMBA_CONF="$BATS_TEST_TMPDIR/smb.conf" KIOSK_USER=kiosk
    write_samba_share "A" "Uno" "/srv/uno"
    write_samba_share "B" "Dos" "/srv/dos"
    write_samba_share "B" "Dos" "/srv/dos"
    [ "$(grep -c '^\[global\]' "$SAMBA_CONF")" -eq 1 ]
    [ "$(grep -c '^\[Uno\]' "$SAMBA_CONF")" -eq 1 ]
    [ "$(grep -c '^\[Dos\]' "$SAMBA_CONF")" -eq 1 ]
}
