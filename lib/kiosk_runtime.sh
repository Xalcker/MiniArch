#!/usr/bin/env bash
# =============================================================================
# lib/kiosk_runtime.sh
# -----------------------------------------------------------------------------
# Piezas comunes de los kioscos Cage (YARG, Clone Hero y RPCS3):
#   - kiosk_wrapper_prelude: prologo del wrapper run-<app>.sh (entorno, DBus,
#     PipeWire). Cada app agrega su bloque especifico despues.
#   - configure_kiosk_audio_output / cuantum de PipeWire / volumen: audio comun.
#   - install_kiosk_exit_hotkey: atajo Ctrl+Alt+Q para cerrar la app.
#   - configure_kiosk_performance / configure_kiosk_zram: limites, sysctl, cpupower
#     y swap comprimido en RAM.
#   - install_kiosk_menu: menu de mantenimiento /usr/local/bin/kiosk-menu.sh.
#   - install_cage_service: servicio cage-kiosk.service.
# Un arreglo en estas piezas aplica a las tres apps.
# =============================================================================

# Elige por que salida suenan los kioscos (hdmi/dp, analog o auto). Se logra
# subiendo la prioridad de los sinks HDMI/DP o analogicos con una regla de
# WirePlumber en el home del usuario; si el dispositivo preferido no existe,
# WirePlumber cae solo al otro. El wrapper arranca wireplumber como el usuario,
# asi que toma ~/.config/wireplumber/wireplumber.conf.d/.
# Uso: configure_kiosk_audio_output [hdmi|dp|analog|auto]   (por defecto hdmi)
configure_kiosk_audio_output() {
    local output="${1:-hdmi}"
    local conf_dir="/mnt/home/$KIOSK_USER/.config/wireplumber/wireplumber.conf.d"
    local pattern

    case "${output,,}" in
        hdmi|dp)
            pattern='~alsa_output.*hdmi.*'
            ;;
        analog)
            pattern='~alsa_output.*analog.*'
            ;;
        auto)
            log "Salida de audio automatica (auto)"
            return 0
            ;;
        *)
            warn "Salida de audio invalida: $output; se deja la salida automatica."
            return 0
            ;;
    esac

    log "Priorizando la salida de audio: ${output,,}"
    mkdir -p "$conf_dir"

    cat > "$conf_dir/51-kiosk-audio-output.conf" << EOF_CONF
monitor.alsa.rules = [
  {
    matches = [ { node.name = "$pattern" } ]
    actions = { update-props = { priority.session = 3000, priority.driver = 3000 } }
  }
]
EOF_CONF

    run_quiet arch-chroot /mnt chown -R "$KIOSK_USER:$KIOSK_USER" "/home/$KIOSK_USER/.config"
}

# Valida un volumen de audio (0 a 1, o vacio). Uso: validate_kiosk_audio_volume <NOMBRE> <valor>
validate_kiosk_audio_volume() {
    local name="$1" value="$2"

    if [[ -n "$value" && ! "$value" =~ ^(0(\.[0-9]+)?|1(\.0+)?)$ ]]; then
        log_error "$name invalido: $value. Use un numero entre 0 y 1 (por ejemplo 1.0) o vacio."
        return 1
    fi
}

# Valida el cuantum de PipeWire (32 a 2048 muestras, o vacio).
# Uso: validate_kiosk_pipewire_quantum <NOMBRE> <valor>
validate_kiosk_pipewire_quantum() {
    local name="$1" value="$2"

    if [[ -n "$value" ]] && { [[ ! "$value" =~ ^[0-9]+$ ]] || (( value < 32 || value > 2048 )); }; then
        log_error "$name invalido: $value. Use un numero entre 32 y 2048 (por ejemplo 128) o vacio."
        return 1
    fi
}

