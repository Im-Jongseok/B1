#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

# 과제 수행에 필요한 기본 패키지를 설치합니다.
# openssh-server: SSH 접속 및 포트 변경 검증
# cron: monitor.sh 매분 자동 실행
# acl(access control list): 권한/접근 제어 확장 가능
# iproute2/net-tools: ss, netstat 등 포트 확인 도구
# ufw/iptables: 방화벽 정책 설정
echo "==> Installing required packages"
apt-get update
apt-get install -y openssh-server sudo vim net-tools iproute2 cron acl python3 iptables ufw
