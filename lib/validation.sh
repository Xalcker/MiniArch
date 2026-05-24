#!/bin/bash

################################################################################
# Módulo de Validación
#
# Este módulo contiene funciones para validar el entorno de ejecución antes
# de comenzar la instalación de Arch Linux.
#
# Funciones:
# - validate_environment(): Verifica que se está ejecutando en Arch Linux
# - check_network(): Verifica conectividad de red
# - check_disk(): Valida que el disco existe y tiene suficiente espacio
# - select_disk_device(): Permite elegir el disco destino de forma interactiva
################################################################################

################################################################################
# validate_environment()
#
# Verifica que el script se está ejecutando desde el instalador live de
# Arch Linux comprobando la existencia de archivos específicos del sistema.
#
# Returns:
#   0 - Si se está ejecutando en el instalador de Arch Linux
#   1 - Si no se está ejecutando en Arch Linux
################################################################################
validate_environment() {
    # Verificar que existe el archivo /etc/arch-release
    if [[ ! -f /etc/arch-release ]]; then
        echo "ERROR: No se detectó Arch Linux. Este script debe ejecutarse desde el instalador live de Arch Linux." >&2
        return 1
    fi

    # Verificar que existe el comando pacstrap (específico del instalador)
    if ! command -v pacstrap &> /dev/null; then
        echo "ERROR: No se encontró el comando 'pacstrap'. Este script debe ejecutarse desde el instalador live de Arch Linux." >&2
        return 1
    fi

    echo "Entorno de Arch Linux validado correctamente."
    return 0
}

################################################################################
# check_network()
#
# Verifica que existe conectividad de red activa intentando hacer ping a
# archlinux.org.
#
# Returns:
#   0 - Si hay conectividad de red
#   1 - Si no hay conectividad de red
################################################################################
check_network() {
    # Intentar hacer ping a archlinux.org (3 paquetes, timeout de 5 segundos)
    if ! ping -c 3 -W 5 archlinux.org &> /dev/null; then
        echo "ERROR: No se detectó conexión de red. Verifique su conexión a Internet." >&2
        return 1
    fi

    echo "Conectividad de red verificada correctamente."
    return 0
}

