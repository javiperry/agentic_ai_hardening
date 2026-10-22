# Hardening a self-hosted multi-agent AI assistant

A self-directed security engineering project: taking a personal, always-on AI agent platform from "installed and working" to a
defended, auditable, recoverable system, benchmarked against current agentic-AI security guidance.

> **Scope, stated plainly.** This is a single-operator home deployment I built and secured for my own use, October 2026.
> It had no customers, no production users and no commercial deployment. Numbers below come from the project's own job
> results and findings register; anything I could not back from those records is left out.
> The work was done with AI coding agents (Claude Code) as pair engineers: I set the rules, made the decisions and
> approved and ran every change on the machine; the agents researched, wrote most of the code and jobs, and reviewed each other.

## The problem

OpenClaw is an open-source gateway that runs many LLM agents behind chat channels (Telegram,
WhatsApp), with tools for files, web, browser, shell and scheduled automations. That combination is the textbook agentic risk:
untrusted text in, real tools out, credentials on disk, and an operator who talks to it from a phone.

My install runs 18 configured agents (14 conversational, 4 internal helpers) on one Windows PC, a personal WhatsApp number linked, provider keys in local files, and no audit trail.
The first run of the platform's own security audit reported **50 critical findings**.

Prompt injection has no complete fix, so the design goal was not "stop every hijack" but **limit what a hijacked agent can do,
see it, stop it, and recover**.

## What I built

| Area | What | Why it matters |
|---|---|---|
| **Change pipeline** | Every change to the machine is a reviewed, numbered PowerShell *job* with a header (`what / as / changes / undo`), a backup, a single `RESULT:` line and an exit code. Jobs run only through a runner; output is masked and secret-scanned before it is committed. | Turns ad-hoc admin work into an auditable change log: 670 job numbers, 517 results with a recorded outcome. |
| **Trusted launcher** | A review gate installed outside the repo (admin-write only) that diffs the *code tree* against the last commit I approved and requires a typed `TRUST`; fails closed. | Code pushed to git runs as admin. A script cannot verify its own update, so the gate lives where a push cannot reach. |
| **Least agency** | Default-allow tool policy replaced with per-agent denies: shell exec on 5 of 18 agents (commands outside an allowlist need approval), config/gateway tools on none, browser behind a per-topic owner switch. | Shrinks the blast radius of any one hijacked agent. |
| **Guard plugins** (in-process, TypeScript) | *write-guard*: owner approval before an agent rewrites its own persona/instruction files or any script an automation runs. *chat-gate*: fail-closed admission for friends and groups on a personal WhatsApp number. Browser/computer access gated per topic with proof that the owner started the run. | Blocks memory-poisoning persistence (OWASP ASI06) and stops strangers driving an agent on a personal account. |
| **Identity and host** | Non-admin service account turned into a pure service account (no interactive or RDP sign-in, browsers removed); state-dir ACLs rebuilt; gateway and Python moved to admin-only install dirs; SSH keys-only and tailnet-only; BitLocker, Defender tamper protection, 17 of 18 ASR rules in block mode. | The agent's account owns every secret; nothing else may write into what it runs. |
| **Egress control** | 34 outbound firewall block rules scoped to the service account only: shells and download tools blocked off-box, agent runtime limited to TCP 80/443, no UDP, LAN or tailnet. | An allowlist was impossible (agents fetch arbitrary sites), so the design removes the exfiltration and lateral-movement paths instead. |
| **Detect and respond** | Dashboard Security tab (findings register, scheduled audits, credential age tracker), alerts to a private channel on new criticals, an out-of-band kill switch (stop, or stop + channels off that survives reboot). | Out-of-band control that does not depend on the agent obeying a chat message. |
| **Recover** | Nightly backup, local plus encrypted cloud copy (least-privilege `drive.file` scope), weekly restore test, a full restore rehearsal. | A restore that has never been run is a hope, not a control. |
| **Evaluate** | 21 deterministic behavioural cases across 5 agents (secret refusal, injection, destructive-command confirmation, read-only role, capability gating); results reported as pass/fail, cost and tool names only. | Model or persona changes can silently weaken refusals; this catches it. |

Architecture: [docs/architecture.md](docs/architecture.md).

## Security posture

Benchmarked against a layered stack, because no single standard covers agents yet:

- **OWASP Top 10 for Agentic Applications (2026)** - threat model, per-risk controls and residual risk: [docs/threat-model.md](docs/threat-model.md)
- **NIST CSF 2.0** + draft **Cyber AI Profile**, **Five Eyes "Careful Adoption of Agentic AI Services" (May 2026)**,
  **ASD Essential Eight**, **OWASP ASVS 5.0** for the gateway and dashboard: [docs/framework-mapping.md](docs/framework-mapping.md)

