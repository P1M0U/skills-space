---
name: ssh-bruteforce-guard
description: "SSH暴力破解自动封禁监控 — 检测每小时攻击超过阈值的IP，自动通过fail2ban和ufw执行封禁拉黑"
version: 1.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [security, ssh, fail2ban, ufw, bruteforce, monitoring]
    related_skills: [security-health-check]
---

# SSH暴力破解自动封禁监控

自动检测SSH暴力破解攻击，对超过阈值的IP执行封禁：
- 分析 /var/log/auth.log 中的失败登录记录
- 统计每个IP在过去1小时内的攻击次数
- 超过30次/小时的IP自动通过 fail2ban 和 ufw 封禁
- 记录封禁日志到 /var/log/ssh-guard.log

## 前置条件

1. **fail2ban** 已安装并运行
   ```bash
   sudo systemctl status fail2ban
   ```

2. **ufw** 已安装并激活
   ```bash
   sudo ufw status
   ```

3. **SSH端口**：确认你的服务器SSH端口（默认22或自定义）

## 脚本位置

```
~/.hermes/scripts/ssh-guard/monitor.sh
```

## 手动运行测试

```bash
# 运行监控脚本
sudo ~/.hermes/scripts/ssh-guard/monitor.sh
```

## 配置定时任务

使用 Hermes cron 每小时运行一次：

```bash
hermes cron create \
  --name "SSH暴力破解监控（每小时）" \
  --schedule "0 * * * *" \
  --script ssh-guard/monitor.sh \
  --no-agent \
  --deliver "你的通知频道"
```

## 封禁阈值

默认阈值：**30次/小时**

修改阈值：编辑脚本顶部的 `THRESHOLD=30` 变量

## 日志文件

- 监控日志：`/var/log/ssh-guard.log`
- 系统认证日志：`/var/log/auth.log`

## 注意事项

1. **需要sudo权限**：脚本需要root权限读取日志和执行封禁
2. **误封风险**：阈值设置过低可能误封正常用户，建议先观察几天再调整
3. **解封方法**：
   ```bash
   # 从ufw解封
   sudo ufw delete deny from <IP>
   
   # 从fail2ban解封
   sudo fail2ban-client set sshd unbanip <IP>
   ```

4. **查看当前封禁**：
   ```bash
   # ufw封禁列表
   sudo ufw status | grep DENY
   
   # fail2ban封禁列表
   sudo fail2ban-client status sshd
   ```