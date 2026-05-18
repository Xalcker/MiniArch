#!/usr/bin/env bash
# =============================================================================
# install-arch-cage.sh
# -----------------------------------------------------------------------------
# Instalación automatizada de Arch Linux + Cage (Wayland kiosk) + YARG
# • Drivers Intel y AMD instalados por defecto
# • Driver NVIDIA opcional (pregunta al usuario)
# • Crea wrapper run-yarg.sh y servicio systemd cage-kiosk.service
# =============================================================================

# ── COLORES ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

section() { echo -e "\n${CYAN}╔══ $1 ══╗${NC}"; }
step()    { printf "${MAGENTA}  ➤ [%s]${NC} %s\n" "$1" "$2"; }
ok()      { echo -e "${GREEN}  ✔ $1${NC}"; }
warn()    { echo -e "${YELLOW}  ⚠ $1${NC}"; }

# ── REQUISITOS ────────────────────────────────────────────────────────────────
set -euo pipefail

DISK="/dev/sda"   # Cambiar a /dev/vda si aplica en Proxmox

# =============================================================================
# ❓ PREGUNTAS INICIALES
# =============================================================================
section "Configuración inicial"

echo -e "${YELLOW}Disco destino:${NC} $DISK"
echo ""
read -rp "$(echo -e ${BLUE}"¿Instalar driver NVIDIA? (s/N): "${NC})" _answer
INSTALL_NVIDIA=false
[[ "${_answer,,}" == "s" || "${_answer,,}" == "y" ]] && INSTALL_NVIDIA=true

if $INSTALL_NVIDIA; then
    ok "Se instalarán drivers NVIDIA (nvidia-dkms, nvidia-utils)"
else
    warn "Driver NVIDIA omitido. Solo se instalarán Intel y AMD."
fi

# =============================================================================
# 1️⃣  PREPARAR DISCO
# =============================================================================
section "Preparando disco $DISK (BIOS/MBR)"
parted -s "$DISK" mklabel msdos
parted -s "$DISK" mkpart primary ext4 1MiB 100%
mkfs.ext4 -F "${DISK}1"
ok "Disco formateado correctamente"

# =============================================================================
# 2️⃣  MONTAR PARTICIÓN
# =============================================================================
section "Montando partición"
mount "${DISK}1" /mnt
ok "Montado en /mnt"

# =============================================================================
# 3️⃣  INSTALAR SISTEMA BASE + STACK GRÁFICO
# =============================================================================
section "Instalando sistema base + stack gráfico"

PKGS=(
    base linux linux-firmware
    nano sudo networkmanager grub
    mesa wayland xorg-xwayland cage foot
    pipewire pipewire-pulse wireplumber ttf-dejavu
    curl unzip
    # ── Intel & AMD (por defecto) ──────────────────
    vulkan-intel intel-media-driver
    vulkan-radeon xf86-video-amdgpu
    # ── Virtualización (Proxmox/QEMU) ─────────────
    virglrenderer
    # ── Base Vulkan ────────────────────────────────
    vulkan-icd-loader egl-wayland linux-headers
    # ── HID (controladores YARG: PS3, Wii, etc.) ──
    hidapi systemd-libs
)

if $INSTALL_NVIDIA; then
    PKGS+=(nvidia-dkms nvidia-utils)
    step "NVIDIA" "nvidia-dkms + nvidia-utils incluidos"
fi

step "pacstrap" "Instalando ${#PKGS[@]} paquetes..."
pacstrap -K /mnt "${PKGS[@]}"
ok "Sistema base instalado"

# =============================================================================
# 4️⃣  GENERAR fstab
# =============================================================================
section "Generando fstab"
genfstab -U /mnt >> /mnt/etc/fstab
ok "fstab generado"

# =============================================================================
# 5️⃣  CONFIGURAR SISTEMA EN CHROOT
# =============================================================================
section "Configuración interna (chroot)"

# Pasar el flag NVIDIA al chroot como archivo temporal
echo "$INSTALL_NVIDIA" > /mnt/tmp/nvidia_flag

arch-chroot /mnt /bin/bash <<'CHROOT'
# ── leer flag ─────────────────────────────────────────────────────────────────
INSTALL_NVIDIA=$(cat /tmp/nvidia_flag)

# ── ⏰ Zona horaria ───────────────────────────────────────────────────────────
ln -sf /usr/share/zoneinfo/America/Phoenix /etc/localtime
hwclock --systohc

