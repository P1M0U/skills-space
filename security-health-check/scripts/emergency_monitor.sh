#!/bin/bash
# ═══════════════════════════════════════════════════════════
# 服务器紧急安全监控 v2.2 — no_agent cron 模式
# ═══════════════════════════════════════════════════════════
# 行为：仅 CRITICAL 级别输出告警（空 stdout = 不发送消息）
# 覆盖范围：SSH 暴力破解、恶意进程、磁盘>92%、内存<200MB、
#           恶意 SUID、Docker 暴露、Gateway 健康
# 新增：早上8:00-8:30生成整晚汇总报告
# ═══════════════════════════════════════════════════════════

set -euo pipefail

ALERTS=""
HAS_ALERT=0
NOW=$(date '+%Y-%m-%d %H:%M:%S %Z')
HOUR=$(date '+%H')
MINUTE=$(date '+%M')

# 检测是否是汇总时间（8:00-8:30）
IS_NIGHT_SUMMARY=0
if [ "$HOUR" -eq 8 ] && [ "$MINUTE" -le 30 ]; then
    IS_NIGHT_SUMMARY=1
fi

# 阈值（可通过环境变量覆盖）
CRIT_DISK_PCT="${CRIT_DISK_PCT:-92}"
CRIT_MEM_MB="${CRIT_MEM_MB:-200}"
SSH_FAIL_THRESHOLD="${SSH_FAIL_THRESHOLD:-50}"

alert() {
    local msg="$1"
    ALERTS="${ALERTS}\\n❌ ${msg}"
    HAS_ALERT=1
}

# ═══════ 1. SSH 暴力破解（最近30分钟） ═══════
if command -v journalctl &>/dev/null; then
    SSH_FAILS=$(sudo -n journalctl -u sshd --since "30 min ago" 2>/dev/null | grep -c "Failed password" || true)
    SSH_INVALID=$(sudo -n journalctl -u sshd --since "30 min ago" 2>/dev/null | grep -c "Invalid user" || true)
    TOTAL=$((SSH_FAILS + SSH_INVALID))
    if [ "$TOTAL" -gt "$SSH_FAIL_THRESHOLD" ]; then
        alert "SSH 暴力破解！最近30min: 失败登录 ${SSH_FAILS} 次，无效用户 ${SSH_INVALID} 次"
        # Top 3 IP
        TOP_IPS=$(sudo -n journalctl -u sshd --since "30 min ago" 2>/dev/null | grep "Failed password" | grep -oP 'from \\K[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+' | sort | uniq -c | sort -rn | head -3)
        if [ -n "$TOP_IPS" ]; then
            ALERTS="${ALERTS}\\n攻击来源 TOP3:\\n${TOP_IPS}"
        fi

        # 尝试 fail2ban 封禁
        if command -v fail2ban-client &>/dev/null; then
            BAN_STATUS=$(sudo -n fail2ban-client status sshd 2>/dev/null | grep -oP "Currently banned:\\s+\\K[0-9]+" || echo "0")
            ALERTS="${ALERTS}\\n[INFO] fail2ban 已封禁 ${BAN_STATUS} 个 IP"
        fi
    fi
fi

# ═══════ 2. 恶意进程 ═══════
MALWARE=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|gates|lady|ddgs" | grep -v grep || true)
if [ -n "$MALWARE" ]; then
    alert "发现可疑恶意进程！\\n${MALWARE}"
fi