# Limites de tiempo real, swappiness y gobernador cpupower=performance para la app.
# Uso: configure_kiosk_performance <app> [clave=valor de sysctl...]
configure_kiosk_performance() {
    local app="$1" slug line
    shift
    slug="${app,,}"
    slug="${slug// /}"

    log "Aplicando optimizaciones de rendimiento para $app"

    mkdir -p /mnt/etc/security/limits.d /mnt/etc/sysctl.d /mnt/etc/default

    cat > "/mnt/etc/security/limits.d/99-$slug.conf" << EOF_LIMITS
$KIOSK_USER - rtprio 99
$KIOSK_USER - memlock unlimited
$KIOSK_USER - nice -20
EOF_LIMITS

    # Con zram, swapear es barato (memoria comprimida): se usa de inmediato y las
    # paginas se leen de una en una (page-cluster=0). Sin zram, el swap es de disco
    # y se evita en lo posible.
    if [[ "${ZRAM_ENABLED:-true}" == "true" ]]; then
        printf '%s\n' 'vm.swappiness=100' 'vm.page-cluster=0' > "/mnt/etc/sysctl.d/99-$slug.conf"
    else
        echo 'vm.swappiness=10' > "/mnt/etc/sysctl.d/99-$slug.conf"
    fi
    for line in "$@"; do
        echo "$line" >> "/mnt/etc/sysctl.d/99-$slug.conf"
    done

    cat > /mnt/etc/default/cpupower << 'EOF_CPUPOWER'
# Versiones antiguas del servicio cpupower leen este archivo (en minusculas o
# mayusculas). Se escriben ambas formas.
GOVERNOR='performance'
MIN_FREQ=''
MAX_FREQ=''
governor='performance'
min_freq=''
max_freq=''
EOF_CPUPOWER

    # Los paquetes recientes de cpupower leen su configuracion de este otro
    # archivo (EnvironmentFile de la unidad), no de /etc/default/cpupower: sin ese
    # archivo el servicio termina con exito pero el gobernador queda en schedutil.
    cat > /mnt/etc/default/cpupower-service.conf << 'EOF_CPUPOWER_SERVICE'
GOVERNOR='performance'
MIN_FREQ=''
MAX_FREQ=''
EOF_CPUPOWER_SERVICE

    if ! run_quiet arch-chroot /mnt systemctl enable cpupower.service; then
        log_error "Fallo al habilitar cpupower.service"
        return 1
    fi
}

# Valida ZRAM_ENABLED (true/false) y ZRAM_MAX_MB (numero >= 256).
validate_kiosk_zram() {
    if [[ "${ZRAM_ENABLED:-true}" != "true" && "${ZRAM_ENABLED:-true}" != "false" ]]; then
        log_error "ZRAM_ENABLED invalido: ${ZRAM_ENABLED}. Use true o false."
        return 1
    fi

    if [[ ! "${ZRAM_MAX_MB:-4096}" =~ ^[0-9]+$ ]] || (( ${ZRAM_MAX_MB:-4096} < 256 )); then
        log_error "ZRAM_MAX_MB invalido: ${ZRAM_MAX_MB}. Use un numero de MiB de 256 o mas (por ejemplo 4096)."
        return 1
    fi
}

# Swap comprimido en RAM (zram) por delante del swap de disco. El tamano es la mitad
# de la RAM con un tope de ZRAM_MAX_MB; el swap de disco baja a prioridad 10 y queda
# como respaldo para cuando zram se llena. zram-generator lo activa al arrancar.
# Uso: configure_kiosk_zram   (respeta ZRAM_ENABLED=false)
configure_kiosk_zram() {
    local root="${INSTALL_ROOT:-/mnt}" max_mb="${ZRAM_MAX_MB:-4096}"
    local fstab="$root/etc/fstab"

    if [[ "${ZRAM_ENABLED:-true}" != "true" ]]; then
        log "zram omitido (ZRAM_ENABLED=false)"
        return 0
    fi

    log "Configurando zram (mitad de la RAM, maximo ${max_mb} MiB, zstd)"
    mkdir -p "$root/etc/systemd"

    cat > "$root/etc/systemd/zram-generator.conf" << EOF_ZRAM
[zram0]
zram-size = min(ram / 2, $max_mb)
compression-algorithm = zstd
swap-priority = 100
EOF_ZRAM

    # genfstab deja el swap de disco sin prioridad; se baja para que zram vaya primero.
    if [[ -f "$fstab" ]]; then
        sed -i -E '/^[^#].*[[:space:]]swap[[:space:]]/{/pri=/!s/(swap[[:space:]]+)defaults/\1defaults,pri=10/}' "$fstab"
    fi
}

