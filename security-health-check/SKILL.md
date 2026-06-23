---
name: security-health-check
description: "Production-grade server security health check — firewall audit, SSH hardening, brute force detection, rootkit/malware scan, user audit, SUID audit, Docker security, systemd health, kernel hardening, crontab analysis, disk/memory thresholds. Supports interactive mode and no-agent cron watchdog."
version: 2.5.0
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
- ⚠️ **Docker 桥接网络误判**：172.17.0.x 是 Docker 默认桥接网络 IP，绑定在此上的服务（如 172.17.0.1:3306）**不直接暴露给互联网**——除非有端口映射（`-p 3306:3306`）。检查时应排除 172.17.0.x/172.18.0.x 等 Docker 桥接网段，仅关注绑定到 0.0.0.0 或公网 IP 的端口

### Phase 3: SSH 安全加固检查

```bash
# SSH 配置完整检查
sudo grep -E "^PermitRootLogin|^PasswordAuthentication|^Port |^MaxAuthTries|^ClientAliveInterval|^ClientAliveCountMax|^AllowUsers|^PubkeyAuthentication|^ChallengeResponseAuthentication" /etc/ssh/sshd_config 2>/dev/null | grep -v "^#"

# SSH 端口是否正在监听（注意实际端口，不一定是 22）
ss -tlnp 2>&1 | grep -E "sshd|ssh"

# ⚠️ 检查 socket 激活（Ubuntu 23.10+ 默认启用，会覆盖 sshd_config 端口设置）
sshd -T 2>/dev/null | grep "^port "   # 有效配置中的端口（socket 激活时可能为空）
sudo systemctl is-active ssh.socket 2>/dev/null   # socket 是否活跃
# 注意：socket 激活时 ss -tlnp | grep ssh 也会返回空（无进程名），
# 用端口号定位：ss -tlnp | grep 2222

# ⚠️ 综合诊断流程（推荐执行顺序）：
# 1. 先检查 ssh.socket 是否活跃
# 2. 如果活跃，用端口号（如 2222）在 ss 输出中定位，不要用进程名 grep
# 3. sshd -T 在 socket 激活时返回空（exit code 1），不代表 SSH 未运行
# 4. 有效端口 = ssh.socket 的 ListenStream（override.conf 或默认 22）
# 如果 ssh.socket 活跃且 sshd -T 返回空，仍应检查 sshd_config 中的
# PermitRootLogin / PasswordAuthentication 等安全配置项（这些不受 socket 影响）
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
> ⚠️ **`sshd -T` 在 socket 激活时返回空**：当 `ssh.socket` 活跃时，`sshd -T | grep "^port "` 可能返回空输出（exit code 1），因为 sshd 进程并非持久运行、端口由 socket 单元控制。
>
> ⚠️ **`ss -tlnp | grep ssh` 在 socket 激活时也返回空**：socket-activated 服务（如 `ssh.socket`）在 `ss -tlnp` 输出中**没有进程名列**（该列为空），因此 `grep ssh` 匹配不到任何内容。这是 2026-06 实测发现的坑。**诊断方法**：直接查看完整 `ss -tlnp` 输出，用端口号（如 `grep 2222`）而非进程名来定位 SSH 监听。`sshd -T` 仅作为辅助参考（它返回的是 sshd_config 中的静态配置，不代表运行时端口）。
>
> ⚠️ **Hermes 安全策略注意**：`sudo sed -i` 修改 `/etc/ssh/sshd_config` 可能被安全策略拦截（判定为"in-place edit of system config"）。拦截后**不要重试**——在报告中列出修复命令供用户手动执行即可。`sudo tee -a` 和 `sudo systemctl restart ssh` 通常不受影响。
>
> ⚠️ 修改 SSH 配置前先确保当前 SSH 会话不会中断（例如：用 screen/tmux 或开第二个窗口测试）。`PermitRootLogin` 和 `PasswordAuthentication` 是最高优先级的修复项。

### Phase 4: SSH 暴力破解检测

> ⚠️ **Ubuntu 服务名称**：Ubuntu 的 SSH 服务名是 `ssh`，不是 `sshd`。以下示例使用 `ssh`，CentOS/RHEL 需改为 `sshd`。不确定时运行 `systemctl list-units | grep ssh` 确认。

```bash
# 最近24小时的失败登录（Ubuntu 用 ssh，CentOS 用 sshd）
sudo journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep "Failed password"

