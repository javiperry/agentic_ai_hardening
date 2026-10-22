// gate-core.ts - fail-closed admission gate for an agent reachable on a personal messaging account.
//
// The agent is linked to the owner's own messaging number. Friends and groups may be admitted, but each chat answers only when
// its trigger word appears, and only the owner may send commands. Every input the gate cannot read drops the message.
//
// Lesson built into resolveChat(): an earlier version took the chat from the hook's `conversationId` field. On this channel that
// field holds the inbound "To", which is the linked account's own number in EVERY chat, so every direct message looked like the
// owner's self-chat and passed. The chat now comes from the session key (plus the sender in a DM, which must agree). Unit tests
// passed at the time because they fed the gate a chat id directly; the tests below feed it the event fields the host really sends.
//
// Pure logic, no host imports: run the tests with  node --experimental-strip-types --test gate-core.test.ts
import crypto from "node:crypto";
import fs from "node:fs";
import path from "node:path";

export type ChatRule = { word: string; by: string; at: string };
export type GateState = { version: 1; chats: Record<string, ChatRule> };
export type GateDecision = "pass" | "drop";

export const COMMAND = "bot";
const WORD_RE = /^[A-Za-z0-9][A-Za-z0-9_-]{1,31}$/; // ASCII only: the dashboard and the gate must agree on every word
export const SILENT_RE = /^x[0-9a-f]{24}$/; // an unguessable word: the chat stays admitted but the agent never wakes there
const KEY_RE = /^(\+\d{6,15}|[0-9a-z-]+@g\.us)$/;

export const emptyState = (): GateState => ({ version: 1, chats: {} });
export const validWord = (w: unknown): w is string => typeof w === "string" && WORD_RE.test(w);
export const silentWord = (): string => `x${crypto.randomBytes(12).toString("hex")}`;
export const isGroup = (key: string): boolean => key.endsWith("@g.us");

/**
 * Load the rules without ever throwing (a throw in a hook can let the message through).
 * ok=false when the file exists but is unusable (corrupt, wrong shape): decide() then closes groups too.
 * A valid chat with a bad rule keeps an empty word, so it never wakes; it must not fall back to "no rule".
 */
export function loadStateEx(file: string): { state: GateState; ok: boolean } {
  const out = emptyState();
  let raw: string;
  try {
    raw = fs.readFileSync(file, "utf8");
  } catch (err) {
    return { state: out, ok: (err as NodeJS.ErrnoException)?.code === "ENOENT" };
  }
  try {
    const s = JSON.parse(raw);
    if (!s || s.version !== 1 || !s.chats || typeof s.chats !== "object" || Array.isArray(s.chats)) return { state: out, ok: false };
    for (const [k, r] of Object.entries(s.chats as Record<string, unknown>)) {
      if (!KEY_RE.test(k)) continue;
      const rr = (r && typeof r === "object" ? r : {}) as Partial<ChatRule>;
      out.chats[k] = { word: validWord(rr.word) ? rr.word : "", by: String(rr.by ?? ""), at: String(rr.at ?? "") };
    }
    return { state: out, ok: true };
  } catch {
    return { state: out, ok: false };
  }
}

/** Atomic save: write a temp file, then rename over the old one. */
export function saveState(file: string, s: GateState): void {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const tmp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(tmp, JSON.stringify(s, null, 2), "utf8");
  fs.renameSync(tmp, file);
}

/** Normalise a chat id: groups keep "<id>@g.us", people become "+<digits>". Anything else is null. */
export function chatKey(raw: unknown): string | null {
  if (typeof raw !== "string" || !raw) return null;
  const v = raw.trim().replace(/^whatsapp:/i, "");
  if (/@g\.us$/i.test(v)) {
    const g = v.toLowerCase();
    return KEY_RE.test(g) ? g : null;
  }
  const m = /^\+?(\d{6,15})(?::\d+)?(?:@s\.whatsapp\.net)?$/i.exec(v.replace(/[\s-]/g, ""));
  return m ? `+${m[1]}` : null;
}

const GROUP_IN_KEY = /(?:^|:)([0-9]{5,30}(?:-[0-9]{5,20})?@g\.us)(?::|$)/i;
const DIRECT_IN_KEY = /:direct:([^:]+)(?::|$)/i;

/** Which chat an inbound event belongs to, from the session key and sender only. null = drop. */
export function resolveChat(sessionKey: unknown, senderId: unknown, isGroupFlag: unknown): string | null {
  const sk = typeof sessionKey === "string" ? sessionKey : "";
  const g = GROUP_IN_KEY.exec(sk);
  if (g) return chatKey(g[1]);
  if (isGroupFlag === true || /:group:/i.test(sk)) return null; // a group we cannot name
  const d = DIRECT_IN_KEY.exec(sk);
  const peer = d ? chatKey(d[1]) : null;
  if (d && !peer) return null; // a DM peer we cannot read: fail closed
  const sender = chatKey(senderId);
  if (peer && sender && peer !== sender) return null;
  return peer ?? sender;
}

/**
 * Any command or inline directive anywhere in the text. The host strips prefixes and the agent's mention before it parses commands,
 * and directives work mid-message, so a start-of-text check is not enough.
 */
export function isCommandLike(content: string): boolean {
  const t = String(content ?? "").replace(new RegExp(`(?<![\\p{L}\\p{N}/])${COMMAND}(?![\\p{L}\\p{N}])|@\\d+`, "giu"), " ");
  return /(^|[\s\[\](){}:@,;"'])(\/[A-Za-z]|![^\s!?.,)])/u.test(t) || /^\s*!/.test(t);
}

/** The exact trigger word, any case, as a whole word ("hi thor" wakes; "thorn", "thor-ish" do not). */
export function wakes(content: string, word: string): boolean {
  if (!validWord(word) || SILENT_RE.test(word)) return false;
  const esc = word.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  return new RegExp(`(?<![\\p{L}\\p{N}_-])${esc}(?![\\p{L}\\p{N}_-])`, "iu").test(content);
}

/**
 * - unknown chat: only the owner's own messages pass
 * - the owner's self-chat: only the owner's messages pass
 * - commands and directives: owner only
 * - a chat with a rule: only when its word appears (empty or silent word: never)
 * - a group without a rule: pass (the host's own mention gating still applies) unless the rules file is unreadable
 * - any other direct message: drop
 */
export function decide(s: GateState, chat: string | null, ownerKey: string, sender: string | null, content: string, loadOk = true): GateDecision {
  if (!chat) return sender === ownerKey ? "pass" : "drop";
  if (chat === ownerKey) return sender === ownerKey ? "pass" : "drop";
  if (isCommandLike(content)) return sender === ownerKey ? "pass" : "drop";
  const rule = s.chats[chat];
  if (rule) return wakes(content, rule.word) ? "pass" : "drop";
  return isGroup(chat) && loadOk ? "pass" : "drop";
}
