---
name: security-health-check
description: "Production-grade server security health check — firewall audit, SSH hardening, brute force detection, rootkit/malware scan, user audit, SUID audit, Docker security, systemd health, kernel hardening, crontab analysis, disk/memory thresholds. Supports interactive mode and no-agent cron watchdog."
version: 2.3.0
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

- `Status: active` / `firewall-cmd running` → ✅
- 防火墙未运行 → ❌ CRITICAL
- 列出所有 ALLOW 规则，检查是否有 0.0.0.0/0 的不安全放行

### Phase 2: 监听端口审计

```bash
# 所有监听端口
ss -tlnp 2>&1

# 对外暴露的端口（非 127.0.0.1）
ss -tlnp 2>&1 | grep -vE "127.0.0.1|::1:"
```

- 列出所有对外暴露的端口
- 每发现一个非预期端口 → ⚠️ WARN
- MySQL (3306)、Redis (6379)、Docker (2375) 暴露到 0.0.0.0 → ❌ CRITICAL

### Phase 3: SSH 安全加固检查

```bash
# SSH 配置完整检查
sudo grep -E "^PermitRootLogin|^PasswordAuthentication|^Port |^MaxAuthTries|^ClientAliveInterval|^ClientAliveCountMax|^AllowUsers|^PubkeyAuthentication|^ChallengeResponseAuthentication" /etc/ssh/sshd_config 2>/dev/null | grep -v "^#"

# SSH 端口是否正在监听（注意实际端口，不一定是 22）
ss -tlnp 2>&1 | grep -E "sshd|ssh"

# ⚠️ 检查 socket 激活（Ubuntu 23.10+ 默认启用，会覆盖 sshd_config 端口设置）
sshd -T 2>/dev/null | grep "^port "   # 有效配置中的端口
sudo systemctl is-active ssh.socket 2>/dev/null   # socket 是否活跃
```

安全基线（CIS Benchmark 级别）：

| 配置项 | ✅ 安全 | ❌ 危险 |
|--------|---------|---------|
| PermitRootLogin | `no` 或 `prohibit-password` | `yes` |
| PasswordAuthentication | `no` | `yes` |
| Port | 非 22（可选加固） | 默认 22 |
| MaxAuthTries | ≤ 3 | > 6 |
| ClientAliveInterval | 300 或更小 | 未设置或 0 |
| PubkeyAuthentication | `yes` | `no` |
| ChallengeResponseAuthentication | `no` | `yes` |
| AllowUsers | 有具体用户名列表 | 未设置 |

**修复命令（发现危险配置后立即执行）：**

```bash
# 修复 PermitRootLogin
sudo sed -i 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

# 修复 PasswordAuthentication
sudo sed -i 's/^PasswordAuthentication yes/PasswordAuthentication no/' /etc/ssh/sshd_config

# 设置 MaxAuthTries 限制
echo 'MaxAuthTries 3' | sudo tee -a /etc/ssh/sshd_config

# 设置 AllowUsers 白名单（仅允许指定用户 SSH 登录）
echo 'AllowUsers pimou' | sudo tee -a /etc/ssh/sshd_config

# 设置空闲超时断开
echo 'ClientAliveInterval 300' | sudo tee -a /etc/ssh/sshd_config
echo 'ClientAliveCountMax 2' | sudo tee -a /etc/ssh/sshd_config

# ⚠️ 重启 SSH 服务（注意：Ubuntu 用 ssh，不是 sshd！）
sudo systemctl restart ssh
```

