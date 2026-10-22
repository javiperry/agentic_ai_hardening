# Samples

Sanitised re-writes of controls from the project. Each one is small, self-contained and has its own tests. They carry no
environment specifics: account names, paths and ids are generic or synthetic, and test values are assembled at runtime so secret
scanners do not flag them.

| Sample | What it shows | Language | Tests |
|---|---|---|---|
| [`trust-gate/`](trust-gate/) | Review gate outside the repo: diff the code tree against the last human-approved commit, require a typed `TRUST`, fail closed | PowerShell + git | 8 checks over a throwaway repo |
| [`job-runner/`](job-runner/) | Change-job contract and round runner: header lint, one approval per round, stop at first failure, RESULT/exit-code agreement, masked results, chained OK guard | PowerShell | 6 scenarios (18 checks) |
| [`masking/`](masking/) | Mandatory output masking before results reach disk or git | PowerShell | 26 secret shapes, 12 must-not-change values |
| [`write-guard/`](write-guard/) | Owner approval before an agent rewrites its persona files or code a scheduler runs; path normalisation that closed a bypass | TypeScript | 5 suites, 43 path cases |
| [`chat-gate/`](chat-gate/) | Fail-closed admission gate for an agent on a personal messaging account; regression for a field-meaning bug | TypeScript | 7 suites |
| [`egress/`](egress/) | Per-account, per-program outbound block plan (Windows Firewall) with backup and restore | PowerShell | 10 plan checks |

Run everything (needs PowerShell 7, Node 22+, git):

```sh
sh samples/run-tests.sh
```

The PowerShell samples are written for Windows PowerShell 5.1 and PowerShell 7; the tests run on PowerShell 7 on Linux too
(`Set-EgressRules` itself needs Windows).
