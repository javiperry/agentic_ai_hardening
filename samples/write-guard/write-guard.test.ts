// node --experimental-strip-types --test write-guard.test.ts
import { test } from "node:test";
import assert from "node:assert/strict";
import { beforeToolCall, preview, protectedTargets, type ToolEvent } from "./write-guard.ts";

const ws = "C:\\agent\\workspace\\";
const gated = (ev: ToolEvent) => protectedTargets(ev).length > 0;
const w = (path: string): ToolEvent => ({ toolName: "write", params: { path, content: "x" } });

test("persona files are gated, memory notes are not", () => {
  assert.ok(gated(w(ws + "SOUL.md")));
  assert.ok(gated({ toolName: "edit", params: { file_path: "AGENTS.md", old_string: "a", new_string: "b" } }));
  assert.ok(gated(w("/x/Memory.MD")));
  assert.ok(!gated(w(ws + "memory\\2026-10-11.md")));
  assert.ok(!gated(w(ws + "USER.md")));
  assert.ok(!gated(w(ws + "SOUL.md.bak")));
});

test("regression: spellings the host normalises after the hook", () => {
  const inWorkspace = ["SOUL.md\\.", "SOUL.md/.", "SOUL.md</arg_value>>", "SOUL.md.", "SOUL.md . .", "SOUL.md::$DATA", "AGENTS.md:hidden",
    "BOOTST~1.MD", "memory\\..\\SOUL.md", "SOUL.md\\x\\..", "\u017Foul.md", "\u0131dent\u0131ty.md"];
  for (const b of inWorkspace) assert.ok(gated(w(ws + b)), b);
  for (const b of ['"' + ws + 'Soul.Md"', "@SOUL.md", "@SOUL.md</arg_value>>", "C:SOUL.md", ".."]) assert.ok(gated(w(b)), b);
  for (const ok of ["@notes.md", ws + "caf\u00e9.md", ws + "notes~draft.md", ws + "memory\\2026-10-11.md."]) assert.ok(!gated(w(ok)), ok);
});

test("patches: every target is read; unreadable patches are gated", () => {
  const patch = (body: string): ToolEvent => ({ toolName: "apply_patch", params: { input: `*** Begin Patch\n${body}\n*** End Patch` } });
  assert.ok(gated(patch("*** Update File: IDENTITY.md\n@@\n-a\n+b")));
  assert.ok(gated(patch("*** Update File: notes.md\n*** Move to: TOOLS.md")), "rename onto a persona file");
  assert.ok(!gated(patch("*** Add File: memory/n.md\n+hi")));
  assert.ok(gated({ toolName: "apply_patch", params: { input: "garbage" } }));
  assert.ok(gated({ toolName: "write", params: {} }), "no readable target");
});

test("code a scheduler may run is gated", () => {
  for (const p of ["scripts/digest.ps1", "scripts/notes.md", "Scripts. \\x.txt", "research/run.py", "research/x.pth", "a.ps1::$DATA", "run.cmd."]) assert.ok(gated(w(p)), p);
  for (const p of ["scripts/../notes.md", "dashboard/app.js", "notes.ps1.txt", "myscripts/x.md"]) assert.ok(!gated(w(p)), p);
});

test("hook asks once-only approval and shows head and tail of the change", () => {
  const r = beforeToolCall(w(ws + "SOUL.md"), "main");
  assert.equal(r?.requireApproval.severity, "critical");
  assert.deepEqual(r?.requireApproval.allowedDecisions, ["allow-once", "deny"]);
  assert.equal(beforeToolCall({ toolName: "read", params: { path: "SOUL.md" } }), undefined);
  const long = "a".repeat(400) + "HIDDEN-PAYLOAD";
  assert.ok(preview({ content: long }).includes("HIDDEN-PAYLOAD"), "tail is shown");
});
