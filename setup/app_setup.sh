#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

# agent-app 바이너리를 표준 실행 위치에 설치합니다.
# install 명령은 복사와 동시에 소유자/그룹/권한을 지정할 수 있어
# cp 후 chown/chmod를 따로 실행하는 것보다 실수 가능성이 적습니다.
echo "==> Installing agent app"
if [ ! -f "${APP_SOURCE}" ]; then
  echo "ERROR: App binary not found: ${APP_SOURCE}"
  exit 1
fi

# 앱은 agent-admin이 실행하고 agent-core 그룹이 접근할 수 있게 배치합니다.
install -o agent-admin -g agent-core -m 750 "${APP_SOURCE}" "${AGENT_HOME}/bin/agent-app"

# monitor.sh는 cron이 매분 실행할 모니터링 스크립트입니다.
# 파일이 없더라도 전체 setup을 중단하지 않고, 나중에 복사할 수 있도록 안내만 출력합니다.
echo "==> Installing monitor.sh"
if [ -f "${MONITOR_SOURCE}" ]; then
  # 스크립트 작성/관리 주체는 agent-dev, 실행 가능 그룹은 agent-core로 둡니다.
  install -o agent-dev -g agent-core -m 750 "${MONITOR_SOURCE}" "${AGENT_HOME}/bin/monitor.sh"
fi
