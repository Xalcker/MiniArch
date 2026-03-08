# Changelog

Todos los cambios notables en este proyecto serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/es-ES/1.0.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/lang/es/).

## [No Publicado]

### Agregado
- Archivo `.env.example` con todas las opciones de configuración disponibles
- Soporte para configuración mediante archivo `.env`
- Archivo `SECURITY.md` con guía completa de seguridad
- Archivo `CHANGELOG.md` para documentar cambios
- Sección de seguridad mejorada en README.md
- Documentación sobre uso de archivo .env en README.md
- `.gitignore` mejorado con categorías organizadas y más patrones

### Cambiado
- Script principal ahora carga configuración desde `.env` si existe
- Variables de configuración ahora usan valores por defecto con `${VAR:-default}`
- Funciones de logging movidas al inicio del script para soportar carga de .env
- README.md reorganizado con nueva sección de configuración de .env
- Estructura del .gitignore mejorada con comentarios y organización por categorías

### Mejorado
- Seguridad: archivo .env no se versiona en Git
- Flexibilidad: configuración más fácil sin modificar el script
- Documentación: guías más completas de seguridad y configuración
- Mantenibilidad: código mejor organizado y documentado

## [1.0.0] - Versión Inicial

### Agregado
- Instalación automatizada de Arch Linux en modo kiosko
- Soporte para UEFI con GRUB
- Configuración de Plymouth para arranque gráfico (opcional)
- Instalación de drivers gráficos (AMD, Intel, NVIDIA, Mesa)
- Sistema de audio PipeWire
- OpenBox como gestor de ventanas minimalista
- Autologin automático al usuario kiosko
- xterm con apagado automático al cerrar
- Configuración SSH habilitada
- Suite completa de pruebas con BATS
- Documentación completa en README.md
- Estructura modular con bibliotecas separadas:
  - validation.sh: Validación de entorno
  - partitioning.sh: Particionamiento de disco
  - base_install.sh: Instalación base
  - bootloader.sh: Configuración de GRUB
  - plymouth.sh: Configuración de Plymouth
  - drivers.sh: Instalación de drivers
  - gui.sh: Configuración de OpenBox
  - customization.sh: Personalización visual
  - finalization.sh: Finalización y limpieza
- Soporte para assets personalizados (imagen Plymouth, cursor)
- Esquema de particionamiento:
  - ESP: 512MB (FAT32)
  - Root: 8GB (ext4)
  - Swap: 2GB
  - Home: Espacio restante (ext4)

### Características
- Arranque silencioso con GRUB
- Modo kiosko con 1 escritorio
- Sin cambio de escritorio con rueda del mouse
- Mensajes del sistema ocultos
- Configuración optimizada para kioscos
- Validación de disco con confirmación de usuario
- Logging completo de instalación
- Manejo de errores robusto

[No Publicado]: https://github.com/tu-usuario/arch-kiosk-installer/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/tu-usuario/arch-kiosk-installer/releases/tag/v1.0.0