# ═══════ 3. 磁盘紧急告警 ═══════
DISK_USAGE=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo 0)
if [ "$DISK_USAGE" -gt "$CRIT_DISK_PCT" ]; then
    alert "磁盘空间告急！使用率 ${DISK_USAGE}% (阈值: ${CRIT_DISK_PCT}%)"
    # 显示大目录
    TOP_DIRS=$(du -sh /* 2>/dev/null | sort -rh | head -5)
    ALERTS="${ALERTS}\\n最大目录:\\n${TOP_DIRS}"
fi

# ═══════ 4. 内存紧急告警 ═══════
MEM_AVAIL=$(free -m 2>/dev/null | awk '/Mem:/ {print $7}' || echo 99999)
if [ "$MEM_AVAIL" -lt "$CRIT_MEM_MB" ]; then
    MEM_TOTAL=$(free -m | awk '/Mem:/ {print $2}')
    MEM_USED=$((MEM_TOTAL - MEM_AVAIL))
    MEM_PCT=$((MEM_USED * 100 / MEM_TOTAL))
    alert "内存告急！可用 ${MEM_AVAIL}MB / 总计 ${MEM_TOTAL}MB (${MEM_PCT}%)"
fi

# ═══════ 5. 异常 SUID 文件（提权攻击检测） ═══════
BAD_SUID=$(find /tmp /dev/shm /var/tmp -perm -4000 -type f 2>/dev/null || true)
if [ -n "$BAD_SUID" ]; then
    alert "用户可写目录下发现 SUID 文件（提权攻击！）:\\n${BAD_SUID}"
fi

# ═══════ 6. Docker TCP 暴露检查 ═══════
if command -v docker &>/dev/null; then
    DOCKER_EXPOSED=$(ss -tlnp 2>/dev/null | grep ":2375" || true)
    if [ -n "$DOCKER_EXPOSED" ]; then
        alert "Docker 无保护 TCP 端口 2375 暴露！任何人均可控制 Docker 守护进程"
    fi
fi

# ═══════ 7. Hermes Gateway 进程健康 ═══════
if ! systemctl --user is-active hermes-gateway &>/dev/null 2>&1; then
    alert "Hermes Gateway 未运行"
fi

# ═══════ 输出（空 = 不发送） ═════
if [ "$HAS_ALERT" -eq 1 ]; then
    HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    echo "═════════════════════════════════════"
    echo "  🚨 服务器紧急安全告警"
    echo "  主机: ${HOSTNAME}"
    echo "  时间: ${NOW}"
    echo "═════════════════════════════════════"
    echo -e "$ALERTS"
    echo ""
    echo "⚠️  请尽快登录服务器排查。"
fi

# ═══════ 汇总报告（8:00-8:30） ═════
if [ "$IS_NIGHT_SUMMARY" -eq 1 ]; then
    HOSTNAME=$(hostname 2>/dev/null || echo "unknown")
    YESTERDAY=$(date -d "yesterday" '+%Y-%m-%d')
    
    echo ""
    echo "═════════════════════════════════════"
    echo "  🌙 每日安全检查汇总报告"
    echo "  主机: ${HOSTNAME}"
    echo "  统计时段: ${YESTERDAY} 18:00 ~ ${NOW}"
    echo "═════════════════════════════════════"
    
    # 1. SSH暴力破解统计（昨晚）
    if command -v journalctl &>/dev/null; then
        SSH_FAILS=$(sudo -n journalctl -u sshd --since "yesterday 18:00" 2>/dev/null | grep -c "Failed password" || true)
        SSH_INVALID=$(sudo -n journalctl -u sshd --since "yesterday 18:00" 2>/dev/null | grep -c "Invalid user" || true)
        SSH_TOTAL=$((SSH_FAILS + SSH_INVALID))
        
        echo ""
        echo "📊 SSH暴力破解统计"
        echo "  失败登录次数: ${SSH_FAILS}"
        echo "  无效用户尝试: ${SSH_INVALID}"
        echo "  总计: ${SSH_TOTAL} 次"
        
        # Top 5 攻击IP
        if [ "$SSH_TOTAL" -gt 0 ]; then
            echo ""
            echo "🎯 攻击来源 TOP5:"
            sudo -n journalctl -u sshd --since "yesterday 18:00" 2>/dev/null | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -5 | while read count ip; do
                echo "  ${ip} - ${count} 次"
            done
            
            # 被尝试的用户名
            echo ""
            echo "🔑 被尝试的用户名:"
            sudo -n journalctl -u sshd --since "yesterday 18:00" 2>/dev/null | grep "Failed password" | grep -oP '(for|for invalid user) \K\S+' | sort | uniq -c | sort -rn | head -5 | while read count user; do
                echo "  ${user} - ${count} 次"
            done
        fi
        
        # fail2ban状态
        if command -v fail2ban-client &>/dev/null; then
            BAN_STATUS=$(sudo -n fail2ban-client status sshd 2>/dev/null | grep -oP "Currently banned:\s+\K[0-9]+" || echo "0")
            TOTAL_BAN=$(sudo -n fail2ban-client status sshd 2>/dev/null | grep -oP "Total banned:\s+\K[0-9]+" || echo "0")
            echo ""
            echo "🛡️ fail2ban状态"
            echo "  当前封禁IP数: ${BAN_STATUS}"
            echo "  累计封禁IP数: ${TOTAL_BAN}"
        fi
    fi
    
    # 2. 系统资源状态
    echo ""
    echo "💻 系统资源状态"
    DISK_USAGE=$(df / 2>/dev/null | tail -1 | awk '{print $5}' | sed 's/%//' || echo 0)
    DISK_FREE=$(df -h / 2>/dev/null | tail -1 | awk '{print $4}' || echo "unknown")
    echo "  磁盘使用率: ${DISK_USAGE}% (剩余: ${DISK_FREE})"
    
    MEM_AVAIL=$(free -m 2>/dev/null | awk '/Mem:/ {print $7}' || echo 0)
    MEM_TOTAL=$(free -m 2>/dev/null | awk '/Mem:/ {print $2}' || echo 0)
    echo "  可用内存: ${MEM_AVAIL}MB / ${MEM_TOTAL}MB"
    
    # 3. 安全事件汇总
    echo ""
    echo "🔒 安全事件汇总"
    
    # 检查是否有恶意进程
    MALWARE=$(ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|gates|lady|ddgs" | grep -v grep || true)
    if [ -n "$MALWARE" ]; then
        echo "  ❌ 发现恶意进程"
    else
        echo "  ✅ 未发现恶意进程"
    fi
    
    # 检查Docker暴露
    if command -v docker &>/dev/null; then
        DOCKER_EXPOSED=$(ss -tlnp 2>/dev/null | grep ":2375" || true)
        if [ -n "$DOCKER_EXPOSED" ]; then
            echo "  ❌ Docker TCP 2375 暴露"
        else
            echo "  ✅ Docker 安全"
        fi
    fi
    
    # 检查Gateway状态
    if systemctl --user is-active hermes-gateway &>/dev/null 2>&1; then
        echo "  ✅ Hermes Gateway 运行正常"
    else
        echo "  ❌ Hermes Gateway 未运行"
    fi
    
    echo ""
    echo "═════════════════════════════════════"
    echo "  📋 汇总完成"
    echo "═════════════════════════════════════"
fi
