---
name: security-health-check
description: "Production-grade server security health check — firewall audit, SSH hardening, brute force detection, rootkit/malware scan, user audit, SUID audit, Docker security, systemd health, kernel hardening, crontab analysis, disk/memory thresholds. Supports interactive mode and no-agent cron watchdog."
version: 2.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [security, monitoring, production, diagnostics, linux, audit]
    related_skills: [hermes-health-check]
---

# 服务器安全健康检查 (Production Edition)

生产级服务器安全扫描，覆盖 **18 个安全检查领域**。支持两种模式：

- **交互模式**（默认）— 全量 18 项检查，输出结构化安全报告 + 评分
- **Watchdog 模式**（`no_agent` cron）— 轻量脚本每 30 分钟运行，仅异常时告警

## 触发方式

| 方式 | 说明 |
|------|------|
| 用户说「安全检查」「安全扫描」「服务器检查」 | 加载本 skill 执行全量检查 |
| 定时 cron job（推荐） | 每天 10:00/22:00 自动执行全量检查 |
| 紧急监控（`no_agent` cron） | 每 30 分钟运行 `scripts/emergency_monitor.sh`，0 token 消耗 |

## 定时建议

| 类型 | 推荐时间 | 说明 |
|------|----------|------|
| 全量检查 | `0 10,22 * * *` | 上午10点 / 晚上10点，不打扰睡眠 |
| 紧急监控 | `*/30 * * * *` | 轻量脚本，仅异常输出 |

> ⚠️ 不要设置在 0:00（午夜）触发——会吵醒用户。

---

## 检查流程（18 项）

按顺序执行。**收集所有结果后再生成报告**，不要跳过任何项。

### Phase 1: 防火墙状态

```bash
# 自动检测防火墙类型
if command -v ufw &>/dev/null; then
  sudo ufw status verbose
elif command -v firewall-cmd &>/dev/null; then
  firewall-cmd --list-all
else
  sudo iptables -L -n --line-numbers 2>&1 | head -30
fi
```

- `Status: active` / `firewall-cmd running` -> ✅
- 防火墙未运行 -> ❌ CRITICAL
- 列出所有 ALLOW 规则，检查是否有 0.0.0.0/0 的不安全放行

### Phase 2: 监听端口审计

```bash
# 所有监听端口
ss -tlnp 2>&1

# 对外暴露的端口（非 127.0.0.1）
ss -tlnp 2>&1 | grep -vE "127.0.0.1|::1:"
```

- 列出所有对外暴露的端口
- 每发现一个非预期端口 -> ⚠️ WARN
- MySQL (3306)、Redis (6379)、Docker (2375) 暴露到 0.0.0.0 -> ❌ CRITICAL

### Phase 3: SSH 安全加固检查

```bash
sudo grep -E "^PermitRootLogin|^PasswordAuthentication|^Port |^MaxAuthTries|^ClientAliveInterval|^ClientAliveCountMax|^AllowUsers|^PubkeyAuthentication|^ChallengeResponseAuthentication" /etc/ssh/sshd_config 2>/dev/null | grep -v "^#"
```

安全基线（CIS Benchmark 级别）：

| 配置项 | ✅ 安全 | ❌ 危险 |
|--------|---------|---------|
| PermitRootLogin | `no` 或 `prohibit-password` | `yes` |
| PasswordAuthentication | `no` | `yes` |
| Port | 非 22（可选加固） | 默认 22 |
| MaxAuthTries | <= 3 | > 6 |
| ClientAliveInterval | 300 或更小 | 未设置或 0 |
| PubkeyAuthentication | `yes` | `no` |
| ChallengeResponseAuthentication | `no` | `yes` |
| AllowUsers | 有具体用户名列表 | 未设置 |

### Phase 4: SSH 暴力破解检测

```bash
SSH_FAILS=$(sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || true)
SSH_INVALID=$(sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Invalid user" || true)
# Top 10 攻击来源 IP
sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -10
# fail2ban 状态
sudo fail2ban-client status sshd 2>/dev/null || echo "fail2ban not installed"
```

阈值：> 20 次/24h -> ⚠️ WARN, > 100 次/24h -> ❌ CRITICAL

### Phase 5: 恶意进程 & Rootkit 扫描

```bash
ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|gates|lady|ddgs"
find /dev/shm /tmp -type f \( -executable -o -name "*.sh" \) -newer /etc/passwd 2>/dev/null | head -10
```

- 匹配到挖矿/后门进程 -> ❌ CRITICAL

### Phase 6: 用户账户审计

