# MiniArch

Instaladores automatizados para crear kioskos de Arch Linux orientados a YARG
(Yet Another Rhythm Game).

Repositorio oficial: [Xalcker/MiniArch](https://github.com/Xalcker/MiniArch).

## Caminos De Instalacion

MiniArch mantiene dos caminos basados en Cage:

- `install-cage-yarg.sh`: camino recomendado para YARG. Instala Arch Linux,
  Cage, Wayland/XWayland, YARG, audio, Samba y la carpeta de canciones en un
  solo flujo.
- `install-cage-kiosk.sh`: camino minimalista. Instala Arch Linux, Cage y
  `foot` solamente, util como base de kiosko o terminal de mantenimiento.

En corto:

```text
Recomendado: install-cage-yarg.sh
Minimal:     install-cage-kiosk.sh
```

Cage es ideal para un equipo dedicado: ejecuta una sola aplicacion fullscreen y
reduce la superficie de escritorio. El instalador tambien habilita XWayland para
compatibilidad con builds de YARG que lo necesiten.

## Estado Actual

`install-cage-yarg.sh` es un orquestador modular. Reutiliza los modulos
compartidos de `lib/` y mueve lo especifico a:

- `lib/cage.sh`: sistema base Cage, usuario, servicio systemd y wrapper
  `/usr/local/bin/run-yarg.sh`.
- `lib/yarg.sh`: descarga de YARG stable, stable-latest o nightly, settings
  iniciales, Samba, rendimiento y updater.

`install-cage-kiosk.sh` conserva el particionado, GRUB, Plymouth opcional,
red y limpieza del instalador, pero arranca directamente `foot` dentro de Cage.

## Caracteristicas

### Compartidas

- Instalacion automatizada desde el live ISO de Arch Linux.
- Validacion de entorno, red, disco y passwords.
- Confirmacion antes de destruir particiones existentes.
- Particionado GPT/UEFI:
  - ESP FAT32 en `/boot`.
  - Root ext4 en `/`.
  - Swap.
  - Home ext4 en `/home`.
- GRUB UEFI con arranque silencioso.
- Plymouth opcional.
- PipeWire, WirePlumber, PipeWire Pulse, PipeWire ALSA, codecs y Bluetooth.
- `/etc/asound.conf` apuntando ALSA default a PipeWire.
- Limpieza automatica de montajes y swap si la instalacion falla.

### Cage/YARG

`install-cage-yarg.sh` instala y configura:

- Cage como compositor de kiosko.
- Wayland y XWayland.
- Mesa, Vulkan Intel/AMD y NVIDIA opcional.
- DBus de sesion para el wrapper de YARG.
- PipeWire iniciado en orden: `pipewire`, `wireplumber`, `pipewire-pulse`.
- YARG en `/opt/YARG`.
- Perfil persistente en `YARG_PERSISTENT_DATA_DIR`.
- Carpeta de canciones fija en `YARG_SONGS_DIR`.
- Share Samba `YARG-Songs`.
- Usuario Samba para el usuario kiosko.
- Reglas HID para instrumentos `hidraw`.
- Dependencias multilib de YARG.
- Limites de tiempo real, `vm.swappiness=10` y `cpupower` en performance.
- Updater `/usr/local/bin/update-yarg`.
- Servicio `cage-kiosk.service`.

### Cage/foot

`install-cage-kiosk.sh` instala:

- Cage como compositor de kiosko.
- `foot` como aplicacion unica.
- Servicio `cage-kiosk.service`.
- SSH opcional.

## Requisitos

- Arch Linux ISO actual.
- Maquina fisica o VM con UEFI habilitado.
- Disco de al menos 16 GB.
- 2 GB de RAM o mas.
- Conexion a internet durante la instalacion.
- ImageMagick en el entorno live si vas a usar imagen personalizada de
  Plymouth.

En VM, habilita EFI/UEFI. En VirtualBox:

```text
Sistema -> Placa base -> Habilitar EFI
```

En Proxmox, SPICE puede servir para probar audio virtual. En hardware real,
PipeWire deberia usar la salida detectada por ALSA/WirePlumber.

## Instalacion

Arranca desde el ISO de Arch Linux y verifica red:

```bash
ping -c 3 archlinux.org
```

### Instalacion Manual

Clona el repositorio:

```bash
pacman -Sy git imagemagick
git clone https://github.com/Xalcker/MiniArch.git
cd MiniArch
```

Copia el ejemplo de configuracion si quieres una instalacion repetible:

```bash
cp .env.example .env
nano .env
```

Para Cage/YARG, `.env` es opcional. Si no existe, `install-cage-yarg.sh`
pregunta lo necesario en modo asistido: usuario, passwords, hostname, timezone,
red, disco, NVIDIA, canal/resolucion de YARG y menu de salida.

Si usas `.env`, define al menos:

```bash
DISK_DEVICE=ask
KIOSK_USER=kiosk
KIOSK_PASSWORD=una-contrasena-real
ROOT_PASSWORD=otra-contrasena-real
KIOSK_HOSTNAME=minikiosk
TIMEZONE=America/Phoenix
ENABLE_SSH=false
INSTALL_NVIDIA=false
ALLOW_INSECURE_DEFAULT_PASSWORD=false
ENABLE_PLYMOUTH=true
YARG_RELEASE_CHANNEL=ask
YARG_SONGS_DIR=/opt/YARG/Songs
YARG_PERSISTENT_DATA_DIR=/home/${KIOSK_USER}/.config/yarg-kiosk
YARG_RESOLUTION=ask
YARG_FORCE_SOFTWARE_RENDER=false
YARG_EXIT_MENU=always
```

Ejecuta el camino recomendado:

```bash
chmod +x install-cage-yarg.sh
./install-cage-yarg.sh
```

Cage/foot minimal:

```bash
chmod +x install-cage-kiosk.sh
./install-cage-kiosk.sh
```

Advertencia: ambos instaladores destruyen el disco seleccionado. Con
`DISK_DEVICE=ask`, el instalador muestra un selector interactivo con los discos
detectados, marca USB/removibles y pide confirmar escribiendo `INSTALAR`.
Tambien puedes fijar `DISK_DEVICE` manualmente, por ejemplo `/dev/sda`,
`/dev/nvme0n1` o `/dev/vda`; aun asi el instalador mostrara el selector para
evitar errores antes de particionar.

## Flujo De Cage/YARG

`install-cage-yarg.sh` ejecuta, en orden:

1. Carga `.env` si existe; si no existe, entra en modo asistido.
2. Pregunta valores faltantes o interactivos de la configuracion.
3. Muestra el selector de disco y confirma el destino.
4. Pregunta por NVIDIA si `INSTALL_NVIDIA` esta vacio.
5. Pregunta por canal de YARG si `YARG_RELEASE_CHANNEL=ask`.
6. Pregunta por resolucion de YARG si `YARG_RESOLUTION=ask`.
7. Valida entorno live, passwords, assets opcionales, red y disco.
8. Resuelve el release mas reciente si se eligio `stable-latest` o `nightly`.
9. Particiona, formatea y monta el disco.
10. Instala Arch base, Cage, Wayland/XWayland, Samba, dbus y stack grafico.
11. Genera `fstab`.
12. Configura hostname, locale, root, GRUB, Plymouth y NVIDIA si aplica.
13. Instala audio, codecs y Bluetooth desde `lib/drivers.sh`.
14. Crea usuario kiosko y sudoers.
15. Habilita multilib y dependencias 32-bit de YARG.
16. Configura HID.
17. Descarga e instala YARG.
18. Crea `settings.json` con la carpeta fija de canciones.
19. Configura Samba.
20. Aplica optimizaciones de rendimiento.
21. Crea `update-yarg`, `run-yarg.sh` y `cage-kiosk.service`.
22. Configura red, target grafico y limpieza visual.
23. Desmonta particiones y desactiva swap.

## YARG Stable Y Nightly

`YARG_RELEASE_CHANNEL` acepta:

- `stable`: usa exactamente `YARG_URL`.
- `stable-latest`: consulta el ultimo release estable de `YARC-Official/YARG`.
- `nightly`: consulta el ultimo release de
  `YARC-Official/YARG-BleedingEdge`.
- `ask`: pregunta durante la instalacion.

El prompt actual es:

```text
Canal de YARG: stable fijo, stable-latest o nightly? [stable/stable-latest/nightly] (stable):
```

`sudo update-yarg` respeta el canal instalado. En `stable` usa `YARG_URL`; en
`stable-latest` consulta el latest estable; en `nightly` consulta el latest de
`YARG-BleedingEdge` antes de descargar.

## Uso Despues De Instalar Cage/YARG

Despues de reiniciar, systemd inicia:

```text
cage-kiosk.service
```

El servicio ejecuta:

```text
/usr/bin/dbus-run-session -- /usr/local/bin/run-yarg.sh
```

El wrapper:

- Aplica ajustes de render software si detecta VM.
- Valida DBus de sesion; normalmente ya viene creado por systemd mediante
  `dbus-run-session`.
- Exporta variables Wayland/Cage.
- Arranca PipeWire, WirePlumber y PipeWire Pulse en orden.
- Espera unos segundos a que exista un sink Pulse/PipeWire; si no aparece,
  lanza YARG de todos modos y deja el aviso en journal.
- Busca un binario ejecutable `YARG*` en `/opt/YARG`.
- Lanza YARG con `-persistent-data-path`.
- Al salir de YARG, abre un menu de mantenimiento en `foot`.
- Abre el menu de mantenimiento como fallback si no encuentra YARG.

El menu de mantenimiento permite:

- Configurar sonido con `pulsemixer`.
- Configurar WiFi con `nmtui` o `nmcli`.
- Ver direccion IP.
- Salir a una shell temporal.
- Volver a YARG.
- Reiniciar `cage-kiosk.service`.
- Apagar el kiosko.

`YARG_EXIT_MENU` controla que pasa al cerrar YARG:

- `always`: muestra el menu de mantenimiento.
- `restart`: vuelve a lanzar YARG sin mostrar menu.
- `never`: sale del wrapper.

El perfil fijo se crea en:

```text
/home/kiosk/.config/yarg-kiosk/settings.json
```

Con contenido equivalente a:

```json
{
  "SongFolders": [
    "/opt/YARG/Songs"
  ],
  "ShowAntiPiracyDialog": false,
  "ShowEngineInconsistencyDialog": false,
  "ShowExperimentalWarningDialog": false
}
```

Esto evita depender del selector de archivos para la operacion normal del
kiosko. El boton Browse puede funcionar en builds nightly recientes, pero el
flujo recomendado sigue siendo subir canciones por Samba y escanear desde YARG.

Share Samba:

```text
\\<hostname>\YARG-Songs
```

Con hostname por defecto:

```text
\\minikiosk\YARG-Songs
```

Ruta local:

```text
/opt/YARG/Songs
```

Actualizar YARG:

```bash
sudo update-yarg
```

## Uso Despues De Instalar Cage/foot

El camino minimal `install-cage-kiosk.sh` inicia el mismo servicio
`cage-kiosk.service`, pero ejecuta:

```text
/usr/bin/dbus-run-session -- /usr/local/bin/run-cage-foot.sh
```

El wrapper abre `foot` como aplicacion unica dentro de Cage. Es util para un
kiosko base, diagnostico o para instalar tu propia aplicacion despues.

## Configuracion

Variables comunes:

- `DISK_DEVICE`: disco destino. Por defecto `ask`, muestra selector interactivo.
- `KIOSK_USER`: usuario kiosko.
- `KIOSK_PASSWORD`: password del usuario kiosko.
- `TIMEZONE`: zona horaria.
- `ENABLE_SSH`: habilita OpenSSH si esta en `true`.
- `ALLOW_INSECURE_DEFAULT_PASSWORD`: permite passwords de ejemplo solo para
  laboratorio.
- `ENABLE_PLYMOUTH`: habilita/deshabilita Plymouth.
- `PLYMOUTH_THEME_NAME`: nombre del tema Plymouth.
- `PLYMOUTH_IMAGE_PATH`: imagen PNG opcional para Plymouth.
- `CURSOR_PATH`: ruta opcional usada solo por validaciones/assets heredados.
- `LOG_FILE`: archivo donde se guarda la salida detallada de la instalacion.
- `VERBOSE_INSTALL`: si es `true`, muestra en consola la salida completa de
  `pacman`, `pacstrap`, `unzip`, `grub-mkconfig`, etc. Por defecto es `false`.

Variables de Cage/YARG:

- `ROOT_PASSWORD`: password de root. Cage lo exige con valor real.
- `KIOSK_HOSTNAME`: hostname. Por defecto `minikiosk`.
- `INSTALL_NVIDIA`: `true`, `false` o vacio para preguntar.
- `YARG_RELEASE_CHANNEL`: `stable`, `stable-latest`, `nightly` o `ask`.
- `YARG_URL`: ZIP estable de YARG.
- `YARG_STABLE_API_URL`: endpoint del ultimo release estable.
- `YARG_STABLE_ASSET_REGEX`: patron usado para elegir el ZIP Linux estable.
- `YARG_NIGHTLY_API_URL`: endpoint del ultimo nightly.
- `YARG_NIGHTLY_ASSET_REGEX`: patron para elegir el ZIP Linux del nightly.
- `YARG_SONGS_DIR`: carpeta local de canciones.
- `YARG_PERSISTENT_DATA_DIR`: perfil persistente de YARG.
- `YARG_RESOLUTION`: `4k`, `2k`, `1080p`, `720p` o `ask`.
- `YARG_FORCE_SOFTWARE_RENDER`: `true` fuerza llvmpipe/software render;
  `false` permite usar la GPU disponible, recomendado para GPU passthrough.
- `YARG_EXIT_MENU`: `always` muestra menu al salir de YARG; `restart`
  relanza YARG directo; `never` sale del wrapper.

Nota: `REQUIRE_ROOT_PASSWORD` existe como control interno. Los caminos Cage lo
activan por defecto.

## Estructura Del Proyecto

```text
MiniArch/
|-- install-cage-kiosk.sh      # Orquestador Cage/foot minimal
|-- install-cage-yarg.sh       # Orquestador Cage/YARG integrado
|-- scripts/
|   |-- clone-miniarch.sh       # Clona disco, cambia UUIDs y puede expandir /home
|   `-- expand-home.sh          # Expande /home despues de clonar
|-- lib/
|   |-- validation.sh          # Validacion de entorno, seguridad, red y disco
|   |-- partitioning.sh        # GPT/UEFI, formateo, montaje y swap
|   |-- base_install.sh        # Pacstrap base y fstab
|   |-- bootloader.sh          # GRUB UEFI y arranque silencioso
|   |-- plymouth.sh            # Plymouth compartido
|   |-- drivers.sh             # Drivers, PipeWire, codecs y Bluetooth
|   |-- cage.sh                # Cage, usuario, servicio y wrapper
|   |-- yarg.sh                # YARG, settings, Samba, rendimiento y updater
|   |-- customization.sh       # Mensajes, cursor, assets y scripts extra
|   `-- finalization.sh        # Red, SSH opcional, limpieza y desmontaje
|-- assets/
|   |-- README.md
|   |-- plymouth-image.png.example
|   `-- cursor/
|-- tests/
|   |-- test_validation.bats
|   |-- test_partitioning.bats
|   |-- test_base_install.bats
|   |-- test_bootloader.bats
|   |-- test_plymouth.bats
|   |-- test_drivers.bats
|   |-- test_gui.bats
|   |-- test_customization.bats
|   |-- test_finalization.bats
|   `-- test_integration.bats
```

La suite BATS cubre principalmente modulos compartidos. Los modulos
`lib/cage.sh` y `lib/yarg.sh` todavia no tienen suite dedicada.

## Desarrollo Y Pruebas

Instala BATS en Linux/WSL:

```bash
sudo apt-get update
sudo apt-get install bats
```

Ejecuta pruebas:

```bash
bats tests/*.bats
```

Valida sintaxis:

```bash
bash -n install-cage-kiosk.sh
bash -n install-cage-yarg.sh
bash -n scripts/clone-miniarch.sh scripts/expand-home.sh
for file in lib/*.sh; do bash -n "$file"; done
```

## Troubleshooting

### No se detecta Arch Linux

Ejecuta los instaladores desde el live ISO de Arch Linux. Deben existir
`/etc/arch-release` y `pacstrap`.

### No hay red

```bash
ip link
ping -c 3 archlinux.org
```

Levanta la interfaz si hace falta:

```bash
ip link set <interfaz> up
dhcpcd
```

### El disco no existe

```bash
lsblk
```

Configura `DISK_DEVICE` en `.env`, por ejemplo:

```bash
DISK_DEVICE=/dev/vda
```

### Plymouth falla

Plymouth es opcional en el camino Cage. Si el paquete, tema o asset falla, el
instalador debe continuar sin pantalla personalizada.

Si ImageMagick no esta disponible, el instalador intenta copiar el PNG sin
redimensionarlo en vez de fallar por el escalado.

### Cage no arranca YARG

```bash
systemctl status cage-kiosk.service
journalctl -u cage-kiosk.service -b
ls -la /opt/YARG
```

### Necesito ver la salida completa del instalador

Por defecto, MiniArch oculta la salida ruidosa de `pacman`, `pacstrap`,
`mkfs`, `grub-mkconfig`, `mkinitcpio`, `curl` y `unzip`, pero la conserva en
`LOG_FILE`.

Para modo detallado:

```bash
VERBOSE_INSTALL=true ./install-cage-yarg.sh
```

O define en `.env`:

```bash
VERBOSE_INSTALL=true
```

Si el binario no existe, el wrapper abre `foot`. Puedes reinstalar con:

```bash
sudo update-yarg
```

### Audio no funciona

Revisa hardware ALSA:

```bash
aplay -l
aplay -L | grep -i pipewire
```

Revisa PipeWire/Pulse:

```bash
pactl info
pactl list short sinks
journalctl -u cage-kiosk.service -b | grep -Ei 'pipewire|wireplumber|dbus|alsa|bass'
```

Si `pactl info` falla, revisa que el wrapper este arrancando con DBus de sesion
y que no haya procesos PipeWire stale del usuario.

### Samba no aparece

```bash
sudo systemctl status smb nmb
testparm
grep -A10 "\[YARG-Songs\]" /etc/samba/smb.conf
ls -la /opt/YARG/Songs
```

### Instrumentos no funcionan

```bash
ls -l /etc/udev/rules.d/69-hid.rules
```

Reconecta el dispositivo despues de instalar para que udev aplique la regla.

## Seguridad

- No versiones `.env`.
- Cambia `KIOSK_PASSWORD` y `ROOT_PASSWORD`.
- El usuario kiosko tiene sudo sin password para mantenimiento.
- Samba permite guest en `YARG-Songs`; no lo expongas a redes no confiables.
- `ENABLE_SSH=false` es el valor recomendado para Cage.

Consulta [SECURITY.md](SECURITY.md) para mas detalles.

## Clonado A Discos Mas Grandes

Si clonas una instalacion a un disco mas grande, revisa [CLONING.md](CLONING.md)
para expandir `/home`.

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md), ejecuta las pruebas disponibles y abre
un pull request con cambios acotados.

## Licencia

Este proyecto esta bajo licencia MIT. Consulta [LICENSE](LICENSE).

## Creditos

- Arch Linux.
- YARG.
- Cage.
- foot.
- Plymouth.
- PipeWire.
- Samba.
- BATS.
