# no_agent Cron 脚本编写陷阱

## 权限问题

`no_agent` cron 脚本以当前用户身份运行，**不继承 sudo 上下文**。

### 错误写法
```bash
echo "log entry" >> /var/log/app.log    # Permission denied!
echo "log entry" >> /etc/config.txt     # Permission denied!
```

### 正确写法
```bash
echo "log entry" | sudo tee -a /var/log/app.log > /dev/null
echo "log entry" | sudo tee -a /etc/config.txt > /dev/null
```

### 诊断

检查 cron 运行输出：
```bash
ls ~/.hermes/cron/output/<job_id>/
cat ~/.hermes/cron/output/<job_id>/<timestamp>.md
```

看到 `Permission denied` + `exit code 1` 就是这个问题。

## 静默 Watchdog 模式

高频监控脚本（每小时/每30分钟）应默认静默：

```bash
#!/bin/bash
set -e

# ... 检测逻辑 ...

if [ "$ANOMALY_COUNT" -gt 0 ]; then
    # 有异常 → 输出到 stdout（触发通知）
    echo "🚨 告警：检测到 $ANOMALY_COUNT 个异常"
    echo "详情..."
fi

# 无异常 → stdout 为空，不发送通知
# 本地日志始终记录（用 sudo tee）
```

### 为什么

用户不希望每小时都收到"一切正常"的消息。只在有新问题时通知。

### Hermes cron 行为

- `no_agent: true` 时，脚本 stdout 直接作为消息发送
- stdout 为空 = 静默（不发送）
- exit code 非 0 = 错误消息发送给用户

## 日志写入模式

始终用 `sudo tee -a` 而非 `>>` 写系统日志：

```bash
BAN_LOG="/var/log/ssh-guard.log"

# 正确
echo "=== 监控开始 ===" | sudo tee -a "$BAN_LOG" > /dev/null

# 错误（Permission denied）
echo "=== 监控开始 ===" >> "$BAN_LOG"
```

重定向 `>` 和 `>>` 在 shell 层面执行，不经过 sudo。
