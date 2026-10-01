# MiniArch

Instaladores automatizados para crear kioskos de Arch Linux orientados a YARG
(Yet Another Rhythm Game).

Repositorio oficial: [Xalcker/MiniArch](https://github.com/Xalcker/MiniArch).

## Caminos De Instalacion

MiniArch mantiene cuatro caminos basados en Cage:

- `install-cage-yarg.sh`: camino recomendado para YARG. Instala Arch Linux,
  Cage, Wayland/XWayland, YARG, audio, Samba y la carpeta de canciones en un
  solo flujo.
- `install-cage-clonehero.sh`: camino equivalente para Clone Hero. Instala
  Arch Linux, Cage, Wayland/XWayland, Clone Hero, audio, Samba y la carpeta de
  canciones en un solo flujo.
- `install-cage-rpcs3.sh`: camino para jugar Rock Band 3 (o cualquier juego de
  PS3) con el emulador RPCS3. Instala Arch Linux, Cage, RPCS3 (AppImage
  extraido a `/opt/RPCS3`), audio, Samba y la carpeta de juegos. Despues de
  configurar el emulador una vez, arranca solo el juego.
- `install-cage-kiosk.sh`: camino minimalista. Instala Arch Linux, Cage y
  `foot` solamente, util como base de kiosko o terminal de mantenimiento.

En corto:

```text
Recomendado: install-cage-yarg.sh
Clone Hero:  install-cage-clonehero.sh
RPCS3:       install-cage-rpcs3.sh (Rock Band 3 via emulador)
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
- `lib/clonehero.sh`: descarga de Clone Hero desde GitHub, carpeta compartida
  de canciones, Samba, updater y wrapper `/usr/local/bin/run-clonehero.sh`.
- `lib/rpcs3.sh`: descarga y extraccion del AppImage de RPCS3, firmware, carpeta
  de juegos, Samba, updater, menu de mantenimiento y wrapper
  `/usr/local/bin/run-rpcs3.sh` (arranque directo del juego).

`install-cage-kiosk.sh` conserva el particionado, GRUB, Plymouth opcional,
red y limpieza del instalador, pero arranca directamente `foot` dentro de Cage.

## Caracteristicas

### Compartidas

- Instalacion automatizada desde el live ISO de Arch Linux.
- Validacion de entorno, red, disco y passwords.
- Confirmacion antes de destruir particiones existentes.
- El disco del ISO live nunca es un destino valido; antes de particionar se
  limpian swap, montajes, LVM/RAID y firmas previas.
- Particionado GPT/UEFI (tamanos ajustables con `ESP_SIZE`, `ROOT_SIZE` y
  `SWAP_SIZE`):
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
- Enlace `/opt/YARG/Songs` apuntando a `YARG_SONGS_DIR`.
- Share Samba `YARG-Songs`.
- Usuario Samba para el usuario kiosko.
- Reglas HID para instrumentos `hidraw`.
- Dependencias multilib de YARG.
- Limites de tiempo real, `vm.swappiness=10` y `cpupower` en performance.
- Updater `/usr/local/bin/update-yarg`.
- Servicio `cage-kiosk.service`.

### Cage/Clone Hero

`install-cage-clonehero.sh` instala y configura:

- Cage como compositor de kiosko.
- Wayland y XWayland.
- Mesa, Vulkan Intel/AMD y NVIDIA opcional.
- DBus de sesion para el wrapper de Clone Hero.
- PipeWire iniciado en orden: `pipewire`, `wireplumber`, `pipewire-pulse`.
- Clone Hero en `/opt/CloneHero`.
- Perfil persistente en `CLONEHERO_DATA_DIR`.
- Carpeta de canciones fija en `CLONEHERO_SONGS_DIR`.
- Enlace `/home/kiosk/Songs` apuntando a la carpeta de canciones.
- Share Samba `CloneHero-Songs`.
- Usuario Samba para el usuario kiosko.
- Reglas HID para instrumentos `hidraw`.
- Updater `/usr/local/bin/update-clonehero`.
- Descargador `/home/kiosk/download-clonehero-songs.sh` usando `links.csv`.
- Servicio `cage-kiosk.service`.

### Cage/RPCS3

`install-cage-rpcs3.sh` instala y configura:

- Cage como compositor de kiosko.
- Wayland y XWayland.
- Mesa, Vulkan Intel/AMD y NVIDIA opcional.
- RPCS3 en `/opt/RPCS3` (AppImage extraido, no necesita FUSE).
- Firmware oficial de PS3 descargado en `/home/kiosk/PS3UPDAT.PUP`.
- Carpeta de juegos `RPCS3_GAMES_DIR` (por defecto `/home/kiosk/Games`).
- Share Samba `RPCS3-Games`.
- Reglas HID para instrumentos `hidraw`, `libusb` y `libevdev`.
- `vm.max_map_count` alto, limites de tiempo real y `cpupower` en performance.
- Updater `/usr/local/bin/update-rpcs3`.
- Servicio `cage-kiosk.service` y wrapper `/usr/local/bin/run-rpcs3.sh`.

Requiere un disco de al menos 32 GB (`RPCS3_MIN_DISK_GB`): el juego y la cache
de shaders no caben en el `/home` de un disco de 16 GB.

### Cage/foot

`install-cage-kiosk.sh` instala:

- Cage como compositor de kiosko.
- `foot` como aplicacion unica.
- Servicio `cage-kiosk.service`.
- SSH opcional.

## Requisitos

- Arch Linux ISO actual.
- Maquina fisica o VM con UEFI habilitado.
- Disco de al menos 16 GB (32 GB para el camino RPCS3).
  Esquema por defecto: ESP 512 MiB, root 8 GiB, swap 2 GiB y `/home` con el
  resto. En un disco de 16 GB `/home` queda de ~5.5 GB, en 32 GB de ~21.5 GB y
  en 128 GB de ~117.5 GB. Ajustable con `ESP_SIZE`, `ROOT_SIZE` y `SWAP_SIZE`.
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
YARG_SONGS_DIR=/home/${KIOSK_USER}/Songs
YARG_PERSISTENT_DATA_DIR=/home/${KIOSK_USER}/.config/yarg-kiosk
YARG_RESOLUTION=ask
YARG_FORCE_SOFTWARE_RENDER=false
YARG_EXIT_MENU=always
```

### Formato del .env

El `.env` **no se ejecuta como script**: el instalador lo lee linea por linea
como `CLAVE=valor` y nunca evalua el valor (no hay sustitucion de comandos).

```bash
# Comentario
KIOSK_USER=kiosk                        # sin comillas: literal; " #" inicia un comentario
KIOSK_PASSWORD='pa$$w0rd&x;(y)!'        # comillas simples: totalmente literal (recomendado para passwords)
ROOT_PASSWORD="con \"comillas\" y \\"   # comillas dobles: admiten \\  \"  \$  \`
YARG_SONGS_DIR=/home/${KIOSK_USER}/Songs  # solo se expande ${NOMBRE} (con llaves)
```

- Un `$` suelto no se expande: `pa$$word` queda tal cual.
- Una linea que no sea `CLAVE=valor`, unas comillas sin cerrar o una variable
  reservada (`PATH`, `IFS`, `HOME`, `LD_PRELOAD`, ...) detienen la instalacion con
  el numero de linea del problema.
- Se aceptan finales de linea CRLF (por si editas el archivo en Windows).

Ejecuta el camino recomendado:

```bash
chmod +x install-cage-yarg.sh
./install-cage-yarg.sh
```

Clone Hero:

```bash
chmod +x install-cage-clonehero.sh
./install-cage-clonehero.sh
```

Rock Band 3 con RPCS3 (disco de al menos 32 GB):

```bash
chmod +x install-cage-rpcs3.sh
./install-cage-rpcs3.sh
```

Cage/foot minimal:

```bash
chmod +x install-cage-kiosk.sh
./install-cage-kiosk.sh
```

Advertencia: los instaladores destruyen el disco seleccionado. Con
`DISK_DEVICE=ask`, el instalador muestra un selector interactivo con los discos
detectados, marca USB/removibles y pide confirmar escribiendo `INSTALAR`.
Tambien acepta `instalar`.
Tambien puedes fijar `DISK_DEVICE` manualmente, por ejemplo `/dev/sda`,
`/dev/nvme0n1` o `/dev/vda`; aun asi el instalador mostrara el selector para
evitar errores antes de particionar.

Proteccion del disco: el selector **oculta el disco del que arrancaste el ISO**
(el USB de instalacion, detectado desde `/run/archiso/bootmnt`) y rechaza
escribirlo a mano o fijarlo en `.env`, incluidas sus particiones. Antes de
particionar, el instalador desactiva el swap y desmonta lo que este usando el
disco destino, detiene volumenes LVM/RAID heredados y borra las firmas
previas (`wipefs` y `sgdisk --zap-all`) para que firmas viejas no se reactiven
ni bloqueen `parted` o `mkfs`.

## Flujo De Cage/YARG

`install-cage-yarg.sh` ejecuta, en orden:

1. Carga `.env` si existe; si no existe, entra en modo asistido.
2. Pregunta valores faltantes o interactivos de la configuracion.
3. Muestra el selector de disco (sin el USB del ISO live) y confirma el destino.
4. Detecta la GPU NVIDIA y pregunta si `INSTALL_NVIDIA` esta vacio; en GPU
   anteriores a Turing omite el driver.
5. Pregunta por canal de YARG si `YARG_RELEASE_CHANNEL=ask`.
6. Pregunta por resolucion de YARG si `YARG_RESOLUTION=ask`.
7. Valida entorno live, passwords, assets opcionales, red, disco y esquema de
   particiones.
8. Resuelve el release mas reciente si se eligio `stable-latest` o `nightly`.
9. Libera y limpia el disco (swap, montajes, LVM/RAID, firmas), particiona,
   formatea y monta.
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
- Actualizar YARG Stable o YARG Nightly, segun el canal instalado.
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
    "/home/kiosk/Songs"
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
/home/kiosk/Songs
```

Ruta de compatibilidad dentro de YARG:

```text
/opt/YARG/Songs -> /home/kiosk/Songs
```

Actualizar YARG:

```bash
sudo update-yarg
```

Descargar canciones desde CSV:

```bash
~/download-yarg-songs.sh
```

El instalador crea o copia `~/links.csv` (el `links.csv` de la raiz del repo si
existe). Cada linea puede ser `nombre,url` o solo una URL; antes de descargar,
el script pregunta por cada enlace, y los ZIP pueden extraerse directamente en
la carpeta Songs. Admite enlaces publicos de Google Drive.

## Uso Despues De Instalar Cage/Clone Hero

Despues de reiniciar, systemd inicia:

```text
cage-kiosk.service
```

El servicio ejecuta:

```text
/usr/bin/dbus-run-session -- /usr/local/bin/run-clonehero.sh
```

El wrapper busca Clone Hero en `/opt/CloneHero`, lo lanza fullscreen dentro de
Cage y abre el menu de mantenimiento al salir, salvo que `CLONEHERO_EXIT_MENU`
este en `restart` o `never`.

Share Samba:

```text
\\<hostname>\CloneHero-Songs
```

Con hostname por defecto del camino Clone Hero:

```text
\\miniclonehero\CloneHero-Songs
```

Ruta local:

```text
/home/kiosk/Songs
```

Actualizar Clone Hero:

```bash
sudo update-clonehero
```

Tambien se puede actualizar desde el menu de mantenimiento con la opcion
`Actualizar Clone Hero`.

Descargar canciones desde CSV:

```bash
~/download-clonehero-songs.sh
```

El instalador crea o copia `~/links.csv`. Cada linea puede ser `nombre,url` o
solo una URL. Los ZIP pueden extraerse directamente en la carpeta Songs.

## Uso Despues De Instalar Cage/RPCS3

RPCS3 no se puede configurar de forma desatendida: hay que instalar el
firmware, agregar el juego y mapear los controles una vez. El kiosko lo hace
asi:

1. En el primer arranque `run-rpcs3.sh` no encuentra el juego y **abre la GUI de
   RPCS3**.
2. En la GUI: `File > Install Firmware` y elige
   `/home/kiosk/PS3UPDAT.PUP`; agrega o instala el juego (disco volcado en
   `/home/kiosk/Games`, o PKG/DLC); configura guitarras, bateria, microfono y
   mandos en `Pads`. Para mandos e instrumentos que no son originales de PS3,
   el `Handler` debe ser `evdev` (ya estan `libevdev` y el grupo `input`).
3. Cierra RPCS3. A partir de ahi, el wrapper busca el juego y lo lanza con
   `rpcs3 --no-gui <EBOOT.BIN>`.

Rock Band 3, los DLC y el firmware de PS3 **no se distribuyen con MiniArch**: tu
aportas tu propio volcado del juego. El firmware se descarga desde los
servidores oficiales de PlayStation (`RPCS3_FIRMWARE_URL`).

Como encuentra el juego el wrapper, en orden:

1. `RPCS3_GAME_PATH`, si esta definida y existe.
2. El primer `PARAM.SFO` cuyo titulo contiene `RPCS3_GAME_MATCH` (por defecto
   `Rock Band 3`), buscando en `RPCS3_GAMES_DIR` (juegos de disco, estructura
   `<juego>/PS3_GAME/`), en `~/.config/rpcs3/dev_hdd0/disc` (volcados de disco
   agregados desde la GUI) y en `~/.config/rpcs3/dev_hdd0/game` (juegos
   instalados).

Si no lo encuentra abre la GUI. Desde el menu de mantenimiento (aparece al
salir del juego, salvo `RPCS3_EXIT_MENU=restart` o `never`) la opcion
`Abrir RPCS3` vuelve a abrir la GUI para cambiar controles o agregar juegos.

Share Samba para subir juegos:

```text
\\<hostname>\RPCS3-Games
```

Con hostname por defecto: `\\minirpcs3\RPCS3-Games`.

Actualizar RPCS3 (tambien desde el menu de mantenimiento):

```bash
sudo update-rpcs3
```

El updater extrae el AppImage nuevo aparte y solo reemplaza `/opt/RPCS3` si
la extraccion salio bien.

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
- `ESP_SIZE`, `ROOT_SIZE`, `SWAP_SIZE`: tamanos de las particiones (numero con
  `M` o `G`; por defecto `512M`, `8G` y `2G`). `/home` ocupa el resto del disco.
  Minimos: ESP 256M, root 4G, swap 512M y 2 GiB libres para `/home`; el
  instalador valida el esquema antes de pedir confirmacion.
- `KIOSK_USER`: usuario kiosko.
- `KIOSK_PASSWORD`: password del usuario kiosko.
- `TIMEZONE`: zona horaria.
- `ENABLE_SSH`: habilita OpenSSH si esta en `true`.
- `ALLOW_INSECURE_DEFAULT_PASSWORD`: permite passwords de ejemplo solo para
  laboratorio.
- `ENABLE_PLYMOUTH`: habilita/deshabilita Plymouth.
- `PLYMOUTH_THEME_NAME`: nombre del tema Plymouth.
- `PLYMOUTH_IMAGE_PATH`: imagen PNG opcional para Plymouth. En Cage/YARG y
  Cage/Clone Hero, si se deja el valor por defecto, el instalador elige primero
  un asset por camino y resolucion.
- `PLYMOUTH_TARGET_RESOLUTION`: resolucion final usada para preparar la imagen
  de Plymouth. En Cage/YARG y Cage/Clone Hero se calcula desde la resolucion
  elegida.
- `CURSOR_PATH`: cursor personalizado (por defecto `./assets/cursor/`, que trae
  `guitar-pick-left.png`). Los caminos YARG, Clone Hero y RPCS3 lo instalan como
  tema `MiniArchPick` (con `xcursorgen`); el camino foot no lo usa.
- `LOG_FILE`: archivo donde se guarda la salida detallada de la instalacion.
- `VERBOSE_INSTALL`: si es `true`, muestra en consola la salida completa de
  `pacman`, `pacstrap`, `unzip`, `grub-mkconfig`, etc. Por defecto es `false`.

Variables de Cage/YARG:

- `ROOT_PASSWORD`: password de root. Cage lo exige con valor real.
- `KIOSK_HOSTNAME`: hostname. Por defecto `minikiosk` (YARG y foot),
  `miniclonehero` (Clone Hero) o `minirpcs3` (RPCS3).
- `INSTALL_NVIDIA`: `true`, `false` o vacio para preguntar. Instala `nvidia-open`
  y `nvidia-utils`, que **solo soportan GPU Turing o mas nuevas** (GTX 16xx,
  RTX 20xx en adelante). Ver "NVIDIA y tarjetas anteriores a Turing".
- `NVIDIA_SKIP_GPU_CHECK`: `true` omite la deteccion de GPU (ver mas abajo).
- `YARG_RELEASE_CHANNEL`: `stable`, `stable-latest`, `nightly` o `ask`.
- `YARG_URL`: ZIP estable de YARG.
- `YARG_STABLE_API_URL`: endpoint del ultimo release estable.
- `YARG_STABLE_ASSET_REGEX`: patron usado para elegir el ZIP Linux estable.
- `YARG_NIGHTLY_API_URL`: endpoint del ultimo nightly.
- `YARG_NIGHTLY_ASSET_REGEX`: patron para elegir el ZIP Linux del nightly.
- `YARG_SONGS_DIR`: carpeta local de canciones. Por defecto
  `/home/${KIOSK_USER}/Songs`; `/opt/YARG/Songs` se crea como enlace hacia
  esta ruta para compatibilidad.
- `YARG_PERSISTENT_DATA_DIR`: perfil persistente de YARG.
- `YARG_RESOLUTION`: `4k`, `2k`, `1080p`, `720p` o `ask`.
- `YARG_FORCE_SOFTWARE_RENDER`: `true` fuerza llvmpipe/software render;
  `false` permite usar la GPU disponible, recomendado para GPU passthrough.
- `YARG_EXIT_MENU`: `always` muestra menu al salir de YARG; `restart`
  relanza YARG directo; `never` sale del wrapper.

Variables de Cage/Clone Hero:

- `CLONEHERO_RELEASE_CHANNEL`: `latest`, `url` o `ask`.
- `CLONEHERO_URL`: descarga fija de Clone Hero cuando se usa `url`.
- `CLONEHERO_API_URL`: endpoint del ultimo release.
- `CLONEHERO_ASSET_REGEX`: patron usado para elegir el asset Linux.
- `CLONEHERO_SONGS_DIR`: carpeta local de canciones. Por defecto
  `/home/${KIOSK_USER}/Songs`; el perfil de Clone Hero enlaza su carpeta
  `Songs` hacia esta ruta.
- `CLONEHERO_DATA_DIR`: perfil persistente de Clone Hero.
- `CLONEHERO_RESOLUTION`: `4k`, `2k`, `1080p`, `720p` o `ask`.
- `CLONEHERO_FORCE_SOFTWARE_RENDER`: `true` fuerza llvmpipe/software render.
- `CLONEHERO_EXIT_MENU`: `always` muestra menu al salir de Clone Hero;
  `restart` relanza Clone Hero directo; `never` sale del wrapper.

Variables de Cage/RPCS3:

- `RPCS3_URL`: descarga fija del AppImage. Si esta vacia se usa el ultimo
  release de `RPCS3/rpcs3-binaries-linux`.
- `RPCS3_API_URL` / `RPCS3_ASSET_REGEX`: endpoint del ultimo release y patron
  del AppImage de Linux x86_64.
- `RPCS3_DOWNLOAD_FIRMWARE`: `true` (por defecto) descarga el firmware en el
  home del usuario; `false` lo omite.
- `RPCS3_FIRMWARE_URL`: URL del `PS3UPDAT.PUP`.
- `RPCS3_GAMES_DIR`: carpeta de juegos y share Samba. Por defecto
  `/home/${KIOSK_USER}/Games`.
- `RPCS3_GAME_PATH`: ruta fija al `EBOOT.BIN` a lanzar; tiene prioridad sobre la
  deteccion automatica.
- `RPCS3_GAME_MATCH`: texto que debe contener el titulo del juego en su
  `PARAM.SFO`. Por defecto `Rock Band 3`.
- `RPCS3_QT_PLATFORM`: vacio (automatico), `wayland` o `xcb` (XWayland). Util
  si la ventana no aparece o falla el teclado/mando.
- `RPCS3_EXIT_MENU`: `always` muestra el menu al salir del juego; `restart`
  relanza directo; `never` sale del wrapper.
- `RPCS3_MIN_DISK_GB`: disco minimo en GB. Por defecto `32`.

Nota: `REQUIRE_ROOT_PASSWORD` existe como control interno. Los caminos Cage lo
activan por defecto.

## Estructura Del Proyecto

```text
MiniArch/
|-- install-cage-kiosk.sh      # Orquestador Cage/foot minimal
|-- install-cage-clonehero.sh  # Orquestador Cage/Clone Hero integrado
|-- install-cage-rpcs3.sh      # Orquestador Cage/RPCS3 (Rock Band 3)
|-- install-cage-yarg.sh       # Orquestador Cage/YARG integrado
|-- scripts/
|   |-- clone-miniarch.sh       # Clona disco, cambia UUIDs y puede expandir /home
|   |-- expand-home.sh          # Expande /home despues de clonar
|   `-- check-encoding.sh       # CI: sin BOM, mojibake ni CRLF
|-- lib/
|   |-- common.sh              # Logging, prompts y limpieza compartidos
|   |-- validation.sh          # Validacion de entorno, seguridad, red y disco
|   |-- partitioning.sh        # GPT/UEFI, formateo, montaje y swap
|   |-- base_install.sh        # Pacstrap base y fstab
|   |-- bootloader.sh          # GRUB UEFI y arranque silencioso
|   |-- plymouth.sh            # Plymouth compartido
|   |-- drivers.sh             # Drivers, PipeWire, codecs y Bluetooth
|   |-- cage.sh                # Cage, usuario, servicio y wrapper
|   |-- clonehero.sh           # Clone Hero, Samba, updater y CSV
|   |-- rpcs3.sh               # RPCS3, firmware, Samba, wrapper y updater
|   |-- yarg.sh                # YARG, settings, Samba, rendimiento y updater
|   |-- customization.sh       # Mensajes, cursor, assets y scripts extra
|   `-- finalization.sh        # Red, SSH opcional, limpieza y desmontaje
|-- assets/
|   |-- README.md
|   |-- yarg_720p.png            # Plymouth del camino YARG
|   |-- yarg_1080p.png
|   |-- clonehero_720p.png       # Plymouth del camino Clone Hero
|   |-- clonehero_1080p.png
|   |-- plymouth-image_720p.png  # imagen generica de respaldo
|   |-- plymouth-image_1080p.png
|   |-- rpcs3_720p.png           # opcional (no incluida)
|   |-- rpcs3_1080p.png          # opcional (no incluida)
|   |-- create-example-assets.sh # genera una imagen de ejemplo con ImageMagick
|   |-- plymouth-image.png.example
|   `-- cursor/                  # guitar-pick-left.png (ver cursor/README.md)
|-- docs/
|   `-- historico/instalador-openbox/   # Specs del instalador OpenBox (obsoletos, archivados)
|-- tests/
|   |-- test_assets.bats
|   |-- test_common.bats
|   |-- test_env_loader.bats
|   |-- test_nvidia.bats
|   |-- test_partition_sizes.bats
|   |-- test_song_paths_and_menu.bats
|   |-- test_validation.bats
|   |-- test_partitioning.bats
|   |-- test_base_install.bats
|   |-- test_bootloader.bats
|   |-- test_plymouth.bats
|   |-- test_rpcs3.bats
|   |-- test_repo_hygiene.bats
|   |-- test_drivers.bats
|   |-- test_disk_safety.bats
|   |-- test_docs.bats
|   |-- test_customization.bats
|   |-- test_finalization.bats
|   `-- test_integration.bats
```

La suite BATS cubre los modulos compartidos (`validation`, `partitioning`,
`bootloader`, `plymouth`, `drivers`, `finalization`, `customization`, `common`),
el cargador del `.env`, la proteccion del disco, la deteccion de NVIDIA, los
tamanos de particion y el camino RPCS3 (con `find_game` y `update-rpcs3`
ejecutados de verdad). Los wrappers y menus de `lib/cage.sh`, `lib/yarg.sh` y
`lib/clonehero.sh` se verifican sobre todo con `grep` sobre el texto (salvo
`update-clonehero`, que si se ejecuta en una prueba)
(`test_song_paths_and_menu.bats`); las pruebas de integracion estan omitidas
(ver #12 y #24). `scripts/clone-miniarch.sh` y `scripts/expand-home.sh` no tienen
pruebas automaticas: pruebalos en una VM con un disco de prueba.

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
bash -n install-cage-clonehero.sh
bash -n install-cage-rpcs3.sh
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

### NVIDIA y tarjetas anteriores a Turing

`nvidia-open` solo soporta Turing (GTX 16xx / RTX 20xx) y posteriores. Con el
driver 590, Arch dejo fuera Pascal (GTX 10xx) y anteriores; para esas tarjetas
solo existe `nvidia-580xx-dkms` en el AUR, que hay que compilar a mano.

Los instaladores detectan la GPU con `lspci` (el nombre del chip indica la
generacion: `GP`/`GM`/`GK`/`GV`... son anteriores a Turing; `TU`/`GA`/`AD`/`GB`
son compatibles):

- Si pides el driver (`INSTALL_NVIDIA=true` o respondes `s`) y la GPU es anterior
  a Turing, **no se instala** `nvidia-open` y se usa Mesa/nouveau, porque
  `nvidia-utils` pone nouveau en la lista negra y el equipo se quedaria sin
  video. El instalador lo avisa.
- Al preguntar, muestra la GPU detectada y si es compatible.
- `NVIDIA_SKIP_GPU_CHECK=true` omite la proteccion (falsos positivos, GPU en
  passthrough...).
- Si no se detecta GPU NVIDIA, solo avisa y respeta tu eleccion.

Para una GTX 10xx, instala `nvidia-580xx-dkms` desde el AUR despues de la
instalacion (con `base-devel`, `git` y los headers del kernel).

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

Si el binario no existe, el wrapper abre `foot`. Puedes reinstalar con:

```bash
sudo update-yarg
```

### Clone Hero no arranca

```bash
systemctl status cage-kiosk.service
journalctl -u cage-kiosk.service -b
ls -la /opt/CloneHero
```

Si el binario no existe, el wrapper abre el menu de mantenimiento. Reinstala con:

```bash
sudo update-clonehero
```

Si el menu de mantenimiento no puede actualizar, revisa que
`CLONEHERO_URL` (canal `url`) o el release de `clonehero-game/releases` (canal
`latest`) tengan un asset Linux.

### RPCS3 no arranca el juego

```bash
systemctl status cage-kiosk.service
journalctl -u cage-kiosk.service -b | grep -i rpcs3
ls -la /opt/RPCS3 /home/kiosk/Games
```

- Si ves `no se encontro el juego`, el titulo no coincide: revisa
  `RPCS3_GAME_MATCH` o fija `RPCS3_GAME_PATH` al `EBOOT.BIN`.
- Si la ventana no aparece o no responde el teclado/mando, prueba
  `RPCS3_QT_PLATFORM=xcb` (XWayland) o `wayland` y reinstala el wrapper.
- RPCS3 necesita Vulkan y una CPU con AVX2; en maquinas virtuales sin GPU no
  correra a una velocidad jugable.
- Si un juego dejo de funcionar de repente, borra la cache (es seguro; solo
  guarda logs y shaders compilados, y el siguiente arranque tarda mas):
  `rm -rf ~/.cache/rpcs3`.
- Si los objetos aparecen de golpe mientras se compilan shaders, en
  `Config > GPU` pon `Shader Mode` en `Async with Shader Interpreter`.
- Si RPCS3 reporta `Failed to set RLIMIT_MEMLOCK size to 2 GiB`, revisa que
  `cage-kiosk.service` tenga `LimitMEMLOCK=infinity` (el instalador lo agrega).

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
grep -A10 "\[YARG-Songs\]" /etc/samba/smb.conf   # o [CloneHero-Songs] / [RPCS3-Games]
ls -la /home/kiosk/Songs                         # RPCS3: /home/kiosk/Games
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
- Samba permite guest en `YARG-Songs`, `CloneHero-Songs` y `RPCS3-Games`; no los
  expongas a redes no confiables.
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