# Atajo Ctrl+Alt+Q para cerrar la app: script comun que lee los teclados y termina
# los procesos que le pase el wrapper (start_kiosk_exit_hotkey).
read -r -d '' KIOSK_EXIT_HOTKEY_TEMPLATE <<'TEMPLATE' || true
#!/usr/bin/env python3
"""Cierra la app del kiosko con un atajo, sin depender del compositor ni de la ventana.

Lee los teclados directamente (como evmapy/hotkeygen en Batocera): Ctrl + Alt + Q.
Al detectar la combinacion termina los procesos indicados; el wrapper del kiosko
vuelve entonces al menu de mantenimiento. Los instrumentos (guitarras, baterias)
se ignoran.

Uso: kiosk-exit-hotkey.py [--list] PROCESO...

Cada PROCESO es un nombre exacto (pkill -x) o, si empieza por /, un prefijo de la
ruta del ejecutable (p. ej. /opt/YARG/). --list muestra que dispositivos detecta.
"""
import glob
import os
import re
import select
import struct
import subprocess
import sys
import time

EV_KEY = 1
# struct input_event en x86_64: timeval (2 long), type, code, value.
EVENT = struct.Struct("llHHi")

KEY_Q, KEY_LEFTCTRL, KEY_LEFTALT, KEY_RIGHTCTRL, KEY_RIGHTALT = 16, 29, 56, 97, 100

CTRL = {KEY_LEFTCTRL, KEY_RIGHTCTRL}
ALT = {KEY_LEFTALT, KEY_RIGHTALT}
EXCLUDED_NAMES = ("santroller", "guitar", "drum", "harmonix", "rock band", "keytar")
RESCAN_SECONDS = 5
COOLDOWN_SECONDS = 3
GRACE_SECONDS = 3


def read_sysfs(event, name):
    try:
        with open("/sys/class/input/%s/device/%s" % (event, name)) as f:
            return f.read().strip()
    except OSError:
        return ""


def key_capabilities(event):
    """Devuelve la mascara de teclas/botones del dispositivo como entero."""
    mask = 0
    words = read_sysfs(event, "capabilities/key").split()
    for i, word in enumerate(reversed(words)):
        mask |= int(word, 16) << (64 * i)
    return mask


def classify(mask, name):
    """Tipos de atajo que admite un dispositivo: 'kbd' si es un teclado."""
    if any(excluded in name.lower() for excluded in EXCLUDED_NAMES):
        return set()
    has = lambda code: (mask >> code) & 1
    kinds = set()
    if has(KEY_Q) and has(KEY_LEFTCTRL) and has(KEY_LEFTALT):
        kinds.add("kbd")
    return kinds


def combo_pressed(kinds, held):
    if "kbd" in kinds and held & CTRL and held & ALT and KEY_Q in held:
        return "teclado"
    return None


def scan(devices, opened):
    for path in sorted(glob.glob("/dev/input/event*")):
        if path in opened:
            continue
        event = os.path.basename(path)
        name = read_sysfs(event, "name")
        kinds = classify(key_capabilities(event), name)
        if not kinds:
            continue
        try:
            fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        except OSError:
            continue
        opened.add(path)
        devices[fd] = {"path": path, "name": name, "kinds": kinds, "held": set()}
        print("kiosk-exit-hotkey: vigilando %s (%s) [%s]" % (path, name, ",".join(sorted(kinds))), flush=True)


def close_device(devices, opened, fd):
    opened.discard(devices[fd]["path"])
    try:
        os.close(fd)
    except OSError:
        pass
    del devices[fd]


def match_args(target):
    """Argumentos de pgrep/pkill para un objetivo: ruta (prefijo) o nombre exacto."""
    if target.startswith("/"):
        return ["-f", "^" + re.escape(target)]
    return ["-x", target]


def running(targets):
    """True si queda algun proceso vivo con esos nombres (un zombi no cuenta)."""
    for target in targets:
        out = subprocess.run(["pgrep"] + match_args(target), capture_output=True, text=True).stdout.split()
        for pid in out:
            try:
                with open("/proc/%s/stat" % pid) as f:
                    state = f.read().rsplit(")", 1)[1].split()[0]
            except (OSError, IndexError):
                continue
            if state != "Z":
                return True
    return False


