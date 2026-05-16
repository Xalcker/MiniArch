# Instalador Automatizado de Arch Linux - Modo Kiosko

Script de instalación automatizada de Arch Linux que configura un sistema tipo kiosko con arranque directo a X, interfaz gráfica minimalista (OpenBox), y personalización visual completa del proceso de arranque mediante Plymouth.

## Características

- ✅ Instalación completamente automatizada de Arch Linux
- 🎨 Arranque silencioso con Plymouth (Logo de YARG por defecto)
- 🖥️ Entorno gráfico minimalista con OpenBox en modo kiosko
- 🔒 Autologin automático al usuario kiosko
- 🛡️ Usuario con privilegios sudoer para mantenimiento fácil
- 🎯 Configuración optimizada para modo kiosko (1 escritorio, sin cambio con rueda del mouse)
- 🎸 Soporte nativo para YARG (Yet Another Rhythm Game)
- 🔌 SSH habilitado para acceso remoto
- 🪟 Aplicación del kiosko (YARG/xterm) con apagado automático al cerrar
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

### Paso 4: Configurar Variables de Entorno (Opcional)

El instalador incluye un archivo `.env.example` con todas las opciones de configuración disponibles. Puedes personalizarlo según tus necesidades:

```bash
# Copiar el archivo de ejemplo
cp .env.example .env

# Editar con tu editor preferido
nano .env
```

Configuraciones importantes que puedes personalizar:

- `DISK_DEVICE`: Dispositivo de disco a usar (por defecto: /dev/sda; soporta nombres tipo `/dev/nvme0n1` y `/dev/mmcblk0`)
- `KIOSK_USER`: Nombre del usuario del sistema (por defecto: kiosk)
- `KIOSK_PASSWORD`: Contraseña del usuario (obligatoria; cambia el valor `change-me` de `.env.example`)
- `TIMEZONE`: Zona horaria del sistema (por defecto: America/Mexico_City)
- `PLYMOUTH_IMAGE_PATH`: Ruta a la imagen de Plymouth
- `CURSOR_PATH`: Ruta al cursor personalizado
- `ENABLE_SSH`: Instala y habilita OpenSSH (`true` por defecto)
- `ALLOW_INSECURE_DEFAULT_PASSWORD`: Permite contraseñas de ejemplo solo para laboratorios/VMs descartables

Debes crear un archivo `.env` y definir una contraseña segura en `KIOSK_PASSWORD`. El instalador rechazará contraseñas vacías o de ejemplo salvo que actives explícitamente `ALLOW_INSECURE_DEFAULT_PASSWORD=true` para pruebas controladas.

### Paso 5: Personalizar Assets (Opcional)

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
- Si la imagen no existe, el instalador omitirá la personalización de Plymouth; si existe pero no es PNG válido, se detendrá antes de modificar el disco.

**Requisitos del cursor:**
- Formato: Cualquier formato soportado por X11 (SVG, PNG, etc.)
- Ubicación: `assets/cursor/`

### Paso 6: Ejecutar el Script

```bash
# Dar permisos de ejecución
chmod +x install-arch-kiosk.sh

# Ejecutar el script
./install-arch-kiosk.sh
```

⚠️ **ADVERTENCIA IMPORTANTE**: El script verificará si el disco `/dev/sda` contiene particiones existentes. Si las encuentra, mostrará una advertencia y solicitará confirmación explícita antes de continuar. **TODOS LOS DATOS EN EL DISCO SERÁN DESTRUIDOS** durante la instalación.

Para confirmar la destrucción de datos, debes escribir exactamente `sí` cuando se te solicite.

El script realizará automáticamente:
1. Validación del entorno y requisitos
2. Verificación de disco vacío y confirmación del usuario
3. Particionamiento y formateo del disco
4. Instalación del sistema base (incluye `sudo`, `wget`, `curl`, `unzip`, `nano`, `git`, `wpa_supplicant`)
4. Configuración de GRUB silencioso
5. Instalación y configuración de Plymouth (con logo de YARG)
6. Instalación de drivers gráficos y audio
7. Configuración de OpenBox en modo kiosko y autologin
8. Configuración de autostart (prioriza YARG, fallback a xterm)
9. Copia de scripts adicionales (`setup-yarg.sh`)
10. Personalización visual y del cursor
11. Configuración de red y SSH
12. Limpieza y finalización

### Paso 7: Reiniciar

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

- **Inicio automático**: El sistema arranca directamente a X con OpenBox.
- **Modo Kiosko**: OpenBox está configurado con 1 solo escritorio y sin cambio de escritorio con la rueda del mouse.
- **Optimización de Audio**: Configurado con PipeWire (ALSA/Pulse/JACK) y prioridad de tiempo real para evitar stuttering.
- **Soporte de Hardware**: Soporte nativo para instrumentos USB/MIDI y dispositivos Bluetooth (habilitado por defecto).
- **Intercambio de Archivos (SMB)**: Los scripts de configuración habilitan carpetas compartidas para subir juegos/canciones remotamente.
- **Protección contra Fallos**: Si la aplicación principal falla (crash), el sistema se reinicia automáticamente. Si se cierra normalmente, el sistema se apaga.

### Kiosko YARG

Al iniciar por primera vez, tendrás el script de configuración en tu carpeta personal (`~/`). Al finalizar se auto-eliminará para dejar el sistema limpio.

#### Instalación de YARG (`setup-yarg.sh`)
*   Descarga e instala la última versión de **YARG (Yet Another Rhythm Game)**.
*   Crea la carpeta `~/YARG/Songs` y la comparte en red (`\\nombre\YARG-Songs`).
*   Optimiza la CPU en modo *performance* y desactiva el ahorro de energía.