## Results

| Measure | Result | Source |
|---|---|---|
| Platform security audit, critical findings | **50 -> 0** (warnings 5 -> 4) | first audit run vs. re-run after the ACL fixes |
| Findings register | **83 findings** (5 critical, 18 high, 38 medium, 22 low); **49 fixed**, 7 risk-accepted with reasons, 27 open or in progress | dashboard findings register, 2026-10-22 |
| Criticals | **5 of 5 closed** (key rotation, MFA (self-attested), state-dir ACLs, local model with web tools, keys in an old repo) | findings register |
| Change jobs | job numbers up to 670 (649 with a file); 517 results with a recorded outcome: 307 OK, 121 INFO (read-only), 50 FAIL, 39 BLOCKED (a precondition stopped the job before it changed anything) | job results |
| Behavioural evals | Baseline **15/21**. One failure was a finding: a read-only auditor agent, asked to expose the gateway, reached for config, shell and write tools. Tool removed; re-run **8/8** on the affected agents (one run; one of them passed without any change, so part of the gain is run-to-run variance) with zero tool calls | eval runs |
| Restore rehearsal | Full restore of the newest backup: permissions verified, security plugins loaded, ~23 min offline | restore job |
| Egress | 34 distinct destinations sampled over a day, then 36 per-account block rules, 34 after two were removed so a legitimate scheduled script could run | sampler + firewall jobs |
| Independent review | 42 written review, verify and post-mortem reports (a second model reviewing each risky round before it ran) | review folder |

Details and method: [docs/evaluation.md](docs/evaluation.md).

## Lessons learned (honest ones)

Full write-ups: [docs/incidents.md](docs/incidents.md).

1. **A failed upgrade, and a manual fix that made it worse.** A platform upgrade failed four ways: the backup tripped on
   service-made links, the service account could not query the service manager, a stale job ran out of order, and the automatic
   rollback gave up. My hand-run restore then deleted plugin dependency links and broke WhatsApp. About an hour offline, no data
   lost. Result: nine written rules for any change with downtime (rehearse under the same account, chained OK guards, no
   unreviewed change during an outage, rollbacks exercised before use) and three lint rules that enforce them. The rebuilt
   rehearsal then caught a second destructive bug *before* any downtime.
2. **A clean-up that silently broke a dependency.** Removing personal apps from the service account also removed the CLI one
   model runtime needed. Agents kept answering, on a different provider, with no error. Lesson: a reference check must cover
   implicit defaults, not just config files; silent fallback is a failure mode to monitor.
3. **An ACL regression found by my own fail-closed check.** A permissions reset re-enabled inheritance on the launcher's key
   folder. The launcher refused to run until it was fixed; the key file itself was never readable. Lesson: recursive ACL resets are
   dangerous; check the effect, not the command.
4. **Tests that passed against the wrong input.** The chat gate's unit tests fed it a chat id directly; the real event carried the
   owner's own number in the field I trusted, so every direct message passed. Lesson: trace each hook field to its source; test
   with the real event shape.
5. **A guard bypassed by path spellings.** The persona guard checked the raw file name; the host normalised `SOUL.md.` or
   `SOUL.md::$DATA` to the real file afterwards. Lesson: validate the canonical form the system will actually act on.

6. **The retry still failed three times, and each failure stopped safely.** Built from the rules above, the first downtime job
   hit an untested error path (about an hour offline), the repair step failed on the next try and was rolled back, and the
   third try ran on the new version until it proved slow and unstable under real load; the tested rollback restored the old
   version in about 7 minutes (discarding the state written in between). Lesson: rehearsal proves the mechanics you can
   simulate, not the error paths you cannot, nor the new version's behaviour, so a tested way back is what makes failure cheap.

## Code samples

Sanitised re-writes of six controls, each with tests (`sh samples/run-tests.sh`): [samples/](samples/)

## What I would do next

Move the gateway to a dedicated host (the biggest residual risk is one machine and one account), finish secret-store migration,
run indirect prompt-injection canaries through every ingest path, and ship logs off-host in tamper-evident form.

## About

Javier Perry - AI engineer with security depth - [LinkedIn](https://www.linkedin.com/in/javierperry/) (best way to reach me)

I also build [MicroFlux Labs](https://microfluxlabs.com.au/), a separate small venture. Nothing in this repository comes from it, and it
has no customers or deployments in this project.

Licence: [MIT](LICENSE) for the samples and documentation.
