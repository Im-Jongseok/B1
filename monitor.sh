#!/usr/bin/env bash

set -u

source /etc/profile.d/agent-env.sh

APP_PATTERN="agent-app"
PORT="${AGENT_PORT:-15034}"
LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
MAX_SIZE=$((10 * 1024 * 1024))  # 10MB
MAX_FILES=10

# === 로그 로테이션 ===
rotate_logs() {
  if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -ge "$MAX_SIZE" ]; then
    for i in $(seq $((MAX_FILES - 1)) -1 1); do
      [ -f "${LOG_FILE}.${i}" ] && mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
    done
    mv "$LOG_FILE" "${LOG_FILE}.1"
    : > "$LOG_FILE"
  fi
}

# === 시스템 리소스 수집 ===
get_cpu_usage() {
  # /proc/stat 기반 측정 (0.5초 간격, watch 호환)
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle1=$((idle + iowait))
  sleep 0.5
  read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
  total2=$((user + nice + system + idle + iowait + irq + softirq + steal))
  idle2=$((idle + iowait))
  total_diff=$((total2 - total1))
  idle_diff=$((idle2 - idle1))
  awk -v total="$total_diff" -v idle="$idle_diff" 'BEGIN {
    if (total == 0) print "0.0";
    else printf "%.1f", (total - idle) * 100 / total
  }'
}

get_mem_usage() {
  free | awk '/Mem:/ { printf "%.1f", ($3 / $2) * 100 }'
}

get_disk_usage() {
  df / | awk 'NR==2 { gsub("%", "", $5); print $5 }'
}

# === 프로세스 리소스 수집 ===
get_proc_stats() {
  local pid="$1"
  ps -p "$pid" -o %cpu=,%mem=,rss= 2>/dev/null | awk '{
    rss_mb = $3 / 1024
    printf "P_CPU:%.1f%% P_MEM:%.1f%% RSS:%.0fMB", $1, $2, rss_mb
  }'
}

# === Health Check ===
echo "====== SYSTEM MONITOR RESULT ======"
echo
echo "[HEALTH CHECK]"

# pgrep -f로 매칭되는 PID 중 실제 워커(멀티스레드)를 우선 선택
# launcher(단일스레드)와 워커(멀티스레드)가 분리된 구조 대응
ALL_PIDS="$(pgrep -f "$APP_PATTERN" || true)"
if [ -z "$ALL_PIDS" ]; then
  echo "Checking process '$APP_PATTERN'... [FAIL]"
  exit 1
fi
PID=""
for p in $ALL_PIDS; do
  tc="$(ps -L -p "$p" --no-headers 2>/dev/null | wc -l)"
  if [ "$tc" -gt 1 ]; then
    PID="$p"
    break
  fi
done
# 멀티스레드 프로세스가 없으면 첫 번째 PID 사용
[ -z "$PID" ] && PID="$(echo "$ALL_PIDS" | head -n 1)"
echo "Checking process '$APP_PATTERN'... [OK] (PID: $PID)"

if ! ss -ltn | awk '{print $4}' | grep -q ":${PORT}$"; then
  echo "Checking port $PORT... [FAIL]"
  exit 1
fi
echo "Checking port $PORT... [OK]"

# === Firewall Check ===
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

# === System Resource ===
CPU="$(get_cpu_usage)"
MEM="$(get_mem_usage)"
DISK_USED="$(get_disk_usage)"

echo
echo "[SYSTEM RESOURCE]"
echo "CPU Usage : ${CPU}%"
echo "MEM Usage : ${MEM}%"
echo "DISK Used : ${DISK_USED}%"

# === Process Resource ===
PROC_STATS="$(get_proc_stats "$PID")"
if [ -z "$PROC_STATS" ]; then
  PROC_STATS="P_CPU:0.0% P_MEM:0.0% RSS:0MB"
fi

echo
echo "[PROCESS RESOURCE] (PID: $PID)"
echo "$PROC_STATS"

# === Deadlock Detection ===
# 프로세스의 모든 스레드가 S(sleeping) 상태이고 CPU 0.0%이면 Deadlock 의심
echo
echo "[DEADLOCK CHECK]"
DEADLOCK="false"
THREAD_COUNT="$(ps -L -p "$PID" --no-headers 2>/dev/null | wc -l)"
if [ "$THREAD_COUNT" -gt 1 ]; then
  # 멀티스레드인 경우: 모든 스레드의 CPU 사용률 합산
  THREAD_CPU_SUM="$(ps -L -p "$PID" -o %cpu= --no-headers 2>/dev/null | awk '{ sum += $1 } END { printf "%.1f", sum }')"
  THREAD_ALL_SLEEPING="$(ps -L -p "$PID" -o stat= --no-headers 2>/dev/null | grep -cv '^S')"
  if awk -v v="$THREAD_CPU_SUM" 'BEGIN { exit (v == 0.0) ? 0 : 1 }' && [ "$THREAD_ALL_SLEEPING" -eq 0 ]; then
    DEADLOCK="true"
    echo "[CRITICAL] Deadlock suspected! (${THREAD_COUNT} threads, all sleeping, CPU=0.0%)"
  else
    echo "Status... [OK] (${THREAD_COUNT} threads, CPU=${THREAD_CPU_SUM}%)"
  fi
else
  echo "Status... [OK] (single thread, skipped)"
fi

# === Threshold Warnings ===
echo
awk -v v="$CPU" 'BEGIN { if (v > 20) exit 0; exit 1 }' && echo "[WARNING] CPU threshold exceeded (${CPU}% > 20%)"
awk -v v="$MEM" 'BEGIN { if (v > 10) exit 0; exit 1 }' && echo "[WARNING] MEM threshold exceeded (${MEM}% > 10%)"
awk -v v="$DISK_USED" 'BEGIN { if (v > 80) exit 0; exit 1 }' && echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > 80%)"

# === Log ===
rotate_logs

TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
DEADLOCK_TAG=""
[ "$DEADLOCK" = "true" ] && DEADLOCK_TAG=" DEADLOCK:suspected"
echo "[$TIMESTAMP] PID:${PID} CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK_USED}% ${PROC_STATS}${DEADLOCK_TAG}" >> "$LOG_FILE"

echo
echo "[INFO] Log appended: $LOG_FILE"

# === Statistics Report ===
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "${SCRIPT_DIR}/report.sh" ]; then
  echo
  bash "${SCRIPT_DIR}/report.sh"
fi
