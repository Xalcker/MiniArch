# Guía de Contribución

¡Gracias por tu interés en contribuir al Instalador Automatizado de Arch Linux - Modo Kiosko! Este documento proporciona pautas para contribuir al proyecto.

## Tabla de Contenidos

- [Código de Conducta](#código-de-conducta)
- [Cómo Contribuir](#cómo-contribuir)
- [Reportar Bugs](#reportar-bugs)
- [Sugerir Mejoras](#sugerir-mejoras)
- [Proceso de Pull Request](#proceso-de-pull-request)
- [Estándares de Código](#estándares-de-código)
- [Pruebas](#pruebas)
- [Documentación](#documentación)

## Código de Conducta

Este proyecto se adhiere a un código de conducta. Al participar, se espera que mantengas un ambiente respetuoso y profesional.

## Cómo Contribuir

Hay muchas formas de contribuir:

- Reportar bugs
- Sugerir nuevas características
- Mejorar la documentación
- Escribir o mejorar pruebas
- Corregir bugs
- Implementar nuevas características

## Reportar Bugs

Antes de reportar un bug:

1. **Verifica que estás usando la última versión**
2. **Busca en los issues existentes** para evitar duplicados
3. **Recopila información del sistema**:
   - Versión de Arch Linux ISO
   - Configuración de hardware (VM o físico)
   - Logs relevantes

### Plantilla de Reporte de Bug

```markdown
**Descripción del Bug**
Una descripción clara y concisa del bug.

**Pasos para Reproducir**
1. Ejecutar '...'
2. Configurar '...'
3. Ver error en '...'

**Comportamiento Esperado**
Qué esperabas que sucediera.

**Comportamiento Actual**
Qué sucedió realmente.

**Logs**
```
Pegar logs relevantes aquí
```

**Entorno**
- Arch Linux ISO: [versión]
- Hardware: [VM/Físico]
- Configuración: [detalles relevantes]

**Información Adicional**
Cualquier otro contexto sobre el problema.
```

## Sugerir Mejoras

Las sugerencias de mejoras son bienvenidas. Antes de sugerir:

1. **Verifica que no exista ya** en los issues
2. **Describe claramente el caso de uso**
3. **Explica por qué sería útil** para otros usuarios

### Plantilla de Sugerencia

```markdown
**Descripción de la Mejora**
Una descripción clara de qué quieres que se agregue.

**Caso de Uso**
Describe el problema que esta mejora resolvería.

**Solución Propuesta**
Cómo crees que debería implementarse.

**Alternativas Consideradas**
Otras soluciones que consideraste.

**Información Adicional**
Cualquier otro contexto o capturas de pantalla.
```

## Proceso de Pull Request

### Antes de Empezar

1. **Fork el repositorio**
2. **Crea una rama** desde `main`:
   ```bash
   git checkout -b feature/mi-nueva-caracteristica
   # o
   git checkout -b fix/correccion-de-bug
   ```

### Convenciones de Nombres de Ramas

- `feature/descripcion`: Nuevas características
- `fix/descripcion`: Correcciones de bugs
- `docs/descripcion`: Cambios en documentación
- `test/descripcion`: Agregar o mejorar pruebas
- `refactor/descripcion`: Refactorización de código

### Durante el Desarrollo

1. **Escribe código limpio y documentado**
2. **Sigue los estándares de código** (ver abajo)
3. **Agrega pruebas** para nuevas características
4. **Actualiza la documentación** si es necesario
5. **Haz commits atómicos** con mensajes descriptivos

### Convenciones de Commits

Usa mensajes de commit descriptivos siguiendo este formato:

```
tipo(alcance): descripción breve

Descripción más detallada si es necesario.

- Punto adicional 1
- Punto adicional 2
```

Tipos de commit:
- `feat`: Nueva característica
- `fix`: Corrección de bug
- `docs`: Cambios en documentación
- `style`: Formato, punto y coma faltantes, etc.
- `refactor`: Refactorización de código
- `test`: Agregar o modificar pruebas
- `chore`: Mantenimiento, actualización de dependencias

Ejemplos:
```
feat(plymouth): agregar soporte para temas personalizados

fix(validation): corregir verificación de disco vacío

docs(readme): actualizar instrucciones de instalación

test(partitioning): agregar pruebas para formateo de particiones
```

### Antes de Enviar el PR

1. **Ejecuta todas las pruebas**:
   ```bash
   bats tests/*.bats
   ```

2. **Verifica la sintaxis de bash**:
   ```bash
   bash -n install-arch-kiosk.sh
   for file in lib/*.sh; do bash -n "$file"; done
   ```

3. **Actualiza CHANGELOG.md** en la sección [No Publicado]

4. **Asegúrate de que tu rama está actualizada**:
   ```bash
   git fetch upstream
   git rebase upstream/main
   ```

### Enviar el Pull Request

1. **Push a tu fork**:
   ```bash
   git push origin feature/mi-nueva-caracteristica
   ```

2. **Crea el Pull Request** en GitHub

3. **Completa la plantilla de PR** con:
   - Descripción de los cambios
   - Tipo de cambio (bug fix, feature, etc.)
   - Checklist de verificación
   - Issues relacionados

### Plantilla de Pull Request

```markdown
## Descripción
Descripción clara de los cambios realizados.

## Tipo de Cambio
- [ ] Bug fix (cambio que corrige un issue)
- [ ] Nueva característica (cambio que agrega funcionalidad)
- [ ] Breaking change (cambio que rompe compatibilidad)
- [ ] Documentación

## ¿Cómo se ha Probado?
Describe las pruebas que ejecutaste.

## Checklist
- [ ] Mi código sigue los estándares del proyecto
- [ ] He realizado una auto-revisión de mi código
- [ ] He comentado mi código, especialmente en áreas complejas
- [ ] He actualizado la documentación correspondiente
- [ ] Mis cambios no generan nuevas advertencias
- [ ] He agregado pruebas que prueban que mi corrección es efectiva
- [ ] Las pruebas nuevas y existentes pasan localmente
- [ ] He actualizado CHANGELOG.md

## Issues Relacionados
Fixes #(issue)
```

## Estándares de Código

### Bash/Shell Script

1. **Usar bash, no sh**:
   ```bash
   #!/bin/bash
   ```

2. **Usar set para manejo de errores**:
   ```bash
   set -e  # Salir en error
   set -u  # Error en variables no definidas
   ```

3. **Comillas en variables**:
   ```bash
   # Bien
   echo "$variable"
   
   # Mal
   echo $variable
   ```

4. **Usar [[ ]] en lugar de [ ]**:
   ```bash
   # Bien
   if [[ "$var" == "value" ]]; then
   
   # Evitar
   if [ "$var" = "value" ]; then
   ```

5. **Funciones documentadas**:
   ```bash
   ################################################################################
   # nombre_funcion()
   #
   # Descripción breve de la función.
   #
   # Arguments:
   #   $1 - Descripción del primer argumento
   #   $2 - Descripción del segundo argumento
   #
   # Returns:
   #   0 - Si fue exitoso
   #   1 - Si hubo un error
   ################################################################################
   nombre_funcion() {
       local arg1="$1"
       local arg2="$2"
       
       # Implementación
   }
   ```

6. **Variables locales en funciones**:
   ```bash
   mi_funcion() {
       local variable_local="valor"
       # ...
   }
   ```

7. **Manejo de errores**:
   ```bash
   if ! comando_que_puede_fallar; then
       log_error "Descripción del error"
       return 1
   fi
   ```

8. **Logging consistente**:
   ```bash
   log "Mensaje informativo"
   log_error "Mensaje de error"
   ```

### Estructura de Archivos

- **Módulos en `lib/`**: Un archivo por funcionalidad
- **Pruebas en `tests/`**: Un archivo de prueba por módulo
- **Assets en `assets/`**: Recursos personalizables
- **Documentación en raíz**: README.md, SECURITY.md, etc.

## Pruebas

### Ejecutar Pruebas

```bash
# Todas las pruebas
bats tests/*.bats

# Prueba específica
bats tests/test_validation.bats

# Con salida detallada
bats --tap tests/*.bats
```

### Escribir Pruebas

Las pruebas usan [BATS (Bash Automated Testing System)](https://github.com/bats-core/bats-core).

Ejemplo de prueba:

```bash
#!/usr/bin/env bats

# Cargar el módulo a probar
load ../lib/validation

@test "validate_environment detecta Arch Linux correctamente" {
    # Simular entorno de Arch Linux
    touch /tmp/arch-release
    
    # Ejecutar función
    run validate_environment
    
    # Verificar resultado
    [ "$status" -eq 0 ]
    [[ "$output" =~ "validado correctamente" ]]
    
    # Limpiar
    rm /tmp/arch-release
}
```

### Cobertura de Pruebas

Intenta mantener alta cobertura de pruebas:
- Casos exitosos
- Casos de error
- Casos límite
- Validación de entrada

## Documentación

### README.md

Actualiza el README si:
- Agregas una nueva característica
- Cambias el proceso de instalación
- Modificas configuraciones importantes

### Comentarios en Código

- Comenta el "por qué", no el "qué"
- Documenta funciones complejas
- Explica decisiones de diseño no obvias

### CHANGELOG.md

Agrega tus cambios en la sección [No Publicado]:

```markdown
## [No Publicado]

### Agregado
- Nueva característica X

### Cambiado
- Modificación en Y

### Corregido
- Bug en Z
```

## Preguntas

Si tienes preguntas sobre cómo contribuir, puedes:
- Abrir un issue con la etiqueta "question"
- Revisar issues existentes
- Consultar la documentación

¡Gracias por contribuir! 🎉