def terminate_app(source, targets, grace=GRACE_SECONDS):
    print("kiosk-exit-hotkey: combinacion de %s; cerrando la app" % source, flush=True)
    for target in targets:
        subprocess.run(["pkill"] + match_args(target), check=False)

    # Algunas apps (la GUI de RPCS3) atrapan SIGTERM y no siempre salen:
    # si pasado el plazo sigue vivo, se escala a SIGKILL.
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline:
        if not running(targets):
            return
        time.sleep(0.25)
    print("kiosk-exit-hotkey: la app no salio con SIGTERM; forzando SIGKILL", flush=True)
    for target in targets:
        subprocess.run(["pkill", "-9"] + match_args(target), check=False)


def main():
    devices, opened = {}, set()
    targets = [arg for arg in sys.argv[1:] if not arg.startswith("--")]

    if "--list" in sys.argv:
        scan(devices, opened)
        if not devices:
            print("Sin dispositivos compatibles.")
        return 0

    if not targets:
        print("Uso: kiosk-exit-hotkey.py [--list] PROCESO...", file=sys.stderr)
        return 2

    last_scan = last_fire = 0.0
    while True:
        now = time.monotonic()
        if now - last_scan >= RESCAN_SECONDS:
            scan(devices, opened)
            last_scan = now

        if not devices:
            time.sleep(1)
            continue

        ready, _, _ = select.select(list(devices), [], [], 1.0)
        for fd in ready:
            dev = devices[fd]
            try:
                data = os.read(fd, EVENT.size * 64)
            except BlockingIOError:
                continue
            except OSError:
                close_device(devices, opened, fd)
                continue

            for offset in range(0, len(data) - EVENT.size + 1, EVENT.size):
                _, _, etype, code, value = EVENT.unpack_from(data, offset)
                if etype != EV_KEY:
                    continue
                if value:
                    dev["held"].add(code)
                else:
                    dev["held"].discard(code)

                source = combo_pressed(dev["kinds"], dev["held"]) if value == 1 else None
                if source and time.monotonic() - last_fire >= COOLDOWN_SECONDS:
                    last_fire = time.monotonic()
                    terminate_app(source, targets)


if __name__ == "__main__":
    sys.exit(main())
TEMPLATE

# Instala /usr/local/bin/kiosk-exit-hotkey.py. Uso: install_kiosk_exit_hotkey <true|false> <app>
install_kiosk_exit_hotkey() {
    local enabled="${1:-true}" app="${2:-la app}"

    if [[ "$enabled" != "true" ]]; then
        log "Atajo de salida omitido (${app}_EXIT_HOTKEY=false)"
        return 0
    fi

    log "Instalando atajo de salida de $app (Ctrl+Alt+Q)"
    mkdir -p /mnt/usr/local/bin
    printf '%s\n' "$KIOSK_EXIT_HOTKEY_TEMPLATE" > /mnt/usr/local/bin/kiosk-exit-hotkey.py
    chmod 755 /mnt/usr/local/bin/kiosk-exit-hotkey.py
}

# Prologo del wrapper. Uso: kiosk_wrapper_prelude <etiqueta> <home> <render-software> [volumen] [cuantum]
#   etiqueta         prefijo de los mensajes (p. ej. run-yarg)
#   home             valor por defecto de HOME
#   render-software  true/false (o un marcador que se sustituye despues)
#   volumen          volumen de la salida al arrancar, de 0 a 1 (o un marcador);
#                    vacio no lo toca
#   cuantum          tamano de ciclo de PipeWire en muestras (32 a 2048); vacio no lo toca
# Deja definidas las funciones wait_for_path, wait_for_pulse_sink y
# start_kiosk_audio <nombre-app>.
kiosk_wrapper_prelude() {
    local tag="$1" home="$2" software="$3" volume="${4-}" quantum="${5-}"
    local out

    read -r -d '' out <<'PRELUDE' || true
#!/usr/bin/env bash
set -euo pipefail

echo "__KIOSK_TAG__: iniciado como $(id -un) pid=$$" >&2

KIOSK_FORCE_SOFTWARE_RENDER="__KIOSK_SOFTWARE__"
KIOSK_AUDIO_VOLUME="__KIOSK_AUDIO_VOLUME__"
KIOSK_PIPEWIRE_QUANTUM="__KIOSK_PIPEWIRE_QUANTUM__"

case "${KIOSK_FORCE_SOFTWARE_RENDER,,}" in
    true|yes|si|1)
        echo "__KIOSK_TAG__: usando render por software por configuracion" >&2
        export WLR_RENDERER_ALLOW_SOFTWARE=1
        export WLR_NO_HARDWARE_CURSORS=1
        export LIBGL_ALWAYS_SOFTWARE=1
        export GALLIUM_DRIVER=llvmpipe
        ;;
