# SSH 暴力破解日志深度分析

当用户要求分析 SSH 暴力破解攻击（如"统计昨天晚上的攻击"、"分析 SSH 攻击日志"）时，使用以下方法。

## 日志位置

| 系统 | 路径 |
|------|------|
| Ubuntu/Debian | `/var/log/auth.log` |
| CentOS/RHEL | `/var/log/secure` |
| systemd 通用 | `journalctl -u sshd --since "24 hours ago"` |

优先用 `auth.log`/`secure`（时间跨度大、无 sudo 限制），`journalctl` 作为补充。

## 攻击类型分类

SSH 异常连接分为 6 类，grep 模式如下：

```bash
# 1. 密码认证失败（最直接的暴力破解证据）
grep "Failed password" /var/log/auth.log | grep "<日期>"

# 2. 无效用户尝试（字典攻击特征）
grep "Invalid user" /var/log/auth.log | grep "<日期>"

# 3. Banner 交换无效格式（端口扫描器特征）
grep "banner exchange: Connection from" /var/log/auth.log | grep "invalid format" | grep "<日期>"

# 4. 密钥交换协议错误（协议级攻击/扫描）
grep "kex_protocol_error" /var/log/auth.log | grep "<日期>"

# 5. 连接重置（Connection reset by peer）
grep "Connection reset by peer" /var/log/auth.log | grep "<日期>"

# 6. 预认证阶段连接关闭（探测后放弃）
grep "Connection closed.*\[preauth\]" /var/log/auth.log | grep "<日期>"
```

## 时间范围定义

用户说"昨晚"通常指前一天 18:00 到当天 06:00：
```bash
# 昨天日期
date -d "yesterday" +%Y-%m-%d

# grep 时间范围（CST 时区）
grep -E "(<昨天>T(1[89]|2[0-3]):|<今天>T0[0-5]:)" /var/log/auth.log
```

## 按 IP 统计

```bash
# 提取 IP（兼容 "from IP" 和 "by IP" 两种格式）
grep "sshd" /var/log/auth.log | grep "<日期范围>" | \
  grep -oP 'from \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+|by \K[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | \
  sort | uniq -c | sort -rn
```

## 被尝试的用户名

```bash
# 提取用户名（区分有效用户和无效用户）
grep "Failed password" /var/log/auth.log | grep "<日期>" | \
  grep -oP 'Failed password for (invalid user )?\K\S+' | sort | uniq -c | sort -rn
```

## 输出格式建议

按用户要求（中文、终端可读），用分隔线和 emoji 组织：
- 📊 总体统计（总次数、密码破解次数、扫描次数、IP 数）
- 🚨 主要攻击源（按 IP 排序，含时段和攻击模式）
- 🔑 被尝试的用户名
- 💡 分析总结 + 建议

## 常见攻击模式识别

| 模式 | 特征 | 说明 |
|------|------|------|
| 字典暴力破解 | 同一 IP 多次 Failed password，间隔约 1 分钟 | 经典自动化工具 |
| 多用户名扫描 | 同一 IP 尝试 admin/root/ubuntu/SDS_Admin 等 | 字典攻击 + 默认凭据 |
| 端口扫描 | banner exchange invalid format，多端口 | Nmap 等扫描器 |
| 协议探测 | kex_protocol_error，无密码尝试 | 服务指纹识别 |
| 连接探测 | Connection closed [preauth]，无后续 | 端口存活检测 |

## 交叉验证

如果 `auth.log` 不存在或数据不全，检查：
- `journalctl -u ssh --since "24 hours ago"` (Ubuntu 用 `ssh` 不是 `sshd`)
- `lastb` 命令（失败登录记录，但可能不全）
- `fail2ban-client status sshd`（如果安装了 fail2ban）
