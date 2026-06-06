#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

# UFW 방화벽 정책을 구성.
# 외부에서 접근해야 하는 SSH(20022)와 앱 포트(15034)만 허용.
echo "==> Configuring UFW"
ufw --force reset
ufw default deny incoming
ufw default allow outgoing

ufw allow "${SSH_PORT}/tcp"
ufw allow "${AGENT_PORT}/tcp"
ufw --force enable