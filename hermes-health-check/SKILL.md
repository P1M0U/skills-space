---
name: hermes-health-check
description: "Production-grade comprehensive health check for Hermes Agent — config, deps, API connectivity, system resources, gateway, network, security baseline, cron jobs, log hygiene, and platform adapters."
version: 2.0.0
platforms: [linux]
metadata:
  hermes:
    tags: [hermes, diagnostics, monitoring, health-check, troubleshooting, production]
    related_skills: [hermes-agent, security-health-check]
---

# Hermes Health Check (Production Edition)

Runs a full production-grade diagnostic on the Hermes Agent installation and host system.

## Health Check Phases

### Phase 1: Hermes Built-in Diagnostics

```bash
hermes doctor 2>&1
hermes status 2>&1
hermes config check 2>&1
```

### Phase 2: System Resources (Full Scan)

```bash
df -h $HOME 2>&1
df -i $HOME 2>&1
free -h 2>&1
uptime 2>&1
nproc 2>&1
```

### Phase 3: Gateway Deep Dive

```bash
hermes gateway status 2>&1
grep -i "error\|fail\|exception\|traceback" ~/.hermes/logs/gateway.log 2>&1 | tail -20
```

### Phase 4: Skills, Memory & Plugin Integrity

```bash
ls -d ~/.hermes/skills/*/ 2>&1 | wc -l
wc -c ~/.hermes/memories/MEMORY.md ~/.hermes/memories/USER.md 2>&1
hermes sessions stats 2>&1
```

### Phase 5: API Connectivity Matrix

```bash
curl -s -o /dev/null -w "%{http_code}" -m 10 https://api.github.com/zen 2>&1
```

### Phase 6: Network & Security Baseline

```bash
sudo ufw status 2>&1 || sudo iptables -L -n --line-numbers 2>&1 | head -10
ss -tlnp 2>&1 | grep -v "127.0.0.1\|::1"
```

### Phase 7: Log Hygiene & Storage

```bash
du -sh ~/.hermes/logs/ 2>&1
du -sh ~/.hermes/ 2>&1
```

### Phase 8: Environment & Deployment Info

```bash
uname -a 2>&1
cat /etc/os-release 2>&1 | head -3
python3 --version 2>&1
```

## Scoring System

| Component | Weight |
|-----------|--------|
| Phase 1 (Hermes core) | 20% |
| Phase 2 (System) | 10% |
| Phase 3 (Gateway) | 25% |
| Phase 4 (Skills/Memory) | 10% |
| Phase 5 (API) | 20% |
| Phase 6 (Security) | 10% |
| Phase 7 (Logs) | 3% |
| Phase 8 (Env) | 2% |

## Watchdog Mode

```bash
hermes cron create --name health-watchdog --schedule "0 */6 * * *" --skill hermes-health-check --prompt "Run health check. Only report if UNHEALTHY."
```

See full documentation in the complete SKILL.md.
