# Guía de Seguridad

Este documento describe las consideraciones de seguridad para el Instalador Automatizado de Arch Linux - Modo Kiosko.

## Tabla de Contenidos

- [Configuración Segura](#configuración-segura)
- [Gestión de Credenciales](#gestión-de-credenciales)
- [Endurecimiento del Sistema](#endurecimiento-del-sistema)
- [SSH y Acceso Remoto](#ssh-y-acceso-remoto)
- [Actualizaciones y Mantenimiento](#actualizaciones-y-mantenimiento)
- [Reporte de Vulnerabilidades](#reporte-de-vulnerabilidades)

## Configuración Segura

### Archivo .env

El archivo `.env` puede contener información sensible como contraseñas. Sigue estas recomendaciones:

1. **NUNCA versiones el archivo .env en Git**
   - El archivo ya está incluido en `.gitignore`
   - Verifica antes de hacer commit: `git status`

2. **Protege los permisos del archivo**
   ```bash
   chmod 600 .env
   ```

3. **Usa contraseñas fuertes**
   - Mínimo 12 caracteres
   - Combina mayúsculas, minúsculas, números y símbolos
   - No uses contraseñas predeterminadas en producción

4. **Elimina el archivo .env después de la instalación**
   ```bash
   shred -u .env  # Sobrescribe y elimina de forma segura
   ```

## Gestión de Credenciales

### Contraseña del Usuario Kiosko

La contraseña predeterminada (`kiosk123`) es INSEGURA y debe cambiarse inmediatamente:

```bash
# Después de la instalación, conectar por SSH o desde xterm
passwd

# O cambiar la contraseña de otro usuario (como root)
sudo passwd kiosk
```

### Contraseña de Root

El instalador NO configura una contraseña de root por defecto. Para establecerla:

```bash
# Desde el usuario kiosk
sudo passwd root
```

**Recomendación**: En sistemas kiosko, considera deshabilitar el acceso root directo y usar `sudo` exclusivamente.

## Endurecimiento del Sistema

### Configuración de Firewall

El instalador NO configura un firewall. Para producción, instala y configura `ufw` o `iptables`:

```bash
# Instalar ufw
sudo pacman -S ufw

# Configurar reglas básicas
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw enable

# Verificar estado
sudo ufw status verbose
```

### Deshabilitar Servicios Innecesarios

Revisa y deshabilita servicios que no necesites:

```bash
# Listar servicios activos
systemctl list-units --type=service --state=running

# Deshabilitar un servicio (ejemplo)
sudo systemctl disable nombre-servicio
sudo systemctl stop nombre-servicio
```

### Actualizaciones Automáticas de Seguridad

Considera configurar actualizaciones automáticas:

```bash
# Instalar herramientas
sudo pacman -S pacman-contrib

# Crear timer de systemd para actualizaciones
sudo systemctl enable --now paccache.timer
```

## SSH y Acceso Remoto

### Configuración Segura de SSH

El instalador habilita SSH con configuración predeterminada. Para producción, endurece la configuración:

```bash
# Editar configuración de SSH
sudo nano /etc/ssh/sshd_config
```

Configuraciones recomendadas:

```
# Cambiar puerto predeterminado
Port 2222

# Deshabilitar login de root
PermitRootLogin no

# Deshabilitar autenticación por contraseña (usar solo claves)
PasswordAuthentication no
PubkeyAuthentication yes

# Limitar usuarios que pueden conectarse
AllowUsers kiosk

# Deshabilitar X11 forwarding si no es necesario
X11Forwarding no

# Configurar timeout de sesión
ClientAliveInterval 300
ClientAliveCountMax 2
```

Reiniciar SSH después de cambios:

```bash
sudo systemctl restart sshd
```

### Autenticación por Clave Pública

Más seguro que contraseñas:

```bash
# En tu máquina local, generar par de claves
ssh-keygen -t ed25519 -C "tu-email@ejemplo.com"

# Copiar clave pública al servidor
ssh-copy-id -i ~/.ssh/id_ed25519.pub kiosk@IP_DEL_SERVIDOR

# Probar conexión
ssh -i ~/.ssh/id_ed25519 kiosk@IP_DEL_SERVIDOR

# Una vez verificado, deshabilitar autenticación por contraseña
# (ver configuración de sshd_config arriba)
```

### Fail2Ban

Protege contra ataques de fuerza bruta:

```bash
# Instalar fail2ban
sudo pacman -S fail2ban

# Configurar
sudo cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local
sudo nano /etc/fail2ban/jail.local

# Habilitar protección SSH
[sshd]
enabled = true
port = ssh
logpath = /var/log/auth.log
maxretry = 3
bantime = 3600

# Iniciar servicio
sudo systemctl enable --now fail2ban

# Verificar estado
sudo fail2ban-client status sshd
```

## Actualizaciones y Mantenimiento

### Mantener el Sistema Actualizado

```bash
# Actualizar sistema regularmente
sudo pacman -Syu

# Limpiar caché de paquetes antiguos
sudo pacman -Sc

# Verificar archivos huérfanos
sudo pacman -Qtdq
```

### Auditoría de Seguridad

```bash
# Instalar herramientas de auditoría
sudo pacman -S lynis

# Ejecutar auditoría
sudo lynis audit system

# Revisar recomendaciones en el reporte
```

### Logs y Monitoreo

```bash
# Revisar logs de autenticación
sudo journalctl -u sshd -f

# Revisar intentos de login fallidos
sudo journalctl _SYSTEMD_UNIT=sshd.service | grep "Failed password"

# Revisar logs del sistema
sudo journalctl -xe
```

## Consideraciones para Modo Kiosko

### Restricción de Aplicaciones

Si el kiosko ejecuta una aplicación específica (ej: navegador), considera:

1. **Ejecutar en modo sandbox**
   ```bash
   # Ejemplo con Chromium
   chromium --no-sandbox --kiosk https://tu-app.com
   ```

2. **Limitar acceso a red**
   - Usa firewall para permitir solo dominios específicos
   - Considera usar un proxy con whitelist

3. **Deshabilitar funcionalidades innecesarias**
   - Descargas de archivos
   - Acceso a configuración
   - Atajos de teclado peligrosos

### Protección Física

En entornos públicos:

1. **Deshabilitar acceso a TTY**
   ```bash
   # Editar /etc/systemd/logind.conf
   NAutoVTs=0
   ReserveVT=0
   ```

2. **Bloquear combinaciones de teclas**
   - Deshabilitar Ctrl+Alt+F1-F12 (cambio de TTY)
   - Configurar OpenBox para ignorar atajos peligrosos

3. **Configurar reinicio automático**
   - Si la aplicación se cierra inesperadamente
   - Reinicio programado diario para limpiar estado

## Reporte de Vulnerabilidades

Si descubres una vulnerabilidad de seguridad:

1. **NO abras un issue público en GitHub**
2. Envía un correo a: [tu-email-de-seguridad]
3. Incluye:
   - Descripción detallada de la vulnerabilidad
   - Pasos para reproducir
   - Impacto potencial
   - Sugerencias de mitigación (si las tienes)

Responderemos dentro de 48 horas y trabajaremos en un parche.

## Recursos Adicionales

- [Arch Linux Security](https://wiki.archlinux.org/title/Security)
- [SSH Hardening](https://wiki.archlinux.org/title/OpenSSH#Security)
- [Firewall Configuration](https://wiki.archlinux.org/title/Uncomplicated_Firewall)
- [System Maintenance](https://wiki.archlinux.org/title/System_maintenance)

## Disclaimer

Este instalador está diseñado para entornos de desarrollo y pruebas. Para entornos de producción, especialmente en espacios públicos, se requiere una revisión y endurecimiento adicional de seguridad según tus necesidades específicas.

La seguridad es un proceso continuo, no un estado final. Mantén tu sistema actualizado y revisa regularmente las configuraciones de seguridad.
