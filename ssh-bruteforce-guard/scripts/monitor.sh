#!/bin/bash
# SSH暴力破解监控脚本
# 功能：检测过去1小时内暴力破解尝试超过30次的IP，自动封禁
# 用法：每小时运行一次
# 注意：仅在有新封禁时才输出到stdout（用于通知），否则静默

set -e

# 配置
THRESHOLD=30  # 封禁阈值：每小时尝试次数
LOG_FILE="/var/log/auth.log"
BAN_LOG="/var/log/ssh-guard.log"

# 获取过去1小时的时间范围
END_TIME=$(date +%s)
START_TIME=$((END_TIME - 3600))

# 将时间戳转换为日志格式（ISO 8601）
START_DATE=$(date -d "@$START_TIME" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -r "$START_TIME" +"%Y-%m-%dT%H:%M:%S")
END_DATE=$(date -d "@$END_TIME" +"%Y-%m-%dT%H:%M:%S" 2>/dev/null || date -r "$END_TIME" +"%Y-%m-%dT%H:%M:%S")

# 记录到本地日志（不输出到stdout）
echo "=== SSH暴力破解监控 ===" >> "$BAN_LOG"
echo "监控时间范围：$START_DATE ~ $END_DATE" >> "$BAN_LOG"
echo "" >> "$BAN_LOG"

# 提取过去1小时的失败登录记录，统计每个IP的次数
ATTACKERS=$(sudo grep -E "(Failed password|Invalid user)" "$LOG_FILE" | \
    awk -v start="$START_DATE" '$0 >= start' | \
    grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
    sort | uniq -c | sort -rn | \
    awk -v threshold="$THRESHOLD" '$1 >= threshold {print $2, $1}')

if [ -z "$ATTACKERS" ]; then
    echo "✓ 未检测到超过阈值（${THRESHOLD}次/小时）的攻击IP" >> "$BAN_LOG"
    echo "" >> "$BAN_LOG"
    # 静默退出，不发送通知
    exit 0
fi

# 封禁每个超阈值的IP
BANNED_COUNT=0
NEW_BANS=""

while IFS=' ' read -r IP COUNT; do
    echo "⚠ 检测到攻击IP：$IP（${COUNT}次/小时）" >> "$BAN_LOG"
    
    # 检查是否已在ufw黑名单中
    if sudo ufw status | grep -q "$IP"; then
        echo "  → $IP 已在ufw黑名单中，跳过" >> "$BAN_LOG"
        continue
    fi
    
    # 通过fail2ban封禁
    sudo fail2ban-client set sshd banip "$IP" 2>/dev/null && \
        echo "  → fail2ban已封禁 $IP" >> "$BAN_LOG" || \
        echo "  → fail2ban未封禁（可能不在jail范围内）" >> "$BAN_LOG"
    
    # 通过ufw封禁
    if sudo ufw deny from "$IP" to any 2>/dev/null; then
        echo "  → ufw已封禁 $IP" >> "$BAN_LOG"
        BANNED_COUNT=$((BANNED_COUNT + 1))
        NEW_BANS="${NEW_BANS}🔒 ${IP}（${COUNT}次/小时）\n"
    else
        echo "  → ufw封禁失败" >> "$BAN_LOG"
    fi
    
    echo "" >> "$BAN_LOG"
done <<< "$ATTACKERS"

echo "=== 封禁完成：${BANNED_COUNT} 个IP ===" >> "$BAN_LOG"
echo "" >> "$BAN_LOG"

# 关键：只有新封禁时才输出到stdout（触发通知）
if [ "$BANNED_COUNT" -gt 0 ]; then
    echo "🚨 SSH暴力破解告警"
    echo ""
    echo "过去1小时内检测到 ${BANNED_COUNT} 个攻击IP，已自动封禁："
    echo ""
    echo -e "$NEW_BANS"
    echo "当前ufw封禁规则："
    sudo ufw status | grep "DENY"
fi

# 无新封禁时静默（stdout为空，不发送通知）
