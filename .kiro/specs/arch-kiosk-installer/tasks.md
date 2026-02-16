# Plan de Implementación: Instalador Automatizado de Arch Linux Modo Kiosko

## Overview

Este plan desglosa la implementación del instalador automatizado de Arch Linux en tareas incrementales. Cada tarea construye sobre las anteriores, comenzando con la estructura del proyecto y los módulos de validación, continuando con el particionamiento y la instalación, y finalizando con la configuración del entorno gráfico y las pruebas.

El enfoque es modular: cada módulo se implementa con sus funciones, seguido de pruebas unitarias BATS opcionales para validar su comportamiento de forma aislada en WSL Ubuntu. Las pruebas son opcionales y están marcadas con `*` para permitir un desarrollo más rápido del MVP.

## Tasks

- [x] 1. Configurar estructura del proyecto y script principal
  - Crear la estructura de directorios (lib/, tests/, assets/)
  - Crear el script principal install-arch-kiosk.sh con el esqueleto básico
  - Configurar variables globales de configuración
  - Implementar función de logging (log, log_error)
  - Crear función main() que orquesta la ejecución secuencial
  - _Requirements: Todos los requisitos (estructura general)_

- [x] 2. Implementar módulo de validación
  - [x] 2.1 Crear lib/validation.sh con funciones de validación
    - Implementar validate_environment() para verificar entorno de Arch Linux
    - Implementar check_network() para verificar conectividad
    - Implementar check_disk() para validar disco y tamaño
    - Implementar check_disk_empty() para detectar particiones existentes y solicitar confirmación
    - Cada función debe retornar códigos de salida apropiados
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9_
  
  - [x]* 2.2 Escribir pruebas unitarias para validación
    - Crear tests/test_validation.bats
    - Probar validate_environment() con mocks de archivos de Arch
    - Probar check_network() con mocks de ping exitoso/fallido
    - Probar check_disk() con diferentes tamaños de disco (15GB, 16GB, 20GB, 1TB)
    - Probar check_disk_empty() con disco vacío y con particiones existentes
    - Probar confirmación del usuario (sí/no)
    - Probar manejo de errores y mensajes
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 1.7, 1.8, 1.9, 15.2_
  
  - [x]* 2.3 Escribir prueba de propiedad para validación de disco
    - **Property 3: Validación de disco**
    - **Validates: Requirements 1.3, 1.8**
    - Probar con 100 tamaños de disco aleatorios
    - Verificar que discos >= 16GB retornan 0 y discos < 16GB retornan 1
  
  - [x]* 2.4 Escribir prueba de propiedad para detección de particiones
    - **Property 4: Detección de particiones existentes**
    - **Validates: Requirements 1.4, 1.5, 1.6, 1.7**
    - Probar con discos vacíos y con diferentes números de particiones
    - Verificar que se detectan correctamente las particiones existentes

- [x] 3. Implementar módulo de particionamiento
  - [x] 3.1 Crear lib/partitioning.sh con funciones de particionamiento
    - Implementar partition_disk() para crear tabla GPT y 4 particiones
    - Implementar format_partitions() para formatear con FAT32, ext4 y swap
    - Implementar mount_partitions() para montar en /mnt
    - Implementar función auxiliar calculate_home_size() para calcular espacio restante
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 2.6, 2.7, 2.8, 2.9, 3.1, 3.2, 3.3, 3.4, 3.5, 3.6_
  
  - [x]* 3.2 Escribir pruebas unitarias para particionamiento
    - Crear tests/test_partitioning.bats
    - Mockear comandos parted, mkfs.fat, mkfs.ext4, mkswap, mount, swapon
    - Verificar que partition_disk() genera comandos correctos de parted
    - Verificar que format_partitions() genera comandos correctos de formateo
    - Verificar que mount_partitions() genera secuencia correcta de montaje
    - Probar con diferentes dispositivos (/dev/sda, /dev/vda)
    - _Requirements: 2.1-2.9, 3.1-3.6, 14.3_
  
  - [x]* 3.3 Escribir prueba de propiedad para cálculo de espacio
    - **Property 6: Cálculo correcto del espacio restante**
    - **Validates: Requirements 2.5**
    - Probar con 100 tamaños de disco aleatorios entre 16GB y 1TB
    - Verificar que home_size = disk_size - 512MB - 8GB - 2GB

- [x] 4. Checkpoint - Validar módulos básicos
  - Asegurarse de que todas las pruebas pasan, preguntar al usuario si surgen dudas.

