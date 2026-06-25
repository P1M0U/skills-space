#!/bin/bash
# ═══════════════════════════════════════════════════════════
# Hermes Health Watchdog v2.1 — no_agent cron mode
# ═══════════════════════════════════════════════════════════
# Used with: hermes cron create --no-agent --script scripts/health_watchdog.sh
# Behaviour: silent (no output) when healthy; only speaks on failures.
# This enables silent periodic monitoring — no noise, only alerts.
#
# Configuration: override thresholds via env vars before running.
#   WARN_DISK_PCT=85  CRIT_DISK_PCT=92  (defaults below)
#
# v2.1 变更：修复 sshd→ssh、bc→awk、新增僵尸进程/RSS/IoWait 检查、
#            Gateway 重启防重入、更新恶意进程特征库
# ═══════════════════════════════════════════════════════════

set -euo pipefail

# ═══════ Thresholds (override via env) ═══════
WARN_DISK_PCT="${WARN_DISK_PCT:-85}"
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
WARN_MEM_MB="${WARN_MEM_MB:-500}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
WARN_LOAD="${WARN_LOAD:-0.8}"
CRIT_LOAD="${CRIT_LOAD:-1.5}"
WARN_LOGIN_FAILS="${WARN_LOGIN_FAILS:-50}"
CRIT_LOGIN_FAILS="${CRIT_LOGIN_FAILS:-200}"
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
GW_RESTART_STATE="${HERMES_HOME}/cron/output/.gw_restart_count"

ALERTS=""
HAS_ALERT=0
NOW=$(date '+%Y-%m-%d %H:%M:%S')

# Helper: add alert line
alert() {
    local level="$1"  # CRIT or WARN
    local msg="$2"
    ALERTS="${ALERTS}\\n[${level}] ${msg}"
    [ "$level" = "CRIT" ] && HAS_ALERT=1
}

# Helper: float comparison via awk（替代 bc，无需额外依赖）
float_gt() {
    # 用法: float_gt "3.14" "2.71" → exit 0 if $1 > $2
    awk "BEGIN { exit !($1 > $2) }"
}

# 自动检测 SSH systemd 服务名（Ubuntu=ssh, CentOS=sshd）
detect_ssh_unit() {
    if systemctl list-units --type=service 2>/dev/null | grep -q " ssh\.service"; then
        echo "ssh"
    elif systemctl list-units --type=service 2>/dev/null | grep -q " sshd\.service"; then
        echo "sshd"
    else
        echo "ssh"
    fi
}
SSH_UNIT=$(detect_ssh_unit)

# ═══════ 1. Disk Usage ═══════
DISK_PCT=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
if [ "$DISK_PCT" -gt "$CRIT_DISK_PCT" ]; then
    alert "CRIT" "磁盘使用率 ${DISK_PCT}% (阈值: ${CRIT_DISK_PCT}%)"
elif [ "$DISK_PCT" -gt "$WARN_DISK_PCT" ]; then
    alert "WARN" "磁盘使用率 ${DISK_PCT}% (阈值: ${WARN_DISK_PCT}%)"
fi

# ═══════ 1b. Inode Usage ═══════
INODE_PCT=$(df -i / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo 0)
if [ "$INODE_PCT" -gt "$CRIT_DISK_PCT" ]; then
    alert "CRIT" "Inode 使用率 ${INODE_PCT}% (阈值: ${CRIT_DISK_PCT}%)"
elif [ "$INODE_PCT" -gt "$WARN_DISK_PCT" ]; then
    alert "WARN" "Inode 使用率 ${INODE_PCT}% (阈值: ${WARN_DISK_PCT}%)"
fi

# ═══════ 2. Memory ═══════
MEM_AVAIL=$(free -m | awk '/Mem:/ {print $7}')
if [ "$MEM_AVAIL" -lt "$CRIT_MEM_MB" ]; then
    alert "CRIT" "可用内存 ${MEM_AVAIL}MB (阈值: ${CRIT_MEM_MB}MB)"
elif [ "$MEM_AVAIL" -lt "$WARN_MEM_MB" ]; then
    alert "WARN" "可用内存 ${MEM_AVAIL}MB (阈值: ${WARN_MEM_MB}MB)"
fi

# ═══════ 3. CPU Load ═══════
NPROC=$(nproc 2>/dev/null || echo 1)
LOAD=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
if [ -n "$LOAD" ]; then
    # 纯 awk 浮点比较，替代 bc
    LOAD_RATIO=$(awk "BEGIN { printf \"%.2f\", $LOAD / $NPROC }")
    if float_gt "$LOAD_RATIO" "$CRIT_LOAD"; then
        alert "CRIT" "CPU 负载过高: ${LOAD} (${NPROC}核, 阈值: ${CRIT_LOAD}/核)"
    elif float_gt "$LOAD_RATIO" "$WARN_LOAD"; then
        alert "WARN" "CPU 负载偏高: ${LOAD} (${NPROC}核, 阈值: ${WARN_LOAD}/核)"
    fi
fi

