# TODO

## Fixes pendientes

### YARG: usar `~/Songs` como carpeta real de canciones

- Decision: la ruta canonica para canciones debe ser `/home/$KIOSK_USER/Songs`.
  `/opt/YARG/Songs` queda solo como enlace simbolico de compatibilidad hacia
  esa carpeta.
- [x] Asegurar que la carpeta real por defecto sea `/home/$KIOSK_USER/Songs`.
- [x] Hacer que `/opt/YARG/Songs` sea un enlace simbolico hacia `/home/$KIOSK_USER/Songs`.
- [x] Evitar que `/home/$KIOSK_USER/Songs` sea un enlace hacia `/opt/YARG/Songs`.
- [x] Confirmar que el `settings.json` inicial de YARG apunte a `/home/$KIOSK_USER/Songs`, no al symlink `/opt/YARG/Songs`.
- [x] Confirmar que el `settings.json` inicial de YARG mantenga deshabilitado el banner/dialogos de inicio.
- [x] Confirmar que Samba comparta directamente `/home/$KIOSK_USER/Songs` en `YARG-Songs`.
- [x] Agregar o ajustar pruebas para cubrir el enlace `/opt/YARG/Songs -> /home/$KIOSK_USER/Songs`.

Archivos probables:

- `install-cage-yarg.sh`
- `lib/yarg.sh`
- `README.md`
- `tests/`

### Clone Hero: validar que canciones no queden en `/opt`

- Decision: mantener `/home/$KIOSK_USER/Songs` como ruta canonica para
  canciones tambien en Clone Hero.
- [x] Confirmar que `CLONEHERO_SONGS_DIR` por defecto siga siendo `/home/$KIOSK_USER/Songs`.
- [x] Confirmar que el perfil de Clone Hero use un enlace desde `$CLONEHERO_DATA_DIR/Songs` hacia `/home/$KIOSK_USER/Songs`.
- [x] Confirmar que Samba comparta directamente `/home/$KIOSK_USER/Songs` en `CloneHero-Songs`.
- [x] Confirmar que updater y descargador CSV escriban en `/home/$KIOSK_USER/Songs`, no en `/opt/CloneHero`.
- [x] Agregar o ajustar pruebas para evitar regresiones que manden canciones a `/opt/CloneHero`.

Archivos probables:

- `install-cage-clonehero.sh`
- `lib/clonehero.sh`
- `README.md`
- `tests/`

### Menu de mantenimiento: evitar error `hostname: command not found`

- [x] Revisar la opcion `3) Ver direccion IP` de `/usr/local/bin/kiosk-menu.sh`.
- [x] Reemplazar el uso directo de `hostname` y `hostname -I` por una funcion con `command -v hostname` y fallback.
- [x] Considerar usar `ip -br addr show scope global` como fuente principal para IPs.
- [x] Mantener la salida util aunque `hostname` no exista.
- [x] Agregar o ajustar pruebas de generacion del wrapper/menu.

Archivos probables:

- `lib/cage.sh`
- `lib/clonehero.sh`
- `tests/`
