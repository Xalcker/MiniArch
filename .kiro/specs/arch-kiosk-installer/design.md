# Documento de Diseño: Instalador Automatizado de Arch Linux Modo Kiosko

## Overview

Este diseño describe un script Bash modular que automatiza la instalación de Arch Linux en una configuración tipo kiosko. El script está estructurado en funciones independientes que manejan cada fase de la instalación: validación, particionamiento, instalación del sistema base, configuración del gestor de arranque, instalación de Plymouth con temas personalizados, configuración de controladores gráficos, sistema de audio, y el entorno OpenBox con inicio automático.

El diseño prioriza la modularidad para facilitar las pruebas unitarias con BATS en WSL Ubuntu, donde cada función puede ser probada de forma aislada mediante mocks y stubs. El script principal orquesta la ejecución secuencial de estas funciones, con manejo de errores en cada paso para garantizar una instalación robusta.

## Architecture

### Arquitectura General

```
┌─────────────────────────────────────────────────────────────┐
│                    Script Principal                          │
│                  (install-arch-kiosk.sh)                     │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ├──> Módulo de Validación
                       │    - validate_environment()
                       │    - check_network()
                       │    - check_disk()
                       │
                       ├──> Módulo de Particionamiento
                       │    - partition_disk()
                       │    - format_partitions()
                       │    - mount_partitions()
                       │
                       ├──> Módulo de Instalación Base
                       │    - install_base_system()
                       │    - generate_fstab()
                       │    - configure_chroot()
                       │
                       ├──> Módulo de Bootloader
                       │    - install_grub()
                       │    - configure_grub_silent()
                       │
                       ├──> Módulo de Plymouth
                       │    - install_plymouth()
                       │    - create_custom_theme()
                       │    - configure_plymouth()
                       │
                       ├──> Módulo de Drivers
                       │    - install_graphics_drivers()
                       │    - install_audio_system()
                       │
                       ├──> Módulo de Entorno Gráfico
                       │    - install_openbox()
                       │    - configure_autologin()
                       │    - configure_autostart_x()
                       │
                       ├──> Módulo de Personalización
                       │    - hide_system_messages()
                       │    - install_custom_cursor()
                       │    - apply_plymouth_image()
                       │
                       └──> Módulo de Finalización
                            - configure_network()
                            - cleanup_and_finish()
```

### Flujo de Ejecución

1. **Fase de Validación**: Verifica entorno, red y disco
2. **Fase de Preparación**: Particiona, formatea y monta el disco
3. **Fase de Instalación**: Instala sistema base y genera fstab
4. **Fase de Configuración (en chroot)**: 
   - Configura GRUB silencioso
   - Instala y configura Plymouth
   - Instala drivers gráficos y audio
   - Configura OpenBox y autologin
   - Oculta mensajes del sistema
5. **Fase de Finalización**: Limpia y prepara para reinicio

### Estrategia de Pruebas

Las pruebas se ejecutarán en WSL Ubuntu usando BATS. Cada función será probada de forma aislada mediante:
- **Mocking de comandos**: Reemplazar comandos del sistema (parted, mkfs, pacstrap) con funciones mock
- **Validación de salidas**: Verificar que las funciones generan los archivos de configuración correctos
- **Pruebas de lógica**: Validar condiciones de error y flujos alternativos

## Components and Interfaces

### 1. Módulo de Validación (`validation.sh`)

**Funciones:**

```bash
validate_environment() -> exit_code
  # Verifica que se está ejecutando en el instalador de Arch Linux
  # Retorna: 0 si válido, 1 si inválido
  
check_network() -> exit_code
  # Verifica conectividad de red mediante ping a archlinux.org
  # Retorna: 0 si hay red, 1 si no hay red
  
check_disk() -> exit_code
  # Verifica que /dev/sda existe y tiene >= 16GB
  # Retorna: 0 si válido, 1 si inválido

check_disk_empty(device: string) -> exit_code
  # Verifica si el disco tiene particiones existentes
  # Muestra advertencia si hay particiones
  # Solicita confirmación explícita del usuario
  # Retorna: 0 si el usuario confirma o disco vacío, 1 si usuario cancela
```

