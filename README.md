# [B1-1] 시스템 관제 스크립트 자동화

![Ubuntu](https://img.shields.io/badge/Ubuntu_24.04-E95420?style=flat&logo=ubuntu&logoColor=white)
![GCP](https://img.shields.io/badge/GCP_Compute_Engine-4285F4?style=flat&logo=googlecloud&logoColor=white)
![Shell](https://img.shields.io/badge/Shell-4EAA25?style=flat&logo=gnubash&logoColor=white)

## Mission

GCP Compute Engine(Ubuntu 24.04) 위에 **계정/그룹/권한 관리**, **네트워크 보안(SSH·방화벽)**, **시스템 관제 자동화(모니터링·로그·cron)** 환경을 구축하고, 원커맨드 프로비저닝 쉘 스크립트를 개발한다.

## 목차

- [실습 환경](#실습-환경)
- [레포지토리 구조](#레포지토리-구조)
- [핵심 개념 정리](#핵심-개념-정리)
- [수행 내역](#수행-내역)
  - [1. 기본 보안 및 네트워크 설정](#1-기본-보안-및-네트워크-설정)
  - [2. 계정/그룹/권한 체계](#2-계정그룹권한-체계)
  - [3. 애플리케이션 실행 환경 구성](#3-애플리케이션-실행-환경-구성)
  - [4. 시스템 관제 자동화](#4-시스템-관제-자동화)
  - [5. 원커맨드 프로비저닝](#5-원커맨드-프로비저닝)
- [검증 명령](#검증-명령)

## 실습 환경

| 항목 | 내용 |
|------|------|
| OS | Ubuntu 24.04 LTS |
| 인프라 | GCP Compute Engine |
| SSH 포트 | 20022 (기본 22에서 변경) |
| 앱 포트 | 15034 |
| 실행 바이너리 | `agent-app` |
| 관제 스크립트 | `monitor.sh`, `report.sh` |
| 자동 실행 | cron (매분) |

## 레포지토리 구조

```
B1-1/
├── setup/                    # 프로비저닝 스크립트 모음
│   ├── setup.sh              # 원커맨드 진입점 (전체 실행)
│   ├── common_setup.sh       # 공통 변수·함수 (require_root, 경로 상수)
│   ├── package_setup.sh      # 패키지 설치
│   ├── ssh_setup.sh          # SSH 포트 변경·Root 로그인 차단
│   ├── firewall_setup.sh     # UFW 방화벽 설정
│   ├── group_setup.sh        # 그룹 생성 (agent-common, agent-core)
│   ├── account_setup.sh      # 계정 생성 (agent-admin, agent-dev, agent-test)
│   ├── permission_setup.sh   # 디렉토리·권한 설정
│   ├── env_setup.sh          # 환경변수 등록 (/etc/profile.d/agent-env.sh)
│   ├── app_setup.sh          # 바이너리·스크립트 배포
│   └── cron.sh               # cron 자동 등록
├── app/
│   ├── agent-app             # 실행 바이너리 (B1-1)
│   └── agent-app-leak        # 실행 바이너리 (B1-2, 장애 시뮬레이션)
├── monitor.sh                # 시스템 관제 스크립트
└── report.sh                 # 통계 리포트 스크립트
```

## 핵심 개념 정리

### SSH (Secure Shell)

- 암호화 기술을 사용하여 원격 컴퓨터에 안전하게 접속하고 명령을 실행하는 네트워크 프로토콜
- 기존 `rsh`, `telnet`, `ftp` 등 평문 전송 프로토콜의 보안 강화 대체
- 기본 포트(22)를 비표준 포트로 변경하여 **무차별 대입 공격(Brute-force)** 감소
- Root 직접 로그인 차단으로 **권한 상승 공격** 방지

### UFW (Uncomplicated Firewall)

- Linux `iptables`/`nftables`를 간편하게 관리하는 방화벽 도구
- 기본 정책: 인바운드 차단(`deny incoming`), 아웃바운드 허용(`allow outgoing`)
- 허용 포트만 명시적으로 개방하는 **화이트리스트** 방식

### cron

- 지정된 시간 간격으로 명령을 자동 실행하는 Linux 스케줄러
- `* * * * *` (분 시 일 월 요일) 형식으로 주기 설정
- 이 과제에서는 `monitor.sh`를 **매분** 실행하여 관제 로그 자동 수집

### 로그 로테이션

- 로그 파일이 무한히 커지는 것을 방지하는 관리 기법
- `monitor.log`가 10MB 초과 시 `.1`, `.2`, ... `.10`까지 순환 보관
- 최대 10개 파일 유지, 가장 오래된 파일은 자동 삭제

### 환경변수와 `/etc/profile.d/`

- `/etc/profile.d/*.sh`에 등록한 환경변수는 **모든 사용자**의 로그인 시 자동 적용
- 개별 사용자 `~/.bashrc`와 달리 시스템 전역 설정으로, 계정 간 일관성 보장

## 수행 내역

### 1. 기본 보안 및 네트워크 설정

#### SSH 설정 변경

##### 실행 명령

```bash
# 포트 변경: 22 → 20022 (기본 포트 스캔 회피)
sudo sed -i 's/^#\?Port .*/Port 20022/' /etc/ssh/sshd_config

# Root 직접 로그인 차단
sudo sed -i 's/^#\?PermitRootLogin .*/PermitRootLogin no/' /etc/ssh/sshd_config

# sshd 재시작
sudo systemctl restart sshd
```

##### 확인 결과

```bash
$ grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
Port 20022
PermitRootLogin no

$ ss -tulnp | grep sshd
tcp  LISTEN  0  128  0.0.0.0:20022  0.0.0.0:*  users:(("sshd",pid=...))
```

##### 정리

- SSH 포트를 22 → 20022로 변경하여 기본 포트 스캔 공격 감소
- Root 직접 로그인 차단, 일반 계정 → `sudo` 경유 방식 적용

#### UFW 방화벽 설정

##### 실행 명령

```bash
# 기본 정책: 인바운드 차단, 아웃바운드 허용
sudo ufw default deny incoming
sudo ufw default allow outgoing

# 허용 포트 설정
sudo ufw allow 20022/tcp   # SSH
sudo ufw allow 15034/tcp   # agent-app

# 방화벽 활성화
sudo ufw enable
```

##### 확인 결과

```bash
$ sudo ufw status verbose
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

##### 정리

- SSH(20022)와 앱(15034)만 인바운드 허용, 나머지 모든 포트 차단
- IPv4 / IPv6 모두 동일 정책 적용

### 2. 계정/그룹/권한 체계

#### 그룹 생성

```bash
sudo groupadd agent-common   # 전체 계정 공통 그룹
sudo groupadd agent-core     # 핵심 계정 전용 그룹
```

#### 계정 생성

```bash
sudo useradd -m -s /bin/bash agent-admin   # 운영 관리자
sudo useradd -m -s /bin/bash agent-dev     # 개발자
sudo useradd -m -s /bin/bash agent-test    # 테스터
```

<details>
<summary>useradd 주요 옵션</summary>

| 옵션 | 설명 |
|------|------|
| `-m` | 홈 디렉토리 자동 생성 |
| `-s [쉘]` | 로그인 쉘 지정 (예: `/bin/bash`) |
| `-g [그룹]` | 기본 그룹(GID) 지정 |
| `-G [그룹들]` | 보조 그룹 지정 |
| `-d [경로]` | 홈 디렉토리 경로 지정 |
| `-r` | 시스템 계정 생성 |
| `-D` | 기본 설정값(`/etc/default/useradd`) 확인 |

</details>

#### 그룹 할당

```bash
# agent-common: admin, dev, test 전원
sudo usermod -aG agent-common agent-admin
sudo usermod -aG agent-common agent-dev
sudo usermod -aG agent-common agent-test

# agent-core: admin, dev만
sudo usermod -aG agent-core agent-admin
sudo usermod -aG agent-core agent-dev
```

##### 확인 결과

```
agent-admin: groups=agent-common,agent-core
agent-dev:   groups=agent-common,agent-core
agent-test:  groups=agent-common
```

#### 디렉토리 구조 및 권한

```bash
AGENT_HOME=/home/agent-admin/agent-app

sudo mkdir -p $AGENT_HOME/upload_files
sudo mkdir -p $AGENT_HOME/api_keys
sudo mkdir -p $AGENT_HOME/bin
sudo mkdir -p /var/log/agent-app
```

##### 권한 설정

```bash
sudo chown agent-admin:agent-admin  $AGENT_HOME
sudo chown agent-admin:agent-common $AGENT_HOME/upload_files && sudo chmod 770 $AGENT_HOME/upload_files
sudo chown agent-admin:agent-core   $AGENT_HOME/api_keys     && sudo chmod 770 $AGENT_HOME/api_keys
sudo chown agent-admin:agent-core   /var/log/agent-app        && sudo chmod 770 /var/log/agent-app
sudo chown agent-dev:agent-core     $AGENT_HOME/bin           && sudo chmod 750 $AGENT_HOME/bin
```

##### 확인 결과

```bash
$ sudo ls -la $AGENT_HOME/
drwxrwx--- 2 agent-admin agent-core   4096 May 12 11:31 api_keys
drwxr-x--- 2 agent-dev   agent-core   4096 May 12 11:31 bin
drwxrwx--- 2 agent-admin agent-common 4096 May 12 11:31 upload_files
```

##### 접근 권한 매트릭스

| 디렉토리 | 소유자 | 그룹 | 권한 | admin | dev | test |
|----------|--------|------|------|-------|-----|------|
| `upload_files` | agent-admin | agent-common | 770 | R/W | R/W | R/W |
| `api_keys` | agent-admin | agent-core | 770 | R/W | R/W | **X** |
| `bin` | agent-dev | agent-core | 750 | R/X | R/X | **X** |
| `/var/log/agent-app` | agent-admin | agent-core | 770 | R/W | R/W | **X** |

### 3. 애플리케이션 실행 환경 구성

#### 환경변수 등록

```bash
# /etc/profile.d/agent-env.sh (시스템 전역)
export AGENT_HOME=/home/agent-admin/agent-app
export AGENT_PORT=15034
export AGENT_UPLOAD_DIR=$AGENT_HOME/upload_files
export AGENT_KEY_PATH=$AGENT_HOME/api_keys/t_secret.key
export AGENT_LOG_DIR=/var/log/agent-app
```

#### 키 파일 생성

```bash
echo "agent_api_key_test" | sudo tee $AGENT_HOME/api_keys/t_secret.key
```

#### 앱 배포 및 실행

```bash
# 로컬 → VM 전송
scp -P 20022 agent-app agent-admin@<VM_IP>:/tmp/

# VM에서 실행
sudo cp /tmp/agent-app $AGENT_HOME/bin/
sudo chmod +x $AGENT_HOME/bin/agent-app
./agent-app &
```

### 4. 시스템 관제 자동화

#### monitor.sh 주요 기능

| 기능 | 설명 |
|------|------|
| Health Check | 프로세스 존재 여부(`pgrep`), 포트 리스닝 확인(`ss`) |
| Firewall Check | UFW/firewalld 활성 상태 확인 |
| Resource Monitoring | CPU(`/proc/stat` 기반), MEM(`free`), DISK(`df`) |
| Process Resource | 프로세스별 CPU, MEM, RSS 수집 |
| Deadlock Detection | 멀티스레드 전체 Sleeping + CPU 0% 감지 |
| Threshold Warning | CPU > 20%, MEM > 10%, DISK > 80% 경고 |
| Log Rotation | 10MB 초과 시 최대 10개 파일 순환 보관 |
| Statistics Report | `report.sh` 호출하여 CPU/MEM/DISK 통계 출력 |

#### 로그 포맷

```
[2026-05-17 14:00:05] PID:12345 CPU:2.3% MEM:5.1% DISK_USED:42% P_CPU:1.2% P_MEM:3.4% RSS:128MB
```

#### report.sh — 통계 리포트

`monitor.log`를 파싱하여 CPU/MEM/DISK의 평균·최대·최소·시간대를 출력한다.

```bash
# 전체 기간 통계
bash report.sh

# 특정 구간 통계
bash report.sh "2026-05-17 14:00:00" "2026-05-17 15:00:00"
```

<details>
<summary>출력 예시</summary>

```
====== STATISTICS REPORT ======
[CPU]
Average : 3.2%
Maximum : 15.1% at 2026-05-17 14:32:05
Minimum : 0.5% at 2026-05-17 14:01:05
[Memory]
Average : 5.8%
Maximum : 8.2% at 2026-05-17 14:45:05
Minimum : 4.1% at 2026-05-17 14:00:05
[Disk]
Average : 42.0%
Maximum : 42.0% at 2026-05-17 14:00:05
Minimum : 42.0% at 2026-05-17 14:00:05
[Samples]
Data Points: 60 samples
```

</details>

#### cron 자동 실행

```bash
# agent-admin 사용자의 crontab에 등록
* * * * * bash -lc 'source /etc/profile.d/agent-env.sh && /home/agent-admin/agent-app/bin/monitor.sh' >> /var/log/agent-app/monitor-cron.out 2>&1
```

- 매분 `monitor.sh` 실행 → `monitor.log`에 관제 데이터 자동 축적
- `monitor-cron.out`에 cron 실행 자체의 stdout/stderr 기록 (디버깅용)

### 5. 원커맨드 프로비저닝

```bash
# VM에 스크립트 전송 후 실행
sudo bash setup/setup.sh /tmp/agent-app
```

`setup.sh`가 아래 순서로 모든 설정을 자동 수행:

```
package_setup.sh → ssh_setup.sh → firewall_setup.sh
→ group_setup.sh → account_setup.sh → permission_setup.sh
→ env_setup.sh → app_setup.sh
```

## 검증 명령

<details>
<summary>전체 검증 명령 보기</summary>

```bash
# SSH 설정
grep -E '^(Port|PermitRootLogin)' /etc/ssh/sshd_config
ss -tulnp | grep sshd

# 방화벽
sudo ufw status verbose

# 계정/그룹
id agent-admin && id agent-dev && id agent-test

# 디렉토리 권한
ls -ld $AGENT_HOME $AGENT_UPLOAD_DIR $AGENT_HOME/api_keys $AGENT_HOME/bin $AGENT_LOG_DIR

# 앱 실행
sudo -u agent-admin bash -lc 'source /etc/profile.d/agent-env.sh && $AGENT_HOME/bin/agent-app'

# 관제 스크립트
sudo -u agent-admin bash -lc 'source /etc/profile.d/agent-env.sh && $AGENT_HOME/bin/monitor.sh'

# cron 확인
sudo -u agent-admin crontab -l

# 로그 확인
tail -n 10 $AGENT_LOG_DIR/monitor.log
```

</details>

---

# [B1-2] 리눅스 프로세스 및 시스템 리소스 트러블슈팅


## Mission

`agent-app-leak` 실행 중 발생하는 3가지 시스템 장애(OOM, CPU Spike, Deadlock)를 분석하고, GitHub Issue 형태의 기술 리포트 3건을 작성한다.

> **선행 미션**: [B1-1 시스템 관제 자동화 스크립트 개발](#b1-1-시스템-관제-스크립트-자동화)에서 구성한 GCP VM 환경을 그대로 사용한다.

## 목차

- [개발 환경](#개발-환경)
- [B1-1 대비 변경 사항](#b1-1-대비-변경-사항)
- [핵심 개념](#핵심-개념)
  - [Memory Leak / OOM](#memory-leak--oom-out-of-memory)
  - [CPU Spike / Watchdog](#cpu-spike--watchdog)
  - [Deadlock](#deadlock-교착상태)
- [스케줄링 알고리즘 추론 (보너스)](#스케줄링-알고리즘-추론-보너스)

## 개발 환경

| 항목 | 내용 |
|------|------|
| OS | Ubuntu 24.04 LTS |
| 인프라 | GCP Compute Engine |
| 실행 바이너리 | `agent-app-leak` |
| 관제 스크립트 | `monitor.sh` |

## B1-1 대비 변경 사항

| 항목 | B1-1 | B1-2 |
|------|------|------|
| 실행 바이너리 | `agent-app` | `agent-app-leak` |
| AGENT_KEY_PATH | `$AGENT_HOME/api_keys/t_secret.key` | `$AGENT_HOME/api_keys` (디렉토리) |
| 추가 환경변수 | - | `MEMORY_LIMIT`, `CPU_MAX_OCCUPY`, `MULTI_THREAD_ENABLE` |

## 실습 환경 (환경변수)

| 항목 | 조건 |
|------|------|
| 실행 계정 | `agent-admin`, `agent-dev`, `agent-test` |
| AGENT_HOME | `/home/agent-admin/agent-app` |
| AGENT_PORT | 15034 |
| AGENT_UPLOAD_DIR | `$AGENT_HOME/upload_files` |
| AGENT_KEY_PATH | `$AGENT_HOME/api_keys` |
| AGENT_LOG_DIR | `/var/log/agent-app` |
| MEMORY_LIMIT | 정수, 50~512 범위 (단위: MB) |
| CPU_MAX_OCCUPY | 정수, 10~100 범위 (단위: %) |
| MULTI_THREAD_ENABLE | true / false (1 / 0, yes / no 허용) |
| secret.key | `$AGENT_HOME/api_keys/secret.key` (내용: `agent_api_key_test`) |
| 네트워크 | `0.0.0.0:15034` |

## 핵심 개념

### Memory Leak / OOM (Out of Memory)

#### 개념

- 프로세스가 Heap 메모리에서 `malloc()`/`new`로 할당한 데이터를 `free()`/`delete` 없이 방치하면, 사용하지 않는 메모리가 계속 누적된다
- 시간이 지날수록 물리 메모리(RAM)를 고갈시켜 시스템 전체가 불안정해진다
- Linux 커널의 **OOM Killer**는 메모리 부족 시 가장 많은 메모리를 사용하는 프로세스를 강제 종료(SIGKILL)한다

#### agent-app-leak에서의 동작

| 구성 요소 | 역할 |
|----------|------|
| `MemoryWorker` | 3초마다 25MB씩 Heap 할당 (해제하지 않음) |
| `MemoryGuard` | `MEMORY_LIMIT` 초과 감지 시 SIGKILL로 자기 종료 |
| `MEMORY_LIMIT` | 허용 메모리 상한 (환경변수, MB 단위) |

### CPU Spike / Watchdog

#### 개념

- 특정 프로세스가 CPU 시간을 과도하게 점유하면, 다른 프로세스가 CPU를 할당받지 못해 시스템 전체 응답 지연(Latency)이 발생한다
- 원인: 무한 루프, 과도한 연산, 비효율적인 알고리즘, 스핀락(Spinlock) 등
- 정상 프로세스: CPU 사용률이 일정 범위 내에서 변동
- CPU Spike: CPU 사용률이 임계치 초과 시 Watchdog이 개입

#### Watchdog 동작 원리

- Watchdog은 하드웨어/소프트웨어 타이머로, 시스템이 정상 동작하는지 주기적으로 감시
- 임계치(`CPU_MAX_OCCUPY`) 초과 시 SIGTERM으로 프로세스에 정상 종료를 요청

#### SIGKILL vs SIGTERM

| 시그널 | 번호 | 특징 | 사용 사례 |
|--------|------|------|----------|
| SIGTERM | 15 | 정상 종료 요청, 프로세스가 cleanup 가능 | Watchdog, `kill <PID>` |
| SIGKILL | 9 | 강제 즉시 종료, 프로세스가 무시 불가 | OOM Killer, `kill -9` |

### Deadlock (교착상태)

#### 개념

- 두 개 이상의 스레드/프로세스가 서로 상대방이 보유한 자원을 무한히 기다리며 **영원히 진행하지 못하는 상태**
- Deadlock에 빠진 프로세스는 종료되지 않고(PID 존재) CPU/MEM 변화도 없으며 로그 출력도 멈춘다

#### 식사하는 철학자들 문제 (Dining Philosophers Problem)

- 5명의 철학자가 원탁에 앉아 있고, 양쪽 포크 2개를 모두 집어야 식사 가능
- 모든 철학자가 동시에 왼쪽 포크를 집으면 → 아무도 오른쪽 포크를 못 집음 → **Deadlock**

#### 교착상태 4대 조건 (Coffman Conditions)

4가지 조건이 **모두** 동시에 성립할 때 Deadlock이 발생한다. 하나라도 깨뜨리면 예방 가능.

| 조건 | 설명 | agent-app-leak 사례 |
|------|------|---------------------|
| 상호 배제 (Mutual Exclusion) | 자원은 한 번에 하나의 스레드만 사용 가능 | `Shared_Memory_A`, `Socket_Pool_B` 각각 단독 점유 |
| 점유 대기 (Hold and Wait) | 자원을 보유한 채로 다른 자원 요청 | Thread-1이 A를 보유한 채 B를 요청 |
| 비선점 (No Preemption) | 다른 스레드가 보유한 자원을 강제로 빼앗을 수 없음 | Thread-2의 B를 Thread-1이 강제 획득 불가 |
| 순환 대기 (Circular Wait) | 스레드들이 원형으로 서로의 자원을 대기 | T1→B→T2→A→T1 순환 고리 |

#### Deadlock vs 정상 상태 비교

| 항목 | 정상 실행 | Deadlock |
|------|---------|----------|
| PID | 존재 | 존재 |
| CPU 사용률 | 변동 있음 | 0% (고정) |
| MEM 사용률 | 변동 있음 | 고정 |
| 로그 출력 | 계속 기록 | 마지막 `BLOCKED`에서 멈춤 |
| 프로세스 상태 | `S` (sleeping) / `R` (running) | `S` (sleeping) - 깨어나지 않음 |

#### Mutex와 Semaphore

Deadlock은 **동기화 도구**의 잘못된 사용에서 발생한다. 대표적인 동기화 도구가 Mutex와 Semaphore이다.

##### Mutex (Mutual Exclusion)

- **1개의 스레드**만 자원에 접근 가능한 **이진 잠금장치**
- Lock을 건 스레드만 Unlock 가능 (소유권 개념)

```
Thread-1            Mutex             Thread-2
   │                 │                   │
   ├── Lock() ──────→│                   │
   │            [잠금: Thread-1]          │
   │    (작업 중)      │←─── Lock() ──────┤
   │                 │   (BLOCKED 대기)   │
   ├── Unlock() ────→│                   │
   │            [해제] ──────────────────→│
   │                 │            [잠금: Thread-2]
   │                 │              (작업 중)
```

##### Semaphore

- **N개의 스레드**가 동시에 자원에 접근 가능한 **카운터 기반 잠금장치**
- 소유권 개념이 없음 (다른 스레드가 Signal 가능)

```
Semaphore (count=2, 최대 2개 동시 접근)

Thread-1 ── Wait() → count: 2→1  [진입] ─── 작업 중
Thread-2 ── Wait() → count: 1→0  [진입] ─── 작업 중
Thread-3 ── Wait() → count: 0    [BLOCKED] ── 대기
                        │
Thread-1 ── Signal() → count: 0→1
                        └──────→ Thread-3 [진입]
```

##### Mutex vs Semaphore 비교

| 항목 | Mutex | Semaphore |
|------|-------|-----------|
| 동시 접근 수 | **1**개만 | **N**개 (카운터 설정) |
| 소유권 | 있음 (Lock한 스레드만 Unlock 가능) | 없음 (다른 스레드가 Signal 가능) |
| 용도 | 임계 영역 보호 (상호 배제) | 자원 풀 관리 (DB 커넥션 풀, 스레드 풀) |
| Deadlock 위험 | 높음 (Lock 순서 문제) | 낮지만 가능 (Wait 순서 문제) |
| 비유 | 화장실 열쇠 1개 (한 명만 사용) | 주차장 (N칸, 카운터로 관리) |

<details>
<summary>agent-app-leak에서의 동기화</summary>

```
[System] CAUTION: Strict resource locking is enabled.
```

- `Shared_Memory_A`, `Socket_Pool_B` 각각 **Mutex**로 보호
- `LOCK ACQUIRED` = Mutex Lock 성공
- `WAITING... BLOCKED` = Mutex Lock 실패, 대기 중
- `futex_` (WCHAN) = Linux 커널의 **Fast Userspace Mutex** 구현체에서 대기 중

```
Thread-1: Mutex_A.lock()  → Mutex_B.lock()  (Thread-2 소유)
Thread-2: Mutex_B.lock()  → Mutex_A.lock()  (Thread-1 소유)
→ 두 Mutex가 교차 잠금 → Deadlock
```

</details>

<details>
<summary>Mutex로 Deadlock을 방지하는 방법</summary>

```
[잘못된 사용] - Deadlock 발생
Thread-1: lock(A) → lock(B)
Thread-2: lock(B) → lock(A)   ← 순서가 반대

[올바른 사용] - Lock Ordering
Thread-1: lock(A) → lock(B)
Thread-2: lock(A) → lock(B)   ← 순서 통일

[Semaphore 활용] - 동시 접근 허용
Semaphore(2)로 A, B를 하나의 자원 그룹으로 관리
→ 두 자원을 한 번에 획득하거나, 둘 다 실패
→ 점유 대기(Hold and Wait) 제거
```

</details>

#### Deadlock 예방/회피 전략

| 전략 | 방법 | 트레이드오프 |
|------|------|------------|
| 순서 강제 (Lock Ordering) | 모든 스레드가 자원을 동일한 순서로 요청 | 순환 대기 제거, 설계 복잡도 증가 |
| 타임아웃 (Try-Lock with Timeout) | 일정 시간 내 자원 획득 실패 시 보유 자원 해제 후 재시도 | 점유 대기 제거, Livelock 가능성 |
| 단일 스레드 (Single Thread) | 멀티스레드 비활성화 (`MULTI_THREAD_ENABLE=false`) | Deadlock 원천 차단, 동시성/성능 포기 |
| 자원 한 번에 요청 | 필요한 자원을 모두 한꺼번에 요청 | 점유 대기 제거, 자원 활용률 저하 |

## 스케줄링 알고리즘 추론 (보너스)

> 실행 조건: `MULTI_THREAD_ENABLE=false`, `MEMORY_LIMIT=512`, `CPU_MAX_OCCUPY=50`
> 정상 실행(Healthy System Monitoring) 상태에서 Worker 스레드 로그를 수집하여 분석

### 1. 로그 수집

<details>
<summary>전체 로그 보기</summary>

```
2026-06-05 12:03:50,764 [INFO] [Scheduler] Task Scheduler Initialized.
2026-06-05 12:03:50,765 [INFO] [Scheduler] Registered Tasks: ['Thread-A', 'Thread-B', 'Thread-C']
2026-06-05 12:03:50,765 [INFO] [Scheduler] Starting task execution...
2026-06-05 12:03:50,765 [INFO] [Thread-A] Task Started. Calculating... (20%)
2026-06-05 12:03:50,815 [INFO] [Thread-A] Calculating... (40%)
2026-06-05 12:03:50,866 [INFO] [Thread-A] Preempted. Progress saved at (40%)
2026-06-05 12:03:50,917 [INFO] [Thread-B] Task Started. Calculating... (20%)
2026-06-05 12:03:50,967 [INFO] [Thread-B] Calculating... (40%)
2026-06-05 12:03:51,018 [INFO] [Thread-B] Preempted. Progress saved at (40%)
2026-06-05 12:03:51,069 [INFO] [Thread-C] Task Started. Calculating... (20%)
2026-06-05 12:03:51,120 [INFO] [Thread-C] Calculating... (40%)
2026-06-05 12:03:51,170 [INFO] [Thread-C] Preempted. Progress saved at (40%)
2026-06-05 12:03:51,221 [INFO] [Thread-A] Resumed. Calculating... (60%)
2026-06-05 12:03:51,272 [INFO] [Thread-A] Calculating... (80%)
2026-06-05 12:03:51,322 [INFO] [Thread-A] Preempted. Progress saved at (80%)
2026-06-05 12:03:51,373 [INFO] [Thread-B] Resumed. Calculating... (60%)
2026-06-05 12:03:51,424 [INFO] [Thread-B] Calculating... (80%)
2026-06-05 12:03:51,474 [INFO] [Thread-B] Preempted. Progress saved at (80%)
2026-06-05 12:03:51,525 [INFO] [Thread-C] Resumed. Calculating... (60%)
2026-06-05 12:03:51,576 [INFO] [Thread-C] Calculating... (80%)
2026-06-05 12:03:51,626 [INFO] [Thread-C] Preempted. Progress saved at (80%)
2026-06-05 12:03:51,677 [INFO] [Thread-A] Resumed. Calculating... (100%)
2026-06-05 12:03:51,727 [INFO] [Thread-B] Resumed. Calculating... (100%)
2026-06-05 12:03:51,778 [INFO] [Thread-C] Resumed. Calculating... (100%)
2026-06-05 12:03:51,829 [INFO] [Scheduler] All tasks completed.
```

</details>

### 2. 실행 타임라인

```
Time(ms)   Thread-A      Thread-B      Thread-C
   0       20% ██
  50       40% ████
 100       Preempted ─┐
 150                  └→ 20% ██
 200                     40% ████
 250                     Preempted ─┐
 300                                └→ 20% ██
 350                                   40% ████
 400                                   Preempted ─┐
 450       60% ██████  ←──────────────────────────┘
 500       80% ████████
 550       Preempted ─┐
 600                  └→ 60% ██████
 650                     80% ████████
 700                     Preempted ─┐
 750                                └→ 60% ██████
 800                                   80% ████████
 850                                   Preempted ─┐
 900       100% ██████████ ←──────────────────────┘
 950                     100% ██████████
1000                                   100% ██████████
```

### 3. 알고리즘 역추론

| 후보 | 판단 | 근거 |
|------|------|------|
| **FCFS** (First Come First Served) | X | Thread-A가 100% 완료 전에 Thread-B가 실행됨 → 순차 처리 아님 |
| **Priority** | X | A, B, C가 동일한 시간(~100ms)만큼 공평하게 실행됨 → 특정 스레드 우대 없음 |
| **Round Robin** | **O** | 각 스레드가 ~100ms Time Quantum 후 `Preempted`되어 다음 스레드에 양보, A→B→C→A→B→C 균등 순환 |

### 4. 결론: Round Robin

- **Time Quantum**: ~100ms (20% x 2회 = 50ms x 2)
- **선점형(Preemptive)**: `Preempted. Progress saved`로 강제 중단, 상태 저장 후 다음 스레드에 CPU 양보
- **순환 순서**: A → B → C → A → B → C → A → B → C (균등 배분)

### 5. Round Robin 장단점 및 적합 아키텍처

| 항목 | 내용 |
|------|------|
| **장점** | 모든 작업에 공평한 CPU 시간 보장, 기아(Starvation) 방지, 응답 시간 예측 가능 |
| **단점** | 컨텍스트 스위칭 오버헤드, Time Quantum이 너무 크면 FCFS와 유사, 너무 작으면 스위칭 비용 증가 |
| **적합** | 실시간 응답이 중요한 웹 서버, 대화형 시스템 (다수 사용자에게 균등한 응답 제공) |
| **부적합** | 처리량(Throughput)이 중요한 배치 서버 (컨텍스트 스위칭 오버헤드가 총 처리 시간을 증가시킴) |

