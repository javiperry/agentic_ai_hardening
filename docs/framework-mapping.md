# Framework mapping

Why a stack and not one standard: as of October 2026 no mature standard covers agent security on its own. The project used
NIST CSF 2.0 (with the draft Cyber AI Profile) for structure, OWASP's agentic list and the Five Eyes guidance for agent controls,
ASD Essential Eight for the host, and OWASP ASVS 5.0 for the web surfaces. ISO 27001/42001 was out of scope (no certification
need). Maturity levels were **not formally assessed**; the tables say what is in place, not a score.

## NIST CSF 2.0 (+ draft Cyber AI Profile)

| Function | What is in place |
|---|---|
| **Govern** | Written working rules and a decisions log (with rejected alternatives); risk acceptance recorded per finding with a reason; one-writer rule for changes; risky rounds reviewed by a second model before they run; nine critical-change rules after an incident. |
| **Identify** | Findings register (83 items, severity, status, evidence, fixing job); host baseline and ACL inventories; egress sample; credential inventory and age tracker; plugin hash baseline. |
| **Protect** | Least-agency tool policy; guard plugins; non-admin pure service account; admin-only install dirs; ACL rebuild; per-account egress rules; ASR rules; full-disk encryption; owner MFA; trusted launcher; masking and secret scanning. |
| **Detect** | Scheduled daily platform audit; alerts to a private security channel on new criticals and failed audits; blocked-connection logging; behavioural evals after changes. *Gap:* no off-host log store. |
| **Respond** | Out-of-band kill switch (two modes); the out-of-band stop mode was drilled once (11 October, before later host changes); the channels-off mode and the dashboard button have not been drilled; runbook; incident write-ups. *Gap:* no tabletop exercise yet. |
| **Recover** | Nightly local + encrypted cloud backup; weekly restore test; full restore rehearsal; every change job writes its own undo. |

## Five Eyes - "Careful Adoption of Agentic AI Services" (May 2026)

| Theme in the guidance | How it shows up here |
|---|---|
| Containment: limit the blast radius of unexpected behaviour; least privilege | Design goal is blast-radius reduction: per-agent tool denies, shell on 5 of 18 agents (commands outside an allowlist need approval), no agent can change config. |
| Human oversight of consequential actions | Owner approval for persona and script writes, exec approvals, browser per-topic switch, once-only approvals, typed confirmations. |
| Strong identity and least privilege for agents | Dedicated non-admin service account with no interactive logon; admin-only binaries; rebuilt ACLs. *Gap:* agents share one account and one key per provider. |
| Segmentation and network control | Loopback-only services, tailnet-only remote access, per-account egress rules. *Gap:* no per-agent sandbox; one shared host. |
| Audit logging, live monitoring and interruption | Scheduled audits and alerts, out-of-band kill switch (stop mode drilled once), eval suite. |
| Unvetted third-party components (design and configuration risks) | No marketplace skills, reviewed plugins with hashes, gated deployment pipeline. |

## ASD Essential Eight (host)

| Strategy | State | Notes |
|---|---|---|
| Patch applications | In place | Platform kept current within days of release, after a 24-48 h cool-down; staged, rehearsed upgrades. |
| Patch operating systems | Not assessed | The host OS channel was reviewed as part of a host-baseline finding; update cadence was not measured. |
| Multi-factor authentication | Partial | Two-step on both messaging accounts and MFA on the six provider and code-hosting accounts (self-attested); phishing-resistant factors not confirmed everywhere. |
| Restrict administrative privileges | In place | Agents and dashboard run non-admin; admin actions only through the reviewed job pipeline. |
| Application control | Partial | No allowlisting product; compensated by ASR rules in block mode, per-account egress blocks and admin-only install dirs. |
| Restrict Office macros | Not applicable | No Office automation on the host. |
| User application hardening | Partial | ASR, network protection; service account has no browsers. |
| Regular backups | In place | Nightly, encrypted off-site copy, weekly restore test, full rehearsal. |

## OWASP ASVS 5.0 (gateway and dashboard)

| Area | Control |
|---|---|
| Architecture / exposure | Loopback bind only; remote access through a private tailnet; no public listener. |
| Authentication | Gateway token via a secret reference; dashboard one-time sign-in link -> HttpOnly, SameSite=Strict cookie; constant-time comparison; token rotated; passkey step-up on the phone for dangerous actions, bound to the credential and invalidated on re-enrolment. |
| Session and request integrity | Host-header allowlist (DNS-rebinding defence), Origin check, CSRF guard header on state-changing requests. |
| Output and content security | Strict Content-Security-Policy; vanilla JS without third-party scripts. |
| Change safety | Every config change from the dashboard: dry-run, backup, apply, validate, restore on failure, audit-logged. |
| Logging | Kill switch and security actions append to an audit log; alerts on criticals. |

Level claimed: none formally; the design target was L2 for the dashboard and gateway, L3 for the control surfaces.
