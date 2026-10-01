# Changelog

Todos los cambios notables en este proyecto se documentan en este archivo.

El formato sigue la idea de Keep a Changelog y el proyecto usa versionado
semantico cuando se publiquen releases formales.

## [No Publicado]

### Agregado

- `tests/test_docs.bats`: verifica que README, CONTRIBUTING, SECURITY y CLONING
  mencionen cada instalador, modulo, script y archivo de pruebas, documenten
  cada variable de `.env.example`, los tres shares Samba y los tres updaters, y
  tengan troubleshooting para cada camino con aplicacion.

- Proteccion del disco destino: el selector oculta y rechaza el disco del que
  arranco el ISO live (`live_boot_disk`), y `prepare_disk_for_install` desactiva
  swap, desmonta, detiene LVM/RAID heredados y borra firmas (`wipefs`,
  `sgdisk --zap-all`) antes de particionar, en los cuatro instaladores.

- CI en GitHub Actions (`.github/workflows/ci.yml`): `bash -n`, `shellcheck -S
  warning`, `bats tests/` y `scripts/check-encoding.sh`, que falla si aparece un
  BOM, doble codificacion UTF-8 o finales de linea CRLF.

- Camino `install-cage-rpcs3.sh` y modulo `lib/rpcs3.sh`: Arch Linux + Cage +
  RPCS3 (AppImage extraido a `/opt/RPCS3`, sin FUSE) con arranque directo de
  Rock Band 3. La primera vez abre la GUI de RPCS3 para instalar firmware, juego
  y controles; despues el wrapper `run-rpcs3.sh` busca el juego por el titulo de
  su `PARAM.SFO` (o `RPCS3_GAME_PATH`) y lo lanza con `--no-gui`. Incluye share
  Samba `RPCS3-Games`, descarga opcional del firmware, `update-rpcs3` con
  reemplazo atomico y menu de mantenimiento. Busca el juego tambien en
  `dev_hdd0/disc` (volcados agregados desde la GUI) y el servicio fija
  `LimitMEMLOCK=infinity` (RPCS3 pide 2 GiB de `RLIMIT_MEMLOCK`).
- `check_disk` acepta un minimo opcional en GB (por defecto 16); el camino
  RPCS3 exige 32 GB (`RPCS3_MIN_DISK_GB`).
- Paquete `inetutils` en el stack Cage para asegurar disponibilidad del comando
  `hostname`.
- Opcion de actualizacion en el menu de mantenimiento: `Actualizar YARG Stable`
  o `Actualizar YARG Nightly` para YARG, y `Actualizar Clone Hero` para Clone
  Hero.
- Instalador `install-cage-clonehero.sh` para el camino Cage/Clone Hero.
- Modulo `lib/clonehero.sh` con descarga desde releases de
  `clonehero-game/releases`, updater `update-clonehero`, wrapper
  `run-clonehero.sh`, share Samba `CloneHero-Songs` y descargador CSV
  `download-clonehero-songs.sh`.
- Instalador `install-cage-yarg.sh` para el camino recomendado Cage/YARG.
- Modulo `lib/cage.sh` con instalacion base de Cage, usuario, wrapper y
  servicio `cage-kiosk.service`.
- Modulo `lib/yarg.sh` con descarga de YARG, soporte stable, stable-latest y
  nightly, settings iniciales, Samba, optimizaciones y updater.
- Soporte para elegir YARG stable fijo, latest estable desde
  `YARC-Official/YARG` o nightly desde `YARC-Official/YARG-BleedingEdge`.
- Configuracion fija de canciones con `YARG_SONGS_DIR` y
  `YARG_PERSISTENT_DATA_DIR`.
- Share Samba `YARG-Songs` para cargar canciones por red.
- Arranque de YARG con DBus de sesion desde `cage-kiosk.service` y PipeWire
  ordenado desde `/usr/local/bin/run-yarg.sh`.
- `update-yarg` respeta `YARG_RELEASE_CHANNEL`; en `stable-latest` consulta el
  latest estable y en `nightly` consulta el latest de `YARG-BleedingEdge`.
- Instalador minimal `install-cage-kiosk.sh` para Cage + foot sin YARG.
- Scripts `scripts/clone-miniarch.sh` y `scripts/expand-home.sh` para clonado,
  cambio de UUIDs y expansion de `/home`.

### Cambiado

- Documentacion alineada con el codigo: README (flujo del instalador, proteccion
  del disco, `CURSOR_PATH`, descriptor de la suite de pruebas, descargador de
  canciones de YARG, troubleshooting de Clone Hero y Samba), SECURITY (wrappers
  y updaters de los tres caminos) y CONTRIBUTING (checklist de PR con los cuatro
  caminos y nota sobre los scripts de clonado).