**Interfaz:**
- Input: Variables de entorno del sistema, ruta del dispositivo de bloque
- Output: Códigos de salida (0 = éxito, 1 = error)
- Side effects: Imprime mensajes de error/advertencia a stderr, solicita input del usuario

### 2. Módulo de Particionamiento (`partitioning.sh`)

**Funciones:**

```bash
partition_disk(device: string) -> exit_code
  # Crea tabla GPT y 4 particiones en el dispositivo
  # device: ruta del dispositivo (ej: /dev/sda)
  # Particiones: 512MB EFI, 8GB root, 2GB swap, resto home
  
format_partitions(device: string) -> exit_code
  # Formatea las particiones creadas
  # ${device}1: FAT32, ${device}2: ext4, ${device}3: swap, ${device}4: ext4
  
mount_partitions(device: string) -> exit_code
  # Monta las particiones en /mnt
  # Orden: root -> /mnt, boot -> /mnt/boot, home -> /mnt/home
  # Activa swap
```

**Interfaz:**
- Input: Ruta del dispositivo de bloque
- Output: Códigos de salida
- Side effects: Modifica el disco, crea puntos de montaje, monta particiones

### 3. Módulo de Instalación Base (`base_install.sh`)

**Funciones:**

```bash
install_base_system() -> exit_code
  # Ejecuta pacstrap para instalar base, linux, linux-firmware
  
generate_fstab() -> exit_code
  # Genera /mnt/etc/fstab usando genfstab -U
  
configure_chroot() -> exit_code
  # Prepara el entorno chroot y ejecuta configuraciones internas
```

**Interfaz:**
- Input: Sistema montado en /mnt
- Output: Códigos de salida
- Side effects: Instala paquetes, genera archivos de configuración

### 4. Módulo de Bootloader (`bootloader.sh`)

**Funciones:**

```bash
install_grub() -> exit_code
  # Instala grub y efibootmgr
  # Ejecuta grub-install --target=x86_64-efi --efi-directory=/boot
  
configure_grub_silent() -> exit_code
  # Modifica /etc/default/grub para:
  # - GRUB_TIMEOUT=0
  # - GRUB_CMDLINE_LINUX_DEFAULT="quiet loglevel=3 rd.systemd.show_status=false rd.udev.log_level=3"
  # - GRUB_DISABLE_SUBMENU=y
  # Ejecuta grub-mkconfig -o /boot/grub/grub.cfg
```

**Interfaz:**
- Input: Sistema en chroot
- Output: Códigos de salida
- Side effects: Instala GRUB, modifica configuración, genera grub.cfg

### 5. Módulo de Plymouth (`plymouth.sh`)

**Funciones:**

```bash
install_plymouth() -> exit_code
  # Instala plymouth y plymouth-theme-spinner
  
create_custom_theme(theme_name: string) -> exit_code
  # Crea un tema personalizado en /usr/share/plymouth/themes/${theme_name}
  # Genera archivos: ${theme_name}.plymouth, ${theme_name}.script
  
configure_plymouth(theme_name: string, image_path: string) -> exit_code
  # Copia la imagen al directorio del tema
  # Escala la imagen a 1280x720 usando ImageMagick
  # Actualiza /etc/mkinitcpio.conf para agregar plymouth hook
  # Regenera initramfs con mkinitcpio -P
  # Activa el tema con plymouth-set-default-theme
  # Actualiza GRUB para agregar "splash" a GRUB_CMDLINE_LINUX_DEFAULT
```

**Interfaz:**
- Input: Nombre del tema, ruta de la imagen PNG
- Output: Códigos de salida
- Side effects: Instala paquetes, crea archivos de tema, modifica initramfs y GRUB

### 6. Módulo de Drivers (`drivers.sh`)

**Funciones:**

```bash
install_graphics_drivers() -> exit_code
  # Instala: xf86-video-amdgpu, xf86-video-intel, nvidia-open, mesa
  
install_audio_system() -> exit_code
  # Instala: pipewire, pipewire-alsa, pipewire-pulse, pipewire-jack, sof-firmware
  # Habilita servicios de PipeWire para el usuario
```

