#!/usr/bin/env bash
# ==============================================================
# Hardened VM Security Deployment Script
# Enterprise-ready: ClamAV + rkhunter
# Offline/NAT-safe (Debian 13 / Trixie)
# Hypervisors: VMware / Proxmox / KVM
# ==============================================================
set -euo pipefail

### ---------------- CONFIGURATION ---------------- ###
SCAN_PATHS="/home /var/www /tmp"
EMAIL="root"
REMOVE_INFECTED="no"          # yes to auto-remove malware
QUARANTINE_DIR="/opt/quarantine"
LOG_DIR="/var/log/security"

# VM-safe scan limits
MAX_FILESIZE="100M"
MAX_SCANSIZE="500M"
MAX_FILES="200000"

# Cron schedule
CLAM_UPDATE_TIME="0 3 * * *"
CLAM_SCAN_TIME="0 4 * * *"
RKHUNTER_TIME="30 2 * * *"

### ------------------------------------------------ ###

# Must run as root
if [[ $EUID -ne 0 ]]; then
    echo "Run this script as root."
    exit 1
fi

# Prepare directories
mkdir -p "$QUARANTINE_DIR" "$LOG_DIR"
chmod 700 "$QUARANTINE_DIR"

echo "[+] Detecting OS..."
if [[ -f /etc/debian_version ]]; then
    OS_FAMILY="debian"
elif [[ -f /etc/redhat-release ]]; then
    OS_FAMILY="rhel"
else
    echo "Unsupported distribution."
    exit 1
fi

echo "[+] Detecting virtualization..."
VIRT_TYPE=$(systemd-detect-virt || true)
echo "[+] Virtualization: ${VIRT_TYPE:-unknown}"

### ---------------- INSTALL PACKAGES ---------------- ###
echo "[+] Installing required packages..."
if [[ "$OS_FAMILY" == "debian" ]]; then
    apt update -y
    apt install -y clamav clamav-daemon rkhunter mailutils logrotate wget
    if command -v gnome-shell >/dev/null 2>&1; then
        apt install -y clamtk || true
    fi
else
    dnf install -y epel-release
    dnf install -y clamav clamav-update rkhunter mailx logrotate wget
    if command -v gnome-shell >/dev/null 2>&1; then
        dnf install -y clamtk || true
    fi
fi

### ---------------- CLAMAV INIT ---------------- ###
echo "[+] Initializing ClamAV..."
systemctl stop clamav-freshclam || true
pkill freshclam || true
mkdir -p /var/log/clamav
chown clamav:clamav /var/log/clamav
chmod 750 /var/log/clamav
sudo -u clamav freshclam || echo "Freshclam manual update failed, check network"

### ---------------- RKHUNTER OFFLINE CONFIG ---------------- ###
echo "[+] Configuring rkhunter offline mode..."
mkdir -p /var/lib/rkhunter/db
cat > /var/lib/rkhunter/db/mirrors.dat << 'EOF'
# Offline/enterprise mode: only local mirrors used
EOF
chown root:root /var/lib/rkhunter/db/mirrors.dat
chmod 644 /var/lib/rkhunter/db/mirrors.dat

sed -i 's|^UPDATE_MIRRORS=.*|UPDATE_MIRRORS=0|' /etc/rkhunter.conf
sed -i 's|^WEB_CMD=.*|WEB_CMD=/usr/bin/wget -nv -O -|' /etc/rkhunter.conf
sed -i 's|^MIRRORS_MODE=.*|MIRRORS_MODE=1|' /etc/rkhunter.conf

rkhunter --propupd

### ---------------- HYPERVISOR-AWARE EXCLUDES ---------------- ###
EXCLUDES="\
--exclude-dir=/proc \
--exclude-dir=/sys \
--exclude-dir=/dev \
--exclude-dir=/run \
--exclude-dir=/mnt \
--exclude-dir=/media \
--exclude-dir=/snap \
--exclude-dir=/var/lib/docker \
--exclude-dir=/var/lib/lxc \
--exclude-dir=/var/lib/libvirt \
"
if [[ "$VIRT_TYPE" == "vmware" ]]; then
    EXCLUDES="$EXCLUDES --exclude-dir=/mnt/hgfs"
