# Documento de Requisitos

## Introducción

Este documento especifica los requisitos para un script de instalación automatizada de Arch Linux que configura un sistema tipo kiosko con arranque directo a X, interfaz gráfica minimalista (OpenBox), y personalización visual completa del proceso de arranque y apagado mediante Plymouth. El sistema está diseñado para ejecutarse en una máquina virtual VirtualBox con un disco de al menos 16GB.

## Glosario

- **Sistema**: El script de instalación automatizada de Arch Linux
- **Instalador**: El entorno live de Arch Linux desde donde se ejecuta el script
- **Disco_Objetivo**: El disco /dev/sda donde se instalará el sistema
- **Partición_ESP**: Partición EFI System Partition en /dev/sda1
- **Partición_Root**: Partición raíz del sistema en /dev/sda2
- **Partición_Swap**: Partición de intercambio en /dev/sda3
- **Partición_Home**: Partición de datos de usuario en /dev/sda4
- **Plymouth**: Sistema de arranque gráfico que muestra imágenes durante boot/shutdown
- **OpenBox**: Gestor de ventanas minimalista para el modo kiosko
- **WM**: Window Manager (Gestor de Ventanas)
- **GRUB**: Gestor de arranque del sistema
- **PipeWire**: Sistema de audio moderno para Linux
- **Hushlogin**: Mecanismo para ocultar mensajes de inicio de sesión
- **MOTD**: Message Of The Day, mensaje mostrado al iniciar sesión
- **SCP**: Secure Copy Protocol para transferencia de archivos
- **WSL**: Windows Subsystem for Linux, entorno Linux en Windows
- **BATS**: Bash Automated Testing System, framework de pruebas para scripts Bash
- **Ubuntu**: Distribución Linux usada en WSL para ejecutar las pruebas

## Requisitos

### Requisito 1: Validación del Entorno de Ejecución

**Historia de Usuario:** Como administrador del sistema, quiero que el script valide el entorno de ejecución antes de comenzar la instalación, para evitar errores y pérdida de datos.

#### Criterios de Aceptación

1. WHEN el script se ejecuta, THE Sistema SHALL verificar que se está ejecutando desde el instalador de Arch Linux
2. WHEN el script se ejecuta, THE Sistema SHALL verificar que existe conexión de red activa
3. WHEN el script se ejecuta, THE Sistema SHALL verificar que el Disco_Objetivo (/dev/sda) existe y tiene al menos 16GB de capacidad
4. IF el Disco_Objetivo no existe o tiene menos de 16GB, THEN THE Sistema SHALL mostrar un mensaje de error y terminar la ejecución
5. IF no hay conexión de red, THEN THE Sistema SHALL mostrar un mensaje de error y terminar la ejecución

### Requisito 2: Particionamiento Automatizado del Disco

**Historia de Usuario:** Como administrador del sistema, quiero que el script particione automáticamente el disco según un esquema predefinido, para tener una estructura consistente y optimizada.

#### Criterios de Aceptación

1. WHEN el particionamiento inicia, THE Sistema SHALL crear una tabla de particiones GPT en el Disco_Objetivo
2. WHEN se crea la tabla GPT, THE Sistema SHALL crear la Partición_ESP con 512MB de tamaño y tipo EFI System
3. WHEN se crea la Partición_ESP, THE Sistema SHALL crear la Partición_Root con 8GB de tamaño y tipo Linux filesystem
4. WHEN se crea la Partición_Root, THE Sistema SHALL crear la Partición_Swap con 2GB de tamaño y tipo Linux swap
5. WHEN se crea la Partición_Swap, THE Sistema SHALL crear la Partición_Home utilizando todo el espacio restante del disco y tipo Linux filesystem
6. WHEN todas las particiones están creadas, THE Sistema SHALL formatear la Partición_ESP con sistema de archivos FAT32
7. WHEN la Partición_ESP está formateada, THE Sistema SHALL formatear la Partición_Root con sistema de archivos ext4
8. WHEN la Partición_Root está formateada, THE Sistema SHALL formatear la Partición_Home con sistema de archivos ext4
9. WHEN la Partición_Home está formateada, THE Sistema SHALL inicializar la Partición_Swap como área de intercambio

