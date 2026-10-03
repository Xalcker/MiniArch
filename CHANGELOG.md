# Changelog

Todos los cambios notables en este proyecto se documentan en este archivo.

El formato sigue la idea de Keep a Changelog y el proyecto usara versionado
semantico cuando se publiquen releases formales (todavia no hay tags ni
releases publicados).

## [No Publicado]

### Agregado

Caminos de instalacion:

- Camino Cage/RPCS3 (`install-cage-rpcs3.sh`, `lib/rpcs3.sh`): Arch Linux + Cage
  + RPCS3 (AppImage extraido a `/opt/RPCS3`, sin FUSE) con arranque directo de
  Rock Band 3. La primera vez abre la GUI de RPCS3 para instalar firmware, juego
  y controles; despues el wrapper `run-rpcs3.sh` busca el juego por el titulo de
  su `PARAM.SFO` (o `RPCS3_GAME_PATH`) en la carpeta de juegos, `dev_hdd0/disc` y
  `dev_hdd0/game`, y lo lanza con `--no-gui`. Incluye share Samba `RPCS3-Games`,
  descarga opcional del firmware, `update-rpcs3` con reemplazo atomico, menu de
  mantenimiento, `LimitMEMLOCK=infinity` y `RPCS3_MIN_DISK_GB` (32 GB).
- Camino Cage/Clone Hero (`install-cage-clonehero.sh`, `lib/clonehero.sh`):
  descarga desde releases de `clonehero-game/releases`, updater
  `update-clonehero`, wrapper `run-clonehero.sh`, share Samba `CloneHero-Songs` y
  descargador de canciones `download-clonehero-songs.sh` (usa `links.csv`).
- Camino Cage/YARG (`install-cage-yarg.sh`, `lib/cage.sh`, `lib/yarg.sh`): YARG
  stable fijo, latest estable desde `YARC-Official/YARG` o nightly desde
  `YARC-Official/YARG-BleedingEdge`; `YARG_SONGS_DIR` y
  `YARG_PERSISTENT_DATA_DIR`; share Samba `YARG-Songs`; DBus de sesion desde
  `cage-kiosk.service` y PipeWire ordenado desde `run-yarg.sh`; `update-yarg`
  respeta `YARG_RELEASE_CHANNEL`; descargador de canciones
  `download-yarg-songs.sh`.
- Camino minimal `install-cage-kiosk.sh` (Cage + foot, sin juego).

Configuracion y experiencia de instalacion:

- Modo asistido en los instaladores: sin `.env` preguntan usuario, passwords,
  hostname, zona horaria, SSH, Plymouth, NVIDIA, canal y resolucion.
- Seleccion de resolucion (`YARG_RESOLUTION` y `CLONEHERO_RESOLUTION`: `4k`,
  `2k`, `1080p`, `720p` o `ask`) y render por software opcional
  (`YARG_FORCE_SOFTWARE_RENDER`, `CLONEHERO_FORCE_SOFTWARE_RENDER`).
- `YARG_EXIT_MENU` y `CLONEHERO_EXIT_MENU` (`always`, `restart`, `never`) para
  decidir que pasa al cerrar el juego, y `RPCS3_EXIT_MENU` en RPCS3.
- Imagen de Plymouth por camino y resolucion (`select_plymouth_image`, assets
  `yarg_*`, `clonehero_*` y `plymouth-image_*`, con `PLYMOUTH_TARGET_RESOLUTION`).
- Cursor personalizado `MiniArchPick` (guitar pick) generado con `xcursorgen`.
- Opcion de actualizacion en el menu de mantenimiento: `Actualizar YARG Stable`
  o `Actualizar YARG Nightly`, `Actualizar Clone Hero` y `Actualizar RPCS3`.
- Selector de disco con lista de discos, etiqueta de USB/removibles y
  confirmacion escribiendo `INSTALAR`.
- Paquetes `mc` (Midnight Commander) e `inetutils` (comando `hostname`) en el
  sistema base de los caminos Cage.
- `ESP_SIZE`, `ROOT_SIZE` y `SWAP_SIZE` configurables, y `check_disk` con minimo
  opcional en GB (por defecto 16).
- `NVIDIA_SKIP_GPU_CHECK` para omitir la deteccion de GPU NVIDIA.
- Scripts `scripts/clone-miniarch.sh` y `scripts/expand-home.sh`: clonado de
  disco, cambio de UUIDs/GUIDs, reparacion de `fstab` (`--repair-fstab`), GRUB
  UEFI en modo removable y expansion de `/home`.

Seguridad del disco:

- El selector oculta y rechaza el disco del que arranco el ISO live
  (`live_boot_disk`), y `prepare_disk_for_install` desactiva swap, desmonta,
  detiene LVM/RAID heredados y borra firmas (`wipefs`, `sgdisk --zap-all`)
  antes de particionar, en los cuatro instaladores.

