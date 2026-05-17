#!/usr/bin/env bash

set -euo pipefail

source "$(dirname "$0")/common_setup.sh"
require_root

# 전역 환경변수 export
echo "==> Writing environment variables"
cat > /etc/profile.d/agent-env.sh <<EOF
export AGENT_HOME=${AGENT_HOME}
export AGENT_PORT=${AGENT_PORT}
export AGENT_UPLOAD_DIR=\$AGENT_HOME/upload_files
export AGENT_KEY_PATH=\$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=${AGENT_LOG_DIR}
EOF
chmod 644 /etc/profile.d/agent-env.sh
