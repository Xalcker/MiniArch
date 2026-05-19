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

- [ ] Revisar fallo de Plymouth cuando no esta disponible ImageMagick.
  El instalador avisa que falta `imagemagick`/`convert` para redimensionar
  `assets/plymouth-image.png`. Confirmar si debe instalarse en el live antes de
  la validacion, incluirse en `pacstrap`, o evitar redimensionar cuando la imagen
  ya viene en 1280x720.
