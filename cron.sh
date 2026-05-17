#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

echo "==> Registering cron for agent-admin"

# * * * * * 는 매분 실행을 의미합니다.
# bash -lc 로 실행하여 source 명령과 환경변수 적용을 안정적으로 처리합니다.
# stdout/stderr는 monitor-cron.out에 누적해 cron 실행 자체의 오류도 추적할 수 있게 합니다.
CRON_LINE="* * * * * bash -lc 'source /etc/profile.d/agent-env.sh && ${AGENT_HOME}/bin/monitor.sh' >> ${AGENT_LOG_DIR}/monitor-cron.out 2>&1"

# 현재 agent-admin의 crontab을 임시 파일로 저장합니다.
current_cron="$(mktemp)"
sudo -u agent-admin crontab -l > "${current_cron}" 2>/dev/null || true

# 기존 monitor.sh 줄 제거 (중복 방지)
grep -Fv "${AGENT_HOME}/bin/monitor.sh" "${current_cron}" > "${current_cron}.new" || true

# 새 규칙 추가 후 등록
echo "${CRON_LINE}" >> "${current_cron}.new"
sudo -u agent-admin crontab "${current_cron}.new"

# 임시 파일 정리
rm -f "${current_cron}" "${current_cron}.new"

echo "  -> cron registered for agent-admin (every minute)"