> ⚠️ **Ubuntu 服务名称陷阱**：Ubuntu 的 SSH systemd 服务名是 `ssh`，不是 `sshd`。执行 `systemctl restart sshd` 会报 `Unit sshd.service not found`。CentOS/RHEL 才用 `sshd`。如果不确定，先运行 `systemctl list-units | grep ssh` 确认实际服务名。
>
> ⚠️ **Ubuntu 23.10+ socket 激活陷阱**：新版 Ubuntu 默认使用 systemd socket activation（`ssh.socket` 监听端口 22，按需启动 `ssh.service`）。此时即使在 `sshd_config` 中修改了 `Port`，`ssh.socket` 仍然监听 22 端口，**完全覆盖 sshd_config 的端口设置**。诊断方法：运行 `sshd -T | grep port` 看有效配置，再对比 `ss -tlnp | grep ssh` 看实际监听——如果两者端口不一致，就是 socket 激活导致的。
>
> 修复方案（修改 SSH 端口时）：
> ```bash
> # 方案 A：创建 socket override（推荐，保留 socket 激活特性）
> sudo mkdir -p /etc/systemd/system/ssh.socket.d
> echo -e "[Socket]\nListenStream=\nListenStream=0.0.0.0:2222\nListenStream=[::]:2222" | sudo tee /etc/systemd/system/ssh.socket.d/override.conf
> sudo systemctl daemon-reload
> sudo systemctl restart ssh.socket
> sudo systemctl restart ssh
>
> # 方案 B：禁用 socket 激活，改用传统模式
> sudo systemctl stop ssh.socket
> sudo systemctl disable ssh.socket
> sudo systemctl enable ssh
> sudo systemctl restart ssh
> ```
>
> ⚠️ **Hermes 安全策略注意**：`sudo sed -i` 修改 `/etc/ssh/sshd_config` 可能被安全策略拦截（判定为"in-place edit of system config"）。拦截后**不要重试**——在报告中列出修复命令供用户手动执行即可。`sudo tee -a` 和 `sudo systemctl restart ssh` 通常不受影响。
>
> ⚠️ 修改 SSH 配置前先确保当前 SSH 会话不会中断（例如：用 screen/tmux 或开第二个窗口测试）。`PermitRootLogin` 和 `PasswordAuthentication` 是最高优先级的修复项。

### Phase 4: SSH 暴力破解检测

```bash
# 最近24小时的失败登录
sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep "Failed password"

# 统计数据
SSH_FAILS=$(sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || true)
SSH_INVALID=$(sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Invalid user" || true)

# Top 10 攻击来源 IP
sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -10

# 检查 lastb 记录
lastb 2>/dev/null | head -10

# 检查 fail2ban 状态（如果安装了）
sudo fail2ban-client status sshd 2>/dev/null || echo "fail2ban not installed"
```

阈值：
- > 20 次/24h → ⚠️ WARN
- > 100 次/24h → ❌ CRITICAL
- 有 fail2ban 且正常运行 → 风险等级降一级

> 深度分析（按时间范围、攻击类型分类、IP/用户名统计）见 `references/ssh-brute-force-log-analysis.md`。当用户要求分析特定时间段的攻击（如"昨晚"、"过去3天"）时，使用该参考文件中的方法。

### Phase 5: 恶意进程 & Rootkit 扫描

```bash
# 标准恶意软件特征
ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|jenkinx|sysupdate|networkservice|gates|lady|ddgs"

# 高 CPU 异常进程（CPU > 50%）
ps aux --sort=-%cpu 2>/dev/null | awk '$3 > 50.0'

# 隐藏进程检查（对比 /proc 与 ps 输出）
# 检查 /proc 中不正常的高 PID 范围
ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -5

# 检查异常网络连接（无对应进程）
ss -tunap 2>&1 | grep -v "users:((" | head -10

# 检查 /dev/shm 和 /tmp 中的可疑文件
find /dev/shm /tmp -type f \( -executable -o -name "*.sh" -o -name "*.pl" \) -newer /etc/passwd 2>/dev/null | head -10

# 检查典型挖矿路径
for d in /dev/shm /tmp /var/tmp /var/spool/cron; do
  ls -la "$d" 2>/dev/null | grep -iE "xmrig|minerd|kinsing|kdevtmpfsi"
done
```

- 匹配到挖矿/后门进程 → ❌ CRITICAL
- 发现隐藏进程、无主连接 → ⚠️ WARN
- /dev/shm 和 /tmp 有新近可执行文件 → ⚠️ WARN

### Phase 6: 用户账户审计

```bash
# 列出所有可登录用户（uid >= 1000 且有 shell）
grep -E "^[^:]+:[^:]+:[0-9]+" /etc/passwd 2>/dev/null | awk -F: '$3 >= 1000 || $3 == 0 {print "User: "$1" (UID: "$3", Shell: "$NF")"}'

# 空密码账户（注：Hermes 安全策略可能拦截此命令，被拦截时跳过即可）
sudo awk -F: '($2 == "" || $2 == "!") && $3 != 65534 {print "⚠️ Empty/no password: "$1}' /etc/shadow 2>/dev/null

# 最近添加的用户（检查 passwd 文件的 mtime）
stat /etc/passwd 2>/dev/null | grep Modify

# sudo 权限用户
grep -E "^\w+.+ALL=\(ALL:ALL\)" /etc/sudoers 2>/dev/null
ls -la /etc/sudoers.d/ 2>/dev/null | grep -v "^d\|^total\|\.\."

# 检查是否有非 root UID 0 的账户
awk -F: '($3 == 0 && $1 != "root") {print "❌ 非root账户但UID=0: "$1}' /etc/passwd 2>/dev/null
```

