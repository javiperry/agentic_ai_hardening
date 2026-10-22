# Incidents and lessons

Blameless write-ups of the things that went wrong. Times are local; impact is stated from job results.

## 1. Failed platform upgrade, then a restore that broke a channel (October 2026)

**Impact.** Gateway offline about 50 minutes in one window plus two short ones (~17 min and ~2 min); WhatsApp broken for a
further few minutes after the manual restore. No data lost. Still on the previous version afterwards.

**What happened.**
1. The pre-upgrade backup failed safely: the admin-run copy hit links the service account had created (plugin dependency links),
   which Windows treats as untrusted mount points for an admin process. The gateway came back on the old version by itself.
2. A fix was shipped without review: skip those links in the backup. It was marked "restore behaviour unverified".
3. The next attempt got further and then stopped: the job host account for service jobs could not query the service manager.
4. A launcher window still open on an older checkout ran a superseded job that started the new version before its config
   migration. The new version refused the old config; the automatic rollback gave up because the service manager kept retrying.
5. I ran the restore by hand. Its mirror copy, combined with the "skip links" change, deleted the plugin dependency links. WhatsApp
   and one model provider failed to load until two jobs recreated the links and restarted the gateway.

**Root causes.** Jobs that had worked for the previous upgrade were reused without re-checking assumptions that had since changed
(service account hardening, a new job-host account, new plugin link layout). The preflight read the environment but did not
exercise the downtime operations under the same accounts. A change was made during downtime without review. Jobs in a downtime
round did not require the previous job's OK. The rollback had never been exercised.

**What changed.** Nine rules for any change with downtime, now enforced by three commit-gate lint rules:
nothing is "proven" by an earlier run; rehearse every precondition and non-mutating step under the same account first; no unreviewed
change during downtime (restore first, then fix with review); each downtime job blocks unless the previous one ended OK; supersede
by quarantine only and close old launcher windows; complete backups that copy links as links and re-link after any restore; exercise
every rollback in the rehearsal and disable a service before stopping it; "unverified" on a destructive path is a blocker; downtime
estimates come from measured timings.

**Did it work?** The rebuilt rehearsal failed by design on its next run: it showed that the restore's mirror copy deletes files
*through* a link in the destination. That would have destroyed data during the next downtime; it was caught with nothing offline.

## 2. Clean-up removed a dependency; agents silently changed provider

**Impact.** For about 15 hours, work meant for one model provider ran on another, with no error shown. No outage.

**What happened.** Removing personal apps and profiles from the service account (a security fix) also removed the folder where
one model runtime's CLI lived, and the folder holding its sign-ins. The clean-up's reference check looked at config and auth files,
not at the runtime's built-in default command name. Every call to that runtime failed and the platform's fallback chain quietly
answered with the next model.

**Found by.** A log read while testing an unrelated feature showed the "executable could not be resolved" line and the fallback.

**Fix.** Reinstalled the CLI admin-only on the gateway's path, restored the sign-in folders, and added dashboard-managed sign-ins
with an automatic switch when an account hits its usage limit. A live test confirmed the intended provider answered.

**Lesson.** Reference checks must include implicit defaults. Silent fallback is a failure mode: it needs monitoring, not just
configuration (per-agent fallback telemetry is an open item).

## 3. Launcher key folder exposed by a permissions reset

**Impact.** For about 30 minutes the folder holding the launcher's repository deploy key was listable by local users; the key file
itself kept its own explicit admin-only permissions and was never readable. No rotation needed.

**What happened.** A job reset permissions recursively on the launcher's folder (`icacls <dir>\* /reset`), which re-enabled
inheritance on a subfolder an earlier job had made admin-only.

**Found by.** The launcher itself: it checks that its key folder is admin-only before using SSH, and refused to run.

**Lesson.** Recursive ACL resets undo deliberate exceptions. A job that changes permissions must read back the effect on every
protected path, not only on the target. The fail-closed check is what turned this into a 30-minute exposure instead of an unknown one.

## 4. Chat gate tests passed against the wrong input