################################################################################
# select_disk_device()
#
# Muestra los discos detectados y permite seleccionar el disco destino por numero
# o ruta. Esto reduce el riesgo de instalar por accidente en /dev/sda cuando el
# destino real es otro disco, por ejemplo una USB.
#
# Arguments:
#   $1 - Disco sugerido desde la configuracion (ej: /dev/sda o ask)
#
# Outputs:
#   Imprime el disco seleccionado en stdout.
#
# Returns:
#   0 - Si el usuario selecciona y confirma un disco valido
#   1 - Si no hay discos, la seleccion es invalida o el usuario cancela
################################################################################
select_disk_device() {
    local configured_device="${1:-ask}"
    local -a disks=()
    local disk selected answer confirmation

    if ! command -v lsblk &> /dev/null; then
        echo "ERROR: No se encontro lsblk; no se pueden listar discos." >&2
        return 1
    fi

    mapfile -t disks < <(lsblk -d -n -p -e 7,11 -o NAME,TYPE 2>/dev/null | awk '$2 == "disk" { print $1 }')

    if [[ ${#disks[@]} -eq 0 ]]; then
        echo "ERROR: No se detectaron discos instalables." >&2
        return 1
    fi

    echo "" >&2
    echo "Discos detectados:" >&2
    local index=1
    for disk in "${disks[@]}"; do
        local size tran rm model label
        size=$(lsblk -d -n -o SIZE "$disk" 2>/dev/null | awk '{$1=$1; print}')
        tran=$(lsblk -d -n -o TRAN "$disk" 2>/dev/null | awk '{$1=$1; print}')
        rm=$(lsblk -d -n -o RM "$disk" 2>/dev/null | awk '{$1=$1; print}')
        model=$(lsblk -d -n -o MODEL "$disk" 2>/dev/null | awk '{$1=$1; print}')
        label=""

        if [[ "$tran" == "usb" || "$rm" == "1" ]]; then
            label=" [USB/removible]"
        fi

        printf "  %d) %-14s %-8s %-10s %s%s\n" "$index" "$disk" "${size:-?}" "${tran:-local}" "${model:-sin-modelo}" "$label" >&2
        index=$((index + 1))
    done
    echo "" >&2

    if [[ "$configured_device" != "ask" && -n "$configured_device" ]]; then
        echo "Disco configurado actualmente: $configured_device" >&2
        read -rp "Presione Enter para usarlo, elija un numero, escriba otra ruta (/dev/...) o 'cancelar': " answer
        answer="${answer:-$configured_device}"
    else
        read -rp "Elija el disco destino por numero o ruta (/dev/...); 'cancelar' para salir: " answer
    fi

    case "${answer,,}" in
        cancelar|cancel|q|quit|salir)
            echo "Operacion cancelada por el usuario." >&2
            return 1
            ;;
    esac

    if [[ "$answer" =~ ^[0-9]+$ ]]; then
        if (( answer < 1 || answer > ${#disks[@]} )); then
            echo "ERROR: Seleccion fuera de rango: $answer" >&2
            return 1
        fi
        selected="${disks[$((answer - 1))]}"
    else
        selected="$answer"
    fi

    if [[ ! -b "$selected" ]]; then
        echo "ERROR: El dispositivo '$selected' no existe o no es un dispositivo de bloque." >&2
        return 1
    fi

    echo "" >&2
    echo "Resumen del disco seleccionado:" >&2
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL "$selected" >&2
    echo "" >&2
    echo "ADVERTENCIA: La instalacion borrara particiones y datos en $selected." >&2
    read -rp "Para confirmar escriba INSTALAR o instalar: " confirmation

    if [[ "${confirmation,,}" != "instalar" ]]; then
        echo "Operacion cancelada. No se modificara el disco." >&2
        return 1
    fi

    echo "$selected"
    return 0
}

################################################################################
# check_disk()
#
# Verifica que el disco especificado existe y tiene al menos 16GB de capacidad.
#
# Arguments:
#   $1 - Ruta del dispositivo de disco (ej: /dev/sda)
#
# Returns:
#   0 - Si el disco existe y tiene >= 16GB
#   1 - Si el disco no existe o tiene < 16GB
################################################################################
check_disk() {
    local disk_device="$1"

    # Verificar que se proporcionó un argumento
    if [[ -z "$disk_device" ]]; then
        echo "ERROR: No se especificó un dispositivo de disco." >&2
        return 1
    fi

    # Verificar que el dispositivo existe
    if [[ ! -b "$disk_device" ]]; then
        echo "ERROR: El dispositivo '$disk_device' no existe o no es un dispositivo de bloque." >&2
        return 1
    fi

    # Obtener el tamaño del disco en GB usando lsblk
    local disk_size_bytes
    disk_size_bytes=$(lsblk -b -d -n -o SIZE "$disk_device" 2>/dev/null)

    if [[ -z "$disk_size_bytes" ]]; then
        echo "ERROR: No se pudo obtener el tamaño del disco '$disk_device'." >&2
        return 1
    fi

    # Convertir bytes a GB (1 GB = 1024^3 bytes)
    local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))

    # Verificar que el disco tiene al menos 16GB
    if [[ $disk_size_gb -lt 16 ]]; then
        echo "ERROR: El disco '$disk_device' tiene solo ${disk_size_gb}GB. Se requieren al menos 16GB." >&2
        return 1
    fi

    echo "Disco '$disk_device' validado correctamente (${disk_size_gb}GB disponibles)."
    return 0
}

################################################################################
# check_disk_empty()
#
# Verifica si el disco especificado tiene particiones existentes. Si las tiene,
# muestra una advertencia y solicita confirmación explícita del usuario antes
# de continuar.
#
# Arguments:
#   $1 - Ruta del dispositivo de disco (ej: /dev/sda)
#
# Returns:
#   0 - Si el disco está vacío o el usuario confirma la destrucción de datos
#   1 - Si el usuario cancela la operación
################################################################################
check_disk_empty() {
    local disk_device="$1"

    # Verificar que se proporcionó un argumento
    if [[ -z "$disk_device" ]]; then
        echo "ERROR: No se especificó un dispositivo de disco." >&2
        return 1
    fi

    # Verificar que el dispositivo existe
    if [[ ! -b "$disk_device" ]]; then
        echo "ERROR: El dispositivo '$disk_device' no existe o no es un dispositivo de bloque." >&2
        return 1
    fi

    # Verificar si el disco tiene particiones usando lsblk
    local partition_count
    partition_count=$(lsblk -n -o TYPE "$disk_device" 2>/dev/null | awk '$1 == "part" { count++ } END { print count + 0 }')

    # Si no hay particiones, el disco está vacío
    if [[ $partition_count -eq 0 ]]; then
        echo "El disco '$disk_device' está vacío. Continuando con la instalación."
        return 0
    fi

    # Si hay particiones, mostrar advertencia
    echo "⚠️  ADVERTENCIA: El disco '$disk_device' contiene $partition_count partición(es) existente(s)." >&2
    echo "⚠️  TODOS LOS DATOS EN ESTE DISCO SERÁN DESTRUIDOS." >&2
    echo "" >&2

    # Mostrar las particiones existentes
    echo "Particiones existentes:" >&2
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$disk_device" >&2
    echo "" >&2

    # Solicitar confirmación explícita del usuario
    echo -n "¿Está seguro de que desea continuar y destruir todos los datos? (sí/no): " >&2
    read -r confirmation

    # Verificar la respuesta del usuario
    if [[ "$confirmation" == "sí" || "$confirmation" == "si" || "$confirmation" == "SI" || "$confirmation" == "SÍ" ]]; then
        echo "Confirmación recibida. Continuando con la instalación."
        return 0
    else
        echo "Operación cancelada por el usuario. No se modificará el disco." >&2
        return 1
    fi
}

################################################################################
# validate_security_config()
#
# Valida parámetros de seguridad antes de modificar el sistema. La contraseña
# del usuario kiosko debe definirse explícitamente y no puede conservar valores
# de ejemplo salvo que se habilite ALLOW_INSECURE_DEFAULT_PASSWORD=true para
# laboratorios o VMs descartables.
#
# Returns:
#   0 - Si la configuración es aceptable
#   1 - Si la contraseña falta o es insegura
################################################################################
validate_security_config() {
    local password="${KIOSK_PASSWORD:-}"
    local root_password="${ROOT_PASSWORD:-}"
    local require_root_password="${REQUIRE_ROOT_PASSWORD:-false}"
    local allow_insecure="${ALLOW_INSECURE_DEFAULT_PASSWORD:-false}"

    if [[ -z "$password" ]]; then
        echo "ERROR: KIOSK_PASSWORD debe definirse en .env antes de ejecutar el instalador." >&2
        return 1
    fi

    if [[ "$require_root_password" == "true" && -z "$root_password" ]]; then
        echo "ERROR: ROOT_PASSWORD debe definirse en .env antes de ejecutar el instalador." >&2
        return 1
    fi

    if [[ "$password" == "kiosk" || "$password" == "kiosk123" || "$password" == "change-me" ]]; then
        if [[ "$allow_insecure" != "true" ]]; then
            echo "ERROR: KIOSK_PASSWORD usa un valor de ejemplo inseguro. Cambie la contraseña o use ALLOW_INSECURE_DEFAULT_PASSWORD=true solo en pruebas." >&2
            return 1
        fi
        echo "ADVERTENCIA: Se permitió una contraseña de ejemplo insegura para un entorno de pruebas." >&2
    fi

    if [[ "$require_root_password" == "true" && ( "$root_password" == "root" || "$root_password" == "change-root" ) ]]; then
        if [[ "$allow_insecure" != "true" ]]; then
            echo "ERROR: ROOT_PASSWORD usa un valor de ejemplo inseguro. Cambie la contraseña o use ALLOW_INSECURE_DEFAULT_PASSWORD=true solo en pruebas." >&2
            return 1
        fi
        echo "ADVERTENCIA: Se permitió una contraseña root de ejemplo insegura para un entorno de pruebas." >&2
    fi

    if [[ "${ENABLE_SSH:-true}" == "true" ]]; then
        echo "ADVERTENCIA: SSH quedará habilitado; use una contraseña fuerte y limite el acceso de red." >&2
    fi

    return 0
}

################################################################################
# preflight_optional_assets()
#
# Valida assets opcionales antes de iniciar operaciones destructivas. Plymouth se
# considera opcional: si la imagen no existe se omite la personalización visual,
# pero si existe debe ser PNG válido. El cursor también es opcional y solo genera
# advertencias cuando falta.
#
# Arguments:
#   $1 - Ruta de imagen Plymouth
#   $2 - Ruta de cursor personalizado
#
# Returns:
#   0 - Si los assets faltantes son opcionales o son válidos
#   1 - Si existe una imagen Plymouth inválida
################################################################################
preflight_optional_assets() {
    local plymouth_image_path="$1"
    local cursor_path="$2"

    PLYMOUTH_ASSET_AVAILABLE=false

    if [[ -z "$plymouth_image_path" ]]; then
        echo "ADVERTENCIA: PLYMOUTH_IMAGE_PATH está vacío; se omitirá Plymouth personalizado." >&2
    elif [[ ! -f "$plymouth_image_path" ]]; then
        echo "ADVERTENCIA: No existe la imagen Plymouth '$plymouth_image_path'; se omitirá la personalización de Plymouth." >&2
    else
        local file_type
        if ! command -v file &> /dev/null; then
            echo "ERROR: No se encontró el comando 'file' para validar la imagen Plymouth." >&2
            return 1
        fi

        file_type=$(file -b --mime-type "$plymouth_image_path")
        if [[ "$file_type" != "image/png" ]]; then
            echo "ERROR: La imagen Plymouth debe ser PNG válido: $plymouth_image_path (detectado: $file_type)." >&2
            return 1
        fi

        PLYMOUTH_ASSET_AVAILABLE=true
        echo "Imagen Plymouth validada correctamente."

        if ! command -v identify &> /dev/null; then
            echo "ADVERTENCIA: ImageMagick 'identify' no está disponible; no se validarán dimensiones antes de instalar." >&2
        fi

        if ! command -v convert &> /dev/null && ! command -v magick &> /dev/null; then
            echo "ADVERTENCIA: ImageMagick no está disponible en el entorno live; Plymouth copiará el PNG sin escalar." >&2
        fi
    fi

    if [[ -z "$cursor_path" ]]; then
        echo "ADVERTENCIA: CURSOR_PATH está vacío; se omitirá cursor personalizado." >&2
    elif [[ ! -e "$cursor_path" ]]; then
        echo "ADVERTENCIA: No existe el cursor '$cursor_path'; se omitirá cursor personalizado." >&2
    else
        echo "Cursor personalizado encontrado: $cursor_path"
    fi

    export PLYMOUTH_ASSET_AVAILABLE
    return 0
}
