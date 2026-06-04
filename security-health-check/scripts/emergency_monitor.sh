#!/bin/bash
# 服务器紧急安全监控 v2.0 — no_agent cron 模式
set -euo pipefail

CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
SSH_FAIL_THRESHOLD="${SSH_FAIL_THRESHOLD:-50}"

ALERTS=""
HAS_ALERT=0
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')

alert() {
    local msg="$1"
    ALERTS="${ALERTS}\n❌ ${msg}"
    HAS_ALERT=1
}

# SSH brute force (last 30 min)
if command -v journalctl &>/dev/null; then
    SSH_FAILS=$(sudo -n journalctl -u sshd --since "30 min ago" 2>/dev/null | grep -c "Failed password" || true)
    SSH_INVALID=$(sudo -n journalctl -u sshd --since "30 min ago" 2>/dev/null | grep -c "Invalid user" || true)
    TOTAL=$((SSH_FAILS + SSH_INVALID))
    if [ "$TOTAL" -gt "$SSH_FAIL_THRESHOLD" ]; then
        alert "SSH暴力破解！最近30min: 失败${SSH_FAILS}, 无效用户${SSH_INVALID}"
        TOP_IPS=$(sudo -n journalctl -u sshd --since "30 min ago" 2>/dev/null | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -3)
        [ -n "$TOP_IPS" ] && ALERTS="${ALERTS}\n攻击来源TOP3:\n${TOP_IPS}"
    fi
fi

# Malware scan
MALWARE=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|kinsing|kdevtmpfsi|pwnrig|masscan" | grep -v grep || true)
[ -n "$MALWARE" ] && alert "发现可疑恶意进程！\n${MALWARE}"

# Disk emergency
DISK_USAGE=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo 0)
[ "$DISK_USAGE" -gt "$CRIT_DISK_PCT" ] && alert "磁盘空间告急！使用率 ${DISK_USAGE}%"

# Memory emergency
MEM_AVAIL=$(free -m 2>/dev/null | awk '/Mem:/ {print $7}' || echo 99999)
[ "$MEM_AVAIL" -lt "$CRIT_MEM_MB" ] && alert "内存告急！可用${MEM_AVAIL}MB"

# SUID privilege escalation
BAD_SUID=$(find /tmp /dev/shm /var/tmp -perm -4000 -type f 2>/dev/null)
[ -n "$BAD_SUID" ] && alert "用户可写目录下发现SUID文件（提权攻击！）\n${BAD_SUID}"

# Docker exposed
if command -v docker &>/dev/null; then
    DOCKER_EXPOSED=$(ss -tlnp 2>/dev/null | grep ":2375" || true)
    [ -n "$DOCKER_EXPOSED" ] && alert "Docker 无保护TCP端口2375暴露！"
fi

# Gateway health
systemctl --user is-active hermes-gateway &>/dev/null 2>&1 || alert "Hermes Gateway未运行"

if [ "$HAS_ALERT" -eq 1 ]; then
    echo "═════════════════════════════════════"
    echo "  🚨 服务器紧急安全告警"
    echo "  时间: ${NOW}"
    echo "═════════════════════════════════════"
    echo -e "$ALERTS"
fi