- [x] 5. Implementar módulo de instalación base
  - [x] 5.1 Crear lib/base_install.sh con funciones de instalación
    - Implementar install_base_system() para ejecutar pacstrap
    - Implementar generate_fstab() para generar /etc/fstab
    - Implementar configure_chroot() para preparar entorno chroot
    - _Requirements: 4.1, 4.2, 4.3_
  
  - [x]* 5.2 Escribir pruebas unitarias para instalación base
    - Crear tests/test_base_install.bats
    - Mockear comandos pacstrap, genfstab, arch-chroot
    - Verificar que install_base_system() genera comando pacstrap con paquetes correctos
    - Verificar que generate_fstab() usa opción -U para UUIDs
    - Verificar que configure_chroot() genera comando arch-chroot correcto
    - _Requirements: 4.1, 4.2, 4.3, 14.4_
  
  - [x]* 5.3 Escribir prueba de propiedad para comando pacstrap
    - **Property 9: Comando pacstrap correcto**
    - **Validates: Requirements 4.1**
    - Verificar que el comando contiene exactamente: base, linux, linux-firmware

- [x] 6. Implementar módulo de bootloader
  - [x] 6.1 Crear lib/bootloader.sh con funciones de GRUB
    - Implementar install_grub() para instalar GRUB con UEFI
    - Implementar configure_grub_silent() para configuración silenciosa
    - Generar archivo /etc/default/grub con todas las opciones necesarias
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 5.5, 5.6_
  
  - [x]* 6.2 Escribir pruebas unitarias para bootloader
    - Crear tests/test_bootloader.bats
    - Mockear comandos pacman, grub-install, grub-mkconfig
    - Verificar que install_grub() genera comandos correctos
    - Verificar que configure_grub_silent() genera archivo /etc/default/grub correcto
    - Validar que el archivo contiene: GRUB_TIMEOUT=0, parámetros quiet, GRUB_DISABLE_SUBMENU=y
    - _Requirements: 5.1-5.6, 14.4_
  
  - [x]* 6.3 Escribir prueba de propiedad para configuración GRUB
    - **Property 13: Configuración de GRUB silencioso completa**
    - **Validates: Requirements 5.3, 5.4, 5.5**
    - Verificar que el archivo generado contiene todas las configuraciones necesarias

- [x] 7. Implementar módulo de Plymouth
  - [x] 7.1 Crear lib/plymouth.sh con funciones de Plymouth
    - Implementar install_plymouth() para instalar paquetes
    - Implementar create_custom_theme() para crear tema personalizado
    - Implementar configure_plymouth() para configurar tema e initramfs
    - Generar archivos .plymouth y .script del tema
    - _Requirements: 6.1, 6.2, 6.3, 6.4, 6.5, 6.6, 6.7_
  
  - [x]* 7.2 Escribir pruebas unitarias para Plymouth
    - Crear tests/test_plymouth.bats
    - Mockear comandos pacman, convert/magick, mkinitcpio, plymouth-set-default-theme
    - Verificar que install_plymouth() instala paquetes correctos
    - Verificar que create_custom_theme() crea estructura de directorios correcta
    - Verificar que configure_plymouth() modifica /etc/mkinitcpio.conf correctamente
    - Verificar que se agrega "splash" a GRUB_CMDLINE_LINUX_DEFAULT
    - _Requirements: 6.1-6.7, 14.4_
  
  - [x]* 7.3 Escribir prueba de propiedad para escalado de imagen
    - **Property 17: Escalado de imagen a resolución fija**
    - **Validates: Requirements 6.3, 11.3**
    - Probar con 100 dimensiones aleatorias de imagen
    - Verificar que se genera comando de escalado a 1280x720 para todas las dimensiones diferentes

- [x] 8. Checkpoint - Validar configuración de arranque
  - Asegurarse de que todas las pruebas pasan, preguntar al usuario si surgen dudas.

- [x] 9. Implementar módulo de drivers
  - [x] 9.1 Crear lib/drivers.sh con funciones de drivers
    - Implementar install_graphics_drivers() para instalar drivers AMD, Intel, NVIDIA, Mesa
    - Implementar install_audio_system() para instalar PipeWire completo
    - _Requirements: 7.1, 7.2, 7.3, 7.4, 8.1, 8.2, 8.3_
  
  - [x]* 9.2 Escribir pruebas unitarias para drivers
    - Crear tests/test_drivers.bats
    - Mockear comandos pacman y systemctl
    - Verificar que install_graphics_drivers() instala todos los drivers necesarios
    - Verificar que install_audio_system() instala todos los componentes de PipeWire
    - Verificar que se habilitan servicios de PipeWire
    - _Requirements: 7.1-7.4, 8.1-8.3, 14.4_
  
  - [x]* 9.3 Escribir prueba de propiedad para instalación de drivers
    - **Property 19: Instalación completa de drivers gráficos**
    - **Validates: Requirements 7.1, 7.2, 7.3, 7.4**
    - Verificar que el comando pacman contiene todos los paquetes de drivers

