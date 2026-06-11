# 🤖 Hermes Health Check

生产级 Hermes Agent 健康检查 — 8 阶段诊断、加权评分、Watchdog 定时监控。

## 🎯 功能

完整的 8 阶段健康检查：
- **Phase 1:** Hermes 核心诊断（doctor / status / config check）
- **Phase 2:** 系统资源（磁盘、Inode、内存、CPU 负载、进程健康）
- **Phase 3:** Gateway 深度分析（适配器健康、重连模式、内存增长）
- **Phase 4:** Skills & Memory 完整性（Skill 校验、Session DB 完整性）
- **Phase 5:** API 连通性矩阵（多 Provider 测试、网络延迟）
- **Phase 6:** 安全基线（防火墙、SSH 配置、暴力破解检测、Crontab 审计）
- **Phase 7:** 日志卫生（日志大小、轮转、存储用量）
- **Phase 8:** 环境信息（内核、云平台、DNS、网络）

## 📦 安装

### 方式一：一键安装（推荐）

告诉你的 Hermes Agent：

> 请帮我安装 hermes-health-check skill，从 https://github.com/P1M0U/skills-space 仓库

Agent 会自动执行：

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/hermes-health-check ~/.hermes/skills/software-development/

# 清理
rm -rf /tmp/skills-space
```

### 方式二：手动安装

```bash
# 克隆仓库
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# 复制 skill 目录
cp -r /tmp/skills-space/hermes-health-check ~/.hermes/skills/software-development/

# 清理
rm -rf /tmp/skills-space
```

## 🚀 使用

### 交互式检查

在 Hermes 会话中说：

```
健康检查
```

或

```
检查 Hermes 健康状态
```

### 定时 Watchdog

```bash
# LLM 驱动（每 6 小时全量检查）
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run full health check. Only report if UNHEALTHY."

# 轻量脚本（每 30 分钟，0 token 消耗）
hermes cron create --name health-watchdog-quiet \
  --schedule "*/30 * * * *" \
  --script health_watchdog.sh \
  --no-agent
```

## 📊 评分系统

| 分数 | 等级 | 说明 |
|------|------|------|
| ≥ 95% | ✅ HEALTHY | 健康 |
| ≥ 75% | ⚠️ NEEDS ATTENTION | 需要关注 |
| < 75% | ❌ UNHEALTHY | 不健康 |

权重分配：
- Gateway: 25%
- API 连通性: 20%
- Hermes 核心: 20%
- 系统资源: 10%
- Skills/Memory: 10%
- 安全基线: 10%
- 日志卫生: 3%
- 环境信息: 2%

## ⚠️ 注意事项

- 需要 sudo 权限执行部分检查
- 阿里云/腾讯云环境需要额外配置元数据端点
- macOS 不支持 `free -h` 和 `ss`，需要使用替代命令

## 📄 License

MIT