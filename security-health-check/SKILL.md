---
name: security-health-check
description: "Production-grade server security health check — firewall, SSH, malware, user audit, SUID, Docker, kernel hardening."
version: 2.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [security, monitoring, production, diagnostics, linux, audit]
    related_skills: [hermes-health-check]
---

# 服务器安全健康检查 (Production Edition)

生产级服务器安全扫描，覆盖 **18 个安全检查领域**。

## 检查流程（18 项）

### Phase 1: 防火墙状态
### Phase 2: 监听端口审计
### Phase 3: SSH 安全加固检查
### Phase 4: SSH 暴力破解检测
### Phase 5: 恶意进程 & Rootkit 扫描
### Phase 6: 用户账户审计
### Phase 7: SUID/SGID 文件审计
### Phase 8: Crontab 安全检查
### Phase 9: Systemd 服务健康
### Phase 10: Docker 安全检查
### Phase 11: SELinux / AppArmor
### Phase 12: 内核参数加固
### Phase 13: 磁盘 & Inode
### Phase 14: 内存 & Swap
### Phase 15: 最近登录 & 认证日志
### Phase 16: SSH 授权密钥审计
### Phase 17: 系统更新
### Phase 18: Auditd 审计状态

See full documentation in the complete SKILL.md.
