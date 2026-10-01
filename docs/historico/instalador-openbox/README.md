# Documentacion historica: instalador OpenBox

Estos documentos son la especificacion (requisitos, diseno y plan de tareas) del
**primer instalador de MiniArch**: Arch Linux con OpenBox/X11, `install-arch-kiosk.sh`
y `lib/gui.sh`. Ese camino fue reemplazado por los instaladores basados en Cage
(`install-cage-yarg.sh`, `install-cage-clonehero.sh`, `install-cage-rpcs3.sh` e
`install-cage-kiosk.sh`) y ya no existe en el repositorio (ver el
[CHANGELOG](../../../CHANGELOG.md)).

**No describen el codigo actual.** Se conservan unicamente como referencia del
razonamiento de diseno original (modularidad en `lib/`, pruebas BATS con mocks,
particionado GPT/UEFI, Plymouth).

- [requirements.md](requirements.md)
- [design.md](design.md)
- [tasks.md](tasks.md)

La documentacion vigente esta en el [README](../../../README.md).
