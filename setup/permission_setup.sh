#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

# 앱 실행에 필요한 디렉토리 구조를 만들고 권한을 적용합니다.
# 디렉토리별 소유자/그룹을 분리해 공유 영역과 민감 영역을 구분합니다.
echo "==> Creating directories and applying permissions"
mkdir -p "${AGENT_UPLOAD_DIR}" "${AGENT_HOME}/api_keys" "${AGENT_HOME}/bin" "${AGENT_LOG_DIR}"

# AGENT_HOME은 앱의 기준 디렉토리입니다.
# 소유자는 운영 계정 agent-admin이며, 다른 계정은 그룹 권한 없이는 접근하지 못하게 750을 사용합니다.
chown agent-admin:agent-common "${AGENT_HOME}"
chmod 750 "${AGENT_HOME}"

# upload_files는 agent-common 그룹이 읽고 쓸 수 있는 공유 업로드 영역입니다.
# admin/dev/test 모두 agent-common에 속하므로 공동 작업이 가능합니다.
chown agent-admin:agent-common "${AGENT_UPLOAD_DIR}"
chmod 770 "${AGENT_UPLOAD_DIR}"

# api_keys는 민감 정보가 들어가는 영역입니다.
# agent-core 그룹(admin/dev)만 접근 가능하게 제한하고 test 계정은 배제합니다.
chown agent-admin:agent-core "${AGENT_HOME}/api_keys"
chmod 770 "${AGENT_HOME}/api_keys"

# bin은 실행 파일과 monitor.sh가 들어가는 디렉토리입니다.
# agent-dev가 스크립트 관리 주체이고, agent-core 그룹이 실행할 수 있도록 750을 부여합니다.
chown agent-dev:agent-core "${AGENT_HOME}/bin"
chmod 750 "${AGENT_HOME}/bin"

# monitor.sh가 기록하는 로그 디렉토리입니다.
# cron 실행 계정(agent-admin)이 쓸 수 있고 agent-core 그룹이 확인할 수 있게 합니다.
chown agent-admin:agent-core "${AGENT_LOG_DIR}"
chmod 770 "${AGENT_LOG_DIR}"

# 앱 부팅 체크에서 요구하는 API key 파일을 생성합니다.
# 파일 자체는 agent-core 그룹까지만 읽고 쓸 수 있게 660으로 제한합니다.
echo "==> Creating API key"
printf '%s\n' "agent_api_key_test" > "${AGENT_KEY_PATH}"
chown agent-admin:agent-core "${AGENT_KEY_PATH}"
chmod 660 "${AGENT_KEY_PATH}"
