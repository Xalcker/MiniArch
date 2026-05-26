# TODO

## Pendientes

### YARG: evaluar Wayland nativo opcional

- Decision preliminar: no usar `-force-wayland` por defecto hasta probarlo en
  hardware real. XWayland/auto sigue siendo el camino mas compatible.
- [ ] Agregar variable opcional `YARG_FORCE_WAYLAND=false`.
- [ ] Si `YARG_FORCE_WAYLAND=true`, lanzar YARG con `-force-wayland`.
- [ ] No usar `-platform wl`; para Unity Linux Player el argumento documentado
  es `-force-wayland`.
- [ ] Probar input, fullscreen, audio y render con guitarras/mandos en hardware
  real antes de considerar cambiar el default.
- [ ] Documentar la variable en `README.md` y agregar cobertura en pruebas.

Archivos probables:

- `install-cage-yarg.sh`
- `lib/cage.sh`
- `README.md`
- `tests/`