- [x] 10. Implementar módulo de entorno gráfico
  - [x] 10.1 Crear lib/gui.sh con funciones de OpenBox
    - Implementar install_openbox() para instalar X, OpenBox, xterm y componentes de diálogos del sistema
    - Implementar create_user() para crear usuario del sistema
    - Implementar configure_autologin() para configurar autologin en getty
    - Implementar configure_autostart_x() para crear .xinitrc y modificar .bash_profile
    - Implementar configure_xterm_autostart() para configurar xterm con apagado automático y OpenBox en modo kiosko
    - Crear rc.xml con configuración de modo kiosko (1 escritorio, sin cambio con rueda del mouse)
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6, 9.7, 9.8, 9.9, 9.10, 9.11, 13.1, 13.2, 13.3, 13.4, 13.5_
  
  - [x]* 10.2 Escribir pruebas unitarias para GUI
    - Crear tests/test_gui.bats
    - Mockear comandos pacman, useradd, mkdir
    - Verificar que install_openbox() instala paquetes correctos (incluyendo xterm, xdg-desktop-portal, xdg-desktop-portal-gtk, gtk3)
    - Verificar que create_user() genera comando useradd correcto
    - Verificar que configure_autologin() crea archivo de configuración correcto
    - Verificar que configure_autostart_x() crea .xinitrc y .bash_profile correctos
    - Verificar que configure_xterm_autostart() crea .config/openbox/autostart con xterm y comando de apagado
    - Probar con diferentes nombres de usuario
    - _Requirements: 9.1-9.8, 13.1-13.5, 15.4_
  
  - [x]* 10.3 Escribir prueba de propiedad para configuración de usuario
    - **Property 22: Creación de usuario del sistema**
    - **Validates: Requirements 9.5**
    - Probar con 100 nombres de usuario aleatorios válidos
    - Verificar que se genera comando useradd correcto para cada uno
  
  - [x]* 10.4 Escribir prueba de propiedad para xterm con apagado
    - **Property 26: Configuración de xterm con apagado automático**
    - **Validates: Requirements 13.1, 13.2, 13.3, 13.4, 13.5**
    - Verificar que el archivo autostart contiene el comando para ejecutar xterm
    - Verificar que al cerrar xterm se ejecuta el comando de apagado

- [x] 11. Implementar módulo de personalización
  - [x] 11.1 Crear lib/customization.sh con funciones de personalización
    - Implementar hide_system_messages() para ocultar todos los mensajes
    - Implementar install_custom_cursor() para instalar cursor personalizado
    - Implementar apply_plymouth_image() para validar y copiar imagen PNG
    - _Requirements: 10.1, 10.2, 10.3, 10.4, 11.1, 11.2, 11.3, 11.4, 11.5_
  
  - [x]* 11.2 Escribir pruebas unitarias para personalización
    - Crear tests/test_customization.bats
    - Mockear comandos touch, echo, file, cp, convert
    - Verificar que hide_system_messages() crea .hushlogin y modifica archivos systemd
    - Verificar que install_custom_cursor() copia cursor y crea index.theme
    - Verificar que apply_plymouth_image() valida PNG correctamente
    - Probar validación con archivos PNG válidos e inválidos
    - _Requirements: 10.1-10.4, 11.1-11.5, 15.4_
  
  - [x]* 11.3 Escribir prueba de propiedad para validación de PNG
    - **Property 28: Validación de formato PNG**
    - **Validates: Requirements 11.1**
    - Probar con 50 archivos PNG válidos y 50 archivos inválidos
    - Verificar que la función detecta correctamente el formato

