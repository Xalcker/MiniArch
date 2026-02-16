# Instalador Automatizado de Arch Linux - Modo Kiosko

Script de instalación automatizada de Arch Linux que configura un sistema tipo kiosko con arranque directo a X, interfaz gráfica minimalista (OpenBox), y personalización visual completa del proceso de arranque mediante Plymouth.

## Características

- ✅ Instalación completamente automatizada de Arch Linux
- 🎨 Arranque silencioso con GRUB (Plymouth opcional)
- 🖥️ Entorno gráfico minimalista con OpenBox en modo kiosko
- 🔒 Autologin automático al usuario kiosko
- 🎯 Configuración optimizada para modo kiosko (1 escritorio, sin cambio con rueda del mouse)
- 🔌 SSH habilitado para acceso remoto
- 🪟 xterm se inicia automáticamente y apaga el sistema al cerrar
- 🧪 Suite completa de pruebas con BATS

## Requisitos Previos

### Hardware y Virtualización

- **VirtualBox** (o cualquier hipervisor compatible con UEFI)
- **Disco virtual**: Mínimo 16GB de espacio
- **RAM**: Mínimo 2GB recomendado
- **Conexión de red**: Requerida durante la instalación

### Software

- **Arch Linux ISO**: Descarga la última versión desde [archlinux.org](https://archlinux.org/download/)
- **Cliente SCP**: Para transferir archivos personalizados (opcional)
- **WSL Ubuntu**: Para ejecutar las pruebas (solo desarrollo)

## Configuración de VirtualBox

1. Crear una nueva máquina virtual:
   - Tipo: Linux
   - Versión: Arch Linux (64-bit)
   - RAM: 2048 MB o más
   - Disco: 16 GB o más (VDI, dinámicamente asignado)

2. Configurar opciones de sistema:
   - **Sistema → Placa base**: Habilitar EFI
   - **Sistema → Procesador**: 2 CPUs recomendado
   - **Red → Adaptador 1**: NAT o Bridged (para acceso a internet)

3. Montar la ISO de Arch Linux:
   - **Almacenamiento → Controlador IDE**: Agregar disco óptico
   - Seleccionar la ISO de Arch Linux

4. Iniciar la máquina virtual

## Instalación

### Paso 1: Arrancar desde el Instalador de Arch Linux

1. Inicia la máquina virtual con la ISO de Arch Linux
2. Selecciona "Arch Linux install medium" en el menú de arranque
3. Espera a que cargue el entorno live

### Paso 2: Verificar Conexión de Red

```bash
# Verificar conectividad
ping -c 3 archlinux.org

# Si no hay conexión, configurar manualmente:
ip link  # Ver interfaces de red
dhcpcd   # Obtener IP automáticamente
```

### Paso 3: Transferir el Script al Instalador

Hay varias formas de obtener el script en el instalador:

#### Opción A: Clonar desde Git (Recomendado)

```bash
# Instalar git si es necesario
pacman -Sy git

# Clonar el repositorio
git clone https://github.com/tu-usuario/arch-kiosk-installer.git
cd arch-kiosk-installer
```

#### Opción B: Transferir vía SCP

Desde tu máquina host (con el script):

```bash
# Obtener la IP de la VM
# En la VM, ejecuta: ip addr show

# Desde el host, transferir archivos
scp -r arch-kiosk-installer/ root@<IP_DE_LA_VM>:/root/
```

#### Opción C: Descargar con curl/wget

```bash
# Si tienes el script en un servidor web
curl -O https://tu-servidor.com/install-arch-kiosk.sh
chmod +x install-arch-kiosk.sh
```

### Paso 4: Personalizar Assets (Opcional)

Si deseas usar una imagen y cursor personalizados:

```bash
# Crear directorio de assets si no existe
mkdir -p assets/cursor

# Transferir imagen PNG (debe ser válida)
# Desde el host:
scp plymouth-image.png root@<IP_DE_LA_VM>:/root/arch-kiosk-installer/assets/

# Transferir cursor personalizado
scp -r cursor/* root@<IP_DE_LA_VM>:/root/arch-kiosk-installer/assets/cursor/
```

**Requisitos de la imagen Plymouth:**
- Formato: PNG válido
- Resolución recomendada: 1280x720 (se escalará automáticamente si es diferente)
- Ubicación: `assets/plymouth-image.png`

**Requisitos del cursor:**
- Formato: Cualquier formato soportado por X11 (SVG, PNG, etc.)
- Ubicación: `assets/cursor/`

### Paso 5: Ejecutar el Script

```bash
# Dar permisos de ejecución
chmod +x install-arch-kiosk.sh

# Ejecutar el script
./install-arch-kiosk.sh
```

El script realizará automáticamente:
1. Validación del entorno y requisitos
2. Particionamiento y formateo del disco
3. Instalación del sistema base
4. Configuración de GRUB silencioso
5. Instalación y configuración de Plymouth (opcional, continúa si falla)
6. Instalación de drivers gráficos y audio
7. Configuración de OpenBox en modo kiosko y autologin
8. Configuración de xterm con apagado automático
9. Personalización visual
10. Configuración de red y SSH
11. Limpieza y finalización

### Paso 6: Reiniciar

```bash
# Una vez completada la instalación
reboot
```

## Configuración Post-Instalación

### Usuario Predeterminado

- **Usuario**: `kiosk`
- **Contraseña**: `kiosk123` (cambiar después del primer inicio)

### Acceso SSH

El sistema tiene SSH habilitado automáticamente. Para conectarte:

```bash
# Desde tu máquina host, obtén la IP de la VM
# En la VM, ejecuta: ip addr show

# Conectar por SSH
ssh kiosk@<IP_DE_LA_VM>

# Usar la contraseña configurada (por defecto: kiosk123)
```

### Comportamiento del Sistema

- **Inicio automático**: El sistema arranca directamente a X con OpenBox
- **xterm automático**: Se abre xterm al iniciar
- **Apagado automático**: Al cerrar xterm (escribiendo `exit` o Ctrl+D), el sistema se apaga
- **Modo kiosko**: OpenBox está configurado con 1 solo escritorio, sin cambio con rueda del mouse

### Cambiar Contraseña

```bash
# Después del primer inicio (por SSH o en xterm)
passwd
```

### Configurar Aplicación Kiosko

El sistema inicia automáticamente en OpenBox con xterm. Para configurar tu aplicación kiosko:

**Opción 1: Reemplazar xterm con tu aplicación**

1. Conectar por SSH o editar desde xterm:

```bash
nano ~/.config/openbox/autostart
```

2. Reemplazar el contenido con tu aplicación (ejemplo con Chromium en modo kiosko):

```bash
#!/bin/bash
# Esperar a que X esté listo
sleep 2

# Iniciar aplicación en modo kiosko
chromium --kiosk --no-first-run --disable-infobars https://tu-aplicacion.com &
APP_PID=$!

# Apagar el sistema cuando la aplicación se cierre
(
    while kill -0 $APP_PID 2>/dev/null; do
        sleep 1
    done
    /usr/bin/shutdown -h now
) &
```

3. Hacer ejecutable y reiniciar OpenBox:

```bash
chmod +x ~/.config/openbox/autostart
openbox --reconfigure
```

**Opción 2: Mantener xterm y agregar tu aplicación**

Si quieres mantener xterm para debugging:

```bash
#!/bin/bash
sleep 2

# Iniciar tu aplicación
tu-aplicacion &

# Iniciar xterm (opcional, para debugging)
xterm -e /bin/bash &
XTERM_PID=$!

# Apagar cuando xterm se cierre
(
    while kill -0 $XTERM_PID 2>/dev/null; do
        sleep 1
    done
    /usr/bin/shutdown -h now
) &
```

**Instalar aplicaciones adicionales:**

```bash
# Por SSH o desde xterm
sudo pacman -S chromium  # Navegador
sudo pacman -S firefox   # Navegador alternativo
sudo pacman -S vlc       # Reproductor multimedia
# O tu aplicación preferida
```

## Desarrollo y Pruebas

### Ejecutar Pruebas en WSL Ubuntu

Las pruebas están diseñadas para ejecutarse en WSL Ubuntu sin modificar el sistema real.

#### Configurar Entorno de Pruebas

```bash
# En WSL Ubuntu, instalar BATS
sudo apt-get update
sudo apt-get install bats

# Navegar al directorio del proyecto
cd /mnt/c/ruta/a/arch-kiosk-installer
```

#### Ejecutar Pruebas

```bash
# Ejecutar todas las pruebas
bats tests/*.bats

# Ejecutar pruebas de un módulo específico
bats tests/test_validation.bats
bats tests/test_partitioning.bats
bats tests/test_bootloader.bats

# Ejecutar con salida detallada
bats --tap tests/*.bats

# Guardar resultados
bats tests/*.bats | tee test-results.log
```

#### Estructura de Pruebas

```
tests/
├── test_validation.bats       # Pruebas de validación de entorno
├── test_partitioning.bats     # Pruebas de particionamiento
├── test_base_install.bats     # Pruebas de instalación base
├── test_bootloader.bats       # Pruebas de GRUB
├── test_plymouth.bats         # Pruebas de Plymouth
├── test_drivers.bats          # Pruebas de drivers
├── test_gui.bats              # Pruebas de OpenBox
├── test_customization.bats    # Pruebas de personalización
├── test_finalization.bats     # Pruebas de finalización
└── test_integration.bats      # Pruebas de integración completa
```

## Estructura del Proyecto

```
arch-kiosk-installer/
├── install-arch-kiosk.sh      # Script principal
├── lib/                        # Módulos del script
│   ├── validation.sh          # Validación de entorno
│   ├── partitioning.sh        # Particionamiento de disco
│   ├── base_install.sh        # Instalación base
│   ├── bootloader.sh          # Configuración de GRUB
│   ├── plymouth.sh            # Configuración de Plymouth
│   ├── drivers.sh             # Instalación de drivers
│   ├── gui.sh                 # Configuración de OpenBox
│   ├── customization.sh       # Personalización visual
│   └── finalization.sh        # Finalización y limpieza
├── assets/                     # Recursos personalizables
│   ├── plymouth-image.png     # Imagen para Plymouth
│   └── cursor/                # Cursor personalizado
├── tests/                      # Suite de pruebas BATS
└── README.md                   # Este archivo
```

## Troubleshooting

### Error: "No se detectó el instalador de Arch Linux"

**Causa**: El script no está ejecutándose desde el entorno live de Arch.

**Solución**: Asegúrate de estar en el instalador de Arch Linux, no en un sistema ya instalado.

### Error: "Sin conexión de red"

**Causa**: La máquina virtual no tiene acceso a internet.

**Solución**:
```bash
# Verificar interfaces
ip link

# Activar interfaz
ip link set <interfaz> up

# Obtener IP
dhcpcd
```

### Error: "Disco /dev/sda no encontrado o muy pequeño"

**Causa**: El disco no existe o tiene menos de 16GB.

**Solución**:
- Verifica la configuración de VirtualBox
- Asegúrate de que el disco virtual tenga al menos 16GB
- El disco debe estar en `/dev/sda` (primer disco SATA)

### Error: "Fallo en instalación de GRUB"

**Causa**: UEFI no está habilitado o la partición ESP no está correctamente montada.

**Solución**:
- Habilita EFI en la configuración de VirtualBox
- Verifica que `/boot` esté montado correctamente
- Ejecuta manualmente: `grub-install --target=x86_64-efi --efi-directory=/boot`

### Error: "Plymouth no muestra la imagen"

**Causa**: La imagen no es un PNG válido o no se escaló correctamente.

**Solución**:
```bash
# Verificar formato de imagen
file assets/plymouth-image.png

# Debe mostrar: PNG image data

# Verificar tema activo
plymouth-set-default-theme --list

# Reconstruir initramfs
mkinitcpio -P
```

### El sistema no inicia X automáticamente

**Causa**: Configuración de autologin o .bash_profile incorrecta.

**Solución**:
```bash
# Verificar autologin
cat /etc/systemd/system/getty@tty1.service.d/autologin.conf

# Verificar .bash_profile
cat ~/.bash_profile

# Debe contener:
# if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" = 1 ]; then
#     exec startx
# fi
```

### No puedo conectarme por SSH

**Causa**: SSH no está iniciado o hay problemas de red.

**Solución**:
```bash
# Verificar que SSH está corriendo
sudo systemctl status sshd

# Si no está corriendo, iniciarlo
sudo systemctl start sshd

# Verificar que está habilitado para inicio automático
sudo systemctl enable sshd

# Verificar IP de la VM
ip addr show

# Verificar firewall (si existe)
sudo iptables -L
```

### xterm no se cierra con 'exit'

**Causa**: Versión anterior del script usaba `-hold` que mantiene xterm abierto.

**Solución**:
```bash
# Editar el archivo autostart
nano ~/.config/openbox/autostart

# Asegurarse de que la línea de xterm NO tenga -hold:
# Correcto: xterm -e /bin/bash &
# Incorrecto: xterm -hold -e /bin/bash &

# Guardar y reiniciar OpenBox
openbox --reconfigure
```

### La rueda del mouse cambia de escritorio

**Causa**: Configuración de OpenBox no está en modo kiosko.

**Solución**:
```bash
# Verificar que existe el archivo rc.xml
ls -la ~/.config/openbox/rc.xml

# Si no existe, crearlo con la configuración de modo kiosko
# Ver sección "Configurar Aplicación Kiosko" para el contenido
```

### Pruebas BATS fallan en WSL

**Causa**: Permisos o dependencias faltantes.

**Solución**:
```bash
# Instalar dependencias
sudo apt-get install bats coreutils

# Dar permisos de ejecución
chmod +x tests/*.bats
chmod +x lib/*.sh

# Ejecutar con bash explícito
bash -c "bats tests/test_validation.bats"
```

## Personalización Avanzada

### Cambiar Zona Horaria

Edita la variable en `install-arch-kiosk.sh`:

```bash
TIMEZONE="America/Mexico_City"  # Cambiar a tu zona horaria
```

### Cambiar Usuario y Contraseña

Edita las variables en `install-arch-kiosk.sh`:

```bash
KIOSK_USER="kiosk"           # Cambiar nombre de usuario
KIOSK_PASSWORD="kiosk123"    # Cambiar contraseña
```

### Agregar Paquetes Adicionales

Edita la función `install_base_system()` en `lib/base_install.sh`:

```bash
pacstrap /mnt base linux linux-firmware \
    tu-paquete-adicional \
    otro-paquete
```

### Modificar Esquema de Particiones

Edita las variables en `install-arch-kiosk.sh`:

```bash
ESP_SIZE="512M"    # Tamaño de partición EFI
ROOT_SIZE="8G"     # Tamaño de partición root
SWAP_SIZE="2G"     # Tamaño de swap
# Home usa el espacio restante automáticamente
```

## Contribuir

Las contribuciones son bienvenidas. Por favor:

1. Fork el repositorio
2. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
3. Ejecuta las pruebas (`bats tests/*.bats`)
4. Commit tus cambios (`git commit -am 'Agregar nueva funcionalidad'`)
5. Push a la rama (`git push origin feature/nueva-funcionalidad`)
6. Crea un Pull Request

## Licencia

Este proyecto está bajo la licencia MIT. Ver archivo LICENSE para más detalles.

## Soporte

Para reportar problemas o solicitar funcionalidades, abre un issue en el repositorio de GitHub.

## Créditos

- Desarrollado para instalaciones automatizadas de Arch Linux
- Usa Plymouth para arranque gráfico
- OpenBox como gestor de ventanas minimalista
- BATS para pruebas automatizadas
