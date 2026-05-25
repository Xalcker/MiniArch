# Guia De Contribucion

Gracias por contribuir a MiniArch. El repositorio mantiene tres caminos de
instalacion basados en Cage:

- Cage/YARG: `install-cage-yarg.sh`, `lib/cage.sh`, `lib/yarg.sh`.
- Cage/Clone Hero: `install-cage-clonehero.sh`, `lib/cage.sh`,
  `lib/clonehero.sh`.
- Cage/foot: `install-cage-kiosk.sh`.

Cuando cambies modulos compartidos en `lib/`, revisa ambos caminos.

## Flujo Recomendado

1. Crea una rama desde `main`.
2. Haz cambios acotados.
3. Actualiza README/SECURITY/CHANGELOG si cambia comportamiento visible.
4. Ejecuta pruebas y validacion de sintaxis.
5. Abre un pull request con el resumen y pruebas ejecutadas.

## Estandares De Bash

- Usa `#!/usr/bin/env bash` para scripts nuevos.
- Usa `set -euo pipefail` donde sea razonable.
- Cita variables: `"$var"`.
- Usa `[[ ... ]]` para condiciones.
- Declara variables locales dentro de funciones.
- Maneja errores con mensajes claros:

```bash
if ! comando; then
    log_error "Descripcion del fallo"
    return 1
fi
```

## Modulos

Mantener responsabilidades claras:

- `validation.sh`: validaciones de entorno, seguridad, red y disco.
- `partitioning.sh`: particionado, formateo, montaje y swap.
- `base_install.sh`: sistema base y fstab.
- `bootloader.sh`: GRUB.
- `plymouth.sh`: Plymouth compartido.
- `drivers.sh`: audio, codecs, Bluetooth y drivers compartidos.
- `cage.sh`: Cage, usuario, servicio y wrapper.
- `yarg.sh`: descarga/configuracion de YARG, Samba y updater.
- `clonehero.sh`: descarga/configuracion de Clone Hero, Samba, updater y CSV.
- `customization.sh`: limpieza visual, cursor y assets.
- `finalization.sh`: red, SSH opcional y desmontaje.

## Pruebas

Ejecuta BATS cuando estes en Linux/WSL:

```bash
bats tests/*.bats
```

Valida sintaxis de Bash:

```bash
bash -n install-cage-kiosk.sh
bash -n install-cage-yarg.sh
bash -n install-cage-clonehero.sh
for file in lib/*.sh; do bash -n "$file"; done
bash -n scripts/clone-miniarch.sh scripts/expand-home.sh
```

Si tocas `lib/drivers.sh`, `lib/validation.sh` o `lib/plymouth.sh`, revisa que
no rompa los caminos Cage.

## Pull Requests

Incluye:

- Que cambio.
- Por que.
- Que camino afecta: Cage/YARG, Cage/foot o ambos.
- Pruebas ejecutadas.
- Riesgos conocidos.

## Changelog

Agrega cambios relevantes en `CHANGELOG.md` bajo `[No Publicado]`.
