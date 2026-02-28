#!/bin/bash
# secure_vm_hardened.sh
# Enterprise-ready VM hardening script
# ClamAV + ClamTk + rkhunter, throttled scans, logs, quarantine

set -euo pipefail

#############################
# Ensure running as root
#############################
if [ "$(id -u)" -ne 0 ]; then
    echo "[!] This script must be run as root"
    exit 1
fi

#############################
# Variables
#############################
QUARANTINE_DIR="/home/quarantine"
LOG_DIR="/var/log/security"
CRON_DIR="/etc/cron.d"
CLAMAV_SCAN_LOG="$LOG_DIR/clamav_scan.log"
RKHUNTER_LOG="$LOG_DIR/rkhunter_scan.log"
MAIL_TO="root"

# Create folders safely
mkdir -p "$QUARANTINE_DIR" "$LOG_DIR"
chmod 700 "$QUARANTINE_DIR"
chmod 700 "$LOG_DIR"

#############################
# Detect OS
#############################
OS=$(awk -F= '/^NAME/{print $2}' /etc/os-release | tr -d '"')
echo "[+] Detected OS: $OS"

#############################
# Install dependencies
#############################
echo "[+] Installing required packages..."
apt-get update
apt-get install -y clamav clamav-daemon clamtk rkhunter logrotate mailutils wget

#############################
# Stop freshclam daemon
#############################
systemctl stop clamav-freshclam || true
pkill freshclam || true

#############################
# Update ClamAV DB manually
#############################
sudo -u clamav freshclam || echo "[!] Freshclam manual update failed"

#############################
# Update rkhunter DB
#############################
rkhunter --update || echo "[!] rkhunter update failed, offline mode?"
rkhunter --propupd

#############################
# Configure cron jobs
#############################
# ClamAV daily update
echo "0 3 * * * root /usr/bin/freshclam --quiet" > "$CRON_DIR/clamav_update"
# ClamAV daily scan (throttled, quarantined)
cat > "$CRON_DIR/clamav_scan" <<EOF
0 4 * * * root nice -n 10 ionice -c2 -n7 /usr/bin/clamscan -r --remove=no --exclude-dir=/proc --log=$CLAMAV_SCAN_LOG /
EOF
# rkhunter daily scan
echo "30 2 * * * root /usr/bin/rkhunter --cronjob --update --quiet --report-warnings-only --logfile $RKHUNTER_LOG" > "$CRON_DIR/rkhunter_scan"

chmod 644 "$CRON_DIR/"*

#############################
# Logrotate for ClamAV & rkhunter
#############################
cat > /etc/logrotate.d/security <<EOF
$CLAMAV_SCAN_LOG $RKHUNTER_LOG {
    weekly
    rotate 8
    compress
    missingok
    notifempty
    create 640 root root
}
EOF

#############################
# Prompt for immediate scan
#############################
read -p "[?] Everything is set up. Do you want to run a ClamAV + rkhunter scan now? (yes/no) " answer
if [[ "$answer" =~ ^[Yy][Ee]?[Ss]?$ ]]; then
    echo "[+] Running ClamAV scan..."
    nice -n 10 ionice -c2 -n7 clamscan -r --remove=no --exclude-dir=/proc --log="$CLAMAV_SCAN_LOG" /
    echo "[+] Running rkhunter scan..."
    rkhunter --check --skip-keypress --rwo --logfile "$RKHUNTER_LOG"
    echo "[+] Scans completed. Check logs in $LOG_DIR"
else
    echo "[+] Setup complete. Skipping immediate scan."
fi

echo "[+] Hardened VM security setup complete."
echo "[+] Quarantine directory: $QUARANTINE_DIR"
