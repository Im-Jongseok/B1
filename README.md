# 시스템 관제 스크립트 자동화

## mission
권한 관리, 네트워크 보안, 로그 자동화 쉘 스크립트 개발

## 기본 보안 및 네트워크 설정

**리눅스 VM 생성 및 실행**
    GCP Compute Engine
    ubuntu:24.04 LTS

**SSH?**
> Secure Shell: 암호화 기술을 사용하여 원격 컴퓨터에 안전하게 접속하고 명령을 실행하는 네트워크 프로토콜. 기본 포트(22). 
> 기존 rsh rcp, rlogin, rexec || telnet, ftp 등 remote 서비스의 보안 강화 

ssh 설정 변경
```bash
    > vim /etc/ssh/sshd_config
    Port 22 -> 20022
    PermitRootLogin no
```
```bash
    sudo sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config
    sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config
```

**UFW(Uncomplicated Firewall)**
> 사용하기 쉽게 설계된 넷필터 방화벽을 관리하는 프로그램. 

```bash
    # 기본 정책: 들어오는 트래픽 차단
    > sudo ufw default deny incoming
    > sudo ufw default allow outgoing

    # 허용 포트 설정
    > sudo ufw allow 20022/tcp
    > sudo ufw allow 15034/tcp

    # 방화벽 활성화
    > sudo ufw enable

    # 확인
    > sudo ufw status verbose
    Status: active
    Logging: on (low)
    Default: deny (incoming), allow (outgoing), disabled (routed)
    New profiles: skip

    To                         Action      From
    --                         ------      ----
    20022/tcp                  ALLOW IN    Anywhere
    15034/tcp                  ALLOW IN    Anywhere
    20022/tcp (v6)             ALLOW IN    Anywhere (v6)
    15034/tcp (v6)             ALLOW IN    Anywhere (v6)
```

### 계정/그룹/권한 체계

1. 그룹 생성
```bash
    > sudo groupadd agent-common
    > sudo groupadd agent-core
```
2. 계정 생성
```bash
    > useradd -D
    GROUP=100
    HOME=/home
    INACTIVE=-1
    EXPIRE=
    SHELL=/bin/sh
    SKEL=/etc/skel
    CREATE_MAIL_SPOOL=no

    > sudo useradd -m -s /bin/bash agent-admin
    > sudo useradd -m -s /bin/bash agent-dev
    > sudo useradd -m -s /bin/bash agent-test
```

**useradd 주요 옵션**

| 옵션 | 설명 |
|------|------|
| -d [디렉토리] | 사용자의 홈 디렉토리를 지정합니다. |
| -m | 사용자의 홈 디렉토리를 자동으로 생성합니다 (보통 -d와 함께 사용). |
| -s [쉘] | 로그인 쉘을 지정합니다 (예: /bin/bash). |
| -g [그룹] | 사용자의 기본 그룹(GID)을 지정합니다. |
| -G [그룹들] | 사용자가 속할 보조 그룹(들)을 지정합니다. |
| -p [비밀번호] | 암호화된 비밀번호를 직접 지정하여 계정을 생성합니다. |
| -e [YYYY-MM-DD] | 계정 만료일을 설정합니다. |
| -r | 시스템 계정(System Account)을 생성합니다. |
| -u [UID] | 사용자 ID(UID)를 직접 지정합니다. |
| -D | 사용자를 추가할 때 사용하는 기본 설정값(/etc/default/useradd)을 보여줍니다. |

3. 그룹 할당
```bash
    # agent-common: admin, dev, test
    sudo usermod -aG agent-common agent-admin
    sudo usermod -aG agent-common agent-dev
    sudo usermod -aG agent-common agent-test

    # agent-core: admin, dev
    sudo usermod -aG agent-core agent-admin
    sudo usermod -aG agent-core agent-dev
```
**확인**
```bash
    id agent-admin
    id agent-dev
    id agent-test
```
agent-admin: groups=agent-common,agent-core
agent-dev:   groups=agent-common,agent-core
agent-test:  groups=agent-common

