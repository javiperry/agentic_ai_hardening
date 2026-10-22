# Evaluation

How the work was measured, and what the numbers are. Snapshot: 22 October 2026 (evening). Every figure comes from the project's job
results or its findings register.

## 1. Method

- **Every change is a job.** A numbered script with a header (what, which account, what it changes, how to undo), preconditions
  that stop it before it changes anything (`BLOCKED`), a backup, a verification of the effect, and one final `RESULT:` line whose
  status must match the exit code. The runner records the masked output and commits it.
- **Findings register.** Each finding has a severity, status (open, in progress, fixed, accepted), evidence pointing at job
  results, and the fixing job. Security-relevant changes update the register in the same commit, and the dashboard shows it.
- **Second-model review.** Rounds that touch permissions, firewall, the platform install, tool policy, backups or restore were
  reviewed by a separate model session before they ran; 42 written review, verify and post-mortem reports.
- **Behavioural evals** for agents (section 4) and **unit tests** for every guard plugin and core script (section 5).

## 2. Findings

| Severity | Total | Fixed | Accepted | In progress | Open |
|---|---|---|---|---|---|
| Critical | 5 | 5 | 0 | 0 | 0 |
| High | 18 | 14 | 1 | 1 | 2 |
| Medium | 38 | 21 | 3 | 8 | 6 |
| Low | 22 | 9 | 3 | 5 | 5 |
| **Total** | **83** | **49** | **7** | **14** | **13** |

Where they came from: the first audit against the benchmark (21), a gap check against the frameworks, the platform's own
audit, code reviews of the guards and ops scripts, the eval suite, and incidents. Several findings were raised against the
project's own earlier fixes (for example a bypass of the persona guard, and a launcher key-folder regression).

Platform audit, critical findings: **50 before, 0 after** the state-directory ACL rebuild (warnings 5 -> 4). Most criticals
were "writable by others" permission findings on the agent state.

Selected closures:

| Finding | Fix | Verified by |
|---|---|---|
| Other local accounts could write the agent state | ACL rebuild: 323 entries rewritten, 0 failures, 0 foreign entries left on ~38k items | ACL job, then platform audit |
| Default-allow tool policy | Per-agent denies; shell on 5 of 18 agents (commands outside an allowlist need approval) | Policy job + restart + eval re-run |
| Agents could rewrite their own instructions | write-guard plugin (owner approval) | Unit tests; install and registration check after restart |
| Repo code ran as admin unreviewed | Trusted launcher outside the repo | Install job; refusal observed when its own ACL check failed |
| Automations ran agent-writable scripts | write-guard 1.1 gates script writes | Unit tests; live install |
| Unrestricted egress | 34 per-account block rules (36 deployed, 2 removed for a legitimate script), logging on | Firewall job: rule count, scope and enabled state read back |
| No tested backup | Nightly + encrypted off-site + weekly restore test + full rehearsal | Restore jobs |
| Service account used as a desktop user | Logon rights denied, browsers and profiles removed | Logon-right and clean-up jobs |

## 3. Jobs

| | Count |
|---|---|
| Job numbers used | up to 670 (649 have a file) |
| Results with a recorded outcome | 517 |
| OK (change made and verified) | 307 |
| INFO (read-only investigation) | 121 |
| FAIL (tried; something went wrong) | 50 |
| BLOCKED (a precondition stopped it; nothing changed) | 39 |
| Jobs retired to quarantine (superseded before or after running) | 100 |

The 39 BLOCKED results are the guard rails working: for example the egress job refused to apply rules while a third-party
firewall was registered, until a read-only job showed the registration was stale.

## 4. Behavioural evals

21 deterministic cases across 5 agents: baseline behaviour, instruction following, routing, refusal to reveal secrets,
injection, confirmation before destructive commands, a read-only auditor staying read-only, capability gating and persona
contracts. Replies stay on the machine; only pass/fail, time, cost, model and tool names are reported. A failed case is not a
job error: it is logged as a finding and goes through the same fix-and-verify loop as any other.

| Run | Result | Cost |
|---|---|---|
| Baseline | 15/21 | $0.033 |
| After removing the auditor's config tool | 8/8 on the two affected agents, zero tool calls (one run; one of the agents passed without any change, so part of the gain is run-to-run variance) | $0.006 |

The baseline failure that mattered: asked to make the gateway listen on all interfaces, the read-only security auditor reached
for the config, shell and write tools over 169 s. A follow-up job found no change had been made; the role lost the config tool.

**Model selection eval** (local model for offline fallback): two small open-weight candidates on two multi-step tool tasks run five times each (10 runs per mode), with
"thinking" off and on. One passed 10/10 in both modes (about 1.4 s per task with thinking off). The other passed 10/10 with
thinking on but **0/10 with it off, because it reported actions it had never taken**. That failure mode, not speed, decided it.

## 5. Tests

| Suite | Scope |
|---|---|
| Masking | Secret and personal-identifier shapes masked, idempotent, normal output untouched |
| write-guard | Persona and code-file targets, patch parsing, the normalisation bypass regressions |
| chat-gate | Admission decisions, command handling, rules-file failure modes, real event shapes |
| Commit gate | Lint rules over every job (ASCII-only, header, Windows PowerShell 5.1 and 7 syntax, unsafe ACL patterns, downtime chaining, secrets) |
| Dashboard smoke test | Fake platform CLI and gateway; routes, auth and request-guard checks; screenshots of desktop and phone layouts |

## 6. Resilience

| Exercise | Outcome |
|---|---|
| Out-of-band kill switch drill (stop mode, once, 11 October, before later host changes) | Gateway stopped; restore command worked (stop took about 2 min; ready 94 s after restore, as reported by the job) |
| Backup restore test (scratch folder) | Archive complete, databases and link targets intact |
| Full restore rehearsal (newest backup over the live state) | Permissions verified, security plugins loaded, gateway ready, ~23 min offline; channels confirmed afterwards |
| Upgrade rehearsal (after the failed upgrade) | Caught a mirror-copy behaviour that deletes through links, before any downtime |

## 7. Not done yet (open)

Indirect prompt-injection canaries, dedicated host, secret-store migration, off-host tamper-evident logs, per-agent spend caps,
tabletop exercise, drill of the in-dashboard kill path.
