# TODO

## Investigar arranque UEFI en Proxmox tras apagado completo

Sintoma observado:

- Despues de instalar, la VM reinicia correctamente mientras no se apague.
- Si se apaga y se vuelve a encender, Proxmox arranca de nuevo el ISO de Arch
  Install e ignora el sistema instalado en `/dev/sda`.

Hipotesis a revisar:

- Orden de arranque de Proxmox deja el CD-ROM/ISO antes que el disco.
- La entrada UEFI creada por `grub-install` no queda persistida en NVRAM/OVMF
  despues de power off.
- Falta instalar tambien el loader fallback en la ESP:
  `/EFI/BOOT/BOOTX64.EFI`.
- Secure Boot/firmado UEFI podria bloquear el loader en hardware real o VMs
  configuradas con Secure Boot.

Puntos de investigacion:

- Confirmar desde el sistema instalado:
  `efibootmgr -v`.
- Confirmar contenido de la ESP:
  `find /boot/EFI -maxdepth 4 -type f`.
- Revisar si `grub-install` debe usar opciones adicionales como
  `--removable` para crear el fallback UEFI.
- Documentar en README el orden de boot recomendado en Proxmox y cuando quitar
  el ISO despues de instalar.
- Documentar opcion futura para Secure Boot: firmar GRUB/shim/kernel o dejar
  claro que Secure Boot debe estar deshabilitado por ahora.
