# Scoring Worked Example

This example uses the score calculation from an actual run on a cloud server (iZ2vc0ggppkz01n7dce43uZ, 2026-06-05).

## Per-Phase Score Assignment

For each phase, assign a score of 0 (❌), 1 (⚠️), or 2 (✅) based on a holistic assessment of all sub-items in that phase. Do NOT average sub-item scores—use expert judgment:

| Score | Meaning | When to use |
|-------|---------|-------------|
| 2 (✅) | All items pass, or minor non-security findings | Phases 1, 2, 5, 6, 7, 8, 9, 10, 13, 14, 15, 16, 17 |
| 1 (⚠️) | Most items OK but 1-2 minor issues or missing optional hardening | Phases 4, 11, 12, 18 |
| 0 (❌) | Any critical finding (root login enabled, password auth enabled, exposed database, malware) | Phase 3 |

## Weighted Calculation Formula

```
phase_score = (score / 2.0) * weight_percentage
total       = sum of all phase_scores, rounded to integer
```

| Phase | Weight | Score | Calculation | Contribution |
|-------|--------|-------|-------------|-------------|
| 1. 防火墙 | 6% | 2/2 | 1.0 × 6 | 6.0 |
| 2. 端口审计 | 6% | 2/2 | 1.0 × 6 | 6.0 |
| 3. SSH 加固 | 7.5% | 0/2 | 0.0 × 7.5 | 0.0 |
| 4. SSH 暴力破解 | 7.5% | 1/2 | 0.5 × 7.5 | 3.75 |
| 5. 恶意进程 | 20% | 2/2 | 1.0 × 20 | 20.0 |
| 6. 用户审计 | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 7. SUID/SGID | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 8. Crontab | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 9. Systemd | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 10. Docker | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 11. SELinux/AppArmor | 4% | 1/2 | 0.5 × 4 | 2.0 |
| 12. 内核参数 | 4% | 1/2 | 0.5 × 4 | 2.0 |
| 13. 磁盘 | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 14. 内存 | 5% | 2/2 | 1.0 × 5 | 5.0 |
| 15. 登录日志 | 2.5% | 2/2 | 1.0 × 2.5 | 2.5 |
| 16. SSH 密钥 | 2.5% | 2/2 | 1.0 × 2.5 | 2.5 |
| 17. 系统更新 | 2.5% | 2/2 | 1.0 × 2.5 | 2.5 |
| 18. Auditd | 2.5% | 1/2 | 0.5 × 2.5 | 1.25 |
| **Total** | **100%** | | | **82.25 → 82** |

## Grade Assignment

```
≥ 90 → ✅ SECURE
≥ 70 → ⚠️ NEEDS ATTENTION
< 70 或任意 Phase 有 ❌ → ❌ INSECURE
```

In this example: score = 82, BUT Phase 3 has ❌ items → **❌ INSECURE**.

## Phase 15-18 Weight Distribution

The scoring table groups "Phase 15-18 (日志/密钥/更新) | 10%". Split evenly: 2.5% each. 
If auditd is not installed (Phase 18), score it as ⚠️ (1/2) rather than ❌ — it's a missing optional tool, not an active vulnerability.

## Common Scoring Pitfalls

- **Phase 3 with multiple ❌**: Even one ❌ in SSH means whole phase = 0/2. Don't "average" sub-items.
- **Phase 4 with fail2ban**: fail2ban running → upgrade "⚠️ no fail2ban" to "✅ fail2ban active", which shifts score to 2/2.
- **Phase 12 with Docker**: `ip_forward=1` when Docker is installed = no penalty. Score as if it were at the CIS value.
- **Phase 18 none/blocked**: auditd not installed = ⚠️ (1/2). Only ❌ if it was expected to be running and failed.