esac

export HOME="${HOME:-__KIOSK_HOME__}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=cage
export PIPEWIRE_RUNTIME_DIR="$XDG_RUNTIME_DIR"
echo "__KIOSK_TAG__: XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR" >&2

if [[ -d /usr/share/icons/MiniArchPick ]]; then
    export XCURSOR_THEME=MiniArchPick
    export XCURSOR_SIZE=64
fi
if [[ -x /usr/bin/Xwayland ]]; then
    export WLR_XWAYLAND=/usr/bin/Xwayland
else
    unset WLR_XWAYLAND
fi

dbus_session_is_usable() {
    local dbus_path=""

    if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
        return 1
    fi

    case "$DBUS_SESSION_BUS_ADDRESS" in
        unix:path=*)
            dbus_path="${DBUS_SESSION_BUS_ADDRESS#unix:path=}"
            dbus_path="${dbus_path%%,*}"
            [[ -S "$dbus_path" ]] || return 1
            ;;
    esac

    if command -v dbus-send >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        timeout 1 dbus-send --session --dest=org.freedesktop.DBus \
            --type=method_call / org.freedesktop.DBus.ListNames >/dev/null 2>&1
        return $?
    fi

    return 0
}

if ! dbus_session_is_usable; then
    echo "__KIOSK_TAG__: DBus de sesion ausente o invalido" >&2
    unset DBUS_SESSION_BUS_ADDRESS
fi

if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" && -z "${KIOSK_DBUS_SESSION_STARTED:-}" ]]; then
    if command -v dbus-run-session >/dev/null 2>&1; then
        echo "__KIOSK_TAG__: iniciando DBus de sesion" >&2
        export KIOSK_DBUS_SESSION_STARTED=1
        exec dbus-run-session -- "$0"
    fi

    echo "Aviso: dbus-run-session no esta disponible; continuando sin DBus de sesion." >&2
fi

echo "__KIOSK_TAG__: DBus=${DBUS_SESSION_BUS_ADDRESS:-sin-dbus}" >&2

wait_for_path() {
    local path="$1"
    local attempts="${2:-100}"

    for _ in $(seq 1 "$attempts"); do
        [[ -e "$path" ]] && return 0
        sleep 0.1
    done

    return 1
}

wait_for_pulse_sink() {
    local attempts="${1:-50}"

    if ! command -v pactl >/dev/null 2>&1; then
        return 1
    fi

    for _ in $(seq 1 "$attempts"); do
        if command -v timeout >/dev/null 2>&1; then
            timeout 1 pactl list short sinks 2>/dev/null | grep -q . && return 0
        elif pactl list short sinks 2>/dev/null | grep -q .; then
            return 0
        fi
        sleep 0.1
    done

    return 1
}

