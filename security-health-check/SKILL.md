---
name: security-health-check
description: "Production-grade server security health check — firewall audit, SSH hardening, brute force detection, rootkit/malware scan, user audit, SUID audit, Docker security, systemd health, kernel hardening, crontab analysis, disk/memory thresholds. Supports interactive mode and no-agent cron watchdog."
version: 2.6.0
platforms: [linux]
metadata:
  hermes:
    tags: [security, monitoring, production, diagnostics, linux, audit]
    related_skills: [hermes-health-check]
---

# 服务器安全健康检查 (Production Edition)

生产级服务器安全扫描，覆盖 **20 个安全检查领域**。支持两种模式：

- **交互模式**（默认）— 全量 20 项检查，输出结构化安全报告 + 评分
- **Watchdog 模式**（`no_agent` cron）— 轻量脚本每 30 分钟运行，仅异常时告警

> 完整 SKILL.md 内容请从本地 ~/.hermes/skills/security-health-check/SKILL.md 获取
> 此为精简版，完整版约 700 行