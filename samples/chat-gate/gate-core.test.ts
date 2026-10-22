// node --experimental-strip-types --test gate-core.test.ts
// Synthetic ids, built at runtime so secret scanners do not flag them.
import { test } from "node:test";
import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { chatKey, decide, emptyState, isCommandLike, loadStateEx, resolveChat, saveState, silentWord, wakes } from "./gate-core.ts";

const num = (n: number) => "+1555" + String(n).padStart(7, "0");
const OWNER = num(1);
const FRIEND = num(2);
const STRANGER = num(3);
const GROUP = "1203" + "0".repeat(14) + "@g.us";
const bare = (k: string) => k.slice(1);
const N = "2026-01-01T00:00:00Z";

test("chatKey normalises ids and refuses lids and junk", () => {
  assert.equal(chatKey(bare(OWNER) + "@s.whatsapp.net"), OWNER);
  assert.equal(chatKey(bare(OWNER) + ":12@s.whatsapp.net"), OWNER);
  assert.equal(chatKey(GROUP.toUpperCase()), GROUP);
  for (const bad of ["9".repeat(14) + "@lid", "123", "", undefined, {}, "msg-ABC"]) assert.equal(chatKey(bad), null);
});

test("resolveChat uses the session key, never the inbound 'To' (regression)", () => {
  // the real event: conversationId would be the owner's own number here; the gate never reads it
  assert.equal(resolveChat(`agent:x:whatsapp:direct:${FRIEND}`, bare(FRIEND) + "@s.whatsapp.net", false), FRIEND);
  assert.equal(resolveChat(`agent:x:whatsapp:group:${GROUP}`, FRIEND, true), GROUP);
  assert.equal(resolveChat(`agent:x:whatsapp:direct:${FRIEND}`, STRANGER, false), null, "peer and sender disagree");
  assert.equal(resolveChat("agent:x:whatsapp:direct:" + "9".repeat(14) + "@lid", FRIEND, false), null, "unreadable peer");
  assert.equal(resolveChat("agent:x:whatsapp:group:unknown", FRIEND, true), null, "unnamed group");
});

test("owner chat and unknown chats", () => {
  const s = emptyState();
  assert.equal(decide(s, OWNER, OWNER, OWNER, "anything"), "pass");
  assert.equal(decide(s, OWNER, OWNER, FRIEND, "anything"), "drop");
  assert.equal(decide(s, null, OWNER, STRANGER, "hi"), "drop");
  assert.equal(decide(s, FRIEND, OWNER, FRIEND, "hello"), "drop", "a DM without a rule drops");
  assert.equal(decide(s, GROUP, OWNER, FRIEND, "hello"), "pass", "a group without a rule keeps host mention gating");
});

test("a rule gates by whole word, any case", () => {
  const s = emptyState();
  s.chats[FRIEND] = { word: "thor", by: OWNER, at: N };
  assert.equal(decide(s, FRIEND, OWNER, FRIEND, "THOR draw a cat"), "pass");
  for (const t of ["hello", "thoroughly", "thor-ish", "thor_x"]) assert.equal(decide(s, FRIEND, OWNER, FRIEND, t), "drop", t);
});

test("commands and directives anywhere in the text are owner-only", () => {
  const s = emptyState();
  s.chats[FRIEND] = { word: "thor", by: OWNER, at: N };
  for (const t of ["/activation always", "thor hi /think high", "[x] /new", "bot/new", "!ls", "thor (/reset)"]) {
    assert.ok(isCommandLike(t), t);
    assert.equal(decide(s, FRIEND, OWNER, FRIEND, t), "drop", t);
    assert.equal(decide(s, FRIEND, OWNER, OWNER, t), "pass", t);
  }
  assert.ok(!isCommandLike("and/or is fine"));
});

test("silent and broken rules never wake", () => {
  const s = emptyState();
  const w = silentWord();
  s.chats[GROUP] = { word: w, by: OWNER, at: N };
  s.chats[FRIEND] = { word: "", by: OWNER, at: N };
  assert.equal(decide(s, GROUP, OWNER, FRIEND, `hi ${w}`), "drop");
  assert.equal(decide(s, FRIEND, OWNER, FRIEND, "anything"), "drop");
  assert.equal(wakes("hi", "x"), false, "a one-letter word is invalid");
});

test("rules file: missing is fine, unreadable closes groups", () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "gate-"));
  const file = path.join(dir, "rules.json");
  assert.equal(loadStateEx(file).ok, true, "missing file = no rules yet");
  fs.writeFileSync(file, "﻿{not json");
  const bad = loadStateEx(file);
  assert.equal(bad.ok, false);
  assert.equal(decide(bad.state, GROUP, OWNER, FRIEND, "hello", bad.ok), "drop");
  const s = emptyState();
  s.chats[FRIEND] = { word: "thor", by: OWNER, at: N };
  (s.chats as Record<string, unknown>)["not-a-key"] = { word: "x1" };
  saveState(file, s);
  const back = loadStateEx(file);
  assert.equal(back.ok, true);
  assert.deepEqual(Object.keys(back.state.chats), [FRIEND], "invalid keys are dropped on load");
  fs.rmSync(dir, { recursive: true, force: true });
});