### Requisito 3: Montaje del Sistema de Archivos

**Historia de Usuario:** Como administrador del sistema, quiero que el script monte correctamente todas las particiones, para poder instalar el sistema base.

#### Criterios de Aceptación

1. WHEN las particiones están formateadas, THE Sistema SHALL montar la Partición_Root en /mnt
2. WHEN la Partición_Root está montada, THE Sistema SHALL crear el directorio /mnt/boot
3. WHEN el directorio /mnt/boot existe, THE Sistema SHALL montar la Partición_ESP en /mnt/boot
4. WHEN la Partición_ESP está montada, THE Sistema SHALL crear el directorio /mnt/home
5. WHEN el directorio /mnt/home existe, THE Sistema SHALL montar la Partición_Home en /mnt/home
6. WHEN todas las particiones están montadas, THE Sistema SHALL activar la Partición_Swap

### Requisito 4: Instalación del Sistema Base

**Historia de Usuario:** Como administrador del sistema, quiero que el script instale el sistema base de Arch Linux con todos los paquetes necesarios, para tener un sistema funcional.

#### Criterios de Aceptación

1. WHEN las particiones están montadas, THE Sistema SHALL instalar el sistema base usando pacstrap con los paquetes: base, linux, linux-firmware
2. WHEN el sistema base está instalado, THE Sistema SHALL generar el archivo /etc/fstab usando genfstab con UUIDs
3. WHEN el fstab está generado, THE Sistema SHALL hacer chroot a /mnt para continuar la configuración

### Requisito 5: Configuración del Gestor de Arranque GRUB

**Historia de Usuario:** Como administrador del sistema, quiero que GRUB esté configurado para arrancar sin mostrar mensajes ni menús, para lograr un arranque silencioso y directo.

#### Criterios de Aceptación

1. WHEN se configura el sistema, THE Sistema SHALL instalar los paquetes grub y efibootmgr
2. WHEN GRUB está instalado, THE Sistema SHALL instalar GRUB en la Partición_ESP con soporte UEFI
3. WHEN GRUB está instalado en la ESP, THE Sistema SHALL configurar GRUB con timeout=0 para arranque inmediato
4. WHEN se configura el timeout, THE Sistema SHALL agregar los parámetros quiet, loglevel=3, rd.systemd.show_status=false, rd.udev.log_level=3 al kernel
5. WHEN los parámetros del kernel están configurados, THE Sistema SHALL deshabilitar el submenu de GRUB
6. WHEN la configuración está completa, THE Sistema SHALL generar el archivo de configuración de GRUB

### Requisito 6: Instalación y Configuración de Plymouth

**Historia de Usuario:** Como administrador del sistema, quiero que Plymouth muestre una imagen personalizada durante el arranque y apagado, para ocultar todos los mensajes del sistema y proporcionar una experiencia visual limpia.

#### Criterios de Aceptación

1. WHEN se instala Plymouth, THE Sistema SHALL instalar los paquetes plymouth y plymouth-theme-spinner
2. WHEN Plymouth está instalado, THE Sistema SHALL crear un tema personalizado de Plymouth que soporte imágenes PNG
3. WHEN el tema está creado, THE Sistema SHALL configurar el tema para escalar la imagen proporcionada por el usuario a 1280x720 píxeles
4. WHEN el tema está configurado, THE Sistema SHALL agregar el hook de Plymouth a mkinitcpio
5. WHEN el hook está agregado, THE Sistema SHALL regenerar el initramfs con mkinitcpio
6. WHEN el initramfs está regenerado, THE Sistema SHALL configurar Plymouth como el tema activo
7. WHEN Plymouth está activo, THE Sistema SHALL agregar splash al final de la línea de comandos del kernel en GRUB

### Requisito 7: Instalación de Controladores Gráficos

**Historia de Usuario:** Como administrador del sistema, quiero que el script instale controladores para AMD, Intel y NVIDIA, para soportar diferentes configuraciones de hardware.

#### Criterios de Aceptación