**Interfaz:**
- Input: Sistema en chroot
- Output: Códigos de salida
- Side effects: Instala paquetes de drivers

### 7. Módulo de Entorno Gráfico (`gui.sh`)

**Funciones:**

```bash
install_openbox() -> exit_code
  # Instala: xorg-server, xorg-xinit, openbox, xterm
  # Instala: xdg-desktop-portal, xdg-desktop-portal-gtk, gtk3
  
create_user(username: string) -> exit_code
  # Crea usuario del sistema con useradd
  # Configura password
  
configure_autologin(username: string) -> exit_code
  # Modifica /etc/systemd/system/getty@tty1.service.d/autologin.conf
  # Configura autologin para el usuario especificado
  
configure_autostart_x(username: string) -> exit_code
  # Crea /home/${username}/.xinitrc con "exec openbox-session"
  # Modifica /home/${username}/.bash_profile para ejecutar startx automáticamente
  
configure_xterm_autostart(username: string) -> exit_code
  # Crea /home/${username}/.config/openbox/autostart con comando para ejecutar xterm
  # Configura xterm para ejecutar shutdown -h now al cerrar
  # Crea /home/${username}/.config/openbox/rc.xml con configuración de modo kiosko:
  #   - Un solo escritorio virtual
  #   - Deshabilita cambio de escritorio con rueda del mouse
  #   - Deshabilita atajos de teclado para cambio de escritorio
```

**Interfaz:**
- Input: Nombre de usuario
- Output: Códigos de salida
- Side effects: Instala paquetes, crea usuario, modifica archivos de configuración, crea configuración de OpenBox para modo kiosko

### 8. Módulo de Personalización (`customization.sh`)

**Funciones:**

```bash
hide_system_messages(username: string) -> exit_code
  # Crea /home/${username}/.hushlogin
  # Vacía /etc/motd
  # Modifica /etc/systemd/system.conf: ShowStatus=no
  # Modifica /etc/systemd/logind.conf: NAutoVTs=0
  
install_custom_cursor(cursor_path: string, username: string) -> exit_code
  # Copia el cursor a /usr/share/icons/default/
  # Crea index.theme para configurar el cursor predeterminado
  # Configura el cursor para el usuario en ~/.icons/default/index.theme
  
apply_plymouth_image(image_path: string, theme_name: string) -> exit_code
  # Valida que el archivo es PNG
  # Copia y escala la imagen al directorio del tema
```

**Interfaz:**
- Input: Nombre de usuario, rutas de archivos personalizados
- Output: Códigos de salida
- Side effects: Crea archivos de configuración, copia recursos

### 9. Módulo de Finalización (`finalization.sh`)

**Funciones:**

```bash
configure_network() -> exit_code
  # Instala networkmanager
  # Habilita NetworkManager.service
  # Instala openssh
  # Habilita sshd.service
  # Configura zona horaria con timedatectl
  
cleanup_and_finish() -> exit_code
  # Sale del chroot
  # Desmonta todas las particiones
  # Desactiva swap
  # Muestra mensaje de éxito
```

**Interfaz:**
- Input: Sistema instalado
- Output: Códigos de salida
- Side effects: Desmonta particiones, muestra mensajes, habilita SSH para acceso remoto

## Data Models

### Estructura de Directorios del Proyecto

```
arch-kiosk-installer/
├── install-arch-kiosk.sh          # Script principal
├── lib/                            # Módulos del script
│   ├── validation.sh
│   ├── partitioning.sh
│   ├── base_install.sh
│   ├── bootloader.sh
│   ├── plymouth.sh
│   ├── drivers.sh
│   ├── gui.sh
│   ├── customization.sh
│   └── finalization.sh
├── assets/                         # Recursos personalizables
│   ├── plymouth-image.png         # Imagen para Plymouth (proporcionada por usuario)
│   └── cursor/                    # Cursor personalizado (proporcionado por usuario)
├── tests/                          # Suite de pruebas BATS
│   ├── test_validation.bats
│   ├── test_partitioning.bats
│   ├── test_base_install.bats
│   ├── test_bootloader.bats
│   ├── test_plymouth.bats
│   ├── test_drivers.bats
│   ├── test_gui.bats
│   ├── test_customization.bats
│   └── test_finalization.bats
└── README.md                       # Documentación de uso
```