- 存在 UID 0 的非 root 账户 → ❌ CRITICAL
- 空密码账户 → ❌ CRITICAL
- sudoers.d 中有可疑文件（非标准命名） → ⚠️ WARN
- 近期添加了用户 → 记录 INFO

### Phase 7: SUID/SGID 文件审计

```bash
# 标准 SUID 文件列表（已知安全的白名单）
find / -perm -4000 -type f 2>/dev/null | sort

# 检查用户可写目录下的 SUID 文件（异常！）
find /tmp /dev/shm /var/tmp /home -perm -4000 -type f 2>/dev/null

# 检查 SGID
find / -perm -2000 -type f 2>/dev/null | sort
```

- /tmp、/dev/shm、/home 下存在 SUID 文件 → ❌ CRITICAL（典型提权攻击）
- 标准路径之外的罕见 SUID 文件 → ⚠️ WARN

### Phase 8: Crontab 安全检查

```bash
# pimou 用户的 crontab
crontab -l 2>/dev/null || echo "(no user crontab)"

# root crontab
sudo crontab -l 2>/dev/null || echo "(no root crontab)"

# 系统 crontab
sudo cat /etc/crontab 2>/dev/null
ls -la /etc/cron.d/ 2>/dev/null
ls -la /etc/cron.hourly/ /etc/cron.daily/ /etc/cron.weekly/ 2>/dev/null

# 检测可疑模式：从外部下载脚本并执行
sudo grep -r "curl\|wget\|/tmp/script\|eval\|base64.*-d\|chmod +x" /var/spool/cron/crontabs/ /etc/cron.d/ /etc/crontab 2>/dev/null || echo "无可疑 crontab 模式"
```

- 发现 `curl` / `wget` 到 `/tmp` 或 `| sh` 管道 → ❌ CRITICAL
- crontab 包含 base64 解码执行 → ❌ CRITICAL
- /etc/cron.d/ 或 /etc/cron.hourly/ 有非预期文件 → ⚠️ WARN

### Phase 9: Systemd 服务健康

```bash
# 列出所有失败的服务
systemctl --failed --no-pager 2>&1

# 最近 24h 的 service 故障
sudo journalctl -p 3 --since "24 hours ago" --no-pager 2>&1 | tail -20
```

- 存在 failed 服务 → ⚠️ WARN（每个记录）
- Hermes Gateway failed → ❌ CRITICAL
- sshd 协议错误（kex_protocol_error / kex_exchange_identification）是常见的扫描器噪声，不是入侵。详见 `references/ssh-kex-errors.md`

### Phase 10: Docker 安全检查

```bash
# 检查 Docker 是否安装
if command -v docker &>/dev/null; then
  docker info --format '{{.ServerVersion}}' 2>/dev/null && echo "Docker: installed" || echo "Docker: not running"

  # 检查 Docker 守护进程是否暴露 TCP（不安全）
  ss -tlnp 2>&1 | grep ":2375" && echo "❌ Docker TCP 端口 2375 暴露（无 TLS！）" || echo "✅ Docker TCP (2375): not exposed"

  # 列出运行中的容器
  docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null

  # 检查特权容器
  docker ps --filter "status=running" --format "{{.Names}}" 2>/dev/null | while read c; do
    PRIV=$(docker inspect "$c" --format '{{.HostConfig.Privileged}}' 2>/dev/null)
    [ "$PRIV" = "true" ] && echo "❌ 特权容器: $c"
  done

  # Docker socket 权限
  ls -la /var/run/docker.sock 2>/dev/null | grep -v "root:docker"
  
  # 检查 Docker 版本（太旧可能有漏洞）
  docker version --format '{{.Server.Version}}' 2>/dev/null
fi
```

- Docker TCP (2375) 暴露 → ❌ CRITICAL
- 存在特权容器 → ⚠️ WARN
- docker.sock 权限异常 → ⚠️ WARN
- Docker 版本 < 20.10 → ⚠️ WARN（可能有已知漏洞）

### Phase 11: SELinux / AppArmor