**Impact.** Friends admitted for a specific trigger word could reach the WhatsApp agent without it, in direct messages. Found by
the owner in normal use.

**What happened.** The gate decided which chat a message belonged to from a hook field named for the conversation. On this
channel that field carries the inbound recipient, which is the linked account's own number in every chat, so each direct
message looked like the owner's self-chat. The unit tests passed because they fed the gate a chat id directly.

**Fix.** The chat now comes from the session key, and in a direct message the sender must agree with it; anything unreadable drops.
Tests now use the event fields the host really sends. A second review then found command and directive forms that could appear
mid-message and closed them too.

**Lesson.** A field's name is not its meaning. Trace every input a security decision uses back to where the host sets it.

## 5. Persona guard bypassed by path spellings

**Impact.** Found in code review before any known abuse.

**What happened.** The guard compared the file name in the tool call with a list. The host and the filesystem normalised the path
*after* the guard ran, so `SOUL.md.`, `SOUL.md\.`, `SOUL.md::$DATA`, an 8.3 short name, trailing markup and later a leading `@`
all reached the real file without approval.

**Fix.** The guard computes the name the filesystem will actually write (dot segments, streams, trailing dots and spaces, markup,
prefixes, look-alike letters) and treats anything still ambiguous as protected. Each bypass is a regression test.

**Lesson.** Validate the canonical form the system will act on, and when unsure, fail closed.

## 6. The retry: three live windows, two rollbacks (21-22 October 2026)

**Impact.** Three outages in two days. About 60 minutes when the first downtime job hit an untested error in its process
sweep and stopped with the gateway down. About 28 minutes when the repair step failed on the second try and the prepared
rollback restored the old version (ready in 154 s). On the last try, about 41 minutes fully stopped, then about an hour on
the new version while it was slow and unstable (a restart took 554 s to become ready, with worker timeouts and Telegram polling
stalls), then a rollback: about 1 h 50 min from that switch to the old version being healthy again. Session state from the hour
on the new version was discarded by the rollback. A WhatsApp group stayed silent until the owner re-linked the account; a
post-start check had flagged that the new version rewrote that group's admission entry (whether that caused the silence is
unverified).

**What was different from incident 1.** The attempts were built from the rules written after it:
- Rehearsals under the same accounts ran first and caught a destructive restore bug. Three runs failed on the same check: the
  test rig could not make a dummy failing version leave child processes behind, so the process sweep's kill path was never
  exercised. The owner accepted that, with three other unrehearsable paths, in writing. The rollback function was rehearsed on
  dummy services; its first real use was after the evening failure.
- A hotfix for a known upstream bug was verified on a *copy* of the state first, with the platform's own repair tool run
  against it.
- On the last try, when the repair tool on the live state changed security-relevant paths and the job could not prove a safe
  revert, it failed closed. The next two jobs refused to run because the previous one had not ended OK. A review gate then
  compared exactly what the repair tool had changed before the new version was allowed to start.

**What happened on the last try.** The new version started (ready in 196 s) with every security plugin loaded. A post-start
check failed because the start had rewritten part of the security config. A restart then took 554 s to become ready. I rolled
back to the backup taken before the switch; the old version was ready in 219 s with plugins and both channels loaded.

**Cause.** Not established. The platform's later release notes describe fixes matching the stall (unverified). The upgrade is
parked until that release is stable.

**Lessons.**
1. The rules contained the damage but did not prevent it: an unrehearsed error path still took the gateway down for an hour,
   and the repair step failed once more on the live state. What held was the chain: every failure stopped the round, nothing
   ran out of order, and both rollbacks were prepared paths rather than improvisations.
2. Rehearsal proves the mechanics you can simulate, not the error paths you cannot, nor the new version's behaviour under load.
   Only a live run showed the stall. The decision rule is now: wait for the next stable release, and make the copy test start a
   gateway on the copy and restart it.
3. Having a measured, tested way back made "roll back now" a cheap decision. It was not free: the rollback discards state
   written since the backup.
