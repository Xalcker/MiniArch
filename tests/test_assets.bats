#!/usr/bin/env bats

# assets/create-example-assets.sh y coherencia de la documentacion de assets.

setup() {
    SCRIPT="$BATS_TEST_TMPDIR/assets/create-example-assets.sh"
    mkdir -p "$BATS_TEST_TMPDIR/assets" "$BATS_TEST_TMPDIR/bin"
    # Se copia a un directorio temporal: el script escribe junto a si mismo.
    cp assets/create-example-assets.sh "$SCRIPT"

    # ImageMagick simulado: registra los argumentos y crea el archivo de salida.
    cat > "$BATS_TEST_TMPDIR/bin/magick" <<'SH'
#!/usr/bin/env bash
echo "$*" > "$MAGICK_LOG"
for last; do :; done
echo "png-falso" > "$last"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/magick"
    export MAGICK_LOG="$BATS_TEST_TMPDIR/magick.log"
}

@test "create-example-assets genera plymouth-image.png en 1920x1080 por defecto" {
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -s "$BATS_TEST_TMPDIR/assets/plymouth-image.png" ]
    grep -Fq -- "-size 1920x1080" "$MAGICK_LOG"
}

@test "create-example-assets acepta otra resolucion y escala el texto" {
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SCRIPT" 1280x720
    [ "$status" -eq 0 ]
    grep -Fq -- "-size 1280x720" "$MAGICK_LOG"
    grep -Fq -- "-pointsize 80" "$MAGICK_LOG"
}

@test "create-example-assets rechaza una resolucion invalida" {
    PATH="$BATS_TEST_TMPDIR/bin:$PATH" run bash "$SCRIPT" "grande"
    [ "$status" -eq 1 ]
    [[ "$output" == *"resolucion invalida"* ]]
    [ ! -e "$BATS_TEST_TMPDIR/assets/plymouth-image.png" ]
}

@test "create-example-assets avisa si no hay ImageMagick" {
    PATH="$BATS_TEST_TMPDIR/vacio" run "$BASH" "$SCRIPT"
    [ "$status" -eq 1 ]
    [[ "$output" == *"ImageMagick no esta instalado"* ]]
    [[ "$output" == *"pacman -S imagemagick"* ]]
}

@test "create-example-assets usa convert si no existe magick" {
    mv "$BATS_TEST_TMPDIR/bin/magick" "$BATS_TEST_TMPDIR/bin/convert"
    PATH="$BATS_TEST_TMPDIR/bin:/usr/bin:/bin" run bash "$SCRIPT"
    [ "$status" -eq 0 ]
    [ -s "$BATS_TEST_TMPDIR/assets/plymouth-image.png" ]
}

# --- Documentacion de assets --------------------------------------------------

@test "assets/README.md menciona cada PNG de assets/ y el cursor" {
    local f
    for f in assets/*.png; do
        grep -Fq "$(basename "$f")" assets/README.md || { echo "assets/README.md no menciona $f" >&2; return 1; }
    done
    grep -Fq "guitar-pick-left.png" assets/cursor/README.md
}

@test "la documentacion de assets no conserva referencias del instalador OpenBox" {
    ! grep -rEq 'arch-kiosk-installer|OpenBox' assets/README.md assets/cursor/README.md assets/plymouth-image.png.example assets/create-example-assets.sh
}

@test "el README del cursor describe lo que hace install_custom_cursor" {
    grep -Fq "64 23 8" assets/cursor/README.md
    grep -Fq "64 23 8" lib/customization.sh
    grep -Fq "MiniArchPick" assets/cursor/README.md
    grep -Fq "XCURSOR_SIZE=64" lib/yarg.sh lib/cage.sh lib/clonehero.sh lib/rpcs3.sh 2>/dev/null || grep -rFq "XCURSOR_SIZE=64" lib
    grep -Fq "xorg-xcursorgen" lib/cage.sh
}

@test "el README de assets describe el orden de seleccion que implementa select_plymouth_image" {
    grep -Fq '${assets_dir}/${app_prefix}_${resolution}.png' lib/plymouth.sh
    grep -Fq 'plymouth-image_${resolution}.png' lib/plymouth.sh
    grep -Fq 'plymouth-image_<resolución>.png' assets/README.md
    grep -Fq 'plymouth-image.png' assets/README.md
}

@test "PLACEHOLDER.txt ya no existe ni se menciona en .gitignore" {
    [ ! -e assets/cursor/PLACEHOLDER.txt ]
    ! grep -Fq "PLACEHOLDER" .gitignore
}

# --- Documentacion historica ----------------------------------------------------

@test "los specs del instalador OpenBox viven archivados y con aviso de obsolescencia" {
    local f
    [ ! -e .kiro/specs/arch-kiosk-installer/design.md ]
    [ -e docs/historico/instalador-openbox/README.md ]
    for f in requirements design tasks; do
        [ -e "docs/historico/instalador-openbox/$f.md" ]
        head -n 1 "docs/historico/instalador-openbox/$f.md" | grep -Fq "Documento historico"
    done
}