```bash
# SELinux
if command -v getenforce &>/dev/null; then
  echo "SELinux: $(getenforce 2>/dev/null)"
  sestatus 2>/dev/null | head -5
fi

# AppArmor
if command -v aa-status &>/dev/null; then
  sudo aa-status 2>/dev/null | head -10
fi
```

- SELinux disabled → ⚠️ WARN
- SELinux permissive → ⚠️ WARN
- SELinux enforcing → ✅

### Phase 12: 内核参数加固

```bash
# 关键安全相关的内核参数
echo "=== 内核安全参数 ==="
for param in \
  kernel.dmesg_restrict \
  kernel.kptr_restrict \
  kernel.randomize_va_space \
  net.ipv4.conf.all.rp_filter \
  net.ipv4.conf.all.accept_source_route \
  net.ipv4.tcp_syncookies \
  net.ipv4.ip_forward \
  net.ipv6.conf.all.disable_ipv6; do
  val=$(sysctl -n "$param" 2>/dev/null || echo "unset")
  echo "$param = $val"
done
```

CIS 基线：

| 参数 | 安全值 | 说明 |
|------|--------|------|
| kernel.dmesg_restrict | 1 | 禁止非root读取内核日志 |
| kernel.kptr_restrict | 2 | 隐藏内核指针地址 |
| kernel.randomize_va_space | 2 | ASLR 全开 |
| net.ipv4.conf.all.rp_filter | 1 | 反向路径过滤 |
| net.ipv4.conf.all.accept_source_route | 0 | 禁用源路由 |
| net.ipv4.tcp_syncookies | 1 | SYN Cookie 保护 |
| net.ipv4.ip_forward | 0 | 禁用 IP 转发（非路由器） |

> ⚠️ **Docker 交互注意**：如果服务器安装了 Docker，Docker 守护进程会自动设置 `net.ipv4.ip_forward=1`（容器网络桥接必需），并可能影响 `net.ipv4.conf.all.rp_filter`（取决于 Docker 网络驱动）。检查时如果发现 `ip_forward=1` 且 Docker 已安装，先判断是否是 Docker 导致的——`sysctl net.ipv4.ip_forward` 返回 1 但同时 Docker 已安装且运行中，这不算安全风险，报告中标注 "Docker 启用" 而不是扣分。

### Phase 13: 磁盘 & Inode

```bash
df -h / 2>&1
df -i / 2>&1
```

- 磁盘 > 80% → ⚠️ / > 92% → ❌
- Inode > 80% → ⚠️ / > 92% → ❌

### Phase 14: 内存 & Swap

```bash
free -h 2>&1
cat /proc/meminfo 2>&1 | grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree):"
```

- 可用内存 < 500MB → ⚠️ / < 200MB → ❌
- Swap 使用 > 50% → ⚠️ / > 80% → ❌

### Phase 15: 最近登录 & 认证日志

```bash
# 最近 5 个登录用户
last -n 10 2>/dev/null

# 当前登录用户
who 2>/dev/null

# 失败的认证尝试（非 SSH, 如 sudo 失败）
sudo journalctl -p err --since "24 hours ago" 2>/dev/null | grep -i "authentication\|auth:" | tail -10
```

### Phase 16: SSH 授权密钥审计

```bash
# pimou 的 authorized_keys
echo "=== pimou authorized_keys ==="
wc -l < ~/.ssh/authorized_keys
head -3 ~/.ssh/authorized_keys | awk '{print "  "substr($0,1,60)"..."}'

# root 的 authorized_keys
echo "=== root authorized_keys ==="
sudo cat /root/.ssh/authorized_keys 2>/dev/null | wc -l
sudo head -3 /root/.ssh/authorized_keys 2>/dev/null | awk '{print "  "substr($0,1,60)"..."}' || echo "  (none)"

# 检查是否有注释明确的「从属/临时」密钥
grep -c "^no-agent-forwarding\|^no-port-forwarding\|^command=" ~/.ssh/authorized_keys 2>/dev/null
```

- root 有 authorized_keys → ⚠️ 提醒确认是否必要
- 密钥数 > 5 → ⚠️ 提醒审计

### Phase 17: 系统更新

```bash
# 待更新数量
apt-get --just-print upgrade 2>/dev/null | grep -c "^Inst" || echo 0

# 安全更新
apt-get --just-print upgrade 2>/dev/null | grep -i security | wc -l || echo 0

# 上次更新时间
stat /var/lib/apt/periodic/update-success-stamp 2>/dev/null | grep Modify || echo "(未记录)"
```

