#!/bin/bash

# Utilidades compartidas por los instaladores (install-cage-*.sh): colores,
# logging, run_quiet, prompts interactivos y limpieza ante fallos.
#
# Requiere que el instalador defina LOG_FILE antes de cargar este modulo.
# prompt_value, prompt_bool y prompt_password consultan ENV_FILE_LOADED
# (true cuando se cargo un .env); cleanup_on_exit consulta INSTALL_SUCCESS e
# INSTALL_MOUNTS_CREATED y usa cleanup_mounts de lib/finalization.sh.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${GREEN}INFO:${NC} $message" | tee -a "$LOG_FILE"
}

log_action() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${CYAN}ACTION:${NC} $message" | tee -a "$LOG_FILE"
}

log_error() {
    local message="$*"
    echo -e "[$(date '+%Y-%m-%d %H:%M:%S')] ${RED}ERROR:${NC} $message" | tee -a "$LOG_FILE" >&2
}

section() {
    echo -e "\n${CYAN}== $1 ==${NC}"
}

step() {
    printf "${MAGENTA}  > [%s]${NC} %s\n" "$1" "$2"
}

warn() {
    echo -e "${YELLOW}  ! $1${NC}"
}

run_quiet() {
    if [[ "${VERBOSE_INSTALL:-false}" == "true" ]]; then
        "$@"
        return $?
    fi

    "$@" >> "$LOG_FILE" 2>&1
}

prompt_value() {
    local var_name="$1"
    local label="$2"
    local default_value="$3"
    local current_value="${!var_name-}"
    local answer

    if [[ -n "$current_value" && "$ENV_FILE_LOADED" == "true" ]]; then
        return 0
    fi

    read -rp "$(echo -e "${BLUE}${label} (${current_value:-$default_value}): ${NC}")" answer
    answer="${answer:-${current_value:-$default_value}}"
    printf -v "$var_name" "%s" "$answer"
}

prompt_bool() {
    local var_name="$1"
    local label="$2"
    local default_value="$3"
    local current_value="${!var_name-}"
    local prompt_default answer normalized

    if [[ -n "$current_value" && "$ENV_FILE_LOADED" == "true" ]]; then
        return 0
    fi

    prompt_default="$default_value"
    [[ "$prompt_default" == "true" ]] && prompt_default="s"
    [[ "$prompt_default" == "false" ]] && prompt_default="N"

    read -rp "$(echo -e "${BLUE}${label} (s/N, default ${prompt_default}): ${NC}")" answer
    answer="${answer:-${current_value:-$default_value}}"
    normalized="${answer,,}"

    case "$normalized" in
        s|si|sí|y|yes|true|1)
            printf -v "$var_name" "%s" "true"
            ;;
        n|no|false|0)
            printf -v "$var_name" "%s" "false"
            ;;
        *)
            log_error "Respuesta invalida para $label: $answer"
            return 1
            ;;
    esac
}

prompt_password() {
    local var_name="$1"
    local label="$2"
    local current_value="${!var_name-}"
    local password confirmation

    if [[ -n "$current_value" && "$ENV_FILE_LOADED" == "true" ]]; then
        return 0
    fi

    while true; do
        read -rsp "$(echo -e "${BLUE}${label}: ${NC}")" password
        echo ""
        read -rsp "$(echo -e "${BLUE}Confirme ${label}: ${NC}")" confirmation
        echo ""

        if [[ -z "$password" ]]; then
            log_error "$label no puede quedar vacia"
            continue
        fi

        if [[ "$password" != "$confirmation" ]]; then
            log_error "Las contrasenas no coinciden"
            continue
        fi

        printf -v "$var_name" "%s" "$password"
        return 0
    done
}

cleanup_on_exit() {
    local exit_status=$?

    if [[ ${INSTALL_SUCCESS:-0} -eq 1 || $exit_status -eq 0 ]]; then
        return 0
    fi

    if [[ ${INSTALL_MOUNTS_CREATED:-0} -ne 1 ]]; then
        return "$exit_status"
    fi

    log_error "Instalacion interrumpida. Intentando desmontar particiones y desactivar swap..."
    cleanup_mounts || log_error "No se pudo completar la limpieza automatica"
    return "$exit_status"
}