# Levanta PipeWire, WirePlumber y pipewire-pulse en orden. $1: nombre de la app.
start_kiosk_audio() {
    local app="$1"

    if command -v pipewire >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire >/dev/null 2>&1; then
        echo "__KIOSK_TAG__: iniciando pipewire" >&2
        pipewire 2>&1 | sed 's/^/[pipewire] /' &
    fi

    wait_for_path "$XDG_RUNTIME_DIR/pipewire-0" 100 || \
        echo "Aviso: PipeWire no creo $XDG_RUNTIME_DIR/pipewire-0 a tiempo." >&2

    if command -v wireplumber >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x wireplumber >/dev/null 2>&1; then
        echo "__KIOSK_TAG__: iniciando wireplumber" >&2
        wireplumber 2>&1 | sed 's/^/[wireplumber] /' &
    fi

    sleep 1

    if command -v pipewire-pulse >/dev/null 2>&1 && ! pgrep -u "$(id -u)" -x pipewire-pulse >/dev/null 2>&1; then
        echo "__KIOSK_TAG__: iniciando pipewire-pulse" >&2
        pipewire-pulse 2>&1 | sed 's/^/[pipewire-pulse] /' &
    fi

    echo "__KIOSK_TAG__: esperando sink Pulse/PipeWire" >&2
    wait_for_pulse_sink 50 || \
        echo "Aviso: no se encontro un sink Pulse/PipeWire antes de iniciar $app." >&2

    # WirePlumber recuerda un volumen bajo (40 %) en algunos equipos; se fija el
    # volumen de la salida por defecto y se quita el silencio.
    if [[ -n "$KIOSK_AUDIO_VOLUME" ]] && command -v wpctl >/dev/null 2>&1; then
        wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null 2>&1 || true
        wpctl set-volume @DEFAULT_AUDIO_SINK@ "$KIOSK_AUDIO_VOLUME" >/dev/null 2>&1 || true
    fi

    # PipeWire trabaja por defecto con ciclos de 1024 muestras (21 ms a 48 kHz) y
    # cada etapa de un microfono (dispositivo, fuente mono, lectura de la app) puede
    # sumar uno. Se fuerza un cuantum menor para bajar la latencia de los
    # microfonos y del audio. Es de ejecucion, asi que se aplica en cada arranque.
    if [[ -n "$KIOSK_PIPEWIRE_QUANTUM" ]] && command -v pw-metadata >/dev/null 2>&1; then
        pw-metadata -n settings 0 clock.force-quantum "$KIOSK_PIPEWIRE_QUANTUM" >/dev/null 2>&1 || true
    fi
}

# Arranca el atajo Ctrl+Alt+Q (si esta instalado) para cerrar la app. Cada argumento
# es un proceso a terminar: un nombre exacto, o una ruta absoluta (prefijo del
# ejecutable, p. ej. /opt/YARG/).
start_kiosk_exit_hotkey() {
    local script=/usr/local/bin/kiosk-exit-hotkey.py

    [[ -f "$script" ]] && command -v python3 >/dev/null 2>&1 || return 0
    pgrep -u "$(id -u)" -f "$script" >/dev/null 2>&1 && return 0

    python3 "$script" "$@" 2>&1 | sed 's/^/[exit-hotkey] /' >&2 &
}
PRELUDE

    out="${out//__KIOSK_TAG__/"$tag"}"
    out="${out//__KIOSK_HOME__/"$home"}"
    out="${out//__KIOSK_SOFTWARE__/"$software"}"
    out="${out//__KIOSK_AUDIO_VOLUME__/"$volume"}"
    out="${out//__KIOSK_PIPEWIRE_QUANTUM__/"$quantum"}"
    printf '%s\n' "$out"
}

# Plantilla del menu de mantenimiento; la completa kiosk_menu_script.
read -r -d '' KIOSK_MENU_TEMPLATE <<'TEMPLATE' || true
#!/usr/bin/env bash
set -euo pipefail

export TERM="${TERM:-xterm-256color}"
UPDATE_LABEL="__KIOSK_UPDATE_LABEL__"
UPDATE_COMMAND="__KIOSK_UPDATE_COMMAND__"
__KIOSK_MENU_SETUP__

pause_menu() {
    echo ""
    read -r -p "Presione Enter para volver al menu..."
}

show_hostname() {
    if command -v hostname >/dev/null 2>&1; then
        hostname
    elif [[ -r /etc/hostname ]]; then
        cat /etc/hostname
    else
        echo "desconocido"
    fi
}

show_hostname_ips() {
    if command -v hostname >/dev/null 2>&1; then
        hostname -I 2>/dev/null || true
    elif command -v ip >/dev/null 2>&1; then
        ip -o -4 addr show scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr '\n' ' '
        echo ""
    fi
}

show_ip_addresses() {
    clear
    echo "Direcciones IP"
    echo "=============="
    echo ""

    if command -v ip >/dev/null 2>&1; then
        ip -br addr show scope global || true
    fi

    echo ""
    if command -v nmcli >/dev/null 2>&1; then
        nmcli -t -f DEVICE,STATE,CONNECTION device status 2>/dev/null || true
    fi

    echo ""
    echo "Hostname: $(show_hostname)"
    echo "IPs: $(show_hostname_ips)"
__KIOSK_MENU_IP_EXTRA__
    pause_menu
}

open_shell() {
    clear
    echo "Shell de mantenimiento"
    echo "Escriba 'exit' para volver al menu."
    echo ""
    "${SHELL:-/bin/bash}"
}

