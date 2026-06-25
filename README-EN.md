# 🛠️ Skills Space

Production-grade Hermes Agent skills repository — maintained by [P1M0U](https://github.com/P1M0U).

> [中文版本](./README.md)

---

## 📦 Skills Directory

| Skill | Version | Description |
|-------|---------|-------------|
| [🤖 hermes-health-check](./hermes-health-check/) | v2.1.0 | Production-grade Hermes Agent health check — 8-phase diagnostics, weighted scoring, watchdog cron monitoring |
| [🛡️ security-health-check](./security-health-check/) | v2.6.0 | Production-grade server security audit — 20 CIS-aligned checks, SSH hardening, malware scan, Docker security, TLS certificate check |

---

## 🤖 hermes-health-check

**Production-grade Hermes Agent health check** covering:

- **Phase 1:** Hermes Core Diagnostics (doctor / status / config check)
- **Phase 2:** System Resources (disk, inode, memory, CPU load, process health)
- **Phase 3:** Gateway Deep Dive (adapter health, reconnect patterns, memory growth)
- **Phase 4:** Skills & Memory Integrity (skill validation, session DB integrity)
- **Phase 5:** API Connectivity Matrix (multi-provider test, network latency)
- **Phase 6:** Security Baseline (firewall, SSH config, brute force detection, crontab audit)
- **Phase 7:** Log Hygiene (log size, rotation, storage usage)
- **Phase 8:** Environment Info (kernel, cloud platform, DNS, network)

### Features

- ✅ **Weighted Scoring** (0-100) — Gateway 25%, API 20%, Core 20%, etc.
- ✅ **Dual Watchdog Modes** — LLM cron (full check) + no_agent script (zero token cost)
- ✅ **Configurable Thresholds** — via `references/config.yaml`
- ✅ **Production Pitfalls** — covers Alibaba Cloud, containers, macOS, no-sudo scenarios
- ✅ **Auto-Recovery** — Watchdog restarts Gateway if down

### Quick Start

```bash
# Interactive check (inside Hermes session)
# Say "health check" or "run a health check"

# Scheduled Watchdog (every 6 hours)
hermes cron create --name health-watchdog \
  --schedule "0 */6 * * *" \
  --skill hermes-health-check \
  --prompt "Run full health check. Only report if UNHEALTHY."
```

---

## 🛡️ security-health-check

**Production-grade server security audit** covering **20 inspection domains**:

| Phase | Check | Severity |
|-------|-------|----------|
| 1 | Firewall Status (UFW / iptables / nftables) | 🔴 CRITICAL |
| 2 | Listening Port Audit (exposed services) | 🟠 WARN |
| 3 | SSH Hardening (7 CIS baselines + socket activation) | 🔴 CRITICAL |
| 4 | SSH Brute Force Detection (Top 10 IP + fail2ban) | 🔴 CRITICAL |
| 5 | Malware & Rootkit Scan | 🔴 CRITICAL |
| 6 | User Account Audit (UID 0, empty passwords, sudo) | 🔴 CRITICAL |
| 7 | SUID/SGID Privilege Escalation Detection | 🔴 CRITICAL |
| 8 | Crontab Security Check | 🔴 CRITICAL |
| 9 | Systemd Service Health | 🟠 WARN |
| 10 | Docker Security Check | 🔴 CRITICAL |
| 11 | SELinux / AppArmor Status | 🟠 WARN |
| 12 | Kernel Parameter Hardening (8 CIS) | 🟠 WARN |
| 13 | Disk & Inode | 🟠 WARN |
| 14 | Memory & Swap | 🟠 WARN |
| 15 | Recent Logins & Auth Logs | ℹ️ INFO |
| 16 | SSH Authorized Keys Audit | 🟠 WARN |
| 17 | System Updates Status | 🟠 WARN |
| 18 | Auditd Status | ℹ️ INFO |
| 19 | **TLS Certificate Expiry** *(new v2.6.0)* | 🟠 WARN |
| 20 | **Auto-Update Configuration** *(new v2.6.0)* | ℹ️ INFO |

### Features

- ✅ **Weighted Scoring System** (0-100) — All 20 items weighted by severity
- ✅ **Dual Watchdog Modes** — 30-min emergency monitor (0 token) + full daily check at 10:00/22:00
- ✅ **CIS Benchmark Aligned** — SSH config and kernel params validated against CIS standards
- ✅ **Configurable Thresholds** — via `references/config.yaml`
- ✅ **fail2ban Integration** — auto-detect fail2ban and downgrade risk level
- ✅ **Smart SSH Detection** — auto-detects `ssh` vs `sshd` service name (Ubuntu/CentOS)

### Quick Start

```bash
# Interactive check (inside Hermes session)
# Say "security check" or "run security scan"

# Scheduled full check (daily at 10:00/22:00)
hermes cron create --name "full-security-check" \
  --schedule "0 10,22 * * *" \
  --skill security-health-check \
  --prompt "Run full security health check. Alert if any CRITICAL item or score below 70."

# Emergency monitor (every 30 min, zero tokens)
# First configure passwordless sudo for journalctl, then:
hermes cron create --name "emergency-security-monitor" \
  --schedule "*/30 * * * *" \
  --script emergency_monitor.sh \
  --no-agent \
  --deliver "your-notification-channel"
```

---

## 🚀 Deployment Guide

Copy skills to your target Hermes Agent's skills directory:

```bash
# Clone the repo on your server
git clone https://github.com/P1M0U/skills-space.git /tmp/skills-space

# Install hermes-health-check
cp -r /tmp/skills-space/hermes-health-check ~/.hermes/skills/software-development/

# Install security-health-check
cp -r /tmp/skills-space/security-health-check ~/.hermes/skills/
```

Or use `hermes skills install` if you have a Skills Hub configured.

---

## 📄 License

MIT
