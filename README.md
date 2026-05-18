# MiniArch

Instaladores automatizados para crear kioskos de Arch Linux orientados a YARG
(Yet Another Rhythm Game).

El repositorio tiene dos caminos principales:

- `install-arch-kiosk.sh`: instalador modular original. Crea un kiosko con
  OpenBox/X11, Plymouth, autologin y `setup-yarg.sh` como paso posterior.
- `install-arch-cage.sh`: instalador Cage/YARG. Reutiliza la base modular del
  instalador original y agrega dentro del mismo script el post-install de YARG:
  descarga del juego, Samba, carpeta de canciones, permisos HID y optimizaciones.

En corto:

```text
install-arch-cage.sh = install-arch-kiosk.sh + setup-yarg.sh,
adaptado a Cage sobre Wayland/XWayland.
```

## Estado Actual

`install-arch-kiosk.sh` sigue siendo el instalador completo para OpenBox/X11.

`install-arch-cage.sh` es ahora un orquestador propio que importa modulos
compartidos desde `lib/` para validacion, particionado, fstab, GRUB, audio,
limpieza y ocultacion de mensajes. La capa especifica de Cage/YARG vive solo en
ese script.

## Caracteristicas

### Compartidas

- Instalacion automatizada desde el live ISO de Arch Linux.
- Validacion de entorno, red y disco.
- Confirmacion antes de destruir particiones existentes.
- Particionado GPT/UEFI:
  - ESP FAT32 en `/boot`.
  - Root ext4 en `/`.
  - Swap.
  - Home ext4 en `/home`.
- GRUB UEFI con parametros de arranque silencioso.
- PipeWire, codecs multimedia y soporte Bluetooth desde `lib/drivers.sh`.
- Limpieza automatica de montajes y swap si la instalacion falla.

### OpenBox Kiosk

`install-arch-kiosk.sh` instala:

- OpenBox/X11.
- Plymouth y tema personalizado opcional.
- Autologin del usuario kiosko.
- Autostart OpenBox que prioriza YARG y usa xterm como fallback.
- Copia de `setup-yarg.sh` al home del usuario para ejecutarlo despues.
- Cursor personalizado opcional.
- SSH opcional segun configuracion.

### Cage YARG

`install-arch-cage.sh` instala y configura:

- Cage como compositor de kiosko.
- Wayland y XWayland para ejecutar YARG.
- Mesa, Vulkan Intel/AMD y soporte opcional NVIDIA.
- YARG en `/opt/YARG`.
- Wrapper `/usr/local/bin/run-yarg.sh`.
- Servicio `cage-kiosk.service`.
- Carpeta `/opt/YARG/Songs`.
- Share Samba `YARG-Songs`.
- Usuario Samba para el usuario kiosko.
- Regla udev para `hidraw`.
- Dependencias multilib necesarias para YARG.
- Limites de tiempo real y memoria para audio/rendimiento.
- `vm.swappiness=10`.
- `cpupower` con governor `performance`.
- Updater `/usr/local/bin/update-yarg`.

## Requisitos

- Arch Linux ISO actual.
- Maquina fisica o VM con UEFI habilitado.
- Disco de al menos 16 GB.
- 2 GB de RAM o mas.
- Conexion a internet durante la instalacion.

En VM, habilita EFI/UEFI. En VirtualBox esta opcion esta en:

```text
Sistema -> Placa base -> Habilitar EFI
```

## Instalacion

Arranca desde el ISO de Arch Linux y verifica red:

```bash
ping -c 3 archlinux.org
```

Clona el repositorio:

```bash
pacman -Sy git
git clone https://github.com/tu-usuario/arch-kiosk-installer.git
cd arch-kiosk-installer
```

Opcionalmente crea un archivo `.env` en la raiz del repo. Los scripts lo cargan
automaticamente si existe.

Ejemplo para `install-arch-cage.sh`:

```bash
DISK_DEVICE="/dev/sda"
KIOSK_USER="kiosk"
KIOSK_PASSWORD="cambia-esto"
ROOT_PASSWORD="cambia-root"
KIOSK_HOSTNAME="minikiosk"
TIMEZONE="America/Phoenix"
ENABLE_SSH="false"
INSTALL_NVIDIA="false"
YARG_URL="https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip"
```

Ejemplo para `install-arch-kiosk.sh`:

```bash
DISK_DEVICE="/dev/sda"
KIOSK_USER="kiosk"
KIOSK_PASSWORD="cambia-esto"
TIMEZONE="America/Mexico_City"
ENABLE_SSH="true"
ALLOW_INSECURE_DEFAULT_PASSWORD="false"
PLYMOUTH_IMAGE_PATH="./assets/plymouth-image.png"
CURSOR_PATH="./assets/cursor/"
```