update_kiosk_app() {
    clear
    echo "$UPDATE_LABEL"
    echo "__KIOSK_UPDATE_RULE__"
    echo ""

    if [[ ! -x "$UPDATE_COMMAND" ]]; then
        echo "No se encontro $UPDATE_COMMAND."
        pause_menu
        return
    fi

    if sudo "$UPDATE_COMMAND"; then
        echo ""
        echo "Actualizacion completada."
    else
        echo ""
        echo "La actualizacion fallo. Revisa journalctl -u cage-kiosk.service -b."
    fi

    pause_menu
}

while true; do
    clear
    cat <<'EOF'
Menu de mantenimiento __KIOSK_APP__
__KIOSK_MENU_RULE__

1) Configurar sonido
2) Configurar WiFi
3) Ver direccion IP
4) Salir a Shell
5) __KIOSK_RETURN_LABEL__
__KIOSK_MENU_OPTIONS__

EOF

    read -r -p "Seleccione una opcion: " option

    case "$option" in
        1)
            if command -v pulsemixer >/dev/null 2>&1; then
                pulsemixer || true
            else
                echo "pulsemixer no esta instalado."
                pause_menu
            fi
            ;;
        2)
            if command -v nmtui >/dev/null 2>&1; then
                nmtui || true
            elif command -v nmcli >/dev/null 2>&1; then
                nmcli device wifi list || true
                echo ""
                read -r -p "SSID: " ssid
                read -r -s -p "Password (vacio para red abierta): " password
                echo ""
                if [[ -n "$password" ]]; then
                    nmcli device wifi connect "$ssid" password "$password" || true
                else
                    nmcli device wifi connect "$ssid" || true
                fi
                pause_menu
            else
                echo "NetworkManager/nmcli no esta disponible."
                pause_menu
            fi
            ;;
        3)
            show_ip_addresses
            ;;
        4)
            open_shell
            ;;
        5)
            exit 0
            ;;
__KIOSK_MENU_CASES__
        *)
            echo "Opcion invalida."
            sleep 1
            ;;
    esac
done
TEMPLATE