Infraestructura:

- CI en GitHub Actions (`.github/workflows/ci.yml`): `bash -n`, `shellcheck -S
  warning`, `bats tests/` y `scripts/check-encoding.sh`, que falla si aparece un
  BOM, doble codificacion UTF-8 o finales de linea CRLF.
- Pruebas nuevas: `test_common`, `test_env_loader`, `test_disk_safety`,
  `test_partition_sizes`, `test_nvidia`, `test_rpcs3`, `test_repo_hygiene`,
  `test_docs` (coherencia de la documentacion con el repo), `test_assets` y
  `test_song_paths_and_menu`.
- `.gitattributes` para mantener LF en scripts, pruebas y documentos.
- Mejoras de RPCS3 compartidas con YARG y Clone Hero en `lib/kiosk_runtime.sh`:
  salida de audio por HDMI con regla de WirePlumber y volumen al arrancar
  (`*_AUDIO_OUTPUT`, `*_AUDIO_VOLUME`), cuantum de PipeWire para bajar la latencia
  (`*_PIPEWIRE_QUANTUM`, 128 por defecto), atajo Ctrl+Alt+Q para cerrar la app
  (`*_EXIT_HOTKEY`, script comun `kiosk-exit-hotkey.py`), disco minimo por ruta
  (`YARG_MIN_DISK_GB` y `CLONEHERO_MIN_DISK_GB`, 32 GB) y updaters que no descargan
  si ya esta la ultima version (`update-yarg --force`, `update-clonehero --force`).
- `configure_kiosk_performance`: una sola implementacion de limites de tiempo real,
  swappiness y cpupower para las tres rutas (antes copiada en cada una).

### Cambiado

