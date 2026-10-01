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

# ---------------------------------------------------------------------------
# Carga de .env
# ---------------------------------------------------------------------------
#
# El .env NO se ejecuta como codigo (antes se hacia con `source`): se lee linea
# por linea con formato CLAVE=valor y el valor nunca se evalua.
#
# Formato:
#   CLAVE=valor              literal; admite espacios y simbolos ($, &, ;, (, ...)
#   CLAVE="valor"            admite los escapes \\ \" \$ \`
#   CLAVE='valor'            totalmente literal (ideal para passwords)
#   CLAVE=valor # nota       un " #" sin comillas inicia un comentario
#   export CLAVE=valor       el "export" se tolera
#   # comentario             y lineas en blanco se ignoran
#
# Solo se expande ${NOMBRE} (con llaves) con variables ya definidas; un $ suelto
# queda tal cual y no existe la sustitucion de comandos. Se aceptan finales de
# linea CRLF.

# Variables que un .env nunca puede modificar: afectan al propio instalador.
ENV_FILE_FORBIDDEN_KEYS=" PATH IFS HOME SHELL BASH_ENV ENV PS4 PROMPT_COMMAND LD_PRELOAD LD_LIBRARY_PATH SCRIPT_DIR "

# env_parse_value TEXTO -> deja el resultado en ENV_PARSED_VALUE.
# Devuelve 1 si las comillas estan mal cerradas o hay texto tras el cierre.
env_parse_value() {
    local __e_raw="$1" __e_mode="plain" __e_out="" __e_i=0 __e_n __e_ch __e_next __e_rest __e_name __e_closed=false __e_tail

    if [[ "$__e_raw" == \"* ]]; then
        __e_mode="double"
        __e_raw="${__e_raw:1}"
    elif [[ "$__e_raw" == \'* ]]; then
        __e_mode="single"
        __e_raw="${__e_raw:1}"
    fi

    __e_n=${#__e_raw}
    while ((__e_i < __e_n)); do
        __e_ch="${__e_raw:__e_i:1}"

        if [[ "$__e_mode" == "single" ]]; then
            if [[ "$__e_ch" == "'" ]]; then
                __e_closed=true
                __e_i=$((__e_i + 1))
                break
            fi
            __e_out+="$__e_ch"
            __e_i=$((__e_i + 1))
            continue
        fi

        if [[ "$__e_mode" == "double" ]]; then
            if [[ "$__e_ch" == '"' ]]; then
                __e_closed=true
                __e_i=$((__e_i + 1))
                break
            fi
            if [[ "$__e_ch" == '\' ]]; then
                __e_next="${__e_raw:__e_i+1:1}"
                case "$__e_next" in
                    '\' | '"' | '$' | '`')
                        __e_out+="$__e_next"
                        __e_i=$((__e_i + 2))
                        continue
                        ;;
                esac
            fi
        else
            # Sin comillas: " #" (o # al inicio) empieza un comentario.
            if [[ "$__e_ch" == "#" ]] && ((__e_i == 0)) || [[ "$__e_ch" == "#" && "${__e_raw:__e_i-1:1}" == [[:space:]] ]]; then
                break
            fi
        fi

        if [[ "$__e_ch" == '$' && "${__e_raw:__e_i+1:1}" == '{' ]]; then
            __e_rest="${__e_raw:__e_i+2}"
            if [[ "$__e_rest" =~ ^([A-Za-z_][A-Za-z0-9_]*)\} ]]; then
                __e_name="${BASH_REMATCH[1]}"
                __e_out+="${!__e_name-}"
                __e_i=$((__e_i + 2 + ${#BASH_REMATCH[0]}))
                continue
            fi
        fi

        __e_out+="$__e_ch"
        __e_i=$((__e_i + 1))
    done

    if [[ "$__e_mode" != "plain" ]]; then
        [[ "$__e_closed" == "true" ]] || return 1
        __e_tail="${__e_raw:__e_i}"
        __e_tail="${__e_tail#"${__e_tail%%[![:space:]]*}"}"
        [[ -z "$__e_tail" || "$__e_tail" == \#* ]] || return 1
    else
        __e_out="${__e_out%"${__e_out##*[![:space:]]}"}"
    fi

    ENV_PARSED_VALUE="$__e_out"
}

# load_env_file RUTA -> exporta cada CLAVE=valor del archivo.
# Devuelve 1 (sin cargar mas lineas) ante una linea invalida o una clave prohibida.
load_env_file() {
    local __e_file="$1" __e_line __e_key __e_value __e_lineno=0

    if [[ ! -r "$__e_file" ]]; then
        log_error "No se puede leer $__e_file"
        return 1
    fi

    while IFS= read -r __e_line || [[ -n "$__e_line" ]]; do
        __e_lineno=$((__e_lineno + 1))
        __e_line="${__e_line%$'\r'}"
        __e_line="${__e_line#"${__e_line%%[![:space:]]*}"}"

        [[ -z "$__e_line" || "$__e_line" == \#* ]] && continue

        if [[ "$__e_line" == "export "* ]]; then
            __e_line="${__e_line#export }"
            __e_line="${__e_line#"${__e_line%%[![:space:]]*}"}"
        fi

        if [[ ! "$__e_line" =~ ^([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*=(.*)$ ]]; then
            log_error "$__e_file:$__e_lineno: linea invalida; se esperaba CLAVE=valor"
            return 1
        fi

        __e_key="${BASH_REMATCH[1]}"
        __e_value="${BASH_REMATCH[2]}"

        if [[ "$__e_key" == __* || "$ENV_FILE_FORBIDDEN_KEYS" == *" $__e_key "* ]]; then
            log_error "$__e_file:$__e_lineno: la variable $__e_key no se puede definir desde .env"
            return 1
        fi

        __e_value="${__e_value#"${__e_value%%[![:space:]]*}"}"

        if ! env_parse_value "$__e_value"; then
            log_error "$__e_file:$__e_lineno: comillas sin cerrar o texto despues de las comillas en $__e_key"
            return 1
        fi

        printf -v "$__e_key" '%s' "$ENV_PARSED_VALUE"
        # shellcheck disable=SC2163
        export "$__e_key"
    done < "$__e_file"
}