1. WHEN se instalan controladores gráficos, THE Sistema SHALL instalar los paquetes xf86-video-amdgpu para soporte AMD
2. WHEN se instalan controladores AMD, THE Sistema SHALL instalar los paquetes xf86-video-intel para soporte Intel
3. WHEN se instalan controladores Intel, THE Sistema SHALL instalar los paquetes nvidia-open para soporte NVIDIA
4. WHEN se instalan controladores NVIDIA, THE Sistema SHALL instalar el paquete mesa para soporte OpenGL genérico

### Requisito 8: Configuración del Sistema de Audio

**Historia de Usuario:** Como administrador del sistema, quiero que PipeWire esté instalado y configurado, para tener soporte de audio funcional.

#### Criterios de Aceptación

1. WHEN se configura el audio, THE Sistema SHALL instalar los paquetes pipewire, pipewire-alsa, pipewire-pulse, pipewire-jack, sof-firmware
2. WHEN PipeWire está instalado, THE Sistema SHALL habilitar el servicio de PipeWire para el usuario del sistema
3. WHEN el servicio está habilitado, THE Sistema SHALL configurar PipeWire como el servidor de audio predeterminado

### Requisito 9: Instalación y Configuración de OpenBox

**Historia de Usuario:** Como administrador del sistema, quiero que OpenBox se inicie automáticamente al arrancar el sistema en modo kiosko, para proporcionar un entorno gráfico minimalista con un solo escritorio y sin distracciones.

#### Criterios de Aceptación

1. WHEN se instala el entorno gráfico, THE Sistema SHALL instalar los paquetes xorg-server, xorg-xinit, openbox
2. WHEN se instalan los paquetes base, THE Sistema SHALL instalar xdg-desktop-portal para el framework de diálogos del sistema
3. WHEN se instala xdg-desktop-portal, THE Sistema SHALL instalar xdg-desktop-portal-gtk para el selector de archivos GTK
4. WHEN se instalan los portales, THE Sistema SHALL instalar gtk3 como dependencia para renderizar los elementos del selector
5. WHEN OpenBox está instalado, THE Sistema SHALL crear un usuario del sistema con permisos estándar
6. WHEN el usuario está creado, THE Sistema SHALL configurar el inicio de sesión automático para ese usuario
7. WHEN el inicio automático está configurado, THE Sistema SHALL crear un archivo .xinitrc que ejecute OpenBox
8. WHEN .xinitrc está creado, THE Sistema SHALL configurar el sistema para ejecutar startx automáticamente al iniciar sesión
9. WHEN OpenBox está configurado, THE Sistema SHALL crear un archivo rc.xml que configure OpenBox para modo kiosko con un solo escritorio
10. WHEN rc.xml está creado, THE Sistema SHALL deshabilitar el cambio de escritorio con la rueda del mouse
11. WHEN se deshabilita la rueda del mouse, THE Sistema SHALL deshabilitar los atajos de teclado para cambio de escritorio

### Requisito 10: Ocultación de Mensajes del Sistema

**Historia de Usuario:** Como administrador del sistema, quiero que todos los mensajes de texto del sistema estén ocultos, para proporcionar una experiencia visual limpia sin distracciones técnicas.

#### Criterios de Aceptación

1. WHEN se configura la ocultación de mensajes, THE Sistema SHALL crear el archivo .hushlogin en el directorio home del usuario
2. WHEN hushlogin está configurado, THE Sistema SHALL deshabilitar el MOTD eliminando o vaciando /etc/motd
3. WHEN el MOTD está deshabilitado, THE Sistema SHALL configurar systemd para ocultar mensajes de servicios con ShowStatus=no
4. WHEN systemd está configurado, THE Sistema SHALL deshabilitar mensajes de getty configurando NAutoVTs=0

### Requisito 11: Personalización Visual

**Historia de Usuario:** Como administrador del sistema, quiero proporcionar una imagen PNG para Plymouth y un cursor personalizado, para adaptar la apariencia del sistema a mis necesidades.

#### Criterios de Aceptación