- [x] 12. Implementar módulo de finalización
  - [x] 12.1 Crear lib/finalization.sh con funciones de finalización
    - Implementar configure_network() para instalar y habilitar NetworkManager
    - Instalar y habilitar OpenSSH para acceso remoto
    - Configurar zona horaria del sistema
    - Sincronizar reloj del hardware con el reloj del sistema
    - Implementar cleanup_and_finish() para desmontar y mostrar mensajes
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 14.1, 14.2, 14.3, 14.4, 14.5_
  
  - [x]* 12.2 Escribir pruebas unitarias para finalización
    - Crear tests/test_finalization.bats
    - Mockear comandos pacman, systemctl, timedatectl, hwclock, umount, swapoff
    - Verificar que configure_network() instala NetworkManager y OpenSSH
    - Verificar que configure_network() habilita servicios NetworkManager y sshd
    - Verificar que configure_network() configura zona horaria y sincroniza reloj
    - Verificar que cleanup_and_finish() genera secuencia correcta de desmontaje
    - Verificar que se muestran mensajes de éxito y reinicio
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5, 12.6, 14.1, 14.2, 14.3, 14.4, 14.5, 15.4_
  
  - [x]* 12.3 Escribir prueba de propiedad para configuración de zona horaria
    - **Property 32: Configuración de zona horaria**
    - **Validates: Requirements 12.5, 12.6**
    - Probar con 50 zonas horarias válidas aleatorias
    - Verificar que se genera comando timedatectl correcto para cada una

- [x] 13. Integrar todos los módulos en el script principal
  - [x] 13.1 Completar función main() en install-arch-kiosk.sh
    - Importar todos los módulos con source
    - Llamar funciones en orden secuencial
    - Implementar manejo de errores entre pasos
    - Agregar logging en cada paso
    - Verificar que errores críticos abortan la ejecución
    - _Requirements: Todos los requisitos (integración)_
  
  - [x]* 13.2 Escribir pruebas de integración
    - Crear tests/test_integration.bats
    - Mockear todos los comandos del sistema
    - Ejecutar el script completo en modo dry-run
    - Verificar que se ejecutan todas las funciones en orden correcto
    - Verificar que el manejo de errores funciona correctamente
    - _Requirements: Todos los requisitos_

- [x] 14. Checkpoint final - Ejecutar suite completa de pruebas
  - Asegurarse de que todas las pruebas pasan, preguntar al usuario si surgen dudas.

- [x] 15. Completar suite de pruebas BATS restantes
  - [x]* 15.1 Crear archivos de pruebas faltantes
    - Crear tests/test_partitioning.bats
    - Crear tests/test_base_install.bats
    - Crear tests/test_bootloader.bats
    - Crear tests/test_plymouth.bats
    - Crear tests/test_drivers.bats
    - Crear tests/test_gui.bats
    - Crear tests/test_customization.bats
    - Crear tests/test_finalization.bats
    - Crear tests/test_integration.bats
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5_
  
  - [x]* 15.2 Implementar pruebas para cada módulo
    - Seguir los patrones establecidos en test_validation.bats
    - Usar mocks para comandos del sistema
    - Verificar generación correcta de comandos y archivos de configuración
    - Incluir pruebas de propiedades donde corresponda
    - _Requirements: 15.1, 15.2, 15.3, 15.4, 15.5_

- [x] 16. Crear documentación y assets
  - [x] 16.1 Crear README.md con instrucciones de uso
    - Documentar requisitos previos (VirtualBox, disco de 16GB, conexión de red)
    - Documentar cómo proporcionar imagen PNG y cursor personalizado vía SCP
    - Documentar cómo ejecutar el script en el instalador de Arch
    - Documentar cómo ejecutar las pruebas en WSL Ubuntu
    - Documentar acceso SSH y configuración de modo kiosko
    - Documentar comportamiento de xterm y apagado automático
    - Incluir ejemplos de uso y troubleshooting actualizado
    - _Requirements: Todos los requisitos (documentación)_
  
  - [x] 16.2 Crear assets de ejemplo
    - Crear assets/plymouth-image.png de ejemplo (1280x720)
    - Crear assets/cursor/ con cursor de ejemplo
    - Documentar cómo reemplazar estos assets con personalizados
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_

- [x] 17. Checkpoint final - Validación completa
  - Asegurarse de que todas las pruebas pasan, preguntar al usuario si surgen dudas.

## Notes

- Las tareas marcadas con `*` son opcionales y pueden omitirse para un MVP más rápido
- Cada tarea referencia requisitos específicos para trazabilidad
- Los checkpoints aseguran validación incremental
- Las pruebas de propiedades validan corrección universal con mínimo 100 iteraciones
- Las pruebas unitarias validan ejemplos específicos y casos edge
- Todas las pruebas se ejecutan en WSL Ubuntu usando BATS
- El script debe ser ejecutable en el instalador de Arch Linux real
- La implementación core está completa; las pruebas son opcionales para validación adicional
- El sistema incluye acceso SSH remoto habilitado por defecto para administración post-instalación
