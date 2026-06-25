#!/bin/bash
# 服务器紧急安全监控 v2.3 — no_agent cron 模式
# 行为：仅 CRITICAL 级别输出告警（空 stdout = 不发送消息）
# v2.3 变更：修复 Ubuntu sshd→ssh、IP正则转义、新增 Inode/OOM 检查
set -euo pipefail
# 完整脚本请从本地 ~/.hermes/skills/security-health-check/scripts/emergency_monitor.sh 获取