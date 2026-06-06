#!/usr/bin/env bash

# 모든 setup 스크립트에서 공통으로 사용하는 변수 모음

APP_SOURCE="${1:-/tmp/agent-app}"
MONITOR_SOURCE="${MONITOR_SOURCE:-/tmp/monitor.sh}"

# 경로 변수
AGENT_HOME="/home/agent-admin/agent-app"
AGENT_PORT="15034"
AGENT_UPLOAD_DIR="${AGENT_HOME}/upload_files"
AGENT_KEY_PATH="${AGENT_HOME}/api_keys/t_secret.key"
AGENT_LOG_DIR="/var/log/agent-app"
SSH_PORT="20022"

# 시스템 계정 생성, /etc 수정, 방화벽, cron 등록은 root 권한이 필요합니다.
# 실수로 일반 사용자 권한에서 실행했을 때 중간에 애매하게 실패하지 않도록 먼저 차단합니다.
require_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: Run this script with sudo."
    exit 1
  fi
}

# 현재 스크립트가 있는 디렉토리를 반환합니다.
# setup.sh가 어느 위치에서 실행되더라도 같은 폴더의 분리 스크립트를 찾기 위한 보조 함수입니다.
script_dir() {
  cd "$(dirname "${BASH_SOURCE[0]}")" && pwd
}
