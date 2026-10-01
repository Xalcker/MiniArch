#!/usr/bin/env bats

# Pruebas de scripts/check-encoding.sh y de que el repo cumple sus reglas.

setup() {
    CHECK="$PWD/scripts/check-encoding.sh"
    D="$BATS_TEST_TMPDIR/repo"
    mkdir -p "$D"
}

@test "check-encoding acepta UTF-8 limpio con acentos" {
    printf 'camión ñ\n' > "$D/ok.md"
    run bash "$CHECK" "$D"
    [ "$status" -eq 0 ]
}

@test "check-encoding rechaza un BOM al inicio" {
    printf '\xef\xbb\xbfhola\n' > "$D/a.sh"
    run bash "$CHECK" "$D"
    [ "$status" -eq 1 ]
    [[ "$output" == *"BOM"* ]]
}

@test "check-encoding rechaza doble codificacion UTF-8" {
    printf 'cami\xc3\x83\xc2\xb3n\n' > "$D/b.md"
    run bash "$CHECK" "$D"
    [ "$status" -eq 1 ]
    [[ "$output" == *"mojibake"* ]]
}

@test "check-encoding rechaza finales de linea CRLF" {
    printf 'hola\r\nmundo\r\n' > "$D/c.bats"
    run bash "$CHECK" "$D"
    [ "$status" -eq 1 ]
    [[ "$output" == *"CRLF"* ]]
}

@test "el repo cumple las reglas de codificacion" {
    run bash "$CHECK" "$PWD"
    [ "$status" -eq 0 ]
}
