# JobLib.ps1 - the job contract shared by the runner and by jobs themselves.
#
# A job is one PowerShell file, NNN-name.ps1, that starts with a header:
#   # job: <one line: what and why>
#   # as: admin|service            (which host account runs it)
#   # Changes: <what it changes, or "nothing (read-only)">
#   # Undo: <how to undo; the backup it makes>      (required for change jobs)
# and ends by printing exactly one final line  RESULT: OK|INFO|FAIL|BLOCKED - <summary>  with the matching exit code:
#   OK / INFO -> exit 0, FAIL -> exit 1 (it tried and something went wrong), BLOCKED -> exit 2 (a precondition was not met; nothing changed).

$script:ResultExit = @{ OK = 0; INFO = 0; FAIL = 1; BLOCKED = 2 }

function Test-JobText([string]$Text) {
  # Jobs are shown to a human before they run. Control bytes (ESC sequences) could rewrite what the terminal shows,
  # and non-ASCII look-alikes could hide intent, so only printable ASCII, tab, CR and LF are accepted.
  if ($Text -match '[^\t\r\n\x20-\x7E]') { return 'contains control or non-ASCII bytes' }
  return ''
}

function Get-JobHeader([string]$Text) {
  $h = @{}
  foreach ($line in ($Text -split "`r?`n" | Select-Object -First 12)) {
    if ($line -match '^#\s*(job|as|Changes|Undo):\s*(.+)$') { $h[$Matches[1].ToLower()] = $Matches[2].Trim() }
  }
  $problems = @()
  foreach ($k in 'job', 'as', 'changes') { if (-not $h.ContainsKey($k)) { $problems += "missing # $k" } }
  if ($h.ContainsKey('as') -and $h['as'] -notin @('admin', 'service')) { $problems += "# as: must be admin or service" }
  if ($h.ContainsKey('changes') -and $h['changes'] -notmatch '^nothing' -and -not $h.ContainsKey('undo')) { $problems += 'change job without # Undo' }
  [pscustomobject]@{ Fields = $h; Problems = $problems }
}

function Get-LastResult([string[]]$Lines) {
  $r = @($Lines | Where-Object { $_ -match '^RESULT: (OK|INFO|FAIL|BLOCKED)\b' } | Select-Object -Last 1)
  if (-not $r.Count) { return $null }
  $null = $r[0] -match '^RESULT: (\w+)'
  [pscustomobject]@{ Status = $Matches[1]; Line = $r[0]; Exit = $script:ResultExit[$Matches[1]] }
}

function Assert-PrevResultOk([string]$ResultsDir, [string[]]$Jobs) {
  # Chained guard for rounds with downtime: a job may only run when every job before it ended with RESULT: OK.
  # Returns '' when all are OK, otherwise the reason (the caller prints RESULT: BLOCKED and exits 2).
  foreach ($j in $Jobs) {
    $f = @(Get-ChildItem -LiteralPath $ResultsDir -Filter "$j-*.txt" -ErrorAction SilentlyContinue | Select-Object -First 1)
    if (-not $f.Count) { return "job $j has no result yet" }
    $r = Get-LastResult @(Get-Content -LiteralPath $f[0].FullName)
    if (-not $r) { return "job $j result has no RESULT line" }
    if ($r.Status -ne 'OK') { return "job $j did not end OK ($($r.Status))" }
  }
  return ''
}
