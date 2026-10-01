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
