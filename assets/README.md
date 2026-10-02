# Assets del instalador

Recursos visuales que usan los instaladores `install-cage-*.sh`: la imagen de
arranque de Plymouth y el cursor del kiosko.

## Contenido

```text
assets/
├── yarg_720p.png            # Plymouth para el camino Cage/YARG (1280x720)
├── yarg_1080p.png           # Plymouth para el camino Cage/YARG (1920x1080)
├── clonehero_720p.png       # Plymouth para el camino Cage/Clone Hero
├── clonehero_1080p.png
├── rpcs3_720p.png           # Plymouth para el camino Cage/RPCS3 (1280x720)
├── rpcs3_1080p.png          # Plymouth para el camino Cage/RPCS3 (1920x1080)
├── plymouth-image_720p.png  # Imagen genérica de respaldo
├── plymouth-image_1080p.png
├── plymouth-image.png.example   # Nota sobre cómo usar tu propia imagen
├── rpcs3-input-Default.yml      # Entrada de RPCS3: jugador 1 = control Xbox por SDL
├── create-example-assets.sh     # Genera una imagen de ejemplo con ImageMagick
└── cursor/                  # Cursor del kiosko (ver cursor/README.md)
```

## Cómo se elige la imagen de Plymouth

Con el valor por defecto de `PLYMOUTH_IMAGE_PATH` (`./assets/plymouth-image.png`),
`install-cage-yarg.sh`, `install-cage-clonehero.sh` e `install-cage-rpcs3.sh`
eligen automáticamente la primera imagen que exista, según el camino y la
resolución elegidos (`select_plymouth_image`):

1. `<camino>_<resolución>.png` (por ejemplo `yarg_1080p.png`) y sus variantes
   `<camino>-<resolución>.png` y `<camino>_<ancho>x<alto>.png`.
2. `plymouth-image_<resolución>.png`.
3. `plymouth-image.png`.

El camino RPCS3 usa 1080p: elige `rpcs3_1080p.png` (el logotipo de RPCS3 sobre el
mismo fondo que `yarg_*.png`) y, si no existiera, cae en
`plymouth-image_1080p.png`. Las dos imagenes `rpcs3_*.png` se generaron a partir
del fondo `plymouth-image_<resolución>.png` y del logotipo de RPCS3, que es marca
de ese proyecto y no se distribuye aqui por separado.

Si defines `PLYMOUTH_IMAGE_PATH` con una ruta propia, se respeta tal cual.
`install-cage-kiosk.sh` (foot) no elige por resolución: usa `PLYMOUTH_IMAGE_PATH` y
la escala a 1280x720.

## Usar tu propia imagen

Requisitos:

- **Formato:** PNG válido (el instalador lo comprueba con `file`; un archivo que
  no sea PNG detiene la instalación).
- **Resolución:** la de tu pantalla. Si ImageMagick está disponible, el
  instalador la **escala a la resolución elegida** (`PLYMOUTH_TARGET_RESOLUTION`,
  por ejemplo `1920x1080`); si no, copia el PNG sin escalar.
- **Recomendado:** fondo oscuro, poco detalle y menos de 5 MB. Es una imagen
  estática que se muestra durante el arranque y el apagado.

Elige una de estas formas:

```bash
# 1) Nombre por camino y resolución: se detecta sola
cp mi-imagen.png assets/yarg_1080p.png

# 2) Ruta explícita en .env
PLYMOUTH_IMAGE_PATH=/ruta/a/mi-imagen.png
```

El repo se clona dentro del ISO live (`git clone https://github.com/Xalcker/MiniArch.git`),
así que copia tus imágenes a la carpeta `assets/` del clon **antes** de ejecutar
el instalador, o apunta `PLYMOUTH_IMAGE_PATH` a un archivo en un USB montado.
ImageMagick no viene en el ISO: instálalo con `pacman -Sy imagemagick` si quieres
el escalado.

Si la imagen falta, Plymouth se instala sin imagen personalizada y la
instalación continúa; si existe pero no es un PNG válido, la instalación se
detiene antes de tocar el disco.

## Crear una imagen de ejemplo

`create-example-assets.sh` genera un degradado con texto en la resolución que
indiques (por defecto `1920x1080`) usando ImageMagick (`magick` o `convert`):

```bash
cd assets
bash create-example-assets.sh              # plymouth-image.png en 1920x1080
bash create-example-assets.sh 1280x720     # otra resolución
```

También puedes diseñarla en GIMP, Inkscape o cualquier editor; basta con
exportar un PNG. Para comprobarla:

```bash
file mi-imagen.png        # PNG image data, 1920 x 1080, ...
identify mi-imagen.png    # (ImageMagick) dimensiones
```

## Cursor

Ver [cursor/README.md](cursor/README.md): el instalador genera el tema
`MiniArchPick` a partir de un PNG.
