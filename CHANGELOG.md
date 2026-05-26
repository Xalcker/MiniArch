# Changelog

Todos los cambios notables en este proyecto se documentan en este archivo.

El formato sigue la idea de Keep a Changelog y el proyecto usa versionado
semantico cuando se publiquen releases formales.

## [No Publicado]

### Agregado

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

- `install-arch-kiosk.sh`, `setup-yarg.sh` y `lib/gui.sh`.
- Instaladores Debian/Ubuntu experimentales.
- Bootstrap `bootstrap-arch-live.sh` y la documentacion de `curl | bash`.

### Corregido

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
