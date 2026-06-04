# 🛠️ Skills Space

Hermes Agent 生产级技能仓库 — 由 [P1M0U](https://github.com/P1M0U) 维护。

> [English Version](./README-EN.md)

---

## 📦 技能目录

| 技能 | 版本 | 描述 |
|------|------|------|
| [🤖 hermes-health-check](./hermes-health-check/) | v2.0.0 | Hermes Agent 生产级健康检查 — 8 阶段诊断、加权评分、Watchdog 定时监控 |
| [🛡️ security-health-check](./security-health-check/) | v2.0.0 | 服务器生产级安全审计 — 18 项 CIS 级别检查、SSH 加固、恶意进程扫描、Docker 安全 |

---

## 🤖 hermes-health-check

**生产级 Hermes Agent 健康检查**，覆盖：

- **Phase 1:** Hermes 核心诊断（doctor / status / config check）
- **Phase 2:** 系统资源（磁盘、Inode、内存、CPU 负载、进程健康）
- **Phase 3:** Gateway 深度分析（适配器健康、重连模式、内存增长）
- **Phase 4:** Skills & Memory 完整性（Skill 校验、Session DB 完整性）
- **Phase 5:** API 连通性矩阵（多 Provider 测试、网络延迟）
- **Phase 6:** 安全基线（防火墙、SSH 配置、暴力破解检测、Crontab 审计）
- **Phase 7:** 日志卫生（日志大小、轮转、存储用量）
- **Phase 8:** 环境信息（内核、云平台、DNS、网络）

### 特性

- ✅ **加权评分系统**（0-100）— Gateway 25%、API 20%、Core 20% 等
- ✅ **双模式 Watchdog** — LLM cron（全量检查）+ no_agent 脚本（0 token 消耗）
- ✅ **可配置阈值** — 通过 `references/config.yaml` 调整所有阀值
- ✅ **生产 Pitfalls** — 覆盖阿里云、容器环境、macOS、无 sudo 场景
- ✅ **自动修复** — Watchdog 检测到 Gateway 宕机时尝试重启

### 快速开始

```bash
# 交互式检查（在 Hermes 会话中）
# 说 "健康检查" 即可

# 定时 Watchdog（每 6 小时）
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run full health check. Only report if UNHEALTHY."
```

---

## 🛡️ security-health-check

**生产级服务器安全审计**，覆盖 **18 个安全检查领域**：

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

### 特性

- ✅ **加权评分系统**（0-100）— 18 项按权重汇总
- ✅ **双模式 Watchdog** — 30 分钟紧急监控（0 token）+ 每天 10:00/22:00 全量检查
- ✅ **CIS Benchmark 对齐** — SSH 配置、内核参数均按 CIS 标准校验
- ✅ **可配置阈值** — 通过 `references/config.yaml` 调整
- ✅ **fail2ban 集成** — 自动识别 fail2ban 状态并降级风险等级

### 快速开始

```bash
# 交互式检查（在 Hermes 会话中）
# 说 "安全检查" 或 "安全扫描" 即可

# 全量定时检查（每天 10:00/22:00）
hermes cron create --name "安全全量检查" \
  --schedule "0 10,22 * * *" \
  --skill security-health-check \
  --prompt "执行完整安全健康检查。如有 CRITICAL 项或评分低于 70，明确告警。"

# 紧急监控（每 30 分钟，0 token）
# 先配置 journalctl 免密码 sudo，然后：
hermes cron create --name "紧急安全监控" \
  --schedule "*/30 * * * *" \
  --script emergency_monitor.sh \
  --no-agent \
  --deliver "你的通知频道"
```

---

## 🚀 部署指南

将技能复制到目标 Hermes Agent 的 skills 目录：

```bash
# 克隆仓库到服务器
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 安装 hermes-health-check
cp -r /tmp/skills-space/hermes-health-check ~/.hermes/skills/software-development/

# 安装 security-health-check
cp -r /tmp/skills-space/security-health-check ~/.hermes/skills/
```

或者直接使用 `hermes skills install`（如果配备了 Skills Hub）。

---

## 📄 License

MIT
