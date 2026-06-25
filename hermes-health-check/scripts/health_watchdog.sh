#!/bin/bash
# Hermes Health Watchdog v2.1 — no_agent cron mode
# v2.1 变更：修复 sshd→ssh、bc→awk、新增僵尸进程/RSS 检查、Gateway 重启防重入
set -euo pipefail
# 完整脚本请从本地 ~/.hermes/skills/autonomous-ai-agents/hermes-agent/scripts/health-watchdog.sh 获取