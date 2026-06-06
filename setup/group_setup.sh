#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

# 역할 기반 권한 관리를 위한 그룹을 생성
# agent-common: admin/dev/test가 공유 파일에 접근하는 공통 그룹
# agent-core: admin/dev만 민감한 파일(api_keys, 로그, 실행 파일)에 접근하는 제한 그룹
echo "==> Creating groups"
getent group agent-common >/dev/null || groupadd agent-common
getent group agent-core >/dev/null || groupadd agent-core
