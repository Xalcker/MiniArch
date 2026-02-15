# Assets para Instalador de Arch Linux Kiosko

Este directorio contiene los recursos visuales personalizables para el instalador.

## Estructura

```
assets/
├── plymouth-image.png     # Imagen para Plymouth (1280x720)
├── cursor/                # Cursor personalizado
│   └── README.md         # Instrucciones para el cursor
└── README.md             # Este archivo
```

## Imagen de Plymouth (plymouth-image.png)

### Requisitos

- **Formato**: PNG válido
- **Resolución recomendada**: 1280x720 píxeles
- **Profundidad de color**: 24-bit o 32-bit (con alpha)
- **Tamaño de archivo**: Preferiblemente < 5MB

### Cómo Crear la Imagen

#### Opción 1: Usar GIMP (Recomendado)

1. Abre GIMP
2. Crea una nueva imagen: `Archivo → Nuevo`
   - Ancho: 1280 píxeles
   - Alto: 720 píxeles
3. Diseña tu imagen de arranque
4. Exporta como PNG: `Archivo → Exportar como`
   - Nombre: `plymouth-image.png`
   - Ubicación: Este directorio (`assets/`)

#### Opción 2: Usar ImageMagick desde línea de comandos

```bash
# Crear una imagen simple con texto
convert -size 1280x720 xc:black \
    -font Arial -pointsize 72 -fill white \
    -gravity center -annotate +0+0 "Arch Linux Kiosko" \
    plymouth-image.png

# Crear una imagen con gradiente
convert -size 1280x720 gradient:blue-black \
    -font Arial -pointsize 60 -fill white \
    -gravity center -annotate +0+0 "Bienvenido" \
    plymouth-image.png

# Redimensionar una imagen existente
convert mi-imagen.png -resize 1280x720! plymouth-image.png
```

#### Opción 3: Usar Python con Pillow

```python
from PIL import Image, ImageDraw, ImageFont

# Crear imagen
img = Image.new('RGB', (1280, 720), color='#1a1a2e')

# Agregar texto
draw = ImageDraw.Draw(img)
try:
    font = ImageFont.truetype("arial.ttf", 60)
except:
    font = ImageFont.load_default()

text = "Arch Linux Kiosko"
bbox = draw.textbbox((0, 0), text, font=font)
text_width = bbox[2] - bbox[0]
text_height = bbox[3] - bbox[1]

position = ((1280 - text_width) // 2, (720 - text_height) // 2)
draw.text(position, text, fill='white', font=font)

# Guardar
img.save('plymouth-image.png')
```

### Imagen de Ejemplo Incluida

Si no proporcionas una imagen personalizada, el script usará una imagen predeterminada simple. Para crear tu propia imagen de ejemplo:

```bash
# Instalar ImageMagick si no lo tienes
# Ubuntu/Debian: sudo apt-get install imagemagick
# macOS: brew install imagemagick
# Windows: Descargar desde https://imagemagick.org/

# Crear imagen de ejemplo
cd assets
convert -size 1280x720 gradient:#0f2027-#203a43-#2c5364 \
    -font Arial-Bold -pointsize 80 -fill white \
    -gravity center -annotate +0-50 "Arch Linux" \
    -pointsize 40 -annotate +0+50 "Modo Kiosko" \
    plymouth-image.png
```

### Validar la Imagen

Antes de usar la imagen, valida que sea un PNG correcto:

```bash
# Verificar formato
file plymouth-image.png
# Debe mostrar: PNG image data, 1280 x 720, ...

# Verificar dimensiones
identify plymouth-image.png
# Debe mostrar: plymouth-image.png PNG 1280x720 ...
```

### Notas Importantes

- El script escalará automáticamente la imagen a 1280x720 si tiene dimensiones diferentes
- Se recomienda usar imágenes con fondo oscuro para mejor contraste
- Evita imágenes muy complejas o con mucho detalle (pueden verse mal durante el arranque)
- La imagen se mostrará durante el arranque y apagado del sistema

## Cursor Personalizado

Ver `cursor/README.md` para instrucciones sobre cómo agregar un cursor personalizado.

## Transferir Assets a la VM

### Método 1: SCP (Recomendado)

```bash
# Desde tu máquina host
scp plymouth-image.png root@<IP_DE_LA_VM>:/root/arch-kiosk-installer/assets/
scp -r cursor/* root@<IP_DE_LA_VM>:/root/arch-kiosk-installer/assets/cursor/
```

### Método 2: Carpeta Compartida de VirtualBox

1. En VirtualBox: `Configuración → Carpetas compartidas`
2. Agregar carpeta compartida apuntando a `assets/`
3. En la VM:
```bash
mkdir /mnt/shared
mount -t vboxsf nombre_compartido /mnt/shared
cp /mnt/shared/plymouth-image.png /root/arch-kiosk-installer/assets/
```

### Método 3: Servidor Web Temporal

```bash
# En tu máquina host (con Python)
cd assets
python3 -m http.server 8000

# En la VM
cd /root/arch-kiosk-installer/assets
wget http://<IP_DEL_HOST>:8000/plymouth-image.png
```

## Ejemplos de Diseño

### Diseño Minimalista

- Fondo negro sólido
- Logo o texto centrado en blanco
- Sin animaciones (Plymouth mostrará la imagen estática)

### Diseño Corporativo

- Colores de la marca
- Logo de la empresa centrado
- Texto opcional con nombre del sistema

### Diseño Moderno

- Gradiente suave de colores
- Tipografía moderna
- Elementos geométricos simples

## Recursos Adicionales

- [Plymouth Themes](https://www.gnome-look.org/browse?cat=108)
- [ImageMagick Documentation](https://imagemagick.org/index.php)
- [GIMP Tutorials](https://www.gimp.org/tutorials/)
- [Pillow Documentation](https://pillow.readthedocs.io/)
