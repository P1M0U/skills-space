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
Use this when the user asks to check Hermes health, diagnose issues, verify everything is working,
or as a scheduled watchdog via cronjob.

Supports two modes:
- **Interactive mode** (default) — full 8-phase check with structured human-readable report
- **Watchdog mode** (cron-friendly) — lightweight periodic check that only reports on status changes or failures

## Quick Start

Say "run a health check" or "check Hermes health" and the agent will execute all phases below.

## Health Check Phases

Execute these phases **in order**. Do NOT skip phases even if an earlier one shows issues —
collect everything first, THEN summarize.

---

### Phase 1: Hermes Built-in Diagnostics

Run these three commands. They are fast, safe, and cover the majority of Hermes internals.

```bash
hermes doctor 2>&1
hermes status 2>&1
hermes config check 2>&1
```

Parse output for:
- ✓ / ⚠ / ✗ markers (count each category)
- Security advisories (CRITICAL if any)
- Python environment issues (venv active? version mismatch?)
- Directory structure integrity
- Gateway status (running / stopped)
- Missing **required** vs **optional** API keys (required missing = CRITICAL)

### Phase 2: System Resources (Full Scan)

```bash
# Disk
df -h $HOME 2>&1
df -i $HOME 2>&1           # inode usage (can fill up even with space left)

# Memory
free -h 2>&1
cat /proc/meminfo 2>&1 | grep -E "^(MemTotal|MemAvailable|SwapTotal|SwapFree):"

# CPU
uptime 2>&1                # load averages
nproc 2>&1                 # CPU core count
cat /proc/loadavg 2>&1     # precise load

# Process health
ps aux --sort=-%mem 2>&1 | head -8  # top 5 memory consumers
ps aux --sort=-%cpu 2>&1 | head -8  # top 5 CPU consumers
```

Thresholds for production:
| Metric | WARNING | CRITICAL |
|--------|---------|----------|
| Disk usage | > 80% | > 92% |
| Inode usage | > 80% | > 92% |
| Available memory | < 500MB | < 200MB |
| Swap usage | > 50% | > 80% |
| CPU load (1min / nproc) | > 0.8 | > 1.5 |
| Zombie/defunct processes | >= 1 | >= 5 |

### Phase 3: Gateway Deep Dive

```bash
# Core status
hermes gateway status 2>&1

# Per-platform adapter check — extract connected platforms from status
# Look for: Feishu, QQBot, Telegram, Discord etc. and their check/x status

# Memory & CPU of gateway process
ps -p $(systemctl --user show -P MainPID hermes-gateway 2>/dev/null) -o pid,%mem,%cpu,rss,etime --no-headers 2>&1

# Recent log errors (last 24h)
grep -i "error\|fail\|exception\|traceback\|CRITICAL" ~/.hermes/logs/gateway.log 2>&1 | tail -30

# Reconnect analysis — count per adapter in last hour
grep -i "WebSocket closed\|reconnect\|disconnect" ~/.hermes/logs/gateway.log 2>&1 | tail -50

# Gateway log growth rate (bytes per hour)
stat --format="%s" ~/.hermes/logs/gateway.log 2>/dev/null
```

Check for:
- Gateway running vs stopped (stopped when expected running = CRITICAL)
- Per-platform adapter connectivity (known-good platforms disconnected = WARN)
- Error rate in last 24h (>= 10 errors = WARN, >= 50 = CRITICAL)
- Reconnect frequency (known-bad patterns: QQ 4009 every ~30min = INFO, erratic reconnects = WARN)
- Gateway memory growth (sustained > 1GB = WARN, > 2GB = CRITICAL)
- Log file size (> 500MB = WARN, > 1GB = CRITICAL, suggests no rotation)

### Phase 4: Skills, Memory & Plugin Integrity

