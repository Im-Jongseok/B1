#!/usr/bin/env bash

set -u

source /etc/profile.d/agent-env.sh

LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"

# 시작/종료 시간 인자 (선택)
# 사용법: bash report.sh [시작시간] [종료시간]
# 예: bash report.sh "2026-05-17 14:00:00" "2026-05-17 15:00:00"
START_TIME="${1:-}"
END_TIME="${2:-}"

if [ ! -f "$LOG_FILE" ]; then
  echo "ERROR: Log file not found: $LOG_FILE"
  exit 1
fi

# 시간 범위 필터링이 있으면 해당 구간만 추출, 없으면 전체 사용
filter_logs() {
  if [ -n "$START_TIME" ] && [ -n "$END_TIME" ]; then
    awk -v start="$START_TIME" -v end="$END_TIME" '
    {
      # [2026-05-17 14:00:05] 형태에서 타임스탬프 추출
      match($0, /\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]/, m)
      ts = m[1]
      if (ts >= start && ts <= end) print
    }' "$LOG_FILE"
  else
    cat "$LOG_FILE"
  fi
}

# 로그 데이터 추출
DATA="$(filter_logs)"

if [ -z "$DATA" ]; then
  echo "ERROR: No log data found"
  [ -n "$START_TIME" ] && echo "  Time range: $START_TIME ~ $END_TIME"
  exit 1
fi

# awk로 통계 계산
echo "$DATA" | awk '
BEGIN {
  cpu_sum = 0; cpu_max = -1; cpu_min = 9999
  mem_sum = 0; mem_max = -1; mem_min = 9999
  disk_sum = 0; disk_max = -1; disk_min = 9999
  count = 0
}
{
  # 로그 포맷: [YYYY-MM-DD HH:MM:SS] PID:... CPU:..% MEM:..% DISK_USED:..%
  match($0, /\[([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})\]/, ts_arr)
  timestamp = ts_arr[1]

  match($0, /CPU:([0-9.]+)%/, cpu_arr)
  match($0, /MEM:([0-9.]+)%/, mem_arr)
  match($0, /DISK_USED:([0-9.]+)%/, disk_arr)

  cpu = cpu_arr[1] + 0
  mem = mem_arr[1] + 0
  disk = disk_arr[1] + 0

  cpu_sum += cpu
  mem_sum += mem
  disk_sum += disk

  if (cpu > cpu_max) { cpu_max = cpu; cpu_max_ts = timestamp }
  if (cpu < cpu_min) { cpu_min = cpu; cpu_min_ts = timestamp }
  if (mem > mem_max) { mem_max = mem; mem_max_ts = timestamp }
  if (mem < mem_min) { mem_min = mem; mem_min_ts = timestamp }
  if (disk > disk_max) { disk_max = disk; disk_max_ts = timestamp }
  if (disk < disk_min) { disk_min = disk; disk_min_ts = timestamp }

  count++
}
END {
  if (count == 0) {
    print "ERROR: No valid log entries found"
    exit 1
  }

  print "====== STATISTICS REPORT ======"
  print "[CPU]"
  printf "Average : %.1f%%\n", cpu_sum / count
  printf "Maximum : %.1f%% at %s\n", cpu_max, cpu_max_ts
  printf "Minimum : %.1f%% at %s\n", cpu_min, cpu_min_ts
  print "[Memory]"
  printf "Average : %.1f%%\n", mem_sum / count
  printf "Maximum : %.1f%% at %s\n", mem_max, mem_max_ts
  printf "Minimum : %.1f%% at %s\n", mem_min, mem_min_ts
  print "[Disk]"
  printf "Average : %.1f%%\n", disk_sum / count
  printf "Maximum : %.1f%% at %s\n", disk_max, disk_max_ts
  printf "Minimum : %.1f%% at %s\n", disk_min, disk_min_ts
  print "[Samples]"
  printf "Data Points: %d samples\n", count
}'