- `ESP_SIZE`, `ROOT_SIZE` y `SWAP_SIZE` ahora se respetan (antes estaban en
  `.env.example` pero el esquema estaba fijo): se validan (minimos ESP 256M,
  root 4G, swap 512M y 2 GiB libres para `/home`) antes de pedir confirmacion.
- `.env.example` alineado con el codigo: rutas de canciones en
  `/home/${KIOSK_USER}/Songs`, hostname por camino documentado y fallback de
  zona horaria unificado en `America/Phoenix` (antes `lib/finalization.sh` usaba
  `America/Mexico_City`).

- Nuevo `lib/common.sh` con el logging, `run_quiet`, los prompts y la limpieza
  ante fallos que estaban copiados en los tres instaladores.
- README alineado al repositorio oficial `Xalcker/MiniArch`.
- Cage/YARG queda documentado como el camino recomendado para YARG.
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

- `TODO.md`: su unico pendiente (`YARG_FORCE_WAYLAND`) se sigue en el issue #10.

- Funciones sin uso heredadas del instalador OpenBox y sus pruebas:
  `install_base_system`, `configure_chroot`, `install_graphics_drivers`,
  `apply_plymouth_image`, `install_extra_scripts` y `calculate_home_size`.

- `install-arch-kiosk.sh`, `setup-yarg.sh` y `lib/gui.sh`.
- Instaladores Debian/Ubuntu experimentales.
- Bootstrap `bootstrap-arch-live.sh` y la documentacion de `curl | bash`.

### Corregido

- El instalador ya no instala `nvidia-open` en GPU anteriores a Turing (GTX 10xx
  y anteriores), donde dejaba el equipo sin video: `detect_nvidia_support` lee la
  generacion con `lspci` y `resolve_nvidia_choice` (compartido por los caminos
  YARG, Clone Hero y RPCS3) omite el driver con una advertencia clara.
  `NVIDIA_SKIP_GPU_CHECK=true` desactiva la proteccion. Tambien se corrigio el
  mensaje que decia `nvidia-dkms` cuando se instalaba `nvidia-open`.

- El `.env` ya no se carga con `source` (que ejecutaba su contenido como root y
  rompia con passwords con simbolos): `load_env_file` en `lib/common.sh` lo lee
  como `CLAVE=valor`, sin evaluar valores, con comillas simples/dobles,
  expansion de `${NOMBRE}`, soporte CRLF y rechazo de variables reservadas.

- La suite BATS vuelve a ser ejecutable: se reparo `test_base_install.bats`
  (estaba duplicado y truncado), se quito el BOM y la doble codificacion UTF-8
  de `lib/drivers.sh`, `lib/bootloader.sh`, `lib/customization.sh` y
  `tests/test_customization.bats`, y se alinearon las pruebas con los mensajes,
  paquetes y comandos actuales (zona horaria con `ln -sf`, GRUB, audio,
  Plymouth). `install_grub` acepta `EFI_FIRMWARE_DIR` para poder probarse sin
  depender del equipo.
- Se agrego `.gitattributes` para mantener LF en scripts, pruebas y docs.

- `update-clonehero` y la instalacion de Clone Hero ya no fallan con
  `Directory not empty` al actualizar sobre una instalacion existente; ahora
  combinan los archivos nuevos con `cp -a` en vez de `mv`.
- Las rutas de canciones y de datos persistentes de YARG y Clone Hero ahora se
  resuelven despues de preguntar el usuario kiosko; antes quedaban fijas en
  `/home/kiosk/...` si se elegia otro usuario.
- YARG ahora usa `/home/$KIOSK_USER/Songs` como carpeta real de canciones y
  crea `/opt/YARG/Songs` como enlace simbolico de compatibilidad, incluyendo
  `update-yarg`.
- El menu de mantenimiento de YARG y Clone Hero ya no muestra error si el
  comando `hostname` no existe.
- Prompt de canal ahora pide `stable`, `stable-latest` o `nightly`, evitando
  una pregunta confusa de si/no.
- Se removio la dependencia a paquetes de tema Plymouth que podian no existir
  en repositorios actuales.
- Plymouth ya no falla si ImageMagick no esta disponible; copia el PNG sin
  escalar como fallback.
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
- Plymouth ya no fuerza modulos graficos en `MODULES`, restaura
  `mkinitcpio.conf` si falla `mkinitcpio -P` y evita regenerar initramfs dos
  veces al activar el tema.

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

[No Publicado]: https://github.com/Xalcker/MiniArch/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Xalcker/MiniArch/releases/tag/v1.0.0
