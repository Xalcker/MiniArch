# Guía de Clonación del Sistema Kiosko

Si ya has instalado y configurado un kiosko perfecto y deseas replicarlo masivamente en otras máquinas (por ejemplo, con discos de igual o mayor tamaño), no necesitas correr el script de instalación desde cero en cada una. Puedes clonar el disco entero usando el entorno Live de Arch Linux.

## Requisitos
- Memoria USB con el ISO Live de Arch Linux.
- El disco de origen (fuente) conectado a la máquina (o una imagen guardada previamente).
- El disco de destino conectado a la máquina.
- **Importante:** El disco de destino debe ser de un tamaño **igual o mayor** al disco de origen.

---

## 1. Identificar los Discos

Arranca la máquina con el USB de Arch Linux y lista los discos conectados:

```bash
lsblk
```

Identifica cuál es tu disco **origen** (ej. `/dev/sda`) y cuál es tu disco **destino** (ej. `/dev/sdb`). Presta mucha atención al tamaño de los discos para diferenciarlos.

---

## 2. Clonar el Disco (usando `dd`)

Usa el comando `dd` para hacer una copia exacta bit a bit. **Asegúrate de no confundir `if` (input file / origen) con `of` (output file / destino)**, de lo contrario destruirás tu instalación.

```bash
# Reemplaza sda (origen) y sdb (destino) con tus discos correspondientes
dd if=/dev/sda of=/dev/sdb bs=4M status=progress
```

Espera a que el proceso termine (puede tomar varios minutos dependiendo de la velocidad de los discos). Una vez terminado, el disco destino ya es una copia exacta, arrancable y completamente funcional.

---

## 3. Expandir la Partición Home (Si el destino es más grande)

Nuestro esquema de particionado crea la partición `/home` al final del disco (Partición 4). Si clonaste un disco pequeño (ej. 16GB) a uno más grande (ej. 128GB), tendrás mucho espacio sin asignar al final del disco. Para aprovecharlo, debemos expandir la partición 4 y luego su sistema de archivos.

### 3.1 Reparar la tabla GPT y expandir la partición
La herramienta `parted` detectará que el disco físico es más grande que la tabla GPT clonada. Al abrirlo, te pedirá repararla (Fix). 

```bash
# Abrir el disco destino con parted
parted /dev/sdb

# Dentro de la consola de parted (si te pregunta Fix/Ignore para reparar GPT, escribe 'F' o 'Fix')
(parted) print
(parted) resizepart 4 100%
(parted) quit
```
*(Nota: Si usas discos NVMe como `/dev/nvme0n1`, la partición a expandir será la número 4, es decir `/dev/nvme0n1p4`).*

### 3.2 Expandir el Sistema de Archivos (ext4)
Ahora que la partición es más grande en la tabla, debemos indicarle al sistema de archivos `ext4` que use todo el nuevo espacio disponible:

```bash
# Revisar el sistema de archivos en busca de errores (recomendado)
e2fsck -f /dev/sdb4

# Expandir el sistema de archivos al máximo de la partición
resize2fs /dev/sdb4
```

---

## 4. Finalización

¡Listo! Has clonado y expandido con éxito tu instalación. Ya puedes apagar la máquina, desconectar el disco de origen y el USB de Arch Linux, y arrancar el kiosko desde el nuevo disco.

```bash
poweroff
```
