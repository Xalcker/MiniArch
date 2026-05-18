# Changelog

Todos los cambios notables en este proyecto se documentan en este archivo.

El formato sigue la idea de Keep a Changelog y el proyecto usa versionado
semantico cuando se publiquen releases formales.

## [No Publicado]

### Agregado

- Instalador `install-arch-cage.sh` para el camino recomendado Cage/YARG.
- Modulo `lib/cage.sh` con instalacion base de Cage, usuario, wrapper y
  servicio `cage-kiosk.service`.
- Modulo `lib/yarg.sh` con descarga de YARG, soporte stable/nightly, settings
  iniciales, Samba, optimizaciones y updater.
- Soporte para elegir YARG stable desde `.env` o nightly desde
  `YARC-Official/YARG-BleedingEdge`.
- Configuracion fija de canciones con `YARG_SONGS_DIR` y
  `YARG_PERSISTENT_DATA_DIR`.
- Share Samba `YARG-Songs` para cargar canciones por red.
- Arranque de YARG con DBus de sesion y PipeWire ordenado desde
  `/usr/local/bin/run-yarg.sh`.
- Archivo `TODO.md` con riesgos pendientes del camino Cage/YARG.

### Cambiado

- README alineado al repositorio oficial `Xalcker/MiniArch`.
- Cage/YARG queda documentado como el camino recomendado para YARG.
- `lib/drivers.sh` instala PipeWire ALSA/Pulse/JACK, WirePlumber, codecs y
  genera `/etc/asound.conf` para que ALSA use PipeWire por defecto.
- Plymouth se trata como opcional en el camino Cage.
- `validate_security_config` permite exigir password de root en Cage sin romper
  el camino OpenBox original.

### Corregido

- Prompt de stable/nightly ahora pide `stable` o `nightly`, evitando una
  pregunta confusa de si/no.
- Se removio la dependencia a paquetes de tema Plymouth que podian no existir
  en repositorios actuales.
- La validacion de disco vacio ya no depende de `grep -c` bajo `pipefail`.

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
