#!/bin/bash
#
# Alpine Linux System Upgrade Script
# ---------------------------------------
# Automates:
#   1. apk upgrade
#   2. initramfs rebuild
#   3. grub reinstall + config update
#   4. Reboot (Optional)

set -eu

# ==== CONFIGURATION ====
LOGFILE="/var/log/system-upgrade.log"
EFI_DIR="/boot/efi"
GRUB_ID="alpine"
BOOT_DISK="/dev/sda3"
REBOOT_ON_SUCCESS=false
# ========================

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

error_exit() {
    log "ERROR: $1"
    exit 1
}

check_root() {
    [ "$(id -u)" -eq 0 ] || error_exit "This script must be run as root"
}

check_mounts() {
    mountpoint -q "$EFI_DIR" || error_exit "EFI directory $EFI_DIR is not mounted"
}

check_internet() {
    ping -c1 -W3 dl-cdn.alpinelinux.org >/dev/null 2>&1 || log "No internet connectivity; skipping apk update"
}

main() {
    check_root
    check_mounts
    check_internet

    log "=== Starting system upgrade ==="

    log "→ Updating repositories and upgrading packages..."
    apk update >>"$LOGFILE" 2>&1
    apk upgrade -U -a >>"$LOGFILE" 2>&1 || error_exit "apk upgrade failed"

    log "→ Rebuilding initramfs for installed kernels..."
    for ver in /lib/modules/*; do
        [ -d "$ver" ] || continue
        KVER=$(basename "$ver")
        log "   - Building initramfs for $KVER"
        mkinitfs -k "$KVER" >>"$LOGFILE" 2>&1 || error_exit "mkinitfs failed for $KVER"
    done

    log "→ Reinstalling GRUB bootloader..."
    grub-install --target=x86_64-efi --efi-directory="$EFI_DIR" \
        --bootloader-id="$GRUB_ID" --removable >>"$LOGFILE" 2>&1 \
        || error_exit "grub-install failed"

    log "→ Regenerating GRUB configuration..."
    grub-mkconfig -o /boot/grub/grub.cfg >>"$LOGFILE" 2>&1 || error_exit "grub-mkconfig failed"

    log "System upgrade completed successfully."

    if [ "$REBOOT_ON_SUCCESS" = true ]; then
        log "Rebooting system in 15 seconds..."
        sleep 15
        reboot
    else
        log "Reboot required to apply kernel changes."
    fi
}

main "$@"
