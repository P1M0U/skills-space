# 🔒 SSH Bruteforce Guard

SSH暴力破解自动封禁监控 — 检测每小时攻击超过阈值的IP，自动通过fail2ban和ufw执行封禁拉黑。

## 🎯 功能

- 自动分析 /var/log/auth.log 中的失败登录记录
- 统计每个IP在过去1小时内的攻击次数
- 超过阈值（默认30次/小时）的IP自动封禁
- 支持 fail2ban 和 ufw 双重封禁
- **静默模式**：无新封禁时不发送通知，只在有新封禁时告警
- 详细的封禁日志记录

## 📦 安装

### 方式一：一键安装（推荐）

告诉你的 Hermes Agent：

> 请帮我安装 ssh-bruteforce-guard skill，从 https://github.com/P1M0U/skills-space 仓库

Agent 会自动执行：

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/ssh-bruteforce-guard ~/.hermes/skills/security/

# 复制监控脚本
mkdir -p ~/.hermes/scripts/ssh-guard
cp /tmp/skills-space/ssh-bruteforce-guard/scripts/monitor.sh ~/.hermes/scripts/ssh-guard/
chmod +x ~/.hermes/scripts/ssh-guard/monitor.sh

# 清理
rm -rf /tmp/skills-space
```

### 方式二：手动安装

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/ssh-bruteforce-guard ~/.hermes/skills/security/

# 复制监控脚本
mkdir -p ~/.hermes/scripts/ssh-guard
cp /tmp/skills-space/ssh-bruteforce-guard/scripts/monitor.sh ~/.hermes/scripts/ssh-guard/
chmod +x ~/.hermes/scripts/ssh-guard/monitor.sh

# 清理
rm -rf /tmp/skills-space
```

## 🚀 使用

### 手动运行

```bash
sudo ~/.hermes/scripts/ssh-guard/monitor.sh
```

### 定时任务（推荐）

```bash
# 每小时运行一次（无新封禁时静默，有新封禁时通知）
hermes cron create --name "SSH暴力破解监控" \
  --schedule "0 * * * *" \
  --script ssh-guard/monitor.sh \
  --no-agent \
  --deliver "qqbot:你的chat_id"
```

## ⚙️ 配置

编辑 `~/.hermes/scripts/ssh-guard/monitor.sh` 顶部的变量：

```bash
THRESHOLD=30  # 封禁阈值：每小时尝试次数
```

## 📋 常用命令

```bash
# 查看封禁日志
tail -f /var/log/ssh-guard.log

# 查看ufw封禁
sudo ufw status | grep DENY

# 查看fail2ban封禁
sudo fail2ban-client status sshd

# 解封IP
sudo ufw delete deny from <IP>
sudo fail2ban-client set sshd unbanip <IP>
```

## 📄 License

MIT