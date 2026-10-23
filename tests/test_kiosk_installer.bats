#!/usr/bin/env bats

# Modo asistido de install-cage-kiosk.sh: se extrae ask_guided_configuration del
# script (sin ejecutar main) y se alimenta por stdin.

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    source lib/common.sh
    eval "$(sed -n '/^ask_guided_configuration() {/,/^}/p' install-cage-kiosk.sh)"
    declare -F ask_guided_configuration >/dev/null

    KIOSK_USER=kiosk
    KIOSK_PASSWORD=""
    ROOT_PASSWORD=""
    REQUIRE_ROOT_PASSWORD=true
    KIOSK_HOSTNAME=minikiosk
    TIMEZONE=America/Phoenix
    ENABLE_SSH=false
    ENABLE_PLYMOUTH=true
}

@test "install-cage-kiosk.sh usa las funciones de prompts compartidas" {
    grep -Eq '^ask_guided_configuration\(\) \{' install-cage-kiosk.sh
    grep -Fq 'ask_guided_configuration || exit 1' install-cage-kiosk.sh
    ! grep -Eq '^prompt_secret\(\) \{' install-cage-kiosk.sh
}

@test "kiosko sin .env: pregunta usuario, hostname, zona horaria, SSH y Plymouth" {
    ENV_FILE_LOADED=false
    ask_guided_configuration > /dev/null <<'IN'
operador
clave1
clave1
raiz1
raiz1
kiosko-taller
America/Mexico_City
s
n
IN
    [ "$KIOSK_USER" = operador ]
    [ "$KIOSK_PASSWORD" = clave1 ]
    [ "$ROOT_PASSWORD" = raiz1 ]
    [ "$KIOSK_HOSTNAME" = kiosko-taller ]
    [ "$TIMEZONE" = America/Mexico_City ]
    [ "$ENABLE_SSH" = true ]
    [ "$ENABLE_PLYMOUTH" = false ]
}

@test "kiosko sin .env: Enter conserva los valores por defecto" {
    ENV_FILE_LOADED=false
    REQUIRE_ROOT_PASSWORD=false
    ask_guided_configuration > /dev/null <<'IN'

clave1
clave1




IN
    [ "$KIOSK_USER" = kiosk ]
    [ "$KIOSK_HOSTNAME" = minikiosk ]
    [ "$TIMEZONE" = America/Phoenix ]
    [ "$ENABLE_SSH" = false ]
    [ "$ENABLE_PLYMOUTH" = true ]
}

@test "kiosko con .env completo: no pregunta nada" {
    ENV_FILE_LOADED=true
    KIOSK_PASSWORD=desde-env
    ROOT_PASSWORD=raiz-env
    run ask_guided_configuration < /dev/null
    [ "$status" -eq 0 ]
    [ "$KIOSK_PASSWORD" = desde-env ]
}