1. WHEN el usuario proporciona una imagen PNG vía SCP, THE Sistema SHALL validar que el archivo es un PNG válido
2. WHEN la imagen es válida, THE Sistema SHALL copiar la imagen a la ubicación del tema de Plymouth
3. WHEN la imagen está copiada, THE Sistema SHALL escalar la imagen a 1280x720 píxeles si tiene dimensiones diferentes
4. WHEN el usuario proporciona un archivo de cursor (SVG u otro formato), THE Sistema SHALL instalar el cursor en el directorio de temas del sistema
5. WHEN el cursor está instalado, THE Sistema SHALL configurar el cursor como predeterminado para el usuario del sistema

### Requisito 12: Configuración de Red, SSH y Zona Horaria

**Historia de Usuario:** Como administrador del sistema, quiero que el sistema tenga configuración básica de red, acceso SSH remoto y zona horaria, para que funcione correctamente y pueda administrarlo remotamente después del reinicio.

#### Criterios de Aceptación

1. WHEN se configura el sistema, THE Sistema SHALL instalar el paquete networkmanager
2. WHEN NetworkManager está instalado, THE Sistema SHALL habilitar el servicio NetworkManager para inicio automático
3. WHEN NetworkManager está habilitado, THE Sistema SHALL instalar el paquete openssh
4. WHEN OpenSSH está instalado, THE Sistema SHALL habilitar el servicio sshd para inicio automático
5. WHEN SSH está habilitado, THE Sistema SHALL configurar la zona horaria del sistema
6. WHEN la zona horaria está configurada, THE Sistema SHALL sincronizar el reloj del hardware con el reloj del sistema

### Requisito 13: Validación de X con xterm

**Historia de Usuario:** Como administrador del sistema, quiero que el sistema inicie xterm automáticamente después del arranque de X, para validar que el servidor X está funcionando correctamente, y que el sistema se apague al cerrar xterm.

#### Criterios de Aceptación

1. WHEN OpenBox se inicia, THE Sistema SHALL ejecutar xterm automáticamente
2. WHEN xterm está en ejecución, THE Sistema SHALL permitir al usuario interactuar con la terminal
3. WHEN el usuario cierra xterm, THE Sistema SHALL detectar el cierre de xterm
4. WHEN xterm se cierra, THE Sistema SHALL ejecutar el comando de apagado del sistema
5. WHEN se ejecuta el apagado, THE Sistema SHALL apagar la máquina de forma limpia

### Requisito 14: Finalización y Limpieza

**Historia de Usuario:** Como administrador del sistema, quiero que el script finalice correctamente y prepare el sistema para el primer arranque, para poder reiniciar y usar el sistema instalado.

#### Criterios de Aceptación

1. WHEN todas las configuraciones están completas, THE Sistema SHALL salir del entorno chroot
2. WHEN se sale del chroot, THE Sistema SHALL desmontar todas las particiones montadas en /mnt
3. WHEN las particiones están desmontadas, THE Sistema SHALL desactivar la Partición_Swap
4. WHEN todo está desmontado, THE Sistema SHALL mostrar un mensaje indicando que la instalación fue exitosa
5. WHEN se muestra el mensaje de éxito, THE Sistema SHALL indicar al usuario que puede reiniciar el sistema

### Requisito 15: Suite de Pruebas Automatizadas

**Historia de Usuario:** Como desarrollador del script, quiero tener pruebas automatizadas usando BATS en WSL Ubuntu, para validar que todas las funciones del script funcionan correctamente antes de ejecutarlo en un entorno real.

#### Criterios de Aceptación

1. WHEN se ejecutan las pruebas, THE Sistema SHALL proporcionar un conjunto de pruebas BATS que se ejecuten en WSL Ubuntu
2. WHEN se prueban las validaciones, THE Sistema SHALL incluir pruebas para la validación del entorno de ejecución
3. WHEN se prueban las funciones de particionamiento, THE Sistema SHALL incluir pruebas que validen la lógica de particionamiento sin modificar discos reales
4. WHEN se prueban las funciones de configuración, THE Sistema SHALL incluir pruebas para validar la generación de archivos de configuración
5. WHEN se ejecutan todas las pruebas, THE Sistema SHALL reportar el resultado de cada prueba con mensajes claros de éxito o fallo