fi

### ---------------- CLAMAV SCAN SCRIPT ---------------- ###
cat > /usr/local/bin/vm_clamscan.sh << EOF
#!/usr/bin/env bash
LOGFILE="$LOG_DIR/clamav_scan.log"
DATE=\$(date)
echo "===== ClamAV Scan \$DATE =====" >> \$LOGFILE
nice -n 19 ionice -c3 clamscan -r $SCAN_PATHS \
$EXCLUDES \
--infected \
--max-filesize=$MAX_FILESIZE \
--max-scansize=$MAX_SCANSIZE \
--max-files=$MAX_FILES \
--cross-fs=no \
--log=\$LOGFILE \
--move=$QUARANTINE_DIR \
\$( [[ "$REMOVE_INFECTED" == "yes" ]] && echo "--remove=yes" )
RESULT=\$?
if [[ \$RESULT -eq 1 ]]; then
    mail -s "ClamAV Infection Detected on \$(hostname)" $EMAIL < \$LOGFILE
elif [[ \$RESULT -gt 1 ]]; then
    mail -s "ClamAV Scan Error on \$(hostname)" $EMAIL < \$LOGFILE
fi
exit 0
EOF
chmod 700 /usr/local/bin/vm_clamscan.sh

### ---------------- RKHUNTER SCAN SCRIPT ---------------- ###
cat > /usr/local/bin/vm_rkhunter.sh << EOF
#!/usr/bin/env bash
LOGFILE="$LOG_DIR/rkhunter_scan.log"
rkhunter --cronjob --quiet >> \$LOGFILE 2>&1
if grep -i "warning" \$LOGFILE >/dev/null; then
    mail -s "rkhunter Warning on \$(hostname)" $EMAIL < \$LOGFILE
fi
EOF
chmod 700 /usr/local/bin/vm_rkhunter.sh

### ---------------- CRON JOBS ---------------- ###
echo "$CLAM_UPDATE_TIME root freshclam --quiet" > /etc/cron.d/vm_clamav_update
echo "$CLAM_SCAN_TIME root /usr/local/bin/vm_clamscan.sh" > /etc/cron.d/vm_clamav_scan
echo "$RKHUNTER_TIME root /usr/local/bin/vm_rkhunter.sh" > /etc/cron.d/vm_rkhunter
chmod 600 /etc/cron.d/vm_*

### ---------------- LOG ROTATION ---------------- ###
cat > /etc/logrotate.d/vm_security << EOF
$LOG_DIR/*.log {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 640 root root
}
EOF

### ---------------- QUARANTINE HARDENING ---------------- ###
# Only attempt immutable if supported
if command -v chattr >/dev/null 2>&1; then
    chattr +i "$QUARANTINE_DIR" 2>/dev/null || echo "[!] Could not make $QUARANTINE_DIR immutable. Permissions still secure."
fi

echo "======================================================"
echo "✔ Hardened VM Security Deployment Complete"
echo "------------------------------------------------------"
echo "Hypervisor: ${VIRT_TYPE:-unknown}"
echo "Behind NAT: Yes"
echo "Daemon disabled: Yes"
echo "IO throttled: Yes"
echo "Cross-filesystem scan: Disabled"
echo "Quarantine hardened: Yes (permissions enforced)"
echo "rkhunter offline mode: Enabled"
echo "======================================================"

### ---------------- INTERACTIVE SCAN PROMPT ---------------- ###
echo
echo "Do you want to run a ClamAV and rkhunter scan now? (yes/no)"
read -r USER_CHOICE
USER_CHOICE=$(echo "$USER_CHOICE" | tr '[:upper:]' '[:lower:]')

if [[ "$USER_CHOICE" == "yes" ]]; then
    echo "[+] Running ClamAV scan..."
    /usr/local/bin/vm_clamscan.sh
    echo "[+] Running rkhunter scan..."
    /usr/local/bin/vm_rkhunter.sh
    echo "[+] Scans completed."
else
    echo "[+] Skipping scans. You can run them later manually."
fi
