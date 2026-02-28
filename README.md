🛡 Enterprise VM Security Deployment

Hypervisor-aware, production-grade Linux security deployment script for virtual machines running on:

VMware

Proxmox VE

KVM

Designed for NAT-isolated environments, production servers, and enterprise Linux desktops.

🔐 Overview

This project provides a hardened, performance-optimized deployment script that installs and configures:

ClamAV (on-demand scanning only)

ClamTk (desktop systems only)

rkhunter

Daily signature updates

Daily scheduled scans

Secure quarantine handling

Email alerting

Log rotation

VM-aware performance throttling

This solution is specifically tuned for virtualized environments to avoid I/O storms and CPU contention on shared hypervisor storage.

🚀 Features
✔ Hypervisor-Aware

Detects virtualization automatically

Adjusts exclusions for:

VMware shared folders

Docker

LXC

libvirt

Mounted ISOs

Disables cross-filesystem scanning

✔ Production-Safe Performance Controls

nice 19

ionice -c3 (idle I/O class)

Maximum file size limit

Maximum total scan size limit

Maximum file count limit

Excludes virtual filesystems (/proc, /sys, /dev, /run)

✔ Security Hardening

ClamAV daemon disabled (no unnecessary service exposure)

On-demand scanning only

Immutable quarantine directory (chattr +i)

Root-only scan scripts

Hardened cron permissions

Log rotation (compressed, weekly)

✔ Email Alerts

Infection detected

Scan error

rkhunter warning

Alerts are sent to:

root

(Modify in configuration if needed.)

🖥 Supported Operating Systems

Automatically detects and supports:

Debian

Ubuntu

RHEL

AlmaLinux

Rocky Linux

CentOS

📦 Installation

Clone repository:

git clone https://github.com/yourorg/linux-vm-enterprise-antivirus.git
cd linux-vm-enterprise-antivirus

Make executable:

chmod +x secure_vm_hardened.sh

Run:

sudo ./secure_vm_hardened.sh
⚙ Configuration

Edit the configuration section at the top of the script:

SCAN_PATHS="/home /var/www /tmp"
EMAIL="root"
REMOVE_INFECTED="no"
Enable automatic removal instead of quarantine:
REMOVE_INFECTED="yes"
🗂 Default Scan Schedule
Task	Time	Tool
rkhunter check	02:30	rkhunter
Virus DB update	03:00	ClamAV
Malware scan	04:00	ClamAV

Cron files installed in:

/etc/cron.d/
🧠 Architecture Decisions
Why Disable ClamAV Daemon?

Reduced attack surface

No open sockets

No background CPU usage

Suitable for NAT-isolated environments

Why Use ionice Idle Class?

In shared storage hypervisors (VMware, Proxmox, KVM):

Prevents disk I/O starvation

Avoids noisy neighbor effects

Reduces latency impact on production workloads

Why Limit Scan Size?

Prevents:

Snapshot performance degradation

Backup interference

Storage controller overload

🔐 Quarantine Model

Infected files are moved to:

/var/quarantine

Permissions:

700

Immutable flag applied where supported

To remove immutable flag manually:

chattr -i /var/quarantine
📊 Logging

Logs stored in:

/var/log/security/

Rotated weekly via:

/etc/logrotate.d/vm_security

Retention:

8 compressed rotations

🔒 Security Scope

This tool is designed for:

Internal enterprise VMs

NAT-protected environments

Production workloads

Security baseline enforcement

This tool is NOT intended as a replacement for:

EDR platforms

SIEM systems

Advanced behavioral detection

📌 Recommended Add-Ons

For maximum enterprise security posture, consider adding:

AIDE (file integrity monitoring)

auditd baseline rules

Centralized syslog forwarding

Fail2ban

SELinux/AppArmor enforcement

Offline full weekly scan job

🛠 Repository Structure
.
├── secure_vm_hardened.sh
├── README.md
└── LICENSE
🧪 Testing

Tested on:

Ubuntu 22.04 LTS (VMware & Proxmox)

Debian 12

Rocky Linux 9 (KVM)

AlmaLinux 9

⚠ Limitations

Requires working mail system for alerts

Not optimized for container host deep scanning

Not designed for internet-facing gateway malware filtering

📜 License

MIT License (recommended for GitHub enterprise tooling)

🤝 Contributing

Contributions welcome.

Please ensure:

Code follows security best practices

No daemon exposure introduced

Performance safety preserved

Hypervisor awareness maintained

🛡 Enterprise Security Philosophy

This project follows principles of:

Minimal attack surface

Deterministic behavior

Explicit scheduling

Controlled resource usage

Least privilege

No unnecessary background services