- 总更新 > 10 → ⚠️ / > 30 → ❌
- 安全更新 > 3 → ⚠️ / > 10 → ❌
- 上次更新 > 30 天前 → ⚠️

### Phase 18: Auditd 审计状态

```bash
# 先检查是否安装（避免 sudo auditctl 被安全策略拦截）
if command -v auditctl &>/dev/null; then
  # auditd 已安装，检查运行状态和规则
  # 注意：sudo auditctl 命令可能被 Hermes 安全策略拦截（标记为"privilege flag"）
  # 被拦截时，可以退而使用 dpkg -l auditd 或 systemctl status auditd
  sudo auditctl -s 2>/dev/null | head -5 || echo "(auditctl status: blocked or unavailable)"
  sudo auditctl -l 2>/dev/null | head -10 || echo "(auditctl rules: blocked or unavailable)"
elif dpkg -l auditd 2>/dev/null | grep -q "^ii"; then
  echo "auditd: installed (package present, but auditctl not in PATH — check systemd)"
  sudo systemctl is-active auditd 2>/dev/null || echo "auditd: not running"
else
  echo "auditd: not installed"
fi
```

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

> ⚠️ **评分计算必须使用 `references/scoring-worked-example.md` 中的逐相位独立权重法**，不要使用上方简化分组表做组内平均。上方分组权重仅为快速参考（各组内相位权重之和），实际计算时应将每个 Phase 拆开，用独立权重逐项乘算后求和。示例文件包含完整的逐相位权重表和加权演算过程。

| 分数 | 等级 |
|------|------|
| ≥ 90 | ✅ **SECURE** |
| ≥ 70 | ⚠️ **NEEDS ATTENTION** |
| < 70 或任意 ❌ CRITICAL | ❌ **INSECURE** |

---

## 输出格式

```
╔═══════════════════════════════════════════════════╗
║        🛡️ 服务器安全健康报告 v2.1.0                ║
╚═══════════════════════════════════════════════════╝

📊 安全评分: 88/100 — ⚠️ NEEDS ATTENTION

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase 1 — 防火墙状态 (✅)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [OK] UFW ................... 活跃 (Status: active)

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase 3 — SSH 安全加固 (⚠️)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [OK] PermitRootLogin ....... no
  [OK] PasswordAuth ........... no
  [⚠] Port ................... 22 (默认端口，建议修改)
  [OK] MaxAuthTries ........... 3

...（每项类似）...

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  Phase 13 — 磁盘使用 (✅)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  [OK] 磁盘 .................. 30% used (27G free)
  [OK] Inode ................. 12% used

┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄┄

📋 行动项:
  1. [MED] SSH 使用默认端口 22 — 建议修改为高位端口
  2. [MED] 8 个待更新软件包
  3. [LOW] SELinux disabled — 考虑启用

📋 汇总: 18 项检查，14✅/3⚠️/1❌。安全状态可接受，建议修复中风险项。
```

---

## Watchdog 模式（紧急监控）

两种定时检查方式：

### 全量检查（LLM cron）

```bash
hermes cron create --name "安全全量检查" \
  --schedule "0 10,22 * * *" \
  --skill security-health-check \
  --prompt "执行完整安全健康检查。输出结构化中文报告。如有 CRITICAL 项或评分低于 70，明确告警。"
```

### 紧急监控（no_agent — 0 token 消耗）

使用 `scripts/emergency_monitor.sh`，每 30 分钟运行一次。

**前提条件：journalctl 免密码 sudo**

```bash
echo 'pimou ALL=(ALL) NOPASSWD: /usr/bin/journalctl' | sudo tee /etc/sudoers.d/emergency-monitor
sudo chmod 440 /etc/sudoers.d/emergency-monitor
```

**创建命令：**

```bash
hermes cron create --name "紧急安全监控" \
  --schedule "*/30 * * * *" \
  --script emergency_monitor.sh \
  --no-agent \
  --deliver qqbot:18D9D3E7BF1696DE25D3C0AE143E9515
```

**Watchdog 行为：** 仅 CRITICAL 级别输出（空 stdout = 不发送消息）

**深夜汇总报告：** 凌晨 5:30-6:00 自动输出整晚安全检查汇总（SSH 攻击统计、系统资源、安全事件），即使无 CRITICAL 告警也会发送。

**多平台投递（fallback）：** `deliver` 支持逗号分隔多个目标，优先发送到第一个，不可用时自动 fallback 到后续目标：
```
--deliver "qqbot:<chat_id>,feishu:<chat_id>"
```

