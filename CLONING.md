# Guia De Clonacion Del Sistema Kiosko

Si ya tienes una instalacion lista y quieres replicarla a otro disco, puedes
clonar el disco completo desde el live ISO de Arch Linux.

Esto aplica tanto para el camino Cage/YARG como para el camino OpenBox/X11.

## Requisitos

- ISO live de Arch Linux.
- Disco origen conectado o una imagen existente.
- Disco destino conectado.
- El disco destino debe ser igual o mayor que el origen.

## 1. Identificar Discos

Arranca con el ISO y revisa:

```bash
lsblk
```

Identifica con cuidado:

- Origen, por ejemplo `/dev/sda`.
- Destino, por ejemplo `/dev/sdb`.

Confundir origen y destino destruye datos.

## 2. Clonar Con `dd`

Ejemplo:

```bash
dd if=/dev/sda of=/dev/sdb bs=4M status=progress conv=fsync
```

Espera a que termine antes de retirar discos.

## 3. Expandir `/home`

MiniArch crea `/home` al final del disco. Si el destino es mas grande, puedes
expandir la particion 4.

### 3.1 Reparar GPT Y Expandir Particion

```bash
parted /dev/sdb
```

Dentro de `parted`:

```text
print
resizepart 4 100%
quit
```

Si `parted` pregunta por reparar GPT, acepta `Fix`.

En NVMe, la particion sera algo como `/dev/nvme0n1p4`.

### 3.2 Expandir Ext4

```bash
e2fsck -f /dev/sdb4
resize2fs /dev/sdb4
```

Para NVMe:

```bash
e2fsck -f /dev/nvme0n1p4
resize2fs /dev/nvme0n1p4
```

## 4. Finalizar

Apaga el equipo:

```bash
poweroff
```

Retira el live ISO y arranca desde el disco clonado.