```bash
# Skills
ls -d ~/.hermes/skills/*/  2>&1 | wc -l
ls ~/.hermes/skills/*/SKILL.md 2>&1 | wc -l   # skills that have valid SKILL.md

# Check for broken skills (no SKILL.md)
comm -23 <(ls -d ~/.hermes/skills/*/ | sed 's|/$||') <(ls -d ~/.hermes/skills/*/SKILL.md 2>/dev/null | xargs -I{} dirname {})

# Memory files
wc -c ~/.hermes/memories/MEMORY.md ~/.hermes/memories/USER.md 2>&1

# Session DB
hermes sessions stats 2>&1

# Check session DB integrity
sqlite3 ~/.hermes/state.db "PRAGMA integrity_check;" 2>&1

# Cron jobs
hermes cron list 2>&1 || ls ~/.hermes/cron/ 2>&1

# Check for plugins
ls ~/.hermes/plugins/ 2>&1
```

Check for:
- Skills directory count vs valid SKILL.md count (discrepancy = broken skills)
- Memory files non-empty and < 100KB (overgrown memory = WARN)
- Session DB integrity check passes
- Cron job directory non-empty if jobs were scheduled
- Plugin directory status

### Phase 5: API Connectivity Matrix

Test ALL configured model providers, not just the primary one.
Extract available providers from `hermes status` output first.

```bash
# 1. Test DeepSeek API (list models endpoint — doesn't consume tokens)
DEEPSEEK_KEY=$(grep -oP '^DEEPSEEK_API_KEY=\K.*' ~/.hermes/.env 2>/dev/null | head -1)
if [ -n "$DEEPSEEK_KEY" ]; then
  HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 \
    -H "Authorization: Bearer $DEEPSEEK_KEY" \
    https://api.deepseek.com/v1/models 2>&1)
  echo "DeepSeek API: HTTP $HTTP_CODE ($([ "$HTTP_CODE" = "200" ] && echo 'OK' || echo 'FAIL'))"
fi

# 2. Test GitHub API (no auth needed for /zen)
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" -m 10 https://api.github.com/zen 2>&1)
echo "GitHub API: HTTP $HTTP_CODE ($([ "$HTTP_CODE" = "200" ] && echo 'OK' || echo 'FAIL'))"

# 3. Network latency to primary provider
ping -c 2 -W 3 api.deepseek.com 2>&1 | tail -1
```

Only test providers that have keys configured (parse from `hermes status` or `.env`).
Flag:
- HTTP 200-299 -> OK
- HTTP 401/403 -> CREDENTIAL_ERROR (key expired/revoked)
- HTTP 429 -> RATE_LIMITED
- Timeout / connection refused -> NETWORK_ERROR
- Primary model provider failed = CRITICAL
- Secondary provider failed = WARN

If curl-based testing is not possible, fall back to `hermes doctor` connectivity results.

### Phase 6: Network & Security Baseline

Quick security posture — cross-reference with `security-health-check` skill for full scan.

```bash
# Firewall status
sudo ufw status 2>&1 || sudo iptables -L -n --line-numbers 2>&1 | head -20

# Listening ports (unexpected open ports?)
ss -tlnp 2>&1 | grep -v "127.0.0.1\|::1"

# SSH config
ss -tlnp 2>&1 | grep ":22"
cat /etc/ssh/sshd_config 2>/dev/null | grep -E "^(PermitRootLogin|PasswordAuthentication|Port )" | grep -v "^#"

# Failed SSH login attempts (last 24h)
sudo journalctl -u sshd --since "24 hours ago" 2>/dev/null | grep "Failed password" | wc -l

# Check for suspicious crontabs
crontab -l 2>/dev/null
sudo cat /etc/crontab 2>/dev/null
ls -la /etc/cron.d/ 2>/dev/null

# System updates available
which apt-get >/dev/null 2>&1 && apt-get --just-print upgrade 2>&1 | grep -c "upgraded\|installed" | tail -1

# Last system boot
who -b 2>&1
```

Security thresholds:
| Check | WARNING | CRITICAL |
|-------|---------|----------|
| SSH root login enabled | - | Yes |
| Password auth enabled | Yes | - |
| SSH on non-standard port | N/A | - |
| Failed SSH (24h) | > 50 | > 200 |
| Open non-local ports (unexpected) | 1-2 | >= 3 |
| Pending security updates | > 10 | > 30 |
| Firewall inactive | - | Yes |

### Phase 7: Log Hygiene & Storage

