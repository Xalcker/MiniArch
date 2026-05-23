#!/usr/bin/env bash
# Bootstrap MiniArch from the Arch Linux live installer.

set -euo pipefail

REPO_URL="${MINIARCH_REPO_URL:-https://github.com/Xalcker/MiniArch.git}"
REPO_DIR="${MINIARCH_REPO_DIR:-/root/MiniArch}"
BRANCH="${MINIARCH_BRANCH:-}"
DEFAULT_INSTALLER="${MINIARCH_INSTALLER:-ask}"
TTY_PATH="${MINIARCH_TTY:-/dev/tty}"
VERBOSE="${MINIARCH_VERBOSE:-false}"
BOOTSTRAP_LOG="${MINIARCH_BOOTSTRAP_LOG:-/tmp/miniarch-bootstrap.log}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${GREEN}INFO:${NC} $*"
}

warn() {
    echo -e "${YELLOW}ADVERTENCIA:${NC} $*" >&2
}

die() {
    echo -e "${RED}ERROR:${NC} $*" >&2
    exit 1
}

run_quiet() {
    if [[ "${VERBOSE,,}" == "true" ]]; then
        "$@"
        return $?
    fi

    if ! "$@" >> "$BOOTSTRAP_LOG" 2>&1; then
        echo -e "${RED}ERROR:${NC} Fallo el comando: $*" >&2
        echo "Ultimas lineas de $BOOTSTRAP_LOG:" >&2
        tail -n 30 "$BOOTSTRAP_LOG" >&2 || true
        return 1
    fi
}

show_banner() {
    cat > "$TTY_PATH" <<EOF
${BLUE}===================================================================${NC}
${GREEN}                 MiniArch Bootstrap para Arch Live${NC}
${BLUE}===================================================================${NC}

Este bootstrap hara lo siguiente:

  1. Verificar que se ejecuta como root en el live ISO de Arch.
  2. Instalar dependencias temporales del live:
     git, curl, imagemagick, gptfdisk, e2fsprogs, dosfstools,
     archlinux-keyring,
     arch-install-scripts.
  3. Clonar o actualizar MiniArch en:
     $REPO_DIR
  4. Preparar los instaladores y herramientas:
     - install-cage-yarg.sh
     - install-cage-kiosk.sh
     - scripts/clone-miniarch.sh
     - scripts/expand-home.sh
  5. Preguntar si quieres ejecutar Cage/YARG, Cage/foot o solo abrir shell.

Salida detallada:
  $BOOTSTRAP_LOG

Para ver salida completa en consola:
  MINIARCH_VERBOSE=true

${YELLOW}Nota:${NC} el bootstrap solo prepara el entorno y lanza el instalador elegido.
La seleccion/destruccion del disco se confirma despues dentro del instalador.
${BLUE}===================================================================${NC}

EOF
}

require_root() {
    [[ "${EUID:-$(id -u)}" -eq 0 ]] || die "Ejecute este bootstrap como root desde el live ISO de Arch."
}

require_arch_live() {
    [[ -f /etc/arch-release ]] || die "No se detecto Arch Linux live. Este bootstrap es para el instalador de Arch."
    command -v pacman >/dev/null 2>&1 || die "No se encontro pacman."
}

require_tty() {
    [[ -r "$TTY_PATH" && -w "$TTY_PATH" ]] || die "No se puede leer/escribir $TTY_PATH. Ejecute desde una consola interactiva."
}

install_live_dependencies() {
    log "Instalando dependencias del live ISO..."
    run_quiet pacman -Sy --needed --noconfirm \
        archlinux-keyring git curl imagemagick gptfdisk e2fsprogs dosfstools arch-install-scripts
}

clone_or_update_repo() {
    if [[ -d "$REPO_DIR/.git" ]]; then
        log "Actualizando repo existente en $REPO_DIR"
        run_quiet git -C "$REPO_DIR" fetch --all --prune
        if [[ -n "$BRANCH" ]]; then
            run_quiet git -C "$REPO_DIR" checkout "$BRANCH"
            run_quiet git -C "$REPO_DIR" pull --ff-only
        else
            run_quiet git -C "$REPO_DIR" pull --ff-only || warn "No se pudo hacer pull fast-forward; continuando con checkout actual."
        fi
    else
        log "Clonando MiniArch en $REPO_DIR"
        if [[ -n "$BRANCH" ]]; then
            run_quiet git clone --branch "$BRANCH" "$REPO_URL" "$REPO_DIR"
        else
            run_quiet git clone "$REPO_URL" "$REPO_DIR"
        fi
    fi
}

choose_installer() {
    local choice="$DEFAULT_INSTALLER"

    case "${choice,,}" in
        yarg|cage-yarg)
            echo "install-cage-yarg.sh"
            return 0
            ;;
        kiosk|cage|foot|cage-foot)
            echo "install-cage-kiosk.sh"
            return 0
            ;;
        ask|"")
            ;;
        *)
            die "MINIARCH_INSTALLER invalido: $choice. Use yarg, kiosk o ask."
            ;;
    esac

    {
        echo ""
        echo "Que quieres instalar?"
        echo "  1) Cage + YARG (recomendado)"
        echo "  2) Cage + foot (kiosko minimal)"
        echo "  3) Solo preparar repo y abrir shell"
        echo ""
    } > "$TTY_PATH"
    read -r -p "$(echo -e "${BLUE}Seleccion: ${NC}")" choice < "$TTY_PATH"

    case "$choice" in
        1|"")
            echo "install-cage-yarg.sh"
            ;;
        2)
            echo "install-cage-kiosk.sh"
            ;;
        3)
            echo ""
            ;;
        *)
            die "Opcion invalida: $choice"
            ;;
    esac
}

show_ready_shell_notes() {
    cat <<EOF

MiniArch esta listo en:
  $REPO_DIR

Comandos utiles:
  cd $REPO_DIR
  bash install-cage-yarg.sh
  bash install-cage-kiosk.sh
  bash scripts/clone-miniarch.sh
  bash scripts/expand-home.sh

Despues de instalar:
  reboot
EOF
}

main() {
    local installer

    require_root
    require_tty
    : > "$BOOTSTRAP_LOG"
    show_banner
    require_arch_live
    install_live_dependencies
    clone_or_update_repo

    run_quiet chmod +x "$REPO_DIR"/install-cage-*.sh "$REPO_DIR"/scripts/*.sh || true

    installer="$(choose_installer)"
    if [[ -z "$installer" ]]; then
        show_ready_shell_notes
        cd "$REPO_DIR"
        exec "${SHELL:-/bin/bash}" < "$TTY_PATH"
    fi

    log "Ejecutando $installer"
    cd "$REPO_DIR"
    bash "$installer" < "$TTY_PATH"

    show_ready_shell_notes
    exec "${SHELL:-/bin/bash}" < "$TTY_PATH"
}

main "$@"
