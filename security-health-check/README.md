# 🛡️ Security Health Check

生产级服务器安全审计 — 18 项 CIS 级别检查、SSH 加固、恶意进程扫描、Docker 安全。

## 🎯 功能

覆盖 **18 个安全检查领域**：

| Phase | 检查项 | 严重级别 |
|-------|--------|----------|
| 1 | 防火墙状态（UFW / iptables / nftables） | 🔴 CRITICAL |
| 2 | 监听端口审计（暴露服务检测） | 🟠 WARN |
| 3 | SSH 安全加固（7 项 CIS 基线） | 🔴 CRITICAL |
| 4 | SSH 暴力破解检测（Top 10 IP + fail2ban） | 🔴 CRITICAL |
| 5 | 恶意进程 & Rootkit 扫描 | 🔴 CRITICAL |
| 6 | 用户账户审计（UID 0、空密码、sudo 权限） | 🔴 CRITICAL |
| 7 | SUID/SGID 提权攻击检测 | 🔴 CRITICAL |
| 8 | Crontab 安全检查 | 🔴 CRITICAL |
| 9 | Systemd 服务健康 | 🟠 WARN |
| 10 | Docker 安全检查 | 🔴 CRITICAL |
| 11 | SELinux / AppArmor 状态 | 🟠 WARN |
| 12 | 内核参数加固（8 项 CIS） | 🟠 WARN |
| 13 | 磁盘 & Inode | 🟠 WARN |
| 14 | 内存 & Swap | 🟠 WARN |
| 15 | 最近登录 & 认证日志 | ℹ️ INFO |
| 16 | SSH 授权密钥审计 | 🟠 WARN |
| 17 | 系统更新状态 | 🟠 WARN |
| 18 | Auditd 审计状态 | ℹ️ INFO |

## 📦 安装

### 方式一：一键安装（推荐）

告诉你的 Hermes Agent：

> 请帮我安装 security-health-check skill，从 https://github.com/P1M0U/skills-space 仓库

Agent 会自动执行：

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/security-health-check ~/.hermes/skills/

# 复制监控脚本（如果需要紧急监控）
mkdir -p ~/.hermes/scripts
cp /tmp/skills-space/security-health-check/scripts/emergency_monitor.sh ~/.hermes/scripts/

# 清理
rm -rf /tmp/skills-space
```

### 方式二：手动安装

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/security-health-check ~/.hermes/skills/

# 清理
rm -rf /tmp/skills-space
```

## 🚀 使用

### 交互式检查

在 Hermes 会话中说：

```
安全检查
```

或

```
安全扫描
```

### 定时任务

```bash
# 全量检查（每天 10:00/22:00）
hermes cron create --name "安全全量检查" \
  --schedule "0 10,22 * * *" \
  --skill security-health-check \
  --prompt "执行完整安全健康检查。如有 CRITICAL 项或评分低于 70，明确告警。"

# 紧急监控（每 30 分钟，0 token 消耗）
# 先配置 journalctl 免密码 sudo：
echo 'pimou ALL=(ALL) NOPASSWD: /usr/bin/journalctl' | sudo tee /etc/sudoers.d/emergency-monitor
sudo chmod 440 /etc/sudoers.d/emergency-monitor

# 然后创建 cron
hermes cron create --name "紧急安全监控" \
  --schedule "*/30 * * * *" \
  --script emergency_monitor.sh \
  --no-agent \
  --deliver "qqbot:你的chat_id"
```

## 📊 评分系统

| 分数 | 等级 | 说明 |
|------|------|------|
| ≥ 90 | ✅ SECURE | 安全 |
| ≥ 70 | ⚠️ NEEDS ATTENTION | 需要关注 |
| < 70 或任意 CRITICAL | ❌ INSECURE | 不安全 |

## ⚠️ 注意事项

- 需要 sudo 权限执行大部分检查
- 部分命令可能被 Hermes 安全策略拦截（如 `sudo sed -i`）
- 首次运行建议使用宽松阈值，逐步收紧
- Docker 环境需要额外检查 Docker 安全配置

## 📄 License

MIT