Ejecuta el instalador que quieras usar.

OpenBox/X11:

```bash
chmod +x install-arch-kiosk.sh
./install-arch-kiosk.sh
```

Cage/YARG:

```bash
chmod +x install-arch-cage.sh
./install-arch-cage.sh
```

Advertencia: ambos instaladores destruyen el contenido del disco configurado en
`DISK_DEVICE`. Si el disco contiene particiones, se mostrara una advertencia y
se pedira confirmacion antes de continuar.

## Flujo De `install-arch-cage.sh`

El instalador Cage ejecuta, en orden:

1. Carga `.env` si existe.
2. Pregunta si debe instalar NVIDIA si `INSTALL_NVIDIA` no fue definido.
3. Valida entorno live de Arch, red y disco.
4. Confirma destruccion de datos si el disco tiene particiones.
5. Crea GPT/UEFI con ESP, root, swap y home.
6. Monta particiones en `/mnt`, `/mnt/boot` y `/mnt/home`.
7. Instala sistema base, Cage, Wayland, XWayland, Vulkan, Samba y cpupower.
8. Genera `/etc/fstab`.
9. Configura hostname, locale, root, GRUB UEFI y parametros NVIDIA si aplica.
10. Instala audio/codificadores/Bluetooth desde `lib/drivers.sh`.
11. Crea el usuario kiosko con grupos `wheel,audio,video,render,input`.
12. Habilita multilib y dependencias 32-bit de YARG.
13. Configura permisos HID.
14. Descarga e instala YARG en `/opt/YARG`.
15. Configura Samba y el share `YARG-Songs`.
16. Aplica optimizaciones de rendimiento.
17. Crea `update-yarg`, `run-yarg.sh` y `cage-kiosk.service`.
18. Configura red, target grafico y limpieza visual.
19. Desmonta particiones y desactiva swap.

## Uso Despues De Instalar Cage/YARG

Despues de reiniciar, el sistema arranca al target grafico y systemd inicia:

```text
cage-kiosk.service
```

Ese servicio toma `tty1`, prepara `XDG_RUNTIME_DIR` y ejecuta:

```text
/usr/local/bin/run-yarg.sh
```

El wrapper:

- Habilita ajustes para VM si detecta `hypervisor`.
- Exporta variables Wayland/Cage.
- Arranca PipeWire, PipeWire Pulse y WirePlumber si no estan corriendo.
- Busca un binario ejecutable `YARG*` en `/opt/YARG`.
- Lanza YARG con Cage.
- Usa `foot` como fallback si no encuentra YARG.

Para subir canciones desde otra maquina, usa el share Samba:

```text
\\<hostname>\YARG-Songs
```

La ruta local compartida es:

```text
/opt/YARG/Songs
```

Para actualizar YARG en el sistema instalado:

```bash
sudo update-yarg
```

## Uso Despues De Instalar OpenBox

`install-arch-kiosk.sh` deja el sistema arrancando a OpenBox/X11. El flujo
original copia `setup-yarg.sh` al home del usuario kiosko para instalar YARG
despues del primer arranque.

En el sistema instalado:

```bash
./setup-yarg.sh
```

Ese script instala YARG en el home del usuario, crea `Songs`, configura Samba y
aplica optimizaciones de rendimiento.

## Configuracion

Variables comunes:

- `DISK_DEVICE`: disco destino. Por defecto `/dev/sda`.
- `KIOSK_USER`: usuario kiosko.
- `KIOSK_PASSWORD`: password del usuario kiosko.
- `TIMEZONE`: zona horaria.
- `ENABLE_SSH`: habilita OpenSSH cuando el flujo usa `configure_network`.

Variables especificas de Cage:

- `ROOT_PASSWORD`: password de root. Por defecto `root`.
- `KIOSK_HOSTNAME`: hostname. Por defecto `minikiosk`.
- `INSTALL_NVIDIA`: `true` o `false`; si queda vacio, el script pregunta.
- `YARG_URL`: URL del zip de YARG.

Variables especificas de OpenBox/Plymouth:

- `PLYMOUTH_THEME_NAME`.
- `PLYMOUTH_IMAGE_PATH`.
- `CURSOR_PATH`.
- `ALLOW_INSECURE_DEFAULT_PASSWORD`.

Recomendacion: define passwords reales en `.env` antes de ejecutar cualquier
instalador. No uses los valores de ejemplo en produccion.

## Estructura Del Proyecto