### Variables de Configuración

El script utilizará variables globales para configuración:

```bash
# Configuración del disco
DISK_DEVICE="/dev/sda"
ESP_SIZE="512M"
ROOT_SIZE="8G"
SWAP_SIZE="2G"

# Configuración del usuario
KIOSK_USER="kiosk"
KIOSK_PASSWORD="kiosk123"

# Configuración de Plymouth
PLYMOUTH_THEME_NAME="arch-kiosk"
PLYMOUTH_IMAGE_PATH="./assets/plymouth-image.png"

# Configuración del cursor
CURSOR_PATH="./assets/cursor/"

# Configuración de zona horaria
TIMEZONE="America/Mexico_City"
```

### Archivos de Configuración Generados

El script generará y modificará los siguientes archivos:

1. **`/etc/default/grub`**: Configuración de GRUB silencioso
2. **`/etc/mkinitcpio.conf`**: Hooks de Plymouth
3. **`/usr/share/plymouth/themes/arch-kiosk/arch-kiosk.plymouth`**: Definición del tema
4. **`/usr/share/plymouth/themes/arch-kiosk/arch-kiosk.script`**: Script del tema Plymouth
5. **`/etc/systemd/system/getty@tty1.service.d/autologin.conf`**: Autologin
6. **`/home/kiosk/.xinitrc`**: Inicio de OpenBox
7. **`/home/kiosk/.bash_profile`**: Autostart de X
8. **`/home/kiosk/.hushlogin`**: Ocultar mensajes de login
9. **`/home/kiosk/.config/openbox/autostart`**: Autostart de xterm con apagado al cerrar
10. **`/etc/motd`**: Message of the day (vacío)
11. **`/etc/systemd/system.conf`**: Configuración de systemd
12. **`/etc/systemd/logind.conf`**: Configuración de logind


## Correctness Properties

*Una propiedad es una característica o comportamiento que debe mantenerse verdadero en todas las ejecuciones válidas de un sistema - esencialmente, una declaración formal sobre lo que el sistema debe hacer. Las propiedades sirven como puente entre las especificaciones legibles por humanos y las garantías de corrección verificables por máquinas.*

### Propiedades de Validación

**Property 1: Detección de entorno de instalación**
*Para cualquier* entorno de ejecución, la función de validación debe detectar correctamente si se está ejecutando desde el instalador de Arch Linux verificando la existencia de archivos y variables específicas del entorno live.
**Validates: Requirements 1.1**

**Property 2: Detección de conectividad de red**
*Para cualquier* estado de red del sistema, la función de validación debe detectar correctamente si hay conectividad activa y retornar el código de salida apropiado (0 para éxito, 1 para fallo).
**Validates: Requirements 1.2, 1.9**

**Property 3: Validación de disco**
*Para cualquier* dispositivo de bloque, la función de validación debe verificar correctamente si existe y tiene al menos 16GB de capacidad, retornando el código de salida apropiado.
**Validates: Requirements 1.3, 1.8**

**Property 4: Detección de particiones existentes**
*Para cualquier* dispositivo de bloque, la función de validación debe detectar correctamente si el disco tiene particiones existentes usando lsblk o parted, y solicitar confirmación del usuario antes de continuar.
**Validates: Requirements 1.4, 1.5, 1.6, 1.7**

### Propiedades de Particionamiento

**Property 5: Generación de comandos de particionamiento completos**
*Para cualquier* dispositivo de bloque válido, la función de particionamiento debe generar la secuencia completa de comandos parted para crear: tabla GPT, partición ESP de 512MB, partición root de 8GB, partición swap de 2GB, y partición home con el espacio restante.
**Validates: Requirements 2.1, 2.2, 2.3, 2.4, 2.5**

