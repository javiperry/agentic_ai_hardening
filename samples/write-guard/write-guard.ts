// write-guard.ts - owner approval before an agent rewrites its own instructions or any code a scheduler will run.
//
// Threat (OWASP ASI06 memory/context poisoning): a prompt-injected agent writes the attacker's instructions into its persona file
// (SOUL.md, AGENTS.md, ...) and they persist into every future session. Second path found later: unattended automations run
// scripts from the agent's own workspace in the host process, with no exec approval, so a write to a .ps1/.py is a code-execution
// path too. Daily memory notes stay ungated so "remember this" keeps working.
//
// Lesson built in: the first version checked the raw file name before the host normalised the path. Spellings such as
// "SOUL.md.", "SOUL.md\.", "SOUL.md::$DATA", an 8.3 alias, trailing tool-call markup or a leading "@" were all written to the real
// file without approval. baseName() now mirrors what the host and the filesystem do AFTER the hook, and anything still ambiguous
// is treated as protected.
//
// Host-agnostic sample: wire beforeToolCall() into your agent host's pre-tool hook.
export const PROTECTED = new Set(["soul.md", "agents.md", "identity.md", "tools.md", "heartbeat.md", "bootstrap.md", "memory.md"]);
export const CODE_EXT = new Set([".ps1", ".psm1", ".psd1", ".py", ".pyw", ".pth", ".cmd", ".bat", ".vbs", ".sh"]);
export const UNRESOLVED = "(unresolved name)";
const PATH_KEYS = ["path", "file_path", "filePath", "file", "target", "destination", "notebook_path"];
const PATCH_HEADER = /^\*\*\* (?:Add File|Update File|Delete File|Move to):\s*(.+?)\s*$/gm;
const SHORT_NAME = /^[^.~]{1,6}~\d+(\.[^.]{0,3})?$/; // 8.3 alias such as SOULMD~1 or BOOTST~1.MD

export type ToolEvent = { toolName?: string; params?: Record<string, unknown>; derivedPaths?: string[] };

function segments(p: string): string[] {
  let s = p.trim().replace(/^["']+|["']+$/g, "");
  s = s.replace(/(?:<\/?[A-Za-z_][\w:-]*>+\s*)+$/, ""); // trailing tool-call markup the host strips
  s = s.replace(/^@+/, ""); // leading "@" file-reference prefix the host strips
  s = s.replace(/^[A-Za-z]:(?![\\/])/, ""); // drive-relative "C:SOUL.md"
  const out: string[] = [];
  for (const seg of s.split(/[\\/]+/)) {
    if (seg === "" || seg === ".") continue;
    if (seg === "..") { out.pop(); continue; }
    out.push(seg);
  }
  return out;
}

/** The file name the filesystem will finally write, lower-cased; UNRESOLVED when it cannot be known. */
export function baseName(p: string): string {
  const out = segments(p);
  let name = out.length ? out[out.length - 1] : "";
  if (out.length > 1 || !/^[A-Za-z]:$/.test(name)) name = name.replace(/:.*$/, ""); // NTFS stream (":$DATA", ":hidden")
  name = name.replace(/[. ]+$/, "").toLowerCase(); // Win32 ignores trailing dots and spaces
  if (!name || SHORT_NAME.test(name)) return UNRESOLVED;
  // a non-ASCII look-alike that folds onto a protected name (U+017F long s, U+0131 dotless i) is gated too
  if (/[^\x20-\x7e]/.test(name) && PROTECTED.has(name.normalize("NFKC").toUpperCase().toLowerCase())) return UNRESOLVED;
  return name;
}

export function targetPaths(event: ToolEvent): { paths: string[]; unknown: boolean } {
  const paths: string[] = [];
  const params = event.params ?? {};
  for (const k of PATH_KEYS) {
    const v = params[k];
    if (typeof v === "string" && v.trim()) paths.push(v);
  }
  for (const p of event.derivedPaths ?? []) if (typeof p === "string" && p.trim()) paths.push(p);
  if (event.toolName === "apply_patch") {
    for (const v of Object.values(params)) if (typeof v === "string") for (const m of v.matchAll(PATCH_HEADER)) paths.push(m[1]);
  }
  return { paths: [...new Set(paths)], unknown: paths.length === 0 };
}

export function isCode(p: string): boolean {
  const b = baseName(p);
  const dot = b.lastIndexOf(".");
  if (dot > 0 && CODE_EXT.has(b.slice(dot))) return true;
  return segments(p).slice(0, -1).some((seg) => seg.replace(/[. ]+$/, "").toLowerCase() === "scripts");
}

export function protectedTargets(event: ToolEvent): string[] {
  const { paths, unknown } = targetPaths(event);
  if (unknown) return ["(target not readable)"]; // a write we cannot read the target of is gated, not allowed
  return paths.filter((p) => {
    const b = baseName(p);
    return b === UNRESOLVED || PROTECTED.has(b) || isCode(p);
  });
}

/** Head and tail of the new text: an injected edit cannot hide its payload after a harmless first part. */
export function preview(params: Record<string, unknown> | undefined): string {
  const p = params ?? {};
  let text = [p.content, p.new_string, p.newText, p.input, p.patch].find((v) => typeof v === "string") as string | undefined;
  if (text === undefined && Array.isArray(p.edits)) {
    text = p.edits.map((e) => (e && typeof e === "object" ? String((e as Record<string, unknown>).newText ?? "") : "")).join(" | ");
  }
  const t = (text ?? "(no new text in the call)").replace(/\s+/g, " ");
  return t.length <= 600 ? t : `${t.slice(0, 300)} ... ${t.length - 600} chars omitted ... ${t.slice(-300)}`;
}

export const MATCHER = ["write", "edit", "apply_patch"];

/** Pre-tool hook: undefined = allow; otherwise ask the owner (allow once or deny; no "always"). */
export function beforeToolCall(event: ToolEvent, agentId = "agent") {
  if (!MATCHER.includes(event.toolName ?? "")) return undefined;
  const hits = protectedTargets(event);
  if (!hits.length) return undefined;
  return {
    requireApproval: {
      severity: "critical" as const,
      title: `${agentId} wants to change ${hits.join(", ")}`,
      description: preview(event.params),
      allowedDecisions: ["allow-once", "deny"],
    },
  };
}