4. 디렉토리 생성
```bash
    export AGENT_HOME=/home/agent-admin/agent-app #환경 변수 등록

    sudo mkdir -p $AGENT_HOME/upload_files
    sudo mkdir -p $AGENT_HOME/api_keys
    sudo mkdir -p $AGENT_HOME/bin
    sudo mkdir -p /var/log/agent-app
```
5. 권한 설정
```bash
    # AGENT_HOME 소유권
    sudo chown agent-admin:agent-admin $AGENT_HOME

    # upload_files: agent-common R/W
    sudo chown agent-admin:agent-common $AGENT_HOME/upload_files
    sudo chmod 770 $AGENT_HOME/upload_files

    # api_keys: agent-core ONLY R/W
    sudo chown agent-admin:agent-core $AGENT_HOME/api_keys
    sudo chmod 770 $AGENT_HOME/api_keys

    # /var/log/agent-app: agent-core ONLY R/W
    sudo chown agent-admin:agent-core /var/log/agent-app
    sudo chmod 770 /var/log/agent-app

    # bin 디렉토리
    sudo chown agent-dev:agent-core $AGENT_HOME/bin
    sudo chmod 750 $AGENT_HOME/bin
```
**권한 확인**
```bash
    sudo su - [user-name]   # 사용자 전환
    exit                    # logout

    ls -la $AGENT_HOME/
    ls -la /var/log/agent-app

    > sudo ls -la $AGENT_HOME/

    drwxrwx--- 2 agent-admin agent-core   4096 May 12 11:31 api_keys
    drwxr-x--- 2 agent-dev   agent-core   4096 May 12 11:31 bin
    drwxrwx--- 2 agent-admin agent-common 4096 May 12 11:31 upload_files
```

## 애플리케이션 실행 환경 구성

**환경 변수**
```bash
    > sudo vi /etc/profile.d/agent-env.sh
    > export AGENT_HOME=/home/agent-admin/agent-app
    > export AGENT_PORT=15034
    > export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
    > export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
    > export AGENT_LOG_DIR=/var/log/agent-app

```

**키 파일 생성**
```bash
    echo "agent_api_key_test" | sudo tee $AGENT_HOME/api_keys/t_secret.key
```

**앱 실행**
```bash
    local> scp -P 20022 ~/Documents/developer/codyssey/basic/B1-1/agent-app B1-1@8.228.249.92:/tmp/
    > ./agent-app &
    > bash monitor.sh
```

**monitor.sh**
```bash
    #!/usr/bin/env bash
    set -u

    source /etc/profile.d/agent-env.sh

    APP_PATTERN="agent-app"
    PORT="${AGENT_PORT:-15034}"
    LOG_FILE="${AGENT_LOG_DIR:-/var/log/agent-app}/monitor.log"
    MAX_SIZE=$((10 * 1024 * 1024)) #1,310,720
    MAX_FILES=10

    # 로그 로테이션: 10MB 초과 시 최대 10개 파일 유지
    rotate_logs() {
    if [ -f "$LOG_FILE" ] && [ "$(stat -c%s "$LOG_FILE")" -ge "$MAX_SIZE" ]; then
        for i in $(seq $((MAX_FILES - 1)) -1 1); do
        [ -f "${LOG_FILE}.${i}" ] && mv "${LOG_FILE}.${i}" "${LOG_FILE}.$((i + 1))"
        done
        mv "$LOG_FILE" "${LOG_FILE}.1"
        : > "$LOG_FILE"
    fi
    }

    get_cpu_usage() {
    read -r _ user nice system idle iowait irq softirq steal _ < /proc/stat
    total1=$((user + nice + system + idle + iowait + irq + softirq + steal))
    idle1=$((idle + iowait))

    sleep 1

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

    # === Health Check ===
    echo "====== SYSTEM MONITOR RESULT ======"
    echo
    echo "[HEALTH CHECK]"

    PID="$(pgrep -f "$APP_PATTERN" | head -n 1 || true)"
    if [ -z "$PID" ]; then
    echo "Checking process '$APP_PATTERN'... [FAIL]"
    exit 1
    fi
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
    awk -v v="$CPU" 'BEGIN { if (v > 20) exit 0; exit 1 }' && echo "[WARNING] CPU threshold exceeded (${CPU}% > 20%)"
    awk -v v="$MEM" 'BEGIN { if (v > 10) exit 0; exit 1 }' && echo "[WARNING] MEM threshold exceeded (${MEM}% > 10%)"
    awk -v v="$DISK_USED" 'BEGIN { if (v > 80) exit 0; exit 1 }' && echo "[WARNING] DISK threshold exceeded (${DISK_USED}% > 80%)"

    # === Log ===
    rotate_logs

    TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S')"
    echo "[$TIMESTAMP] PID:${PID} CPU:${CPU}% MEM:${MEM}% DISK_USED:${DISK_USED}%" >> "$LOG_FILE"

    echo
    echo "[INFO] Log appended: $LOG_FILE"
```

#### Verification commands
```bash
grep -E '(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep sshd"
ufw status"
id agent-admin && id agent-dev && id agent-test"
ls -ld ${AGENT_HOME} ${AGENT_UPLOAD_DIR} ${AGENT_HOME}/api_keys ${AGENT_HOME}/bin ${AGENT_LOG_DIR}"
sudo -u agent-admin bash -lc 'source /etc/profile.d/agent-env.sh && ${AGENT_HOME}/bin/agent-app'"
sudo -u agent-admin bash -lc 'source /etc/profile.d/agent-env.sh && ${AGENT_HOME}/bin/monitor.sh'"
sudo -u agent-admin crontab -l"
tail -n 10 ${AGENT_LOG_DIR}/monitor.log"
```