**Property 6: Cálculo correcto del espacio restante**
*Para cualquier* disco con tamaño >= 16GB, el tamaño de la partición home debe ser igual al tamaño total del disco menos (512MB + 8GB + 2GB), garantizando que se usa todo el espacio disponible.
**Validates: Requirements 2.5**

**Property 7: Generación de comandos de formateo completos**
*Para cualquier* dispositivo de bloque particionado, la función de formateo debe generar los comandos correctos: mkfs.fat para ESP, mkfs.ext4 para root y home, y mkswap para swap.
**Validates: Requirements 2.6, 2.7, 2.8, 2.9**

### Propiedades de Montaje

**Property 8: Secuencia de montaje correcta**
*Para cualquier* conjunto de particiones formateadas, la función de montaje debe generar la secuencia correcta de comandos: montar root en /mnt, crear /mnt/boot, montar ESP en /mnt/boot, crear /mnt/home, montar home en /mnt/home, y activar swap.
**Validates: Requirements 3.1, 3.2, 3.3, 3.4, 3.5, 3.6**

### Propiedades de Instalación Base

**Property 9: Comando pacstrap correcto**
*Para cualquier* sistema montado, la función de instalación base debe generar el comando pacstrap con exactamente los paquetes: base, linux, linux-firmware.
**Validates: Requirements 4.1**

**Property 10: Generación de fstab con UUIDs**
*Para cualquier* sistema instalado, la función debe generar el comando genfstab con la opción -U para usar UUIDs en lugar de nombres de dispositivo.
**Validates: Requirements 4.2**

**Property 11: Comando chroot correcto**
*Para cualquier* sistema con fstab generado, la función debe generar el comando arch-chroot apuntando a /mnt.
**Validates: Requirements 4.3**

### Propiedades de GRUB

**Property 12: Instalación de GRUB con UEFI**
*Para cualquier* sistema en chroot, la función de instalación de GRUB debe generar los comandos para instalar grub y efibootmgr, seguido de grub-install con las opciones --target=x86_64-efi y --efi-directory=/boot.
**Validates: Requirements 5.1, 5.2**

**Property 13: Configuración de GRUB silencioso completa**
*Para cualquier* archivo /etc/default/grub generado, debe contener todas las configuraciones para arranque silencioso: GRUB_TIMEOUT=0, GRUB_CMDLINE_LINUX_DEFAULT con los parámetros quiet, loglevel=3, rd.systemd.show_status=false, rd.udev.log_level=3, y GRUB_DISABLE_SUBMENU=y.
**Validates: Requirements 5.3, 5.4, 5.5**

**Property 14: Generación de configuración de GRUB**
*Para cualquier* configuración de GRUB modificada, la función debe generar el comando grub-mkconfig con salida a /boot/grub/grub.cfg.
**Validates: Requirements 5.6**

### Propiedades de Plymouth

**Property 15: Instalación de paquetes Plymouth**
*Para cualquier* sistema en chroot, la función debe generar el comando pacman para instalar plymouth y plymouth-theme-spinner.
**Validates: Requirements 6.1**

**Property 16: Estructura de tema Plymouth válida**
*Para cualquier* nombre de tema proporcionado, la función debe crear un directorio en /usr/share/plymouth/themes/ con archivos .plymouth y .script que sigan el formato correcto de Plymouth.
**Validates: Requirements 6.2**

**Property 17: Escalado de imagen a resolución fija**
*Para cualquier* imagen PNG válida con dimensiones diferentes a 1280x720, la función debe generar el comando de ImageMagick (convert o magick) para escalar la imagen exactamente a 1280x720 píxeles.
**Validates: Requirements 6.3, 11.3**

**Property 18: Configuración completa de Plymouth en initramfs**
*Para cualquier* sistema con Plymouth instalado, la función debe: agregar el hook plymouth a /etc/mkinitcpio.conf, generar el comando mkinitcpio -P, ejecutar plymouth-set-default-theme, y agregar "splash" a GRUB_CMDLINE_LINUX_DEFAULT.
**Validates: Requirements 6.4, 6.5, 6.6, 6.7**