---

## 注意事项 & 易错点

### Watchdog 脚本陷阱

- **`find` + `set -e` 静默退出**：`emergency_monitor.sh` 使用 `set -euo pipefail`。`find` 命令在找不到匹配文件时返回 exit code 1，会被 `set -e` 捕获导致脚本**静默退出**（无任何输出、无错误信息）。修复：所有 `find` 赋值命令必须加 `|| true`，例如 `BAD_SUID=$(find /tmp ... -perm -4000 -type f 2>/dev/null || true)`。调试此类问题时，临时将 `set -euo pipefail` 改为 `set -uo pipefail`（去掉 `-e`）可快速定位是否是 `set -e` 导致的。
- `ufw status` 可能在云服务器上返回 `Status: inactive`（云厂商使用 iptables/nftables）。配合 `iptables -L -n` 交叉验证。
- `journalctl` 需要 sudo 权限。如果没有 passwordless sudo，跳过 journalctl 相关检查。
- `fail2ban` 为可选依赖。未安装时不影响其他检查。
- 首次运行时 SSH 暴力破解阈值建议从宽松开始（100/24h），逐渐收紧。
- `/etc/shadow` 中 `!!` 表示账户已被锁定（安全），`!` + 空字符串才是空密码。

### Hermes 安全策略限制
- `sudo ufw status` / `sudo iptables -L -n`（Phase 1）需要终端输入密码，在 cron 模式下会失败。依赖云服务器安全组作为主防御层，报告中标注"因安全策略无法验证"即可。
- `sudo sed -i ... /etc/ssh/sshd_config`（Phase 3 自动修复）被 Hermes 安全策略拦截（判定为"in-place edit of system config"）。**SSH 修复无法在本次会话中自动完成**——必须在终端中手动执行。报告中列出完整修复命令供用户复制，不要允诺"自动修复完成"。
- `sudo awk ... /etc/shadow`（Phase 6）可能被 Hermes 安全扫描拦截（变体选择子检测）。被拦截时依然能从已有的 `/etc/passwd` 信息判断大部分安全问题（UID 0 非 root、空 shell 等）。
- `sudo auditctl -s` 和 `sudo auditctl -l`（Phase 18）可能被标记为"privilege flag"而拦截。Skill 2.0.0+ 已提供 `command -v` + `dpkg -l` 退路路径，直接执行即可。注意：**不要将多个 sudo 命令包装在 `if-then-elif` 单行中**——Hermes 策略会扫描整个命令文本，如果包含 `sudo auditctl`（即使 `command -v` 会先返回 false），仍会被标记为"privilege flag"而整个拒绝。应分别用独立的 `terminal()` 调用执行 `command -v auditctl` → `dpkg -l auditd` → 分步判断。
- 如果某个 Phase 的 sudo 命令被持续拦截，跳过该子项、继续后续检查，不要重试同一命令三次以上。报告中标明"因安全策略跳过"即可。

### Docker
- Docker TCP 暴露 (2375 无 TLS) 在云服务器上极其危险——等于把 root 权限开放给任何人。
- 特权容器可以突破容器隔离，应尽量避免。
- Docker socket (`/var/run/docker.sock`) 只应属于 `root:docker` 组。
- ⚠️ **ufw 路由阻断**：如果 ufw 启用且 `DEFAULT_ROUTING="deny"`，Docker 容器无法连接宿主机服务（如 MySQL、Redis）。诊断方法：检查 `sudo ufw status verbose` 中是否有 `deny (routed)`，然后从容器内测试连接。修复方案见 `docker-firewall-integration` skill。

### 云服务器特有
- 阿里云/腾讯云安全组提供网络层防火墙，UFW/iptables 是主机层补充。
- 云平台的 SSH 登录告警在控制台已有，主机级检查作为补充验证。
- 云服务器通常无 swap，这是设计使然——非问题。

### 安全
- 不要在输出中泄露完整 IP（SSH 攻击来源 IP 除外，那是需要展示的）。
- `authorized_keys` 只显示前 60 字符，不显示完整公钥。
- 暴露的 /etc/shadow 哈希值绝不在输出中展示——只检查空密码和锁定状态。
- 如果检查脚本被用于 cron，确保 sudo 策略文件 (emergency-monitor) 的最小权限原则（`NOPASSWD: /usr/bin/journalctl` 而不是 `ALL`）。