```text
MiniArch/
├── install-arch-kiosk.sh      # Orquestador OpenBox/X11 original
├── install-arch-cage.sh       # Orquestador Cage/YARG integrado
├── setup-yarg.sh              # Instalacion/post-install YARG standalone
├── lib/
│   ├── validation.sh          # Validacion de entorno, red y disco
│   ├── partitioning.sh        # GPT/UEFI, formateo, montaje y swap
│   ├── base_install.sh        # Pacstrap base y fstab
│   ├── bootloader.sh          # GRUB UEFI y arranque silencioso
│   ├── plymouth.sh            # Plymouth para el flujo OpenBox
│   ├── drivers.sh             # Drivers, PipeWire, codecs y Bluetooth
│   ├── gui.sh                 # OpenBox/X11 y autostart
│   ├── customization.sh       # Mensajes, cursor, assets y scripts extra
│   └── finalization.sh        # Red, SSH opcional, limpieza y desmontaje
├── assets/
│   ├── README.md
│   ├── plymouth-image.png.example
│   └── cursor/
└── tests/
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

Nota: la suite BATS cubre principalmente los modulos compartidos y el flujo
OpenBox original. `install-arch-cage.sh` reutiliza esos modulos, pero sus
funciones especificas de Cage/YARG todavia no tienen una suite dedicada.

## Desarrollo Y Pruebas

Instala BATS en un entorno de desarrollo Linux/WSL:

```bash
sudo apt-get update
sudo apt-get install bats
```

Ejecuta toda la suite:

```bash
bats tests/*.bats
```

Pruebas puntuales:

```bash
bats tests/test_validation.bats
bats tests/test_partitioning.bats
bats tests/test_bootloader.bats
bats tests/test_drivers.bats
```

Validacion rapida de sintaxis:

```bash
bash -n install-arch-kiosk.sh
bash -n install-arch-cage.sh
```

## Troubleshooting

### No se detecta Arch Linux

Debes ejecutar los instaladores desde el live ISO de Arch Linux. El entorno debe
tener `/etc/arch-release` y el comando `pacstrap`.

### No hay red

Verifica conectividad:

```bash
ip link
ping -c 3 archlinux.org
```

Levanta la interfaz si hace falta:

```bash
ip link set <interfaz> up
dhcpcd
```

### El disco no existe o es muy pequeno

Revisa discos disponibles:

```bash
lsblk
```

Configura `DISK_DEVICE` en `.env`, por ejemplo:

```bash
DISK_DEVICE="/dev/vda"
```

Para NVMe, el modulo de particionado genera rutas como `/dev/nvme0n1p1`.

### GRUB falla

El esquema actual espera UEFI. Revisa que la VM o equipo tenga UEFI habilitado
y que `/mnt/boot` este montado.

### Cage no arranca YARG

Entra por tty/SSH y revisa:

```bash
systemctl status cage-kiosk.service
journalctl -u cage-kiosk.service -b
ls -la /opt/YARG
```

Si el binario no existe, el wrapper abre `foot` como fallback. Puedes reinstalar
o actualizar YARG con:

```bash
sudo update-yarg
```

### Samba no aparece en la red

Verifica servicios:

```bash
sudo systemctl status smb nmb
testparm
```

Revisa el share:

```bash
grep -A10 "\[YARG-Songs\]" /etc/samba/smb.conf
```

La ruta debe existir:

```bash
ls -la /opt/YARG/Songs
```

### Audio o instrumentos no funcionan

Revisa PipeWire y permisos HID:

```bash
pgrep -a pipewire
pgrep -a wireplumber
ls -l /etc/udev/rules.d/69-hid.rules
```

Reconecta el dispositivo despues de instalar para que udev aplique la regla.

## Seguridad

- No versiones `.env`; puede contener passwords.
- Cambia `KIOSK_PASSWORD` y `ROOT_PASSWORD` antes de usar una maquina real.
- `install-arch-kiosk.sh` puede habilitar SSH segun `ENABLE_SSH`.
- `install-arch-cage.sh` usa `ENABLE_SSH=false` por defecto, pero hereda la
  funcion de red que puede instalar OpenSSH si lo activas.
- El usuario kiosko tiene sudo sin password para tareas de mantenimiento.
  Endurece sudoers si el equipo queda expuesto.
- Samba permite acceso guest al share de canciones. Es comodo para un kiosko
  local, pero no lo expongas a redes no confiables.

Consulta [SECURITY.md](SECURITY.md) para mas detalles.

## Clonado A Discos Mas Grandes

Si clonas una instalacion a un disco mas grande, revisa [CLONING.md](CLONING.md)
para expandir la particion `/home` y aprovechar el espacio restante.

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md), ejecuta las pruebas disponibles y abre
un pull request con cambios acotados.

## Licencia

Este proyecto esta bajo licencia MIT. Consulta [LICENSE](LICENSE).

## Creditos

- Arch Linux como base del sistema.
- Plymouth para el arranque visual del flujo OpenBox.
- OpenBox para el instalador kiosko original.
- Cage para el kiosko Wayland/XWayland de YARG.
- BATS para pruebas automatizadas.
