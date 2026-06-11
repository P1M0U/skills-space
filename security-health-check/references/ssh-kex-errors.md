# SSH kex_protocol_error / kex_exchange_identification Pattern

## What it is

```
sshd[XXXX]: error: kex_protocol_error: type 20 seq 2 [preauth]
sshd[XXXX]: error: kex_protocol_error: type 30 seq 3 [preauth]
sshd[XXXX]: error: kex_exchange_identification: read: Connection reset by peer
```

These appear in `journalctl -p 3` under systemd service health (Phase 9).

## Cause (not an intrusion)

- **kex_protocol_error**: Incoming SSH connection from a client that sends malformed key exchange packets. Common causes: SSH scanner tools (Shodan, Censys, masscan), outdated SSH clients, misconfigured load balancer health checks, or aggressive network probes.
- **kex_exchange_identification: read: Connection reset by peer**: Client disconnected during SSH handshake. Often a scan tool probing the port and moving on after identifying the SSH banner.

## Assessment in security report

- These are **not** security breaches — they are pre-authentication noise.
- Do NOT flag as WARN or CRITICAL.
- In Phase 9 output, mention them as "sshd protocol errors (incompatible client scanning, not intrusion)" and move on.
- Only worry if accompanied by a matching "Failed password" or "Invalid user" entry from the same source IP.

## Threshold for concern

- ≤ 50 such errors/24h = background noise, ignore.
- > 50/24h = note in report as elevated scanning activity, still not a breach.
- Only escalate if the same source IP transitions from kex errors → Failed password attempts.
