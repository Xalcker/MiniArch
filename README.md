# MiniArch

Instaladores automatizados para crear kioskos de Arch Linux orientados a YARG
(Yet Another Rhythm Game).

Repositorio oficial: [Xalcker/MiniArch](https://github.com/Xalcker/MiniArch).

## Caminos De Instalacion

MiniArch mantiene dos caminos:

- `install-arch-cage.sh`: camino recomendado para YARG. Instala Arch Linux,
  Cage, Wayland/XWayland, YARG, audio, Samba y la carpeta de canciones en un
  solo flujo.
- `install-arch-kiosk.sh` + `setup-yarg.sh`: camino original OpenBox/X11. Sirve
  como fallback si algun hardware o version de YARG se comporta mejor fuera de
  Cage.

En corto:

```text
Recomendado: install-arch-cage.sh
Fallback:    install-arch-kiosk.sh y luego setup-yarg.sh
```

Cage es ideal para un equipo dedicado: ejecuta una sola aplicacion fullscreen y
reduce la superficie de escritorio. El instalador tambien habilita XWayland para
compatibilidad con builds de YARG que lo necesiten.

## Estado Actual

`install-arch-cage.sh` es un orquestador modular. Reutiliza los modulos
compartidos de `lib/` y mueve lo especifico a:

- `lib/cage.sh`: sistema base Cage, usuario, servicio systemd y wrapper
  `/usr/local/bin/run-yarg.sh`.
- `lib/yarg.sh`: descarga de YARG stable/nightly, settings iniciales, Samba,
  rendimiento y updater.

`install-arch-kiosk.sh` sigue usando el flujo original OpenBox/X11 y copia
`setup-yarg.sh` para instalar YARG despues del primer arranque.

## Caracteristicas

### Compartidas

- Instalacion automatizada desde el live ISO de Arch Linux.
- Validacion de entorno, red, disco y passwords.
- Confirmacion antes de destruir particiones existentes.
- Particionado GPT/UEFI:
  - ESP FAT32 en `/boot`.
  - Root ext4 en `/`.
  - Swap.
  - Home ext4 en `/home`.
- GRUB UEFI con arranque silencioso.
- Plymouth opcional.
- PipeWire, WirePlumber, PipeWire Pulse, PipeWire ALSA, codecs y Bluetooth.
- `/etc/asound.conf` apuntando ALSA default a PipeWire.
- Limpieza automatica de montajes y swap si la instalacion falla.

### Cage/YARG

`install-arch-cage.sh` instala y configura:

- Cage como compositor de kiosko.
- Wayland y XWayland.
- Mesa, Vulkan Intel/AMD y NVIDIA opcional.
- DBus de sesion para el wrapper de YARG.
- PipeWire iniciado en orden: `pipewire`, `wireplumber`, `pipewire-pulse`.
- YARG en `/opt/YARG`.
- Perfil persistente en `YARG_PERSISTENT_DATA_DIR`.
- Carpeta de canciones fija en `YARG_SONGS_DIR`.
- Share Samba `YARG-Songs`.
- Usuario Samba para el usuario kiosko.
- Reglas HID para instrumentos `hidraw`.
- Dependencias multilib de YARG.
- Limites de tiempo real, `vm.swappiness=10` y `cpupower` en performance.
- Updater `/usr/local/bin/update-yarg`.
- Servicio `cage-kiosk.service`.

### OpenBox/X11

`install-arch-kiosk.sh` instala:

- OpenBox/X11.
- Autologin del usuario kiosko.
- Autostart que prioriza YARG y usa xterm como fallback.
- Cursor personalizado opcional.
- Copia de `setup-yarg.sh` al home del usuario.
- SSH opcional.

## Requisitos

- Arch Linux ISO actual.
- Maquina fisica o VM con UEFI habilitado.
- Disco de al menos 16 GB.
- 2 GB de RAM o mas.
- Conexion a internet durante la instalacion.

En VM, habilita EFI/UEFI. En VirtualBox:

```text
Sistema -> Placa base -> Habilitar EFI
```

En Proxmox, SPICE puede servir para probar audio virtual. En hardware real,
PipeWire deberia usar la salida detectada por ALSA/WirePlumber.

## Instalacion

Arranca desde el ISO de Arch Linux y verifica red:

```bash
ping -c 3 archlinux.org
```

Clona el repositorio:

```bash
pacman -Sy git
git clone https://github.com/Xalcker/MiniArch.git
cd MiniArch
```

Copia el ejemplo de configuracion:

```bash
cp .env.example .env
nano .env
```

Para Cage/YARG, `.env` es obligatorio. Define al menos:

```bash
DISK_DEVICE=/dev/sda
KIOSK_USER=kiosk
KIOSK_PASSWORD=una-contrasena-real
ROOT_PASSWORD=otra-contrasena-real
KIOSK_HOSTNAME=minikiosk
TIMEZONE=America/Phoenix
ENABLE_SSH=false
INSTALL_NVIDIA=false
ALLOW_INSECURE_DEFAULT_PASSWORD=false
ENABLE_PLYMOUTH=true
YARG_RELEASE_CHANNEL=ask
YARG_SONGS_DIR=/opt/YARG/Songs
YARG_PERSISTENT_DATA_DIR=/home/${KIOSK_USER}/.config/yarg-kiosk
```

Ejecuta el camino recomendado:

```bash
chmod +x install-arch-cage.sh
./install-arch-cage.sh
```

Fallback OpenBox/X11:

```bash
chmod +x install-arch-kiosk.sh
./install-arch-kiosk.sh
```

Advertencia: ambos instaladores destruyen el disco configurado en
`DISK_DEVICE`. Si el disco contiene particiones, el script pedira confirmacion.

## Flujo De Cage/YARG

`install-arch-cage.sh` ejecuta, en orden:

1. Exige y carga `.env`.
2. Pregunta por NVIDIA si `INSTALL_NVIDIA` esta vacio.
3. Pregunta por canal de YARG si `YARG_RELEASE_CHANNEL=ask`.
4. Valida entorno live, passwords, assets opcionales, red y disco.
5. Resuelve el nightly mas reciente si se eligio `nightly`.
6. Particiona, formatea y monta el disco.
7. Instala Arch base, Cage, Wayland/XWayland, Samba, dbus y stack grafico.
8. Genera `fstab`.
9. Configura hostname, locale, root, GRUB, Plymouth y NVIDIA si aplica.
10. Instala audio, codecs y Bluetooth desde `lib/drivers.sh`.
11. Crea usuario kiosko y sudoers.
12. Habilita multilib y dependencias 32-bit de YARG.
13. Configura HID.
14. Descarga e instala YARG.
15. Crea `settings.json` con la carpeta fija de canciones.
16. Configura Samba.
17. Aplica optimizaciones de rendimiento.
18. Crea `update-yarg`, `run-yarg.sh` y `cage-kiosk.service`.
19. Configura red, target grafico y limpieza visual.
20. Desmonta particiones y desactiva swap.

## YARG Stable Y Nightly

`YARG_RELEASE_CHANNEL` acepta:

- `stable`: usa exactamente `YARG_URL`.
- `nightly`: consulta el ultimo release de
  `YARC-Official/YARG-BleedingEdge`.
- `ask`: pregunta durante la instalacion.

El prompt actual es:

```text
Canal de YARG: stable desde .env o nightly mas reciente? [stable/nightly] (stable):
```

El updater actual guarda el URL resuelto durante la instalacion. Si instalaste
nightly, `sudo update-yarg` reinstala ese build exacto por ahora. Esta en
`TODO.md` hacer que vuelva a consultar el latest nightly.

## Uso Despues De Instalar Cage/YARG

Despues de reiniciar, systemd inicia:

```text
cage-kiosk.service
```

El servicio ejecuta:

```text
/usr/local/bin/run-yarg.sh
```

El wrapper:

- Aplica ajustes de render software si detecta VM.
- Crea un DBus de sesion con `dbus-run-session` si no existe.
- Exporta variables Wayland/Cage.
- Arranca PipeWire, WirePlumber y PipeWire Pulse en orden.
- Espera unos segundos a que exista un sink Pulse/PipeWire; si no aparece,
  lanza YARG de todos modos y deja el aviso en journal.
- Busca un binario ejecutable `YARG*` en `/opt/YARG`.
- Lanza YARG con `-persistent-data-path`.
- Abre `foot` como fallback si no encuentra YARG.

El perfil fijo se crea en:

```text
/home/kiosk/.config/yarg-kiosk/settings.json
```

Con contenido equivalente a:

```json
{
  "SongFolders": [
    "/opt/YARG/Songs"
  ]
}
```

Esto evita depender del selector de archivos para la operacion normal del
kiosko. El boton Browse puede funcionar en builds nightly recientes, pero el
flujo recomendado sigue siendo subir canciones por Samba y escanear desde YARG.

Share Samba:

```text
\\<hostname>\YARG-Songs
```

Con hostname por defecto:

```text
\\minikiosk\YARG-Songs
```

Ruta local:

```text
/opt/YARG/Songs
```

Actualizar YARG:

```bash
sudo update-yarg
```

## Uso Despues De Instalar OpenBox

El camino OpenBox/X11 deja `setup-yarg.sh` en el home del usuario. En el sistema
instalado:

```bash
./setup-yarg.sh
```

Ese script instala YARG en el home del usuario, crea `Songs`, configura Samba y
aplica optimizaciones de rendimiento. No usa `lib/cage.sh` ni `lib/yarg.sh`.

## Configuracion

Variables comunes:

- `DISK_DEVICE`: disco destino. Por defecto `/dev/sda`.
- `KIOSK_USER`: usuario kiosko.
- `KIOSK_PASSWORD`: password del usuario kiosko.
- `TIMEZONE`: zona horaria.
- `ENABLE_SSH`: habilita OpenSSH si esta en `true`.
- `ALLOW_INSECURE_DEFAULT_PASSWORD`: permite passwords de ejemplo solo para
  laboratorio.
- `ENABLE_PLYMOUTH`: habilita/deshabilita Plymouth.
- `PLYMOUTH_THEME_NAME`: nombre del tema Plymouth.
- `PLYMOUTH_IMAGE_PATH`: imagen PNG opcional para Plymouth.
- `CURSOR_PATH`: cursor opcional para el camino OpenBox.

Variables de Cage/YARG:

- `ROOT_PASSWORD`: password de root. Cage lo exige con valor real.
- `KIOSK_HOSTNAME`: hostname. Por defecto `minikiosk`.
- `INSTALL_NVIDIA`: `true`, `false` o vacio para preguntar.
- `YARG_RELEASE_CHANNEL`: `stable`, `nightly` o `ask`.
- `YARG_URL`: ZIP estable de YARG.
- `YARG_NIGHTLY_API_URL`: endpoint del ultimo nightly.
- `YARG_NIGHTLY_ASSET_REGEX`: patron para elegir el ZIP Linux del nightly.
- `YARG_SONGS_DIR`: carpeta local de canciones.
- `YARG_PERSISTENT_DATA_DIR`: perfil persistente de YARG.

Nota: `REQUIRE_ROOT_PASSWORD` existe como control interno. Cage lo activa por
defecto; el camino OpenBox no lo requiere.

## Estructura Del Proyecto

```text
MiniArch/
|-- install-arch-kiosk.sh      # Orquestador OpenBox/X11 original
|-- install-arch-cage.sh       # Orquestador Cage/YARG integrado
|-- setup-yarg.sh              # Post-install YARG standalone
|-- lib/
|   |-- validation.sh          # Validacion de entorno, seguridad, red y disco
|   |-- partitioning.sh        # GPT/UEFI, formateo, montaje y swap
|   |-- base_install.sh        # Pacstrap base y fstab
|   |-- bootloader.sh          # GRUB UEFI y arranque silencioso
|   |-- plymouth.sh            # Plymouth compartido
|   |-- drivers.sh             # Drivers, PipeWire, codecs y Bluetooth
|   |-- cage.sh                # Cage, usuario, servicio y wrapper
|   |-- yarg.sh                # YARG, settings, Samba, rendimiento y updater
|   |-- gui.sh                 # OpenBox/X11 y autostart
|   |-- customization.sh       # Mensajes, cursor, assets y scripts extra
|   `-- finalization.sh        # Red, SSH opcional, limpieza y desmontaje
|-- assets/
|   |-- README.md
|   |-- plymouth-image.png.example
|   `-- cursor/
|-- tests/
|   |-- test_validation.bats
|   |-- test_partitioning.bats
|   |-- test_base_install.bats
|   |-- test_bootloader.bats
|   |-- test_plymouth.bats
|   |-- test_drivers.bats
|   |-- test_gui.bats
|   |-- test_customization.bats
|   |-- test_finalization.bats
|   `-- test_integration.bats
`-- TODO.md
```

La suite BATS cubre principalmente modulos compartidos y el flujo OpenBox. Los
modulos `lib/cage.sh` y `lib/yarg.sh` todavia no tienen suite dedicada.

## Desarrollo Y Pruebas

Instala BATS en Linux/WSL:

```bash
sudo apt-get update
sudo apt-get install bats
```

Ejecuta pruebas:

```bash
bats tests/*.bats
```

Valida sintaxis:

```bash
bash -n install-arch-kiosk.sh
bash -n install-arch-cage.sh
for file in lib/*.sh; do bash -n "$file"; done
```

## Troubleshooting

### No se detecta Arch Linux

Ejecuta los instaladores desde el live ISO de Arch Linux. Deben existir
`/etc/arch-release` y `pacstrap`.

### No hay red

```bash
ip link
ping -c 3 archlinux.org
```

Levanta la interfaz si hace falta:

```bash
ip link set <interfaz> up
dhcpcd
```

### El disco no existe

```bash
lsblk
```

Configura `DISK_DEVICE` en `.env`, por ejemplo:

```bash
DISK_DEVICE=/dev/vda
```

### Plymouth falla

Plymouth es opcional en el camino Cage. Si el paquete, tema o asset falla, el
instalador debe continuar sin pantalla personalizada.

### Cage no arranca YARG

```bash
systemctl status cage-kiosk.service
journalctl -u cage-kiosk.service -b
ls -la /opt/YARG
```

Si el binario no existe, el wrapper abre `foot`. Puedes reinstalar con:

```bash
sudo update-yarg
```

### Audio no funciona

Revisa hardware ALSA:

```bash
aplay -l
aplay -L | grep -i pipewire
```

Revisa PipeWire/Pulse:

```bash
pactl info
pactl list short sinks
journalctl -u cage-kiosk.service -b | grep -Ei 'pipewire|wireplumber|dbus|alsa|bass'
```

Si `pactl info` falla, revisa que el wrapper este arrancando con DBus de sesion
y que no haya procesos PipeWire stale del usuario.

### Samba no aparece

```bash
sudo systemctl status smb nmb
testparm
grep -A10 "\[YARG-Songs\]" /etc/samba/smb.conf
ls -la /opt/YARG/Songs
```

### Instrumentos no funcionan

```bash
ls -l /etc/udev/rules.d/69-hid.rules
```

Reconecta el dispositivo despues de instalar para que udev aplique la regla.

## Seguridad

- No versiones `.env`.
- Cambia `KIOSK_PASSWORD` y `ROOT_PASSWORD`.
- El usuario kiosko tiene sudo sin password para mantenimiento.
- Samba permite guest en `YARG-Songs`; no lo expongas a redes no confiables.
- `ENABLE_SSH=false` es el valor recomendado para Cage.

Consulta [SECURITY.md](SECURITY.md) para mas detalles.

## Clonado A Discos Mas Grandes

Si clonas una instalacion a un disco mas grande, revisa [CLONING.md](CLONING.md)
para expandir `/home`.

## Contribuir

Lee [CONTRIBUTING.md](CONTRIBUTING.md), ejecuta las pruebas disponibles y abre
un pull request con cambios acotados.

## Licencia

Este proyecto esta bajo licencia MIT. Consulta [LICENSE](LICENSE).

## Creditos

- Arch Linux.
- YARG.
- Cage.
- OpenBox.
- Plymouth.
- PipeWire.
- Samba.
- BATS.