### Propiedades de Drivers

**Property 19: Instalación completa de drivers gráficos**
*Para cualquier* sistema en chroot, la función debe generar el comando pacman para instalar todos los drivers: xf86-video-amdgpu, xf86-video-intel, nvidia-open, y mesa.
**Validates: Requirements 7.1, 7.2, 7.3, 7.4**

**Property 20: Instalación completa de PipeWire**
*Para cualquier* sistema en chroot, la función debe generar el comando pacman para instalar todos los componentes de PipeWire: pipewire, pipewire-alsa, pipewire-pulse, pipewire-jack, sof-firmware.
**Validates: Requirements 8.1**

**Property 21: Habilitación de servicios de PipeWire**
*Para cualquier* usuario del sistema, la función debe generar los comandos systemctl para habilitar los servicios de PipeWire en el contexto del usuario.
**Validates: Requirements 8.2, 8.3**

### Propiedades de Entorno Gráfico

**Property 22: Instalación de OpenBox, X y xterm**
*Para cualquier* sistema en chroot, la función debe generar el comando pacman para instalar xorg-server, xorg-xinit, openbox, xterm, xdg-desktop-portal, xdg-desktop-portal-gtk, y gtk3.
**Validates: Requirements 9.1, 9.2, 9.3, 9.4**

**Property 23: Creación de usuario del sistema**
*Para cualquier* nombre de usuario válido, la función debe generar el comando useradd con las opciones apropiadas para crear un usuario estándar.
**Validates: Requirements 9.5**

**Property 24: Configuración de autologin**
*Para cualquier* nombre de usuario, la función debe crear el archivo /etc/systemd/system/getty@tty1.service.d/autologin.conf con la configuración correcta de ExecStart para autologin.
**Validates: Requirements 9.6**

**Property 25: Configuración de autostart de X**
*Para cualquier* usuario, la función debe crear .xinitrc con "exec openbox-session" y modificar .bash_profile para ejecutar startx automáticamente si no está en X.
**Validates: Requirements 9.7, 9.8**

**Property 26: Configuración de xterm con apagado automático**
*Para cualquier* usuario, la función debe crear el archivo .config/openbox/autostart que ejecute xterm, y configurar xterm para que al cerrarse ejecute el comando de apagado del sistema.
**Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**

### Propiedades de Ocultación de Mensajes

**Property 27: Configuración completa de ocultación de mensajes**
*Para cualquier* usuario del sistema, la función debe: crear .hushlogin, vaciar /etc/motd, configurar ShowStatus=no en /etc/systemd/system.conf, y configurar NAutoVTs=0 en /etc/systemd/logind.conf.
**Validates: Requirements 10.1, 10.2, 10.3, 10.4**

### Propiedades de Personalización

**Property 28: Validación de formato PNG**
*Para cualquier* archivo proporcionado, la función debe detectar correctamente si es un PNG válido usando el comando file o verificando la firma del archivo.
**Validates: Requirements 11.1**

**Property 29: Copia de imagen al tema Plymouth**
*Para cualquier* ruta de imagen válida y nombre de tema, la función debe generar el comando cp correcto para copiar la imagen al directorio /usr/share/plymouth/themes/${theme_name}/.
**Validates: Requirements 11.2**

**Property 30: Instalación de cursor personalizado**
*Para cualquier* archivo de cursor y usuario, la función debe copiar el cursor a /usr/share/icons/default/ y crear el archivo index.theme con la configuración correcta.
**Validates: Requirements 11.4, 11.5**

### Propiedades de Red y Zona Horaria

**Property 31: Configuración de NetworkManager**
*Para cualquier* sistema en chroot, la función debe generar los comandos para instalar networkmanager y habilitar NetworkManager.service.
**Validates: Requirements 12.1, 12.2**

**Property 32: Configuración de zona horaria**
*Para cualquier* zona horaria válida (formato Region/City), la función debe generar el comando timedatectl set-timezone correcto y el comando hwclock --systohc.
**Validates: Requirements 12.3, 12.4**