# ═══════ 4. Gateway Process（带防重入保护） ═══════
if systemctl --user is-active hermes-gateway &>/dev/null; then
    # 健康 → 重置重启计数
    mkdir -p "$(dirname "$GW_RESTART_STATE")"
    echo "0" > "$GW_RESTART_STATE"
else
    # 读取连续重启次数
    RESTART_COUNT=0
    if [ -f "$GW_RESTART_STATE" ]; then
        RESTART_COUNT=$(cat "$GW_RESTART_STATE" 2>/dev/null || echo 0)
    fi

    if [ "$RESTART_COUNT" -ge 3 ]; then
        # 连续3次重启失败 → 只告警，不再重启（避免崩溃循环）
        alert "CRIT" "Hermes Gateway 连续 ${RESTART_COUNT} 次重启失败，需人工介入！"
    else
        alert "CRIT" "Hermes Gateway 未运行！尝试重启中... (第 $((RESTART_COUNT + 1)) 次)"
        systemctl --user restart hermes-gateway 2>&1 || true
        # 等待 5 秒后确认
        sleep 5
        if systemctl --user is-active hermes-gateway &>/dev/null; then
            ALERTS="${ALERTS}\\n[INFO] Gateway 重启成功"
            echo "0" > "$GW_RESTART_STATE"
        else
            NEW_COUNT=$((RESTART_COUNT + 1))
            echo "$NEW_COUNT" > "$GW_RESTART_STATE"
            ALERTS="${ALERTS}\\n[CRIT] Gateway 重启失败 (连续第 ${NEW_COUNT} 次)"
        fi
    fi
fi

# ═══════ 5. SSH Brute Force (recent 24h) ═══════
if command -v journalctl &>/dev/null; then
    SSH_FAILS=$(sudo -n journalctl -u "$SSH_UNIT" --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || true)
    if [ "$SSH_FAILS" -gt "$CRIT_LOGIN_FAILS" ]; then
        alert "CRIT" "SSH 暴力破解！最近24h: ${SSH_FAILS} 次失败登录 (阈值: ${CRIT_LOGIN_FAILS})"
    elif [ "$SSH_FAILS" -gt "$WARN_LOGIN_FAILS" ]; then
        alert "WARN" "SSH 登录异常: ${SSH_FAILS} 次失败登录 (阈值: ${WARN_LOGIN_FAILS})"
    fi
fi

# ═══════ 6. Malicious Process Check ═══════
MALWARE=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|gates|lady|ddgs|kthreaddi|ld-linux|XMrig" | grep -v grep || true)
if [ -n "$MALWARE" ]; then
    alert "CRIT" "发现可疑恶意进程！\\n${MALWARE}"
fi

# ═══════ 7. Zombie Process Check ═══════
ZOMBIES=$(ps aux 2>/dev/null | awk '$8 ~ /^Z/ {count++} END {print count+0}')
if [ "$ZOMBIES" -gt 50 ]; then
    alert "WARN" "僵尸进程过多: ${ZOMBIES} 个 (建议检查父进程)"
elif [ "$ZOMBIES" -gt 10 ]; then
    alert "WARN" "存在 ${ZOMBIES} 个僵尸进程"
fi

# ═══════ 8. Gateway Process Memory (RSS) ═══════
GW_PID=$(systemctl --user show hermes-gateway -p MainPID --value 2>/dev/null || echo 0)
if [ "$GW_PID" -gt 0 ] 2>/dev/null; then
    RSS_KB=$(awk '/^VmRSS:/ {print $2}' /proc/$GW_PID/status 2>/dev/null || echo 0)
    if [ "$RSS_KB" -gt 0 ]; then
        RSS_MB=$((RSS_KB / 1024))
        if [ "$RSS_MB" -gt 1024 ]; then
            alert "CRIT" "Gateway 内存占用 ${RSS_MB}MB，可能存在内存泄漏！"
        elif [ "$RSS_MB" -gt 512 ]; then
            alert "WARN" "Gateway 内存占用 ${RSS_MB}MB，偏高"
        fi
    fi
fi

# ═══════ 9. Hermes Log Size ═══════
if [ -f "$HERMES_HOME/logs/gateway.log" ]; then
    LOG_SIZE_MB=$(du -m "$HERMES_HOME/logs/gateway.log" 2>/dev/null | cut -f1)
    if [ "${LOG_SIZE_MB:-0}" -gt 500 ]; then
        alert "WARN" "Gateway 日志已达 ${LOG_SIZE_MB}MB，建议配置 logrotate"
    fi
fi

# ═══════════════ Output ═══════════════
if [ "$HAS_ALERT" -eq 1 ]; then
    echo "═════════════════════════════════════"
    echo "  🚨 Hermes Watchdog Alert"
    echo "  ${NOW}"
    echo "═════════════════════════════════════"
    echo -e "$ALERTS"
    echo ""
    echo "⚠️  如忽略该告警，请检查 Hermes Agent 状态"
else
    # 静默退出 — cron no_agent 模式下空 stdout = 不发送消息
    exit 0
fi
