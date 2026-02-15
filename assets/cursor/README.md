# Cursor Personalizado para Arch Linux Kiosko

Este directorio contiene el cursor personalizado que se usará en el sistema kiosko.

## Estructura Requerida

Para que el cursor funcione correctamente, debe seguir la estructura estándar de temas de cursor de X11:

```
cursor/
├── cursors/              # Directorio con los archivos de cursor
│   ├── default          # Cursor predeterminado
│   ├── pointer          # Cursor de puntero
│   ├── hand             # Cursor de mano (enlaces)
│   ├── text             # Cursor de texto (I-beam)
│   ├── wait             # Cursor de espera
│   └── ...              # Otros cursores opcionales
└── index.theme          # Archivo de configuración del tema
```

## Opción 1: Usar un Tema de Cursor Existente

### Descargar Temas Populares

Puedes descargar temas de cursor desde:
- [GNOME Look - Cursors](https://www.gnome-look.org/browse?cat=107)
- [KDE Store - Cursors](https://store.kde.org/browse?cat=107)

### Instalar un Tema Descargado

```bash
# Descargar y extraer el tema
wget https://ejemplo.com/cursor-theme.tar.gz
tar -xzf cursor-theme.tar.gz

# Copiar a este directorio
cp -r cursor-theme/* assets/cursor/
```

## Opción 2: Crear un Cursor Personalizado

### Usando Inkscape (Para cursores SVG)

1. Crea tu diseño de cursor en Inkscape (32x32 o 48x48 píxeles)
2. Exporta como PNG con transparencia
3. Convierte a formato X11 cursor usando `xcursorgen`

### Usando xcursorgen

```bash
# Instalar herramientas necesarias
sudo apt-get install x11-apps

# Crear archivo de configuración (cursor.cfg)
cat > cursor.cfg << EOF
32 16 16 cursor-32.png
48 24 24 cursor-48.png
EOF

# Generar cursor
xcursorgen cursor.cfg cursors/default
```

## Opción 3: Usar un Cursor Simple (Recomendado para Principiantes)

### Crear un Cursor Básico con ImageMagick

```bash
# Crear directorio de cursors
mkdir -p cursors

# Crear una imagen simple de cursor (flecha negra)
convert -size 32x32 xc:transparent \
    -fill black -draw "polygon 0,0 0,20 8,16 12,24 16,22 12,14 20,14" \
    cursor-temp.png

# Convertir a formato X11 cursor
# Nota: Esto requiere xcursorgen
echo "32 0 0 cursor-temp.png" > cursor.cfg
xcursorgen cursor.cfg cursors/default

# Crear enlaces simbólicos para otros tipos de cursor
cd cursors
ln -s default pointer
ln -s default hand
ln -s default text
ln -s default wait
cd ../..
```

## Archivo index.theme

Crea el archivo `index.theme` con el siguiente contenido:

```ini
[Icon Theme]
Name=Kiosk Cursor
Comment=Cursor personalizado para modo kiosko
```

### Ejemplo Completo de index.theme

```bash
cat > index.theme << 'EOF'
[Icon Theme]
Name=Kiosk Cursor
Comment=Cursor personalizado para Arch Linux Kiosko
Example=default
EOF
```

## Cursores Recomendados para Modo Kiosko

Para un sistema kiosko, generalmente solo necesitas:

1. **default** - Cursor predeterminado (flecha)
2. **pointer** - Cursor sobre elementos clicables (mano)
3. **text** - Cursor sobre texto (I-beam)
4. **wait** - Cursor de espera (reloj/spinner)

## Instalación Rápida: Usar Cursor del Sistema

Si no quieres crear un cursor personalizado, puedes copiar uno del sistema:

```bash
# En un sistema Linux con X11
cp -r /usr/share/icons/Adwaita/cursors/* assets/cursor/cursors/

# O usar el cursor predeterminado de X11
cp -r /usr/share/icons/default/cursors/* assets/cursor/cursors/
```

## Ejemplo: Cursor Minimalista Negro

Aquí hay un script completo para crear un cursor simple:

```bash
#!/bin/bash

# Crear estructura
mkdir -p cursors

# Función para crear cursor
create_cursor() {
    local name=$1
    local size=$2
    
    # Crear imagen temporal
    convert -size ${size}x${size} xc:transparent \
        -fill black -draw "polygon 0,0 0,20 8,16 12,24 16,22 12,14 20,14" \
        temp_${name}.png
    
    # Crear configuración
    echo "${size} 0 0 temp_${name}.png" > temp_${name}.cfg
    
    # Generar cursor
    xcursorgen temp_${name}.cfg cursors/${name}
    
    # Limpiar
    rm temp_${name}.png temp_${name}.cfg
}

# Crear cursors en diferentes tamaños
create_cursor default 32
create_cursor pointer 32
create_cursor hand 32
create_cursor text 32
create_cursor wait 32

# Crear index.theme
cat > index.theme << 'EOF'
[Icon Theme]
Name=Kiosk Cursor
Comment=Cursor minimalista para modo kiosko
EOF

echo "Cursor creado exitosamente en assets/cursor/"
```

## Validar el Cursor

Antes de usar el cursor, valida que los archivos existen:

```bash
# Verificar estructura
ls -la cursors/
ls -la index.theme

# Verificar que los archivos de cursor son válidos
file cursors/default
# Debe mostrar: X11 cursor
```

## Transferir a la VM

```bash
# Desde tu máquina host
scp -r cursor/* root@<IP_DE_LA_VM>:/root/arch-kiosk-installer/assets/cursor/
```

## Troubleshooting

### Error: "xcursorgen: command not found"

```bash
# Ubuntu/Debian
sudo apt-get install x11-apps

# Arch Linux
sudo pacman -S xorg-xcursorgen
```

### El cursor no se muestra correctamente

1. Verifica que el directorio `cursors/` existe y contiene archivos
2. Verifica que `index.theme` existe y tiene el formato correcto
3. Asegúrate de que los archivos de cursor son formato X11 cursor (no PNG o SVG)

### Usar cursor predeterminado del sistema

Si tienes problemas, el script puede usar el cursor predeterminado del sistema. Simplemente no proporciones archivos en este directorio.

## Recursos Adicionales

- [X11 Cursor Specification](https://www.x.org/releases/X11R7.7/doc/man/man3/Xcursor.3.xhtml)
- [xcursorgen Manual](https://linux.die.net/man/1/xcursorgen)
- [Cursor Themes on GNOME Look](https://www.gnome-look.org/browse?cat=107)
- [Creating Custom Cursors Tutorial](https://wiki.archlinux.org/title/Cursor_themes)

## Cursores Populares Recomendados

- **Breeze** - Cursor moderno de KDE
- **Adwaita** - Cursor predeterminado de GNOME
- **Oxygen** - Cursor clásico de KDE
- **DMZ** - Cursor simple y limpio
- **Vanilla** - Cursor minimalista

Puedes instalar estos desde los repositorios:

```bash
# En Arch Linux
sudo pacman -S breeze-icons
sudo pacman -S adwaita-icon-theme
```

Luego copiar los cursors a este directorio.
