# Guia De Seguridad

Este documento resume las consideraciones de seguridad para MiniArch.

## Archivo `.env`

`.env` puede contener passwords y no debe versionarse.

Recomendaciones:

- Mantener `.env` fuera de Git. Ya esta incluido en `.gitignore`.
- Usar permisos restrictivos:

```bash
chmod 600 .env
```

- Usar passwords reales antes de instalar.
- Eliminar `.env` del medio de instalacion cuando termines:

```bash
shred -u .env
```

## Passwords

MiniArch bloquea valores de ejemplo como `change-me`, `change-root`, `kiosk` o
`root` salvo que `ALLOW_INSECURE_DEFAULT_PASSWORD=true`.

Ese modo solo debe usarse en laboratorios o VMs desechables.

En los caminos Cage, `ROOT_PASSWORD` se exige por defecto. Tambien puedes
administrarlo despues con:

```bash
sudo passwd root
```

## Sudo

El usuario kiosko queda en `wheel` con sudo sin password para facilitar
mantenimiento local. Si el equipo queda en una red no confiable, endurece
`/etc/sudoers.d/10-wheel` o usa sudo con password.

## SSH

Para Cage/YARG se recomienda:

```bash
ENABLE_SSH=false
```

Si habilitas SSH:

- Deshabilita root remoto.
- Prefiere llaves publicas.
- Considera deshabilitar `PasswordAuthentication`.
- Limita usuarios permitidos.

Ejemplo de `/etc/ssh/sshd_config`:

```text
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
AllowUsers kiosk
X11Forwarding no
```

Reinicia:

```bash
sudo systemctl restart sshd
```

## Samba

El camino Cage/YARG crea el share:

```text
\\<hostname>\YARG-Songs
```

La configuracion permite `guest ok = yes` y fuerza escritura como el usuario
kiosko para que cargar canciones sea simple.

No expongas ese share a redes publicas o no confiables. En produccion, considera:

- Firewall que limite SMB a tu LAN.
- Password Samba obligatoria.
- Desactivar guest.

## Firewall

MiniArch no instala firewall por defecto. Para equipos expuestos, considera
`ufw`:

```bash
sudo pacman -S ufw
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow from 192.168.0.0/16 to any port 445 proto tcp
sudo ufw enable
```

Ajusta el rango de red a tu LAN real.

## Cage, DBus Y PipeWire

`run-yarg.sh` crea un DBus de sesion con `dbus-run-session` si el servicio
systemd no lo provee. Esto ayuda a que WirePlumber, PipeWire Pulse y apps con
integraciones de escritorio funcionen en un kiosko minimo.

El wrapper tambien arranca PipeWire en orden. Si audio falla, revisa:

```bash
pactl info
pactl list short sinks
journalctl -u cage-kiosk.service -b
```

## Bluetooth E HID

El instalador habilita Bluetooth e instala una regla udev para `hidraw`.
Reconecta instrumentos despues de instalar para que udev aplique permisos.

## Actualizaciones

Mantener Arch actualizado reduce exposicion:

```bash
sudo pacman -Syu
```

Para YARG:

```bash
sudo update-yarg
```

Nota: si instalaste `stable-latest` o `nightly`, `update-yarg` consulta el
latest correspondiente al actualizar.

## Proteccion Fisica

En un kiosko publico:

- Protege BIOS/UEFI con password.
- Deshabilita boot desde USB si aplica.
- Limita acceso a puertos fisicos.
- Considera bloquear cambios de TTY si no necesitas mantenimiento local.

## Reporte De Vulnerabilidades

Si encuentras una vulnerabilidad, no abras un issue publico con detalles
explotables. Contacta al mantenedor del repo y proporciona:

- Descripcion.
- Pasos para reproducir.
- Impacto.
- Mitigacion sugerida si la tienes.