### Propiedades de Finalización

**Property 33: Secuencia de desmontaje correcta**
*Para cualquier* sistema instalado, la función de limpieza debe generar la secuencia correcta: salir de chroot, desmontar /mnt/boot, desmontar /mnt/home, desmontar /mnt, y ejecutar swapoff.
**Validates: Requirements 14.1, 14.2, 14.3**

**Property 34: Mensajes de finalización**
*Para cualquier* instalación completada, la función debe mostrar un mensaje de éxito y un mensaje indicando que el usuario puede reiniciar el sistema.
**Validates: Requirements 14.4, 14.5**

## Error Handling

### Estrategia General de Manejo de Errores

Cada función del script debe:
1. Verificar precondiciones antes de ejecutar operaciones
2. Retornar códigos de salida apropiados (0 = éxito, 1 = error)
3. Imprimir mensajes de error descriptivos a stderr
4. Permitir que el script principal decida si continuar o abortar

### Errores Críticos (Abortan la Instalación)

Los siguientes errores deben detener la ejecución inmediatamente:

1. **Validación de entorno fallida**: No se está ejecutando en el instalador de Arch
2. **Sin conexión de red**: No se puede descargar paquetes
3. **Disco inválido**: /dev/sda no existe o tiene menos de 16GB
4. **Fallo en particionamiento**: No se pueden crear las particiones
5. **Fallo en formateo**: No se pueden formatear las particiones
6. **Fallo en montaje**: No se pueden montar las particiones
7. **Fallo en pacstrap**: No se puede instalar el sistema base
8. **Fallo en instalación de GRUB**: El sistema no será arrancable

### Errores No Críticos (Advertencias)

Los siguientes errores pueden generar advertencias pero no detienen la instalación:

1. **Imagen Plymouth no proporcionada**: Se usa una imagen predeterminada
2. **Cursor personalizado no proporcionado**: Se usa el cursor predeterminado
3. **Fallo en escalado de imagen**: Se usa la imagen sin escalar
4. **Fallo en instalación de drivers específicos**: Se continúa con otros drivers

### Implementación de Manejo de Errores

```bash
# Patrón general para funciones
function_name() {
    # Verificar precondiciones
    if ! check_precondition; then
        echo "ERROR: Precondition failed" >&2
        return 1
    fi
    
    # Ejecutar operación
    if ! execute_operation; then
        echo "ERROR: Operation failed" >&2
        return 1
    fi
    
    return 0
}

# En el script principal
if ! function_name; then
    echo "FATAL: Critical error occurred" >&2
    exit 1
fi
```

### Logging

El script debe mantener un log de todas las operaciones:

```bash
LOG_FILE="/var/log/arch-kiosk-install.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] ERROR: $*" | tee -a "$LOG_FILE" >&2
}
```

## Testing Strategy

### Enfoque Dual de Pruebas

Este proyecto utiliza un enfoque dual de pruebas para garantizar la corrección del script:

1. **Pruebas Unitarias con BATS**: Validan funciones individuales y casos específicos
2. **Pruebas Basadas en Propiedades**: Verifican propiedades universales a través de múltiples entradas

Ambos tipos de pruebas son complementarios y necesarios para una cobertura completa.

### Pruebas Unitarias con BATS

Las pruebas unitarias se ejecutarán en WSL Ubuntu usando BATS (Bash Automated Testing System). Cada módulo tendrá su propio archivo de pruebas.

**Configuración de BATS en WSL Ubuntu:**

```bash
# Instalar BATS
sudo apt-get update
sudo apt-get install bats

# Ejecutar pruebas
bats tests/test_validation.bats
bats tests/*.bats  # Ejecutar todas las pruebas
```

**Estrategia de Mocking:**

Para probar funciones sin modificar el sistema real, se usarán mocks:

```bash
# Ejemplo de mock para comandos del sistema
parted() {
    echo "Mock: parted $*" >> /tmp/commands.log
    return 0
}
export -f parted

# Ejemplo de mock para verificar archivos
cat() {
    if [[ "$1" == "/etc/arch-release" ]]; then
        echo "Arch Linux"
        return 0
    fi
    command cat "$@"
}
export -f cat
```

**Estructura de Pruebas Unitarias:**

Cada archivo de prueba BATS debe:
- Probar una función o módulo específico
- Usar mocks para comandos del sistema
- Verificar salidas y códigos de retorno
- Probar casos de éxito y error
- Incluir casos edge (discos pequeños, archivos inválidos, etc.)

**Ejemplo de Prueba BATS:**

```bash
#!/usr/bin/env bats

# tests/test_validation.bats

setup() {
    source lib/validation.sh
}

@test "check_disk: disco válido de 20GB retorna 0" {
    # Mock de lsblk
    lsblk() {
        echo "20G"
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 0 ]
}

@test "check_disk: disco de 10GB retorna 1" {
    lsblk() {
        echo "10G"
    }
    export -f lsblk
    
    run check_disk "/dev/sda"
    [ "$status" -eq 1 ]
}
```

### Pruebas Basadas en Propiedades

Las pruebas basadas en propiedades verifican que las propiedades de corrección se mantienen para múltiples entradas generadas aleatoriamente.

**Configuración:**
- Mínimo 100 iteraciones por prueba de propiedad
- Cada prueba debe referenciar su propiedad del documento de diseño
- Formato de tag: **Feature: arch-kiosk-installer, Property {número}: {texto de la propiedad}**

**Implementación con BATS:**

Aunque BATS no tiene soporte nativo para property-based testing, podemos simular el comportamiento:

```bash
#!/usr/bin/env bats

# Feature: arch-kiosk-installer, Property 5: Cálculo correcto del espacio restante
@test "Property 5: espacio restante calculado correctamente para múltiples tamaños de disco" {
    source lib/partitioning.sh
    
    # Probar con 100 tamaños de disco diferentes
    for i in {1..100}; do
        # Generar tamaño aleatorio entre 16GB y 1TB
        disk_size=$((16 + RANDOM % 1000))
        
        # Calcular espacio esperado para home
        expected_home=$((disk_size - 512/1024 - 8 - 2))
        
        # Ejecutar función y verificar
        result=$(calculate_home_size "$disk_size")
        
        [ "$result" -eq "$expected_home" ]
    done
}
```

### Cobertura de Pruebas

**Pruebas Unitarias deben cubrir:**
- Validación de entorno (archivos específicos de Arch)
- Validación de red (ping exitoso/fallido)
- Validación de disco (tamaños límite: 15GB, 16GB, 17GB)
- Generación de comandos de particionamiento
- Generación de comandos de formateo
- Generación de comandos de montaje
- Generación de archivos de configuración (GRUB, Plymouth, systemd)
- Creación de usuario y configuración de autologin
- Manejo de errores en cada función

**Pruebas de Propiedades deben cubrir:**
- Cálculo de espacio de particiones para múltiples tamaños de disco
- Generación correcta de comandos para diferentes dispositivos (/dev/sda, /dev/vda, /dev/nvme0n1)
- Configuración correcta para diferentes nombres de usuario
- Configuración correcta para diferentes zonas horarias
- Escalado de imágenes de múltiples dimensiones a 1280x720
- Validación de PNG para archivos válidos e inválidos

### Ejecución de Pruebas

```bash
# Ejecutar todas las pruebas unitarias
bats tests/*.bats

# Ejecutar pruebas de un módulo específico
bats tests/test_validation.bats

# Ejecutar con salida detallada
bats --tap tests/*.bats

# Ejecutar y generar reporte
bats tests/*.bats | tee test-results.log
```

### Criterios de Éxito

Las pruebas se consideran exitosas si:
- Todas las pruebas unitarias pasan (100% de éxito)
- Todas las pruebas de propiedades pasan con 100 iteraciones
- No hay errores de sintaxis en el script
- Los archivos de configuración generados son válidos
- Los comandos generados son sintácticamente correctos