### Pasos para el despliegue:

1. Inicia el sistema y ejecuta el script de instalación:
   ```bash
   ./setup-yarg.sh
   ```
2. Sigue las instrucciones en pantalla.
3. El script realizará la instalación, optimizará el sistema y **se auto-eliminará**.
4. El sistema se reiniciará automáticamente en 5 segundos y entrará en "Modo Producción".

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
├── .env.example                # Plantilla de configuración
├── README.md                   # Documentación principal
├── SECURITY.md                 # Guía de seguridad
├── CONTRIBUTING.md             # Guía de contribución
├── CHANGELOG.md                # Registro de cambios
├── LICENSE                     # Licencia MIT
├── .gitignore                  # Archivos ignorados por Git
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
│   ├── cursor/                # Cursor personalizado
│   └── README.md              # Documentación de assets
└── tests/                      # Suite de pruebas BATS
    ├── test_validation.bats
    ├── test_partitioning.bats
    ├── test_base_install.bats
    ├── test_bootloader.bats
    ├── test_plymouth.bats
    ├── test_drivers.bats
    ├── test_gui.bats
    ├── test_customization.bats
    ├── test_finalization.bats
    └── test_integration.bats
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

### El script se detiene pidiendo confirmación

**Causa**: El disco `/dev/sda` contiene particiones existentes.

**Solución**:
- El script muestra esta advertencia para prevenir pérdida accidental de datos
- Revisa cuidadosamente las particiones mostradas
- Si estás seguro de que quieres destruir todos los datos, escribe exactamente `sí` cuando se te solicite
- Si no quieres continuar, escribe `no` o presiona Ctrl+C para cancelar
- **IMPORTANTE**: Asegúrate de estar usando el disco correcto antes de confirmar

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

### Usar Archivo de Configuración .env

El instalador soporta configuración mediante variables de entorno usando un archivo `.env`. Esto facilita la personalización sin modificar el script principal:

```bash
# 1. Copiar el archivo de ejemplo
cp .env.example .env

# 2. Editar según tus necesidades
nano .env

# 3. Ejecutar el instalador (cargará automáticamente .env)
./install-arch-kiosk.sh
```

El archivo `.env` tiene prioridad sobre los valores por defecto del script. Si no existe, se usan los valores predeterminados.

### Cambiar Zona Horaria

Opción 1: Usando .env (recomendado)
```bash
# En .env
TIMEZONE="America/New_York"
```

Opción 2: Editando el script
```bash
# En install-arch-kiosk.sh
TIMEZONE="America/Mexico_City"  # Cambiar a tu zona horaria
```

### Cambiar Usuario y Contraseña

Opción 1: Usando .env (recomendado)
```bash
# En .env
KIOSK_USER="miusuario"
KIOSK_PASSWORD="mipassword123"
```

Opción 2: Editando el script
```bash
# En install-arch-kiosk.sh
KIOSK_USER="kiosk"              # Cambiar nombre de usuario
KIOSK_PASSWORD="contraseña-segura"  # Definir una contraseña segura
```

Evita valores de ejemplo como `kiosk123` o `change-me`; el instalador los rechazará salvo que actives `ALLOW_INSECURE_DEFAULT_PASSWORD=true` para pruebas controladas.

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

Las contribuciones son bienvenidas. Para contribuir al proyecto:

1. Lee la [Guía de Contribución](CONTRIBUTING.md) para conocer el proceso completo
2. Fork el repositorio
3. Crea una rama para tu feature (`git checkout -b feature/nueva-funcionalidad`)
4. Ejecuta las pruebas (`bats tests/*.bats`)
5. Commit tus cambios siguiendo las convenciones de commits
6. Push a la rama (`git push origin feature/nueva-funcionalidad`)
7. Crea un Pull Request

Para más detalles sobre estándares de código, pruebas y proceso de PR, consulta [CONTRIBUTING.md](CONTRIBUTING.md).

## Seguridad

### Consideraciones Importantes

- El archivo `.env` puede contener información sensible (contraseñas). NUNCA lo versiones en Git.
- **Cuenta Root**: Por defecto, la cuenta `root` no tiene contraseña configurada (está bloqueada para login directo). Esto es una medida de seguridad.
- **Administración**: Usa `sudo` desde la cuenta `kiosk` para realizar tareas administrativas.
- Cambia la contraseña predeterminada (`kiosk123`) inmediatamente después de la instalación.
- El usuario `kiosk` tiene permisos de sudoer, pero considera restringirlos en entornos de producción altamente sensibles.
- SSH está habilitado por defecto. Considera:
  - Cambiar el puerto SSH predeterminado.
  - Usar autenticación por clave pública en lugar de contraseña.
  - Configurar fail2ban para prevenir ataques de fuerza bruta.

Para una guía completa de seguridad, consulta [SECURITY.md](SECURITY.md).

### Reporte de Vulnerabilidades

Si encuentras una vulnerabilidad de seguridad, por favor NO abras un issue público. En su lugar, consulta las instrucciones en [SECURITY.md](SECURITY.md) para reportarla de forma responsable.

## Licencia

Este proyecto está bajo la licencia MIT. Ver archivo [LICENSE](LICENSE) para más detalles.

## Soporte

Para reportar problemas o solicitar funcionalidades, abre un issue en el repositorio de GitHub.

## Créditos

- Desarrollado para instalaciones automatizadas de Arch Linux
- Usa Plymouth para arranque gráfico
- OpenBox como gestor de ventanas minimalista
- BATS para pruebas automatizadas