```bash
# 空密码账户
sudo awk -F: '($2 == "" || $2 == "!") && $3 != 65534 {print $1}' /etc/shadow 2>/dev/null
# 非 root UID 0 的账户
awk -F: '($3 == 0 && $1 != "root") {print $1}' /etc/passwd 2>/dev/null
# sudo 权限用户
grep -E "^\w+.+ALL=\(ALL:ALL\)" /etc/sudoers 2>/dev/null
```

- UID 0 的非 root 账户 -> ❌ CRITICAL
- 空密码账户 -> ❌ CRITICAL

### Phase 7: SUID/SGID 文件审计

```bash
# 用户可写目录下的 SUID 文件（异常！）
find /tmp /dev/shm /var/tmp /home -perm -4000 -type f 2>/dev/null
```

- /tmp、/dev/shm、/home 下存在 SUID 文件 -> ❌ CRITICAL（典型提权攻击）

### Phase 8: Crontab 安全检查

```bash
sudo grep -r "curl\|wget\|/tmp/script\|eval\|base64.*-d\|chmod +x" /var/spool/cron/crontabs/ /etc/cron.d/ /etc/crontab 2>/dev/null
```

- 发现 `curl` / `wget` 到 `/tmp` -> ❌ CRITICAL

### Phase 9: Systemd 服务健康

```bash
systemctl --failed --no-pager 2>&1
```

- Hermes Gateway failed -> ❌ CRITICAL

### Phase 10: Docker 安全检查

```bash
if command -v docker &>/dev/null; then
  ss -tlnp 2>&1 | grep ":2375" && echo "CRITICAL: Docker TCP exposed"
  docker ps --filter "status=running" --format "{{.Names}}" | while read c; do
    docker inspect "$c" --format '{{.HostConfig.Privileged}}' | grep "true" && echo "Privileged: $c"
  done
fi
```

- Docker TCP (2375) 暴露 -> ❌ CRITICAL

### Phase 11: SELinux / AppArmor

```bash
if command -v getenforce &>/dev/null; then echo "SELinux: $(getenforce)"; fi
if command -v aa-status &>/dev/null; then sudo aa-status 2>/dev/null | head -5; fi
```

### Phase 12: 内核参数加固

CIS 基线：kernel.dmesg_restrict=1, kernel.kptr_restrict=2, kernel.randomize_va_space=2, net.ipv4.conf.all.rp_filter=1, net.ipv4.conf.all.accept_source_route=0, net.ipv4.tcp_syncookies=1, net.ipv4.ip_forward=0

### Phase 13-14: 磁盘 & 内存

磁盘 > 80% -> ⚠️ / > 92% -> ❌  内存可用 < 500MB -> ⚠️ / < 200MB -> ❌

### Phase 15-18: 登录日志 / SSH 密钥 / 系统更新 / Auditd

See the complete SKILL.md in the Hermes Agent skills directory for full details.

---

## 评分系统

| 组件 | 权重 |
|------|------|
| Phase 1-2 (防火墙/端口) | 12% |
| Phase 3-4 (SSH) | 15% |
| Phase 5 (恶意进程) | 20% |
| Phase 6-7 (用户/SUID) | 10% |
| Phase 8-10 (Crontab/Systemd/Docker) | 15% |
| Phase 11-12 (SELinux/内核) | 8% |
| Phase 13-14 (磁盘/内存) | 10% |
| Phase 15-18 (日志/密钥/更新) | 10% |

单项评分：✅=2分，⚠️=1分，❌=0分。加权后总分 0-100。

| 分数 | 等级 |
|------|------|
| >= 90 | ✅ SECURE |
| >= 70 | ⚠️ NEEDS ATTENTION |
| < 70 或任意 ❌ CRITICAL | ❌ INSECURE |

---

## Watchdog 模式

### 全量检查（LLM cron）

```bash
hermes cron create --name "安全全量检查" \
  --schedule "0 10,22 * * *" \
  --skill security-health-check \
  --prompt "执行完整安全健康检查。如有 CRITICAL 项或评分低于 70，明确告警。"
```

### 紧急监控（no_agent — 0 token）

```bash
# 前提条件：journalctl 免密码 sudo
echo 'pimou ALL=(ALL) NOPASSWD: /usr/bin/journalctl' | sudo tee /etc/sudoers.d/emergency-monitor
# 创建监控
hermes cron create --name "紧急安全监控" \
  --schedule "*/30 * * * *" \
  --script emergency_monitor.sh \
  --no-agent
```

## 注意事项

- `ufw status` 可能在云服务器上返回 `Status: inactive`（云厂商使用 iptables/nftables）
- `journalctl` 需要 sudo 权限
- Docker TCP (2375) 暴露在云服务器上极其危险——等于把 root 权限开放给任何人
- 不要在输出中泄露完整 API Key 或 shadow 哈希值
