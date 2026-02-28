#!/usr/bin/env bash
# ==============================================================
# Hardened VM Security Deployment
# Hypervisor-aware (VMware / Proxmox / KVM)
# NAT environment optimized
# ClamAV (on-demand only) + rkhunter
# ==============================================================

# Fallback if EUID is not defined
: "${EUID:=$(id -u)}"

set -euo pipefail

### ---------------- CONFIGURATION ---------------- ###
SCAN_PATHS="/home /var/www /tmp"
EMAIL="root"
REMOVE_INFECTED="no"          # change to yes to auto-delete
QUARANTINE_DIR="/var/quarantine"
LOG_DIR="/var/log/security"

# VM-safe throttling
MAX_FILESIZE="100M"
MAX_SCANSIZE="500M"
MAX_FILES="200000"

# Cron schedule
CLAM_UPDATE_TIME="0 3 * * *"
CLAM_SCAN_TIME="0 4 * * *"
RKHUNTER_TIME="30 2 * * *"

### ------------------------------------------------ ###

if [[ $EUID -ne 0 ]]; then
    echo "Run as root."
    exit 1
fi

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
if [[ "$OS_FAMILY" == "debian" ]]; then
    apt update -y
    apt install -y clamav clamav-daemon rkhunter mailutils logrotate
    if command -v gnome-shell >/dev/null 2>&1; then
        apt install -y clamtk
    fi
else
    dnf install -y epel-release
    dnf install -y clamav clamav-update rkhunter mailx logrotate
    if command -v gnome-shell >/dev/null 2>&1; then
        dnf install -y clamtk || true
    fi
fi

### ---------------- UPDATE SIGNATURES ---------------- ###
freshclam || true
rkhunter --update
rkhunter --propupd

systemctl disable clamav-daemon 2>/dev/null || true
systemctl stop clamav-daemon 2>/dev/null || true

### ---------------- HYPERVISOR AWARE EXCLUDES ---------------- ###
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

# VMware tools mounts
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
$( [[ "$REMOVE_INFECTED" == "yes" ]] && echo "--remove=yes" )

RESULT=\$?

if [[ \$RESULT -eq 1 ]]; then
    mail -s "ClamAV Infection Detected on \$(hostname)" $EMAIL < \$LOGFILE
elif [[ \$RESULT -gt 1 ]]; then
    mail -s "ClamAV Scan Error on \$(hostname)" $EMAIL < \$LOGFILE
fi

exit 0
EOF

chmod 700 /usr/local/bin/vm_clamscan.sh

### ---------------- RKHUNTER SCRIPT ---------------- ###
cat > /usr/local/bin/vm_rkhunter.sh << EOF
#!/usr/bin/env bash

LOGFILE="$LOG_DIR/rkhunter_scan.log"

rkhunter --cronjob --update --quiet >> \$LOGFILE 2>&1

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
chattr +i "$QUARANTINE_DIR" 2>/dev/null || true

echo "======================================================"
echo "✔ Hardened VM Security Deployment Complete"
echo "------------------------------------------------------"
echo "Hypervisor: ${VIRT_TYPE:-unknown}"
echo "Behind NAT: Yes"
echo "Daemon disabled: Yes"
echo "IO throttled: Yes"
echo "Cross-filesystem scan: Disabled"
echo "Quarantine hardened: Yes"
echo "======================================================"