# Imprime el script del menu de mantenimiento.
# Uso: kiosk_menu_script <app> <etiqueta-volver> <etiqueta-update> <comando-update> [opciones]
# Opciones (todas con valor):
#   --extra-label <texto>   opcion adicional antes de "Actualizar"
#   --extra-code <codigo>   cuerpo Bash de esa opcion
#   --setup <codigo>        lineas Bash tras las variables iniciales del menu
#   --ip-extra <codigo>     lineas Bash al final de "Ver direccion IP"
kiosk_menu_script() {
    local app="$1" return_label="$2" update_label="$3" update_command="$4"
    shift 4

    local extra_label="" extra_code="" setup="" ip_extra=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --extra-label) extra_label="$2" ;;
            --extra-code) extra_code="$2" ;;
            --setup) setup="$2" ;;
            --ip-extra) ip_extra="$2" ;;
            *) echo "kiosk_menu_script: opcion desconocida: $1" >&2; return 1 ;;
        esac
        shift 2
    done

    local title="Menu de mantenimiento $app"
    local rule update_rule n=5 options="" cases=""

    rule="$(printf '%*s' "${#title}" '' | tr ' ' '=')"
    update_rule="$(printf '%*s' "${#update_label}" '' | tr ' ' '=')"

    if [[ -n "$extra_label" ]]; then
        n=$((n + 1))
        options+="$n) $extra_label"$'\n'
        cases+="        $n)"$'\n'"$extra_code"$'\n'"            ;;"$'\n'
    fi

    n=$((n + 1))
    options+="$n) $update_label"$'\n'
    cases+="        $n)"$'\n'"            update_kiosk_app"$'\n'"            ;;"$'\n'

    n=$((n + 1))
    options+="$n) Reiniciar Kiosko"$'\n'
    cases+="        $n)"$'\n'
    cases+='            echo "Reiniciando servicio cage-kiosk..."'$'\n'
    cases+='            sudo systemctl restart cage-kiosk.service'$'\n'
    cases+='            exit 0'$'\n'"            ;;"$'\n'

    n=$((n + 1))
    options+="$n) Apagar Kiosko"
    cases+="        $n)"$'\n'
    cases+='            echo "Apagando kiosko..."'$'\n'
    cases+='            sudo systemctl poweroff'$'\n'
    cases+='            exit 0'$'\n'"            ;;"

    local out="$KIOSK_MENU_TEMPLATE"
    out="${out//__KIOSK_UPDATE_LABEL__/"$update_label"}"
    out="${out//__KIOSK_UPDATE_COMMAND__/"$update_command"}"
    out="${out//__KIOSK_UPDATE_RULE__/"$update_rule"}"
    out="${out//__KIOSK_MENU_SETUP__/"$setup"}"
    out="${out//__KIOSK_MENU_IP_EXTRA__/"$ip_extra"}"
    out="${out//__KIOSK_APP__/"$app"}"
    out="${out//__KIOSK_MENU_RULE__/"$rule"}"
    out="${out//__KIOSK_RETURN_LABEL__/"$return_label"}"
    out="${out//__KIOSK_MENU_OPTIONS__/"$options"}"
    out="${out//__KIOSK_MENU_CASES__/"$cases"}"
    printf '%s\n' "$out"
}

# Instala el menu en /usr/local/bin/kiosk-menu.sh (mismos argumentos que
# kiosk_menu_script).
install_kiosk_menu() {
    local script
    script="$(kiosk_menu_script "$@")" || return 1

    mkdir -p /mnt/usr/local/bin
    printf '%s\n' "$script" > /mnt/usr/local/bin/kiosk-menu.sh
    chmod +x /mnt/usr/local/bin/kiosk-menu.sh
}

# Imprime la unidad systemd de cage-kiosk.service.
# Uso: kiosk_service_unit <descripcion> <wrapper> <usuario> <uid> [lineas-[Service]-extra]
kiosk_service_unit() {
    local description="$1" wrapper="$2" user="$3" uid="$4" extra="${5:-}"

    cat << EOF
[Unit]
Description=$description
After=systemd-user-sessions.service network-online.target
Wants=network-online.target
Conflicts=getty@tty1.service

[Service]
User=$user
PAMName=login
TTYPath=/dev/tty1
StandardInput=tty
StandardOutput=journal
StandardError=journal
TTYReset=yes
TTYVHangup=yes
TTYVTDisallocate=yes
${extra:+$extra
}Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
Environment=XDG_RUNTIME_DIR=/run/user/$uid
ExecStartPre=+/usr/bin/mkdir -p /run/user/$uid
ExecStartPre=-/usr/bin/pkill -u $user -x pipewire-pulse
ExecStartPre=-/usr/bin/pkill -u $user -x wireplumber
ExecStartPre=-/usr/bin/pkill -u $user -x pipewire
ExecStartPre=-/usr/bin/rm -f /run/user/$uid/pipewire-0 /run/user/$uid/pipewire-0.lock /run/user/$uid/pulse/native
ExecStartPre=+/usr/bin/chown $user:$user /run/user/$uid
ExecStartPre=+/usr/bin/chmod 700 /run/user/$uid
ExecStart=/usr/bin/dbus-run-session -- $wrapper
ExecStopPost=-/usr/bin/pkill -u $user -x pipewire-pulse
ExecStopPost=-/usr/bin/pkill -u $user -x wireplumber
ExecStopPost=-/usr/bin/pkill -u $user -x pipewire
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
EOF
}

# Crea y habilita cage-kiosk.service.
# Uso: install_cage_service <app> <wrapper> [lineas-[Service]-extra]
install_cage_service() {
    local app="$1" wrapper="$2" extra="${3:-}"

    log "Creando servicio systemd cage-kiosk.service para $app"

    local kiosk_uid
    if ! kiosk_uid=$(arch-chroot /mnt id -u "$KIOSK_USER"); then
        log_error "No se pudo resolver UID de $KIOSK_USER para cage-kiosk.service"
        return 1
    fi

    kiosk_service_unit "Kiosk $app con Cage" "$wrapper" "$KIOSK_USER" "$kiosk_uid" "$extra" \
        > /mnt/etc/systemd/system/cage-kiosk.service

    if ! arch-chroot /mnt systemctl enable cage-kiosk.service; then
        log_error "Fallo al habilitar cage-kiosk.service"
        return 1
    fi
}