- Wrapper, menu de mantenimiento y `cage-kiosk.service` de YARG, Clone Hero y
  RPCS3 unificados en `lib/kiosk_runtime.sh` (#28): antes eran tres copias casi
  identicas. El wrapper de YARG ahora tambien fija `HOME`, y el
  menu de RPCS3 gana el respaldo de `nmcli` para el WiFi; el resto del
  comportamiento no cambia.
- Documentacion de `assets/` reescrita para describir el flujo real:
  seleccion de la imagen de Plymouth por camino y resolucion, y generacion del
  tema de cursor `MiniArchPick` a partir de un PNG (`xcursorgen`, punto activo
  fijo en 23,8). `assets/create-example-assets.sh` ahora acepta `ANCHOxALTO`,
  soporta `magick` y `convert`, y ya no genera un tema X11 completo.
- Los specs del instalador OpenBox (`.kiro/specs/arch-kiosk-installer/`) se
  archivaron en `docs/historico/instalador-openbox/` con un aviso de que no
  describen el codigo actual.

- Nuevo `lib/common.sh` con el logging, `run_quiet`, los prompts y la limpieza
  ante fallos que estaban copiados en los instaladores.
- `ESP_SIZE`, `ROOT_SIZE` y `SWAP_SIZE` ahora se respetan (antes estaban en
  `.env.example` pero el esquema estaba fijo): se validan (minimos ESP 256M,
  root 4G, swap 512M y 2 GiB libres para `/home`) antes de pedir confirmacion.
- `.env.example` alineado con el codigo: rutas de canciones en
  `/home/${KIOSK_USER}/Songs`, hostname por camino documentado y fallback de
  zona horaria unificado en `America/Phoenix` (antes `lib/finalization.sh` usaba
  `America/Mexico_City`).
- Documentacion alineada con el codigo: README, SECURITY, CLONING y CONTRIBUTING
  cubren los cuatro caminos (wrappers, updaters, shares Samba, troubleshooting).
- README alineado al repositorio oficial `Xalcker/MiniArch`; Cage/YARG queda
  como el camino recomendado para YARG.
- La salida ruidosa de `pacman`, `pacstrap`, `mkfs`, `grub-mkconfig`,
  `mkinitcpio`, `curl` y `unzip` se envia al log por defecto. Use
  `VERBOSE_INSTALL=true` para verla en consola.
- `lib/drivers.sh` instala PipeWire ALSA/Pulse/JACK, WirePlumber, codecs y
  genera `/etc/asound.conf` para que ALSA use PipeWire por defecto.
- Plymouth se trata como opcional en el camino Cage.
- `validate_security_config` permite exigir password de root en los caminos
  Cage.
- El antiguo camino OpenBox fue reemplazado por Cage/foot.

### Removido

- `assets/cursor/PLACEHOLDER.txt` (el directorio ya incluye el cursor) y la
  configuracion de Kiro `.kiro/specs/arch-kiosk-installer/.config.kiro`.

- `TODO.md`: su unico pendiente (`YARG_FORCE_WAYLAND`) se sigue en el issue #10.
- Funciones sin uso heredadas del instalador OpenBox y sus pruebas:
  `install_base_system`, `configure_chroot`, `install_graphics_drivers`,
  `apply_plymouth_image`, `install_extra_scripts` y `calculate_home_size`.
- `install-arch-kiosk.sh`, `setup-yarg.sh` y `lib/gui.sh`.
- Instaladores Debian/Ubuntu experimentales.
- Bootstrap `bootstrap-arch-live.sh` y la documentacion de `curl | bash`.

### Corregido

- El `.env` ya no se carga con `source` (que ejecutaba su contenido como root y
  rompia con passwords con simbolos): `load_env_file` en `lib/common.sh` lo lee
  como `CLAVE=valor`, sin evaluar valores, con comillas simples/dobles,
  expansion de `${NOMBRE}`, soporte CRLF y rechazo de variables reservadas.
- El instalador ya no instala `nvidia-open` en GPU anteriores a Turing (GTX 10xx
  y anteriores), donde dejaba el equipo sin video: `detect_nvidia_support` lee la
  generacion con `lspci` y `resolve_nvidia_choice` (compartido por los caminos
  YARG, Clone Hero y RPCS3) omite el driver con una advertencia clara. Tambien se
  corrigio el mensaje que decia `nvidia-dkms` cuando se instalaba `nvidia-open`.
- Las rutas de canciones y de datos persistentes de YARG y Clone Hero se
  resuelven despues de preguntar el usuario kiosko; antes quedaban fijas en
  `/home/kiosk/...` si se elegia otro usuario.
- Las canciones de YARG y Clone Hero usan `/home/$KIOSK_USER/Songs` como carpeta
  real (YARG crea `/opt/YARG/Songs` como enlace simbolico de compatibilidad,
  tambien en `update-yarg`; Clone Hero enlaza su carpeta `Songs` hacia esa ruta,
  y los updaters respetan la normalizacion).
- `update-clonehero` y la instalacion de Clone Hero ya no fallan con
  `Directory not empty` al actualizar sobre una instalacion existente; ahora
  combinan los archivos nuevos con `cp -a` en vez de `mv`.
- La suite BATS vuelve a ser ejecutable: se reparo `test_base_install.bats`
  (estaba duplicado y truncado), se quito el BOM y la doble codificacion UTF-8
  de `lib/drivers.sh`, `lib/bootloader.sh`, `lib/customization.sh` y
  `tests/test_customization.bats`, y se alinearon las pruebas con los mensajes,
  paquetes y comandos actuales. `install_grub` acepta `EFI_FIRMWARE_DIR` y las
  pruebas ya no dependen de los discos reales del equipo (`is_block_device`).
- El menu de mantenimiento de YARG y Clone Hero ya no muestra error si el
  comando `hostname` no existe.
- Prompt de canal ahora pide `stable`, `stable-latest` o `nightly`, evitando
  una pregunta confusa de si/no.
- Se removio la dependencia a paquetes de tema Plymouth que podian no existir
  en repositorios actuales.
- Plymouth ya no falla si ImageMagick no esta disponible; copia el PNG sin
  escalar como fallback.
- Plymouth ya no fuerza modulos graficos en `MODULES`, restaura
  `mkinitcpio.conf` si falla `mkinitcpio -P` y evita regenerar initramfs dos
  veces al activar el tema.
- La validacion de disco vacio ya no depende de `grep -c` bajo `pipefail`.
- El wrapper de YARG deja trazas claras en journal antes de iniciar DBus,
  PipeWire y Cage para diagnosticar pantallas negras.
- El camino Cage/YARG ya no instala `pulseaudio-alsa` encima de
  `pipewire-alsa`; despues de multilib reafirma `/etc/asound.conf` hacia
  PipeWire para evitar el error de `pipewire-alsa` al iniciar YARG.
- El wrapper espera a que ALSA `default` pueda abrir audio via PipeWire antes
  de lanzar YARG.
- `cage-kiosk.service` ahora escribe `XDG_RUNTIME_DIR` con el UID real del
  usuario kiosk en vez de usar `%U`, que podia expandirse como root (`0`) en
  los `ExecStartPre` y romper PipeWire/ALSA.

## [1.0.0] - Version Inicial

### Agregado

- Instalacion automatizada de Arch Linux en modo kiosko OpenBox/X11.
- Soporte UEFI con GRUB.
- Plymouth opcional.
- Drivers graficos AMD, Intel, NVIDIA y Mesa.
- Sistema de audio PipeWire.
- Autologin al usuario kiosko.
- Suite inicial de pruebas BATS.
- Estructura modular en `lib/`.
- Assets personalizables para Plymouth y cursor.
- Esquema de particionado GPT/UEFI con ESP, root, swap y home.
