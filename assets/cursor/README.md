# Cursor del kiosko

El kiosko usa un cursor con forma de **púa de guitarra**. Basta con un PNG: el
instalador genera el tema de cursor a partir de él.

## Archivos

```text
assets/cursor/
├── guitar-pick-left.png   # PNG usado por el instalador (50x64, RGBA)
├── guitar-pick-left.svg   # Fuente vectorial del PNG
└── README.md
```

## Qué hace el instalador

`install-cage-yarg.sh`, `install-cage-clonehero.sh` e `install-cage-rpcs3.sh`
llaman a `install_custom_cursor` con `CURSOR_PATH` (por defecto
`./assets/cursor/`):

1. Si `CURSOR_PATH` es un directorio que contiene `guitar-pick-left.png`, o es
   directamente un archivo `.png`, genera el tema **`MiniArchPick`** con
   `xcursorgen` (paquete `xorg-xcursorgen` de Arch, ya incluido en el sistema
   base de estos caminos) usando la configuración `64 23 8 <png>`: tamaño 64 y
   punto activo en x=23, y=8.
2. Crea los cursores `default`, `left_ptr`, `pointer` y `hand` en
   `/usr/share/icons/MiniArchPick/cursors/` y lo deja como cursor por defecto
   (`/usr/share/icons/default/index.theme` y `~/.icons/default/index.theme`
   heredan de `MiniArchPick`).
3. Los wrappers `run-yarg.sh`, `run-clonehero.sh` y `run-rpcs3.sh` exportan
   `XCURSOR_THEME=MiniArchPick` y `XCURSOR_SIZE=64` si el tema existe.

El camino minimal `install-cage-kiosk.sh` (foot) **no instala cursor**.

Si `CURSOR_PATH` no existe, se omite el cursor personalizado y se usa el del
sistema. Si apunta a un directorio sin `guitar-pick-left.png` (por ejemplo un
tema X11 completo con `cursors/` e `index.theme`), el instalador copia su
contenido a `/usr/share/icons/default/`.

## Usar tu propio cursor

1. Dibuja un cursor de unos **64 px de alto** con fondo transparente (Inkscape,
   GIMP, etc.) y expórtalo como PNG.
2. Reemplaza `guitar-pick-left.png` (conservando el nombre) o apunta
   `CURSOR_PATH` a tu PNG:

   ```bash
   CURSOR_PATH=/ruta/a/mi-cursor.png
   ```

3. El punto activo (la "punta" que hace clic) está fijo en x=23, y=8 de un
   cursor de 64 px. Si tu diseño tiene la punta en otro lugar, ajusta la línea
   `64 23 8 ...` en `install_custom_cursor` (`lib/customization.sh`).

## Probar el PNG en tu equipo

En Arch Linux (o con `xcursorgen` instalado):

```bash
cd assets/cursor
echo "64 23 8 guitar-pick-left.png" > /tmp/cursor.cfg
xcursorgen /tmp/cursor.cfg /tmp/cursor-prueba && file /tmp/cursor-prueba
# Debe mostrar: X11 cursor
```

`xcursorgen` viene en `xorg-xcursorgen` (Arch) o `x11-apps` (Debian/Ubuntu).