# 统计数据
SSH_FAILS=$(sudo journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Failed password" || true)
SSH_INVALID=$(sudo journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep -c "Invalid user" || true)

# Top 10 攻击来源 IP
sudo journalctl -u ssh --since "24 hours ago" 2>/dev/null | grep "Failed password" | grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | sort | uniq -c | sort -rn | head -10

# 检查 lastb 记录
lastb 2>/dev/null | head -10

# 检查 fail2ban 状态（如果安装了）
sudo fail2ban-client status sshd 2>/dev/null || echo "fail2ban not installed"
```

阈值：
- > 20 次/24h → ⚠️ WARN
- > 100 次/24h → ❌ CRITICAL
- 有 fail2ban 且正常运行 → 风险等级降一级（❌ 降为 ⚠️，⚠️ 降为 ✅）

**极端攻击量场景（1000+ 次/24h）的评分决策：**
即使 fail2ban 活跃，攻击量达到四位数时 fail2ban 只能延缓而非消除风险（攻击者不断换 IP）。评分规则：
- ≤ 500 次 + fail2ban 活跃 → ✅ 2/2（fail2ban 有效控制）
- 500-2000 次 + fail2ban 活跃 → ⚠️ 1/2（fail2ban 在工作但压力大）
- > 2000 次 + fail2ban 活跃 → ⚠️ 1/2（仍优于 ❌，但需报告攻击规模）
- 无 fail2ban + > 100 次 → ❌ 0/2

> 深度分析（按时间范围、攻击类型分类、IP/用户名统计）见 `references/ssh-brute-force-log-analysis.md`。当用户要求分析特定时间段的攻击（如"昨晚"、"过去3天"）时，使用该参考文件中的方法。

### Phase 5: 恶意进程 & Rootkit 扫描

> ⚠️ **必须拆分为独立 terminal 调用**——不要把多个检查合并到一个 bash 块中。Hermes terminal 工具会将 `&&` 误解析为后台操作符（`&`），导致 "Foreground command uses '&' backgrounding" 错误。每组检查用独立的 `terminal()` 调用。

```bash
# 检查 1：标准恶意软件特征（独立调用）
ps aux 2>/dev/null | grep -iE "xmrig|cryptonight|minerd|stratum|kinsing|kdevtmpfsi|pwnrig|masscan|sustes|watchbog|jenkinx|sysupdate|networkservice|gates|lady|ddgs" | grep -v grep || echo "MALWARE: none"

# 检查 2：高 CPU 异常进程（独立调用）
ps aux --sort=-%cpu 2>/dev/null | head -6

# 检查 3：隐藏进程检查（独立调用）
ls /proc/ 2>/dev/null | grep -E '^[0-9]+$' | sort -n | tail -5

# 检查 4：异常网络连接（独立调用）
ss -tunap 2>&1 | grep -v "users:((" | head -10

# 检查 5：可疑文件（独立调用）
find /dev/shm /tmp -type f \( -executable -o -name "*.sh" -o -name "*.pl" \) -newer /etc/passwd 2>/dev/null | head -10

# 检查 6：挖矿路径（独立调用）
for d in /dev/shm /tmp /var/tmp /var/spool/cron; do ls -la "$d" 2>/dev/null | grep -iE "xmrig|minerd|kinsing|kdevtmpfsi"; done || echo "MINING: none"
```

- 匹配到挖矿/后门进程 → ❌ CRITICAL
- 发现隐藏进程、无主连接 → ⚠️ WARN
- /dev/shm 和 /tmp 有新近可执行文件 → ⚠️ WARN
- ⚠️ **Hermes 临时脚本误判**：Hermes 自身会在 `/tmp` 创建 `hermes-snap-*.sh`（terminal 会话快照）和 `test_*.sh`（调试脚本），这些文件会被 Phase 5 的 `find /tmp` 捕获。**不要将它们标记为可疑**——它们属于 pimou 用户且文件名匹配 `hermes-` 或 `test_` 前缀时应排除。报告中可标注 INFO 级别说明发现的是 Hermes 临时文件。

### Phase 6: 用户账户审计

```bash
# 列出所有可登录用户（uid >= 1000 且有 shell）
grep -E "^[^:]+:[^:]+:[0-9]+" /etc/passwd 2>/dev/null | awk -F: '$3 >= 1000 || $3 == 0 {print "User: "$1" (UID: "$3", Shell: "$NF")"}'

# 空密码账户（注：Hermes 安全策略可能拦截此命令，被拦截时跳过即可）
# 注意：$2 == "!" 是锁定账户（安全），不要误判为空密码！仅 $2 == "" 才是空密码
sudo awk -F: '$2 == "" && $3 != 65534 {print "⚠️ Empty/no password: "$1}' /etc/shadow 2>/dev/null

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

> ⚠️ **`find / -perm -4000` 超时陷阱**：全盘 SUID 搜索（`find / -perm -4000 -type f`）在大磁盘或高 inode 使用的服务器上容易超过 30 秒超时。**分步执行**：先用 `find / -perm -4000 -type f 2>/dev/null | head -20`（带 head 截断）或限定范围 `find /usr /bin /sbin -perm -4000 -type f`。如果全盘搜索超时，优先检查高风险目录（`/tmp /dev/shm /var/tmp /home`），全量 SUID 列表可标记为"因超时跳过"。

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

> ⚠️ **Docker 检查必须拆分为独立 terminal 调用**。`if/else/fi` 块在 Hermes terminal 工具中会因 bash `eval` 包装器而报语法错误（`else` token error）。先用 `command -v docker` 判断是否安装，再分步执行各项检查。

```bash
# 步骤 1：检查 Docker 是否安装（独立调用）
command -v docker && echo "Docker: installed" || echo "Docker: not installed"

# 步骤 2：版本（独立调用）
docker version --format '{{.Server.Version}}' 2>/dev/null

# 步骤 3：TCP 2375 暴露检查（独立调用）
ss -tlnp 2>&1 | grep ":2375" && echo "EXPOSED" || echo "Docker TCP 2375: not exposed"

# 步骤 4：运行中容器（独立调用）
docker ps --format "table {{.Names}}\t{{.Image}}\t{{.Status}}\t{{.Ports}}" 2>/dev/null

# 步骤 5：Docker socket 权限（独立调用）
ls -la /var/run/docker.sock 2>/dev/null
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
# ⚠️ sudo PATH 陷阱：aa-status 通常在 /usr/sbin/，而 sudo 的 secure_path
# 可能不包含 /usr/sbin，导致 `sudo aa-status` 静默失败（空输出）。
# 修复：检测完整路径后用 sudo 调用全路径。
AA_PATH=$(command -v aa-status 2>/dev/null || [ -x /usr/sbin/aa-status ] && echo "/usr/sbin/aa-status")
if [ -n "$AA_PATH" ]; then
  sudo "$AA_PATH" 2>/dev/null | head -10
fi
```

**AppArmor 降级检查**（aa-status 不可用时的退路）：

```bash
# Ubuntu 24.04+ 即使安装了 AppArmor，aa-status 也可能不在 PATH 中。
# 降级方案：检查内核模块是否加载 + dpkg 确认已安装。
cat /sys/module/apparmor/parameters/enabled 2>/dev/null  # 返回 Y = 已加载
dpkg -l apparmor 2>/dev/null | grep -E "^ii"             # 确认已安装
```

- aa-status 返回 profiles/enforced 信息 → ✅
- 内核模块已加载 (Y) + 已安装 → ✅ (降级确认)
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

### 逐相位权重表（直接使用，无需再查参考文件）

| Phase | 权重 | 评分规则 |
|-------|------|----------|
| 1. 防火墙 | 6% | ✅=2, ⚠️=1, ❌=0 |
| 2. 端口审计 | 6% | ✅=2, ⚠️=1, ❌=0 |
| 3. SSH 加固 | 7.5% | **任何 ❌ CRITICAL → 整个 Phase = 0/2**（不取平均） |
| 4. SSH 暴力破解 | 7.5% | ≤500+fail2ban→✅, 500-2000+fail2ban→⚠️, >2000+fail2ban→⚠️, 无fail2ban+>100→❌ |
| 5. 恶意进程 | 20% | ✅=2, ⚠️=1, ❌=0 |
| 6. 用户审计 | 5% | ✅=2, ⚠️=1, ❌=0 |
| 7. SUID/SGID | 5% | ✅=2, ⚠️=1, ❌=0 |
| 8. Crontab | 5% | ✅=2, ⚠️=1, ❌=0 |
| 9. Systemd | 5% | ✅=2, ⚠️=1, ❌=0 |
| 10. Docker | 5% | ✅=2, ⚠️=1, ❌=0 |
| 11. SELinux/AppArmor | 4% | ✅=2, ⚠️=1, ❌=0 |
| 12. 内核参数 | 4% | ✅=2, ⚠️=1, ❌=0 |
| 13. 磁盘 | 5% | ✅=2, ⚠️=1, ❌=0 |
| 14. 内存 | 5% | ✅=2, ⚠️=1, ❌=0 |
| 15. 登录日志 | 2.5% | ✅=2, ⚠️=1, ❌=0 |
| 16. SSH 密钥 | 2.5% | ✅=2, ⚠️=1, ❌=0 |
| 17. 系统更新 | 2.5% | ✅=2, ⚠️=1, ❌=0 |
| 18. Auditd | 2.5% | ✅=2, ⚠️=1, ❌=0 |

### 加权公式

```
phase_contribution = (score / 2.0) × weight_percentage
total = sum(all phase_contributions), rounded to integer
```

### 关键评分陷阱

1. **Phase 3 一票否决**：SSH 加固中出现任何 ❌ CRITICAL（如 PasswordAuthentication=yes、PermitRootLogin=yes），**整个 Phase 直接判 0/2**，不要因为其他子项通过就给 1/2 或 2/2。这是最常见的评分错误。
2. **Phase 4 + fail2ban**：fail2ban 活跃时，攻击量阈值可适当放宽（见 Phase 4 详细规则）。
3. **Phase 12 + Docker**：`ip_forward=1` 在 Docker 已安装时不算安全风险，不扣分。
4. **Phase 18 auditd**：未安装 = ⚠️ (1/2)，不是 ❌。
5. **Phase 9 sudo auth 失败 ≠ failed 服务**：journalctl 中出现 `pam_unix(sudo:auth): conversation failed` 是 cron 任务的 sudo 认证问题（通常是 sudoers.d 配置不完整），**不是 systemd 服务失败**。不要因此将 Phase 9 降为 1/2——只要 `systemctl --failed` 返回空，Phase 9 就是 2/2。这类 sudo auth 错误应在报告中作为 INFO 标注，提醒用户检查 cron 任务的 sudoers 配置。

> 📖 完整演算示例见 `references/scoring-worked-example.md`。

### 评分双重评估（重要）

评分由两个独立系统组成，**不要混淆**：

1. **数值评分**：按加权公式计算，范围 0-100，用于 `📊 安全评分: X/100` 行
2. **安全等级**：基于数值评分 + CRITICAL 覆盖规则，用于最终判定

```
数值评分 = Σ (phase_score / 2.0 × weight%)，四舍五入到整数

安全等级判定：
  ≥ 90 → ✅ SECURE
  ≥ 70 且无任何 ❌ CRITICAL → ⚠️ NEEDS ATTENTION
  < 70 或任意 ❌ CRITICAL → ❌ INSECURE
```

**常见错误**：数值评分为 83（NEEDS ATTENTION 级别），但因 Phase 3 存在 CRITICAL，最终等级为 INSECURE。这是**正确的**——报告应显示 `📊 安全评分: 83/100 — ❌ INSECURE`（因 CRITICAL 覆盖），**不要**为了匹配 INSECURE 等级而篡改数值评分为 <70。

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

**每日汇总报告：** 早上 8:00-8:30 自动输出整晚安全检查汇总（SSH 攻击统计、系统资源、安全事件），即使无 CRITICAL 告警也会发送。

**多平台投递（fallback）：** `deliver` 支持逗号分隔多个目标，优先发送到第一个，不可用时自动 fallback 到后续目标：
```
--deliver "qqbot:<chat_id>,feishu:<chat_id>"
```

---

## 注意事项 & 易错点

### Skill 更新说明

本 skill 是 **local** 来源（本地创建/维护），不是从官方 hub 安装的。因此：

- `hermes skills check` **不会**检查本 skill 的更新（只检查 `official` 和 `builtin` 来源）
- `hermes skills update` **不会**更新本 skill
- 如需更新，需手动对比远程仓库（如有）或直接编辑 `~/.hermes/skills/security-health-check/SKILL.md`
- 版本号在 SKILL.md frontmatter 的 `version` 字段中维护（当前: 2.5.0）

与之对比：`hermes-agent` 是 `builtin` 来源，随 Hermes 核心更新；`pixel-art`、`creative-ideation` 等是 `official` 来源，通过 `hermes skills update` 自动更新。

### Watchdog 脚本陷阱

- **`no_agent` cron 脚本写入 `/var/log/` 权限被拒**：Hermes `no_agent` cron 脚本以当前用户身份运行，没有继承 sudo 上下文。脚本中 `echo "..." >> /var/log/xxx.log` 会因 Permission denied 失败，exit code 为 1，**Hermes 会把 stderr 当作消息发送给用户**（表现为"明明没有异常却收到了通知"）。修复：所有写入系统路径的 echo 必须用 `echo "..." | sudo tee -a /var/log/xxx.log > /dev/null` 代替 `>>` 重定向。诊断方法：检查 `~/.hermes/cron/output/<job_id>/` 下最近的 `.md` 文件，看是否有 `Permission denied` 错误。相关 commit: `ssh-bruteforce-guard/scripts/monitor.sh`。
- **静默 Watchdog 模式**：高频定时监控脚本（每小时/每30分钟）应默认静默——无异常时 stdout 为空（不发送通知），只在检测到问题时才输出。实现方式：正常路径 `exit 0` 且不 echo 到 stdout，异常路径才 echo 到 stdout。本地日志用 `sudo tee -a` 始终记录，便于事后排查。用户明确表示不希望"每小时都收到消息"，只在有新封禁/新异常时通知。
- **`find` + `set -e` 静默退出**：`emergency_monitor.sh` 使用 `set -euo pipefail`。`find` 命令在找不到匹配文件时返回 exit code 1，会被 `set -e` 捕获导致脚本**静默退出**（无任何输出、无错误信息）。修复：所有 `find` 赋值命令必须加 `|| true`，例如 `BAD_SUID=$(find /tmp ... -perm -4000 -type f 2>/dev/null || true)`。调试此类问题时，临时将 `set -euo pipefail` 改为 `set -uo pipefail`（去掉 `-e`）可快速定位是否是 `set -e` 导致的。
- `ufw status` 可能在云服务器上返回 `Status: inactive`（云厂商使用 iptables/nftables）。配合 `iptables -L -n` 交叉验证。
- `journalctl` 需要 sudo 权限。如果没有 passwordless sudo，跳过 journalctl 相关检查。
- `fail2ban` 为可选依赖。未安装时不影响其他检查。
- 首次运行时 SSH 暴力破解阈值建议从宽松开始（100/24h），逐渐收紧。
- `/etc/shadow` 密码字段含义：`$id$salt$hash` = 有密码哈希，`!` 或 `!!` = 账户已锁定（安全，不应报警），`*` = 账户禁用，`` (空字符串) = 无密码（CRITICAL）。Phase 6 的 awk 检查仅匹配 `$2 == ""`（真正空密码），不匹配 `!`（锁定）。

### Hermes 安全策略限制

- **Terminal 工具 `&&` 误解析**：Hermes terminal 工具会将 bash 命令中的 `&&` 误解析为后台操作符（`&`），导致 "Foreground command uses '&' backgrounding" 错误。**所有多步骤 bash 命令必须拆分为独立的 `terminal()` 调用**，不要用 `&&` 串联。同样，`if/else/fi` 块在 `eval` 包装器中会报 `syntax error near unexpected token 'else'`——Docker 等条件检查也必须拆分。已知受影响的 Phase：5（恶意进程）、10（Docker）。其他 Phase 如需组合命令，同样应拆分。
- `sudo ufw status` / `sudo iptables -L -n`（Phase 1）需要终端输入密码，在 cron 模式下会失败。依赖云服务器安全组作为主防御层，报告中标注"因安全策略无法验证"即可。
- `sudo sed -i ... /etc/ssh/sshd_config`（Phase 3 自动修复）被 Hermes 安全策略拦截（判定为"in-place edit of system config"）。**SSH 修复无法在本次会话中自动完成**——必须在终端中手动执行。报告中列出完整修复命令供用户复制，不要允诺"自动修复完成"。
- **Emoji/Unicode 变体选择子拦截**：Hermes 安全策略会扫描 terminal 命令中的 Unicode 变体选择子（VS1-256），触发 `tirith:variation_selector` 检测。**任何包含 emoji 字符（✅、⚠️、❌、🛡️ 等）的 terminal 命令都会被拦截**，包括 `sudo awk ... /etc/shadow`（Phase 6）和 `echo` 汇总块。**规避方法**：在 terminal 命令中使用纯 ASCII 文本（如 `[OK]`、`[WARN]`、`[CRITICAL]`），不要使用 emoji。报告的最终输出（作为 agent response 而非 terminal 命令）可以正常使用 emoji。
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
- 完整的 `no_agent` cron 脚本编写陷阱（权限、静默模式、日志写入）见 `references/no_agent-cron-script-patterns.md`。