# ── 🌐 Locale ─────────────────────────────────────────────────────────────────
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# ── 🖥 Hostname ───────────────────────────────────────────────────────────────
echo "minikiosk" > /etc/hostname

# ── 📡 Red ────────────────────────────────────────────────────────────────────
systemctl enable NetworkManager

# ── 🛠 GRUB ───────────────────────────────────────────────────────────────────
if [[ "$INSTALL_NVIDIA" == "true" ]]; then
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet nvidia_drm.modeset=1"/' /etc/default/grub
else
    sed -i 's/^GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"/' /etc/default/grub
fi
grub-install --target=i386-pc /dev/sda
grub-mkconfig -o /boot/grub/grub.cfg

# ── 🔐 Contraseñas ────────────────────────────────────────────────────────────
echo "root:root" | chpasswd
useradd -m -G wheel,audio,video,render kiosk
echo "kiosk:kiosk" | chpasswd
echo "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel
chmod 440 /etc/sudoers.d/wheel

# ── 📦 Multilib + dependencias 32-bit (YARG) ─────────────────────────────────
sed -i '/\[multilib\]/,/Include/s/^#//' /etc/pacman.conf
pacman -Syu --noconfirm \
    lib32-pipewire lib32-alsa-plugins lib32-libpulse \
    hidapi systemd-libs pulseaudio-alsa pulsemixer

# ── 🎮 Regla udev para dispositivos HID (wiki oficial YARG) ──────────────────
# Permite acceder a controladores (PS3, Wii, etc.) sin root
echo 'KERNEL=="hidraw*", TAG+="uaccess"' > /etc/udev/rules.d/69-hid.rules
chmod 644 /etc/udev/rules.d/69-hid.rules

# ── 📥 Descargar e instalar YARG ─────────────────────────────────────────────
curl -L -o /tmp/YARG.zip \
    https://github.com/YARC-Official/YARG/releases/download/v0.14.0/YARG_v0.14.0-Linux-x86_64.zip
mkdir -p /opt/YARG
unzip -o /tmp/YARG.zip -d /opt/YARG
chmod +x /opt/YARG/YARG
rm /tmp/YARG.zip

# ── 🎮 Wrapper run-yarg.sh ────────────────────────────────────────────────────
cat > /usr/local/bin/run-yarg.sh <<'WRAPPER'
#!/usr/bin/env bash
# Detectar si estamos en una VM y habilitar software rendering completo
if grep -q "hypervisor" /proc/cpuinfo 2>/dev/null; then
    # Wayland/wlroots: forzar renderer por software y deshabilitar cursors HW
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    export WLR_NO_HARDWARE_CURSORS=1
    # XWayland/Glamor: evitar "failed to initialize glamor" en VMs sin GPU real
    export LIBGL_ALWAYS_SOFTWARE=1
    export GALLIUM_DRIVER=llvmpipe
fi
exec /usr/bin/cage /opt/YARG/YARG
WRAPPER
chmod +x /usr/local/bin/run-yarg.sh

# ── ⚙️ Servicio systemd cage-kiosk.service ────────────────────────────────────
cat > /etc/systemd/system/cage-kiosk.service <<'SERVICE'
[Unit]
Description=Kiosk YARG con Cage (Wayland)
After=network.target

[Service]
User=kiosk
Environment=PATH=/usr/local/sbin:/usr/local/bin:/usr/bin:/bin
ExecStart=/usr/local/bin/run-yarg.sh
StandardOutput=journal
StandardError=journal
Restart=always
RestartSec=5

[Install]
WantedBy=graphical.target
SERVICE

systemctl enable cage-kiosk.service

# ── 🧹 Limpiar ────────────────────────────────────────────────────────────────
rm -f /tmp/nvidia_flag
CHROOT

# =============================================================================
# 6️⃣  FINAL
# =============================================================================
section "Instalación completada"
echo -e "${GREEN}"
echo "  ╔══════════════════════════════════════════╗"
echo "  ║   ✔  ¡Instalación finalizada con éxito!  ║"
echo "  ║                                          ║"
echo "  ║  • Cage + YARG instalados en /opt/YARG   ║"
echo "  ║  • Servicio cage-kiosk habilitado        ║"
echo "  ║  • Wrapper: /usr/local/bin/run-yarg.sh   ║"
echo "  ╚══════════════════════════════════════════╝"
echo -e "${NC}"
echo "Escribe 'reboot' para reiniciar."
echo "(Recuerda desmontar/quitar la ISO en Proxmox antes de arrancar)"
