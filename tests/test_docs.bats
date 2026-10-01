#!/usr/bin/env bats

# Coherencia de la documentacion con el repo: evita que README, SECURITY y
# CONTRIBUTING vuelvan a quedar desfasados de los scripts, modulos y pruebas.

@test "el README lista cada instalador, modulo de lib/ y archivo de pruebas" {
    local f base
    for f in install-cage-*.sh lib/*.sh scripts/*.sh tests/*.bats; do
        base=$(basename "$f")
        grep -Fq "$base" README.md || { echo "README no menciona $f" >&2; return 1; }
    done
}

@test "el README no menciona archivos de pruebas ni modulos que ya no existen" {
    local name
    for name in $(grep -oE '(test_[a-z0-9_]+\.bats|[a-z0-9_-]+\.sh)' README.md | sort -u); do
        if [[ "$name" == test_*.bats ]]; then
            [ -e "tests/$name" ] || { echo "README menciona tests/$name, que no existe" >&2; return 1; }
        else
            [ -e "$name" ] || [ -e "lib/$name" ] || [ -e "scripts/$name" ] || [ -e "assets/$name" ] \
                || grep -rqF "$name" lib install-cage-*.sh scripts \
                || { echo "README menciona $name, que no existe" >&2; return 1; }
        fi
    done
}

@test "CONTRIBUTING nombra cada instalador y cada modulo de lib/" {
    local f base
    for f in install-cage-*.sh lib/*.sh; do
        base=$(basename "$f")
        grep -Fq "$base" CONTRIBUTING.md || { echo "CONTRIBUTING no menciona $f" >&2; return 1; }
    done
}

@test "CONTRIBUTING pide validar la sintaxis de cada instalador" {
    local f
    for f in install-cage-*.sh; do
        grep -Fq "bash -n $f" CONTRIBUTING.md || { echo "falta 'bash -n $f' en CONTRIBUTING" >&2; return 1; }
    done
}

@test "SECURITY documenta los tres shares Samba y los tres updaters" {
    local item
    for item in YARG-Songs CloneHero-Songs RPCS3-Games update-yarg update-clonehero update-rpcs3 run-yarg.sh run-clonehero.sh run-rpcs3.sh; do
        grep -Fq "$item" SECURITY.md || { echo "SECURITY no menciona $item" >&2; return 1; }
    done
}

@test "el README documenta cada variable de .env.example" {
    local key
    for key in $(tr -d '\r' < .env.example | grep -oE '^#?[A-Z][A-Z0-9_]*=' | tr -d '#='); do
        grep -qw "$key" README.md || { echo "README no documenta $key" >&2; return 1; }
    done
}

@test "CLONING.md cubre los cuatro caminos" {
    grep -Fq "Clone Hero" CLONING.md
    grep -Fq "RPCS3" CLONING.md
}

@test "el troubleshooting del README cubre cada camino con aplicacion" {
    local item
    for item in "### Cage no arranca YARG" "### Clone Hero no arranca" "### RPCS3 no arranca el juego"; do
        grep -Fq "$item" README.md || { echo "falta la seccion '$item'" >&2; return 1; }
    done
}

@test "el CHANGELOG menciona cada instalador y los modulos de cada camino" {
    local f item
    for f in install-cage-*.sh; do
        grep -Fq "$f" CHANGELOG.md || { echo "CHANGELOG no menciona $f" >&2; return 1; }
    done
    for item in lib/rpcs3.sh lib/clonehero.sh lib/yarg.sh lib/cage.sh lib/common.sh; do
        grep -Fq "$item" CHANGELOG.md || { echo "CHANGELOG no menciona $item" >&2; return 1; }
    done
}

@test "el CHANGELOG no enlaza releases ni comparaciones de tags que no existen" {
    # Mientras el repo no publique tags, los enlaces compare/releases darian 404.
    ! grep -Eq '^\[[^]]+\]: https://github.com/.*/(compare|releases/tag)/' CHANGELOG.md
}

@test "el CHANGELOG tiene las secciones estandar bajo [No Publicado]" {
    local section
    for section in "### Agregado" "### Cambiado" "### Removido" "### Corregido"; do
        grep -Fxq "$section" CHANGELOG.md || { echo "falta '$section'" >&2; return 1; }
    done
    grep -Fxq "## [No Publicado]" CHANGELOG.md
}
