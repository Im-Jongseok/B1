#!/usr/bin/env bash
# shebang입니다. PATH에서 bash를 찾아 이 파일을 bash 스크립트로 실행하게 합니다.

set -euo pipefail
# -e: 명령 실패 시 즉시 중단합니다.
# -u: 정의되지 않은 변수를 사용하면 에러로 처리합니다.
# -o pipefail: 파이프라인 중간 명령 실패도 전체 실패로 처리합니다.
# SSH 설정처럼 접속 경로에 영향을 주는 작업은 실패를 조기에 발견해야 합니다.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# agent-app 바이너리 위치입니다.
APP_SOURCE="${1:-/tmp/agent-app}"

# 시스템 설정을 변경하므로 root 권한 실행을 강제합니다.
source "${SCRIPT_DIR}/common_setup.sh"
  require_root

# 1. 패키지 설치하고
# 2. ssh 설정 후, 방화벽 설정
# 3. 그룹/계정/권한
# 4. 환경변수, 앱/모니터링 스크립트, cron 자동 실행 등록 순서로 진행합니다.
"${SCRIPT_DIR}/package_setup.sh" "${APP_SOURCE}"

"${SCRIPT_DIR}/ssh_setup.sh" "${APP_SOURCE}"
"${SCRIPT_DIR}/firewall_setup.sh" "${APP_SOURCE}"

"${SCRIPT_DIR}/group_setup.sh" "${APP_SOURCE}"
"${SCRIPT_DIR}/account_setup.sh" "${APP_SOURCE}"
"${SCRIPT_DIR}/permission_setup.sh" "${APP_SOURCE}"

"${SCRIPT_DIR}/env_setup.sh" "${APP_SOURCE}"
"${SCRIPT_DIR}/app_setup.sh" "${APP_SOURCE}"

# cron 등록은 setup에서 하지 않음 — agent-admin이 직접 등록
# sudo -u agent-admin crontab -e

echo
echo "==> Setup complete"
echo

# 설치 후 과제 증빙에 사용할 수 있는 확인 명령입니다.
echo "Verification commands:"
echo "  grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config"
echo "  ss -tulnp | grep sshd"
echo "  ufw status verbose"
echo "  id agent-admin && id agent-dev && id agent-test"
echo "  ls -ld ${AGENT_HOME} ${AGENT_UPLOAD_DIR} ${AGENT_HOME}/api_keys ${AGENT_HOME}/bin ${AGENT_LOG_DIR}"
echo "  sudo -u agent-admin bash -lc 'source /etc/profile.d/agent-env.sh && ${AGENT_HOME}/bin/agent-app'"
echo "  sudo -u agent-admin bash -lc 'source /etc/profile.d/agent-env.sh && ${AGENT_HOME}/bin/monitor.sh'"
echo "  sudo -u agent-admin crontab -l"
echo "  tail -n 10 ${AGENT_LOG_DIR}/monitor.log"
