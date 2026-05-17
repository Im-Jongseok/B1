#!/usr/bin/env bash

set -u
# -u: 정의되지 않은 변수를 사용하면 에러로 처리합니다.

# setup.sh에서 작성한 환경변수 파일을 로드합니다.
# AGENT_PORT, AGENT_LOG_DIR, AGENT_HOME 등을 사용하기 위함입니다.
source /etc/profile.d/agent-env.sh

APP_PATTERN="agent-app"
PORT="${AGENT_PORT:-15034}"
LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
MAX_SIZE=$((10 * 1024 * 1024))  # 10MB
MAX_FILES=10                     # 로테이션 최대 보관 파일 수

# 로그 로테이션: 10MB 초과 시 최대 10개 파일 유지
# monitor.log → monitor.log.1 → monitor.log.2 → ... → monitor.log.10
# 10번째 이후 파일은 자연스럽게 덮어씌워집니다.
rotate_logs() {
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -ge "$MAX_SIZE" ]; then
    for i in $(seq $((MAX_FILES - 1)) -1 1); do
      [ -f "${LOG_FILE}.${i}" ] && mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
    : > "$LOG_FILE"  # 빈 파일로 초기화
  fi
}

# top을 비대화형(-b)으로 2회(-n2) 실행하고 마지막 측정값을 사용합니다.
# 첫 번째 측정은 부팅 이후 누적값이라 부정확하므로 두 번째 값을 씁니다.
get_cpu_usage() {
  top -bn2 -d 1 | awk '/^%?Cpu/ { cpu=$2 } END { printf "%.1f", cpu }'
}

# free 명령의 Mem 행에서 사용량($3) / 전체($2) * 100 으로 퍼센트를 계산합니다.
get_mem_usage() {
  free | awk '/Mem:/ { printf "%.1f", ($3 / $2) * 100 }'
}

# 루트 파티션(/)의 사용률을 가져옵니다.
# df 출력의 5번째 컬럼이 "42%" 형태이므로 % 기호를 제거합니다.
get_disk_usage() {
  df / | awk 'NR==2 { gsub("%", "", $5); print $5 }'
}

# === Health Check ===
# 프로세스와 포트가 정상이 아니면 exit 1로 즉시 종료합니다.
echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

# pgrep -f: 명령줄 전체에서 패턴 검색. 없으면 빈 문자열.
PID="$(pgrep -f "$APP_PATTERN" | head -n 1 || true)"
if [ -z "$PID" ]; then
  echo "Checking process '$APP_PATTERN'... [FAIL]"
  exit 1
fi
echo "Checking process '$APP_PATTERN'... [OK] (PID: $PID)"

# ss -ltn: TCP LISTEN 상태 소켓 목록에서 해당 포트가 있는지 확인합니다.
if ! ss -ltn | awk '{print $4}' | grep -q ":${PORT}$"; then
  echo "Checking port $PORT... [FAIL]"
  exit 1
fi
echo "Checking port $PORT... [OK]"

# === Firewall Check ===
# 방화벽 비활성이어도 WARNING만 출력하고 스크립트는 계속 진행합니다.
echo
echo "[FIREWALL CHECK]"
if command -v ufw >/dev/null 2>&1; then
  if sudo ufw status 2>/dev/null | grep -q "Status: active"; then
    echo "UFW status... [OK]"
  else
    echo "[WARNING] UFW is inactive"
  fi
elif command -v firewall-cmd >/dev/null 2>&1; then
  if firewall-cmd --state 2>/dev/null | grep -q "running"; then
    echo "firewalld status... [OK]"
  else
    echo "[WARNING] firewalld is inactive"
  fi
else
  echo "[WARNING] No supported firewall command found"
fi

# === Resource Monitoring ===
CPU="$(get_cpu_usage)"
MEM="$(get_mem_usage)"
DISK_USED="$(get_disk_usage)"

echo
echo "[RESOURCE MONITORING]"
echo "CPU Usage : ${CPU}%"
echo "MEM Usage : ${MEM}%"
echo "DISK Used : ${DISK_USED}%"

# === Threshold Warnings ===
# bash는 소수점 비교를 지원하지 않아 awk로 비교합니다.
# 임계값 초과 시 WARNING 출력만 하고 종료하지 않습니다.
awk -v v="$CPU" 'BEGIN { if (v > 20) exit 0; exit 1 }' && echo "[WARNING] CPU threshold exceeded (${CPU}% > 20%)"
awk -v v="$MEM" 'BEGIN { if (v > 10) exit 0; exit 1 }' && echo "[WARNING] MEM threshold exceeded (${MEM}% > 10%)"
awk -v v="$DISK_USED" 'BEGIN { if (v > 80) exit 0; exit 1 }' && echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > 80%)"

# === Log ===
# 로그 파일 크기 체크 후 필요시 로테이션 수행
rotate_logs

# 로그 포맷: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
echo "[$TIMESTAMP] PID:${PID} CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK_USED}%" >> "$LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"

# === Statistics Report ===
# 로그 기록 후 report.sh를 호출해 누적 통계를 출력합니다.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/report.sh" ]; then
  echo
  bash "${SCRIPT_DIR}/report.sh"
fi
