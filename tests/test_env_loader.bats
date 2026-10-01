#!/usr/bin/env bats

# Pruebas de load_env_file / env_parse_value (lib/common.sh): el .env se lee
# como CLAVE=valor y nunca se ejecuta.

setup() {
    export LOG_FILE="$BATS_TEST_TMPDIR/install.log"
    source lib/common.sh
    ENVF="$BATS_TEST_TMPDIR/test.env"
}

@test "carga valores simples, ignora comentarios y lineas en blanco y tolera export" {
    printf '%s\n' '# comentario' '' 'A=uno' '  B = dos' 'export C=tres' > "$ENVF"
    load_env_file "$ENVF"
    [ "$A" = "uno" ]
    [ "$B" = "dos" ]
    [ "$C" = "tres" ]
}

@test "exporta las variables al entorno de los procesos hijos" {
    printf 'EXPORTADA=si\n' > "$ENVF"
    load_env_file "$ENVF"
    run bash -c 'echo "$EXPORTADA"'
    [ "$output" = "si" ]
}

@test "comillas dobles: admiten escapes \\\\ \\\" \\\$ y \\\`" {
    printf '%s\n' 'A="con \"comillas\" y \\ y \$x y \`b"' > "$ENVF"
    load_env_file "$ENVF"
    [ "$A" = 'con "comillas" y \ y $x y `b' ]
}

@test "comillas simples: todo es literal" {
    printf "%s\n" "A='lit \$HOME & ; (x) \`id\` \"q\"'" > "$ENVF"
    load_env_file "$ENVF"
    [ "$A" = 'lit $HOME & ; (x) `id` "q"' ]
}

@test "sin comillas: simbolos y \$\$ quedan literales, los espacios internos se conservan" {
    printf '%s\n' 'PW=pa$$w0rd&x;(y)!  z' > "$ENVF"
    load_env_file "$ENVF"
    [ "$PW" = 'pa$$w0rd&x;(y)!  z' ]
}

@test "un ' #' sin comillas inicia un comentario; dentro de comillas no" {
    printf '%s\n' 'A=valor # nota' 'B="con # dentro" # nota' 'C=sin#espacio' > "$ENVF"
    load_env_file "$ENVF"
    [ "$A" = "valor" ]
    [ "$B" = "con # dentro" ]
    [ "$C" = "sin#espacio" ]
}

@test "expande \${NOMBRE} con variables ya definidas; las no definidas quedan vacias" {
    printf '%s\n' 'U=kiosk' 'DIR=/home/${U}/Songs' 'VACIO=a${NO_EXISTE_XYZ}b' 'LIT=$U' > "$ENVF"
    load_env_file "$ENVF"
    [ "$DIR" = "/home/kiosk/Songs" ]
    [ "$VACIO" = "ab" ]
    [ "$LIT" = '$U' ]
}

@test "NO ejecuta sustitucion de comandos ni backticks" {
    local marker="$BATS_TEST_TMPDIR/PWNED"
    printf '%s\n' "A=\$(touch $marker)" "B=\`touch $marker\`" "C=\"\$(touch $marker)\"" > "$ENVF"
    load_env_file "$ENVF"
    [ ! -e "$marker" ]
    [ "$A" = "\$(touch $marker)" ]
}

@test "acepta finales de linea CRLF" {
    printf 'A=uno\r\nB="dos"\r\n' > "$ENVF"
    load_env_file "$ENVF"
    [ "$A" = "uno" ]
    [ "$B" = "dos" ]
}

@test "procesa la ultima linea aunque no termine en salto de linea" {
    printf 'A=uno\nB=dos' > "$ENVF"
    load_env_file "$ENVF"
    [ "$B" = "dos" ]
}

@test "una linea invalida falla indicando archivo y numero de linea, sin cargar las siguientes" {
    printf '%s\n' 'A=uno' 'esto no es una asignacion' 'DESPUES=x' > "$ENVF"
    unset DESPUES
    run load_env_file "$ENVF"
    [ "$status" -eq 1 ]
    [[ "$output" == *":2:"* ]]
    [[ "$output" == *"CLAVE=valor"* ]]
    [ -z "${DESPUES:-}" ]
}

@test "comillas sin cerrar o texto despues del cierre son un error" {
    printf '%s\n' 'A="abierta' > "$ENVF"
    run load_env_file "$ENVF"
    [ "$status" -eq 1 ]

    printf '%s\n' "B='x' sobrante" > "$ENVF"
    run load_env_file "$ENVF"
    [ "$status" -eq 1 ]
}

@test "rechaza variables que afectan al propio instalador" {
    local original_path="$PATH"
    printf 'PATH=/tmp/evil\n' > "$ENVF"
    run load_env_file "$ENVF"
    [ "$status" -eq 1 ]
    [[ "$output" == *"PATH"* ]]
    [ "$PATH" = "$original_path" ]

    printf 'LD_PRELOAD=/tmp/x.so\n' > "$ENVF"
    run load_env_file "$ENVF"
    [ "$status" -eq 1 ]

    printf '__e_key=x\n' > "$ENVF"
    run load_env_file "$ENVF"
    [ "$status" -eq 1 ]
}

@test "un archivo inexistente es un error" {
    run load_env_file "$BATS_TEST_TMPDIR/no-existe.env"
    [ "$status" -eq 1 ]
}

@test "los instaladores usan load_env_file y ya no hacen source del .env" {
    local f
    for f in install-cage-yarg.sh install-cage-clonehero.sh install-cage-rpcs3.sh install-cage-kiosk.sh; do
        grep -Fq 'load_env_file "$SCRIPT_DIR/.env"' "$f"
        ! grep -Fq 'source <(grep' "$f"
    done
}

@test ".env.example da exactamente los mismos valores con el cargador nuevo que con el source anterior" {
    local keys key old new
    keys=$(grep -oE '^[A-Z][A-Z0-9_]*=' .env.example | tr -d '=' | tr '\n' ' ')
    [ -n "$keys" ]

    old=$(bash -c '
        set -a
        source <(tr -d "\r" < .env.example | grep -v "^#" | grep -v "^$")
        for k in '"$keys"'; do printf "%s=%s\n" "$k" "${!k}"; done')

    for key in $keys; do unset "$key"; done
    load_env_file .env.example
    new=$(for key in $keys; do printf '%s=%s\n' "$key" "${!key}"; done)

    [ "$old" = "$new" ]
}
