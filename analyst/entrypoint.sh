#!/usr/bin/env bash
set -euo pipefail

user_name="${ANALYST_USER:-analyst}"
user_password="${ANALYST_PASSWORD:-analyst123}"
group_name="${GROUP_NAME:-Workshop Group}"
group_id="${GROUP_ID:-0}"
web_port="${WEB_PORT:-5000}"
target_service="${TARGET_SERVICE:-helpdesk-group${group_id}}"

if ! id "$user_name" >/dev/null 2>&1; then
    useradd --create-home --shell /bin/bash "$user_name"
fi

echo "${user_name}:${user_password}" | chpasswd
passwd -l root >/dev/null 2>&1 || true

cat > /etc/sudoers.d/workshop-mitigation <<SUDOERS
${user_name} ALL=(root) NOPASSWD: /usr/local/bin/workshop-block-ip, /usr/local/bin/workshop-unblock-ip, /usr/local/bin/workshop-list-blocked
SUDOERS
chmod 0440 /etc/sudoers.d/workshop-mitigation
visudo -cf /etc/sudoers.d/workshop-mitigation >/dev/null

cat > /etc/workshop-mitigation.conf <<MITIGATION
GROUP_ID=${group_id}
WEB_PORT=${web_port}
TARGET_SERVICE=${target_service}
MITIGATION
chown root:root /etc/workshop-mitigation.conf
chmod 0644 /etc/workshop-mitigation.conf

install -d -m 0755 "/home/${user_name}"
cp /opt/workshop/README-WORKSHOP.md "/home/${user_name}/README-WORKSHOP.md"
chown "${user_name}:${user_name}" "/home/${user_name}/README-WORKSHOP.md"

cat > /etc/motd <<MOTD
${group_name} analyst container

Group ID: ${group_id}
Protected web app: http://<vps-ip>:${web_port}
Internal target service: http://${target_service}:5000

Start here:
  less ~/README-WORKSHOP.md
  ls -R /logs
  tail -f /logs/web/access.log
  curl -s http://${target_service}:5000/health

Security boundary:
  - /logs is mounted read-only.
  - Docker socket is not mounted.
  - Host iptables is not available here.
  - sudo is limited to workshop-block-ip, workshop-unblock-ip, and workshop-list-blocked.
MOTD

exec /usr/sbin/sshd -D -e
