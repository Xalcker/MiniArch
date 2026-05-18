# TODO

## Cage / YARG

- [ ] Hacer que `update-yarg` respete `YARG_RELEASE_CHANNEL=nightly`.
  Actualmente, si se instala nightly, el updater queda apuntando al URL exacto
  resuelto durante la instalacion. Conviene que vuelva a consultar el latest de
  `YARG-BleedingEdge` al actualizar.

- [ ] Decidir si el audio debe ser obligatorio antes de lanzar YARG.
  Hoy `run-yarg.sh` espera unos segundos a que `pactl info` responda, pero si
  PipeWire/Pulse no queda listo lanza YARG de todos modos. Para kiosko puede ser
  mejor fallar claro o abrir `foot` con diagnostico si no hay audio.
