# Guia De Clonacion Del Sistema Kiosko

Si ya tienes una instalacion lista y quieres replicarla a otro disco, puedes
clonar el disco completo desde el live ISO de Arch Linux.

Esto aplica tanto para el camino Cage/YARG como para el camino Cage/foot.

## Requisitos

- ISO live de Arch Linux.
- Disco origen conectado o una imagen existente.
- Disco destino conectado.
- El disco destino debe ser igual o mayor que el origen.
- `gptfdisk` para `sgdisk`.
- `e2fsprogs` para `e2fsck`, `tune2fs` y `resize2fs`.
- `dosfstools` para regenerar la particion EFI si cambias su UUID.
- `arch-install-scripts` para `genfstab`.
- `parted` para expandir `/home`.
- `ddrescue` opcional; si no existe, el script usa `dd`.

Si solo quieres copiar de A hacia B, el script puede clonar con herramientas
basicas del live ISO. Las herramientas anteriores se necesitan cuando eliges
cambiar UUIDs/GUIDs, regenerar GRUB o expandir `/home`.

En Arch live puedes instalarlas con:

```bash
pacman -Sy --needed gptfdisk e2fsprogs dosfstools arch-install-scripts parted util-linux
```

## Flujo Recomendado

Arranca desde el ISO live, entra al repo y ejecuta:

```bash
sudo bash scripts/clone-miniarch.sh
```

El script:

- Lista discos detectados.
- Pregunta origen y destino.
- Exige confirmar con `CLONAR`.
- Usa `ddrescue` si esta disponible o `dd` como fallback.
- Al final pregunta si quieres cambiar UUIDs/GUIDs del clon.
- Regenera `fstab` con los UUIDs actuales.
- Regenera GRUB para que apunte al nuevo UUID de root.
- Puede instalar GRUB UEFI en modo removable para que el clon arranque en otro
  equipo sin depender de una entrada NVRAM existente.
- Pregunta si quieres expandir `/home` al espacio disponible.

Tambien puedes pasar los discos directo:

```bash
sudo bash scripts/clone-miniarch.sh /dev/sda /dev/sdb
```

Confundir origen y destino destruye datos. El destino se borra completo.

## Expandir `/home` Solamente

Si ya clonaste el disco y solo quieres expandir la particion 4:

```bash
sudo bash scripts/expand-home.sh /dev/sdb
```

Sin argumento, el script muestra el selector de discos:

```bash
sudo bash scripts/expand-home.sh
```

Si lo llamas desde un flujo que ya confirmo la operacion, puedes omitir la
confirmacion fuerte:

```bash
sudo bash scripts/expand-home.sh --yes /dev/sdb
```

MiniArch crea `/home` como particion 4 al final del disco. El script repara GPT
si el disco crecio despues de clonar, expande la particion 4 y ejecuta
`resize2fs`.

## Flujo Manual De Respaldo

Si necesitas hacerlo manualmente, identifica con cuidado origen y destino:

```bash
lsblk
```

Clona:

```bash
dd if=/dev/sda of=/dev/sdb bs=4M status=progress conv=fsync
sync
```

Repara GPT y expande `/home`:

```bash
sgdisk -e /dev/sdb
parted -s /dev/sdb resizepart 4 100%
partprobe /dev/sdb
e2fsck -f /dev/sdb4
resize2fs /dev/sdb4
```

Para NVMe, la particion sera algo como `/dev/nvme0n1p4`.

## Cambiar UUIDs Manualmente

Si vas a conectar el original y el clon al mismo tiempo, conviene cambiar IDs
del clon y regenerar `fstab`:

```bash
sgdisk -G /dev/sdb
e2fsck -f /dev/sdb2
tune2fs -U random /dev/sdb2
swaplabel -U "$(uuidgen)" /dev/sdb3
e2fsck -f /dev/sdb4
tune2fs -U random /dev/sdb4
```

Luego monta root, boot y home del clon y regenera `fstab`:

```bash
mount /dev/sdb2 /mnt
mount /dev/sdb1 /mnt/boot
mount /dev/sdb4 /mnt/home
genfstab -U /mnt > /mnt/etc/fstab
umount -R /mnt
```

## Finalizar

Apaga el equipo:

```bash
poweroff
```

Retira el live ISO y arranca desde el disco clonado.
