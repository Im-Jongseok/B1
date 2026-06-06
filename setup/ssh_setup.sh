#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

echo "==> Configuring SSH"

# sshd 요구 사항
mkdir -p /run/sshd

# 기존 Port 설정이 있으면 교체하고, 없으면 새로 추가
if grep -qE '^#?Port ' /etc/ssh/sshd_config; then
  sed -i "s/^#\?Port .*/Port ${SSH_PORT}/" /etc/ssh/sshd_config
else
  echo "Port ${SSH_PORT}" >> /etc/ssh/sshd_config
fi

# root 원격 로그인을 차단합니다.
# 공격자가 root 계정으로 직접 브루트포스하는 위험을 줄이기 위한 기본 보안 설정입니다.
if grep -qE '^#?PermitRootLogin ' /etc/ssh/sshd_config; then
  sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
else
  echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

# 일부 클라우드 이미지, 특히 GCP Ubuntu 계열은 sshd_config.d/*.conf에서
# PasswordAuthentication 값을 다시 덮어쓸 수 있습니다.
# 본체 설정과 override 설정이 충돌하지 않도록 함께 보정합니다.
if [ -d /etc/ssh/sshd_config.d ]; then
  for f in /etc/ssh/sshd_config.d/*.conf; do
    [ -f "$f" ] && sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$f"
  done
fi

# 과제 계정(agent-admin/dev/test)으로 비밀번호 기반 접속을 확인할 수 있게 합니다.
if grep -qE '^#?PasswordAuthentication ' /etc/ssh/sshd_config; then
  sed -i 's/^#\?PasswordAuthentication .*/PasswordAuthentication yes/' /etc/ssh/sshd_config
else
  echo "PasswordAuthentication yes" >> /etc/ssh/sshd_config
fi

# Ubuntu 24.04에서는 ssh.socket이 포트 listen을 관리하는 경우가 있습니다.
# 이 경우 sshd_config만 바꿔도 실제 LISTEN 포트가 바뀌지 않을 수 있어
# systemd socket override를 함께 작성합니다.
if systemctl list-units --type=socket 2>/dev/null | grep -q ssh.socket; then
  echo "  -> Configuring ssh.socket override for port ${SSH_PORT}"
  mkdir -p /etc/systemd/system/ssh.socket.d
  cat > /etc/systemd/system/ssh.socket.d/override.conf <<SOCKETEOF
[Socket]
ListenStream=
ListenStream=0.0.0.0:${SSH_PORT}
ListenStream=[::]:${SSH_PORT} 
SOCKETEOF
  systemctl daemon-reload
  systemctl restart ssh.socket
  systemctl restart ssh || true
else
# ssh.socket을 쓰지 않는 환경에서는 ssh/sshd 서비스를 재시작합니다.
  if command -v systemctl >/dev/null 2>&1; then
    systemctl restart ssh || systemctl restart sshd || true
  else
    service ssh restart || service sshd restart || true
  fi
fi