```bash
# Log directory size
du -sh ~/.hermes/logs/ 2>&1

# Per-logfile sizes
ls -lh ~/.hermes/logs/ 2>&1

# Session DB size
ls -lh ~/.hermes/state.db 2>&1

# Check for log rotation
ls -la ~/.hermes/logs/*.gz ~/.hermes/logs/*.old ~/.hermes/logs/*.[0-9] 2>&1 | head -5

# Hermes home total size
du -sh ~/.hermes/ 2>&1
```

Thresholds:
| Metric | WARNING | CRITICAL |
|--------|---------|----------|
| gateway.log | > 200MB | > 500MB |
| All logs total | > 500MB | > 1GB |
| Session DB | > 100MB | > 500MB |
| ~/.hermes total | > 2GB | > 5GB |

### Phase 8: Environment & Deployment Info

```bash
# Kernel & arch
uname -a 2>&1

# OS release
cat /etc/os-release 2>&1 | head -5

# Cloud metadata (if on cloud VM)
curl -s -m 2 http://100.100.100.200/latest/meta-data/instance-id 2>&1 || echo "(not Alibaba Cloud)"
curl -s -m 2 http://169.254.169.254/latest/meta-data/instance-id 2>&1 || echo "(not AWS)"

# Python & venv info
which python3 2>&1
python3 --version 2>&1
echo "$VIRTUAL_ENV" 2>&1

# Hermes version
hermes --version 2>&1 || head -1 ~/.hermes/hermes-agent/hermes_cli/__init__.py 2>/dev/null

# Network info
hostname -I 2>&1 | awk '{print $1}'
ip route show default 2>&1 | head -1

# DNS resolution test
nslookup api.deepseek.com 2>&1 | tail -3
```

---

## Scoring System

Each check produces a numeric score. The overall health is computed as a weighted sum:

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

Each check yields 0 (CRITICAL), 1 (WARN), or 2 (OK). Weighted sum / max possible = health %.

Final severity:
| Score | Severity |
|-------|----------|
| >= 95% | **HEALTHY** check mark |
| >= 75% | **NEEDS ATTENTION** warning |
| < 75% | **UNHEALTHY** cross mark |
| Any CRITICAL check | Auto-downgrade to UNHEALTHY |

---

## Output Format

After all phases complete, present a structured summary:

See the full SKILL.md in the Hermes Agent skills directory for the complete output template with sample health report.

---

## Watchdog Mode (Cron Scheduling)

### Option A: LLM-driven (default cron)

```bash
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run a full health check in watchdog mode. Only report if overall status is UNHEALTHY or if any CRITICAL check fails. If HEALTHY or NEEDS ATTENTION, stay silent."
```

### Option B: no_agent script (lightweight, zero tokens)

Uses the standalone shell script at `scripts/health_watchdog.sh`:

```bash
hermes cron create --name "health-watchdog-quiet" \
  --schedule "*/30 * * * *" \
  --script health_watchdog.sh \
  --no-agent
```

### Watchdog behavior
- HEALTHY -> silent (no notification)
- NEEDS ATTENTION -> silent (unless user asked for all reports)
- UNHEALTHY -> full report delivered to configured channel

---

## Pitfalls & Production Gotchas

### Command Failures
- `hermes chat -q` blocks indefinitely if the model provider is down. Use `timeout 30`.
- `hermes gateway status` calls `systemctl --user`. If DBUS not set, check PID file.
- `ufw status` may be inactive on cloud VMs; fallback to `iptables -L -n`.
- `journalctl` may require sudo. Skip gracefully if unavailable.
- `sqlite3` may not be installed; skip DB integrity check.

### Platform Differences
- macOS: No `free -h`, use `vm_stat`. No `ss`, use `lsof -i`.
- Alibaba Cloud / Tencent Cloud: Metadata endpoints differ from AWS. Check both.
- Container environments: `systemctl` won't work; check process directly with `ps`.

### Edge Cases
- Gateway log empty if never started — not an error.
- No swap on cloud VMs is normal.
- `.env` file special chars in API keys — use `source ~/.hermes/.env` style.
- `ps` output on Alpine has different flags. Use `ps -o pid,pcpu,pmem,rss,etime`.

### Security
- Do NOT echo full API keys. Always truncate: `sk-8...1873`.
- `iptables -L -n` output can be very long; limit to INPUT/FORWARD.
- Do NOT expose cloud metadata tokens in output.
