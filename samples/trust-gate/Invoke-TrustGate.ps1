# Invoke-TrustGate.ps1 - review gate in front of a job runner that executes repository code with admin rights.
#
# Problem: the runner shows each job before it runs, but the runner itself and its libraries also execute every time. A pushed change
# to them would run unreviewed. A script cannot safely verify its own update, so this gate lives OUTSIDE the repository
# (installed into an admin-write-only folder) and compares the code tree, not the history, against the last commit a human approved.
#
#   Unchanged code  -> update and hand the pinned commit to the runner.
#   Changed code    -> list commits and files, offer the full diff, continue only after the human types TRUST (exact case).
#   Anything odd    -> stop (approved commit missing, diff failed, repo writable by non-admins, wrong branch).
#
# Sanitised sample: the original also ran an SSH deploy-key path, an ACL check on the repo folder and a watch loop.
param(
  [Parameter(Mandatory)][string]$Repo,
  [Parameter(Mandatory)][string]$ApprovedFile,
  [string]$Target = 'origin/main',
  [switch]$NoFetch,                 # tests: the target ref already exists locally
  [string]$Answer                   # tests: the reply to the prompt; a human types it otherwise
)
$ErrorActionPreference = 'Stop'

# What counts as code: everything except documentation, job results and the job files themselves (the runner shows those one by one).
$Gate = @('.', ':(exclude)docs', ':(exclude)results', ':(exclude)jobs', ':(exclude,glob)**/*.md')

# Repository config must not be able to run code during the review: no fsmonitor, no hooks, no background maintenance.
$env:GIT_CONFIG_COUNT = '4'
$env:GIT_CONFIG_KEY_0 = 'core.fsmonitor'; $env:GIT_CONFIG_VALUE_0 = 'false'
$env:GIT_CONFIG_KEY_1 = 'core.hooksPath'; $env:GIT_CONFIG_VALUE_1 = '/nonexistent-hooks'
$env:GIT_CONFIG_KEY_2 = 'gc.auto'; $env:GIT_CONFIG_VALUE_2 = '0'
$env:GIT_CONFIG_KEY_3 = 'maintenance.auto'; $env:GIT_CONFIG_VALUE_3 = 'false'
$env:GIT_PAGER = ''; $env:GIT_TERMINAL_PROMPT = '0'

# Commit subjects and file names come from the remote: print printable ASCII only so escape codes cannot redraw the screen.
function Format-Safe([string]$Text) { $Text -replace '[^\t\x20-\x7E]', '?' }
function Write-Line([string]$Text) { Write-Host (Format-Safe $Text) }
function Invoke-Git([string[]]$A) {
  $o = & git -C $Repo --no-pager @A 2>$null
  if ($LASTEXITCODE) { throw "git $($A[0]) failed (exit $LASTEXITCODE)" }
  return $o
}
function Test-Git([string[]]$A) { & git -C $Repo --no-pager @A 2>$null | Out-Null; $LASTEXITCODE -eq 0 }
function Get-Gated([string[]]$A) { @(Invoke-Git ($A + @('--') + $Gate) | Where-Object { $_ }) }

try {
  $approved = if (Test-Path -LiteralPath $ApprovedFile) { (Get-Content -LiteralPath $ApprovedFile -TotalCount 1).Trim() } else { '' }
  if ($approved -notmatch '^[0-9a-f]{40}$') { Write-Line 'No approved baseline: re-run the install step.'; exit 2 }
  if (-not (Test-Git @('cat-file', '-e', "$approved^{commit}"))) { Write-Line "Approved commit $($approved.Substring(0, 10)) is missing (history rewritten?). Stopping."; exit 2 }
  if (-not $NoFetch) { Invoke-Git @('fetch', '--quiet', 'origin', 'main') | Out-Null }
  $tip = (Invoke-Git @('rev-parse', $Target)) | Select-Object -First 1
  $head = (Invoke-Git @('rev-parse', 'HEAD')) | Select-Object -First 1

  $remote = Get-Gated @('diff', '--name-only', $approved, $tip)
  $local = @(Get-Gated @('diff', '--name-only', $approved, $head) | Where-Object { $remote -notcontains $_ })
  $dirty = Get-Gated @('status', '--porcelain', '--untracked-files=all')

  if ($remote.Count + $local.Count + $dirty.Count) {
    Write-Line "Code changed since the last approval ($($approved.Substring(0, 10))). It will run with admin rights."
    if ($remote.Count) { Get-Gated @('log', '--format=  %h %s', "$approved..$tip") | ForEach-Object { Write-Line $_ } }
    ($remote + $local + $dirty) | Select-Object -Unique | ForEach-Object { Write-Line "  file: $_" }
    # fail closed: the full diff must be producible, or there is no approval
    $diff = @(Get-Gated @('diff', '--no-ext-diff', '--no-textconv', $approved, $tip))
    while ($true) {
      $a = if ($PSBoundParameters.ContainsKey('Answer')) { $Answer } else { Read-Host '[d] full diff   [TRUST] approve   [n] stop' }
      if ($a -match '^d' -and -not $PSBoundParameters.ContainsKey('Answer')) { $diff | ForEach-Object { Write-Line $_ }; continue }
      if ($a -ceq 'TRUST') { break }
      Write-Line 'Stopped. Nothing updated or run; approval unchanged.'
      exit 1
    }
  } else { Write-Line 'No code changes since the last approval.' }

  # update to exactly the reviewed commit, then re-check nothing else slipped in between review and update
  if ($head -ne $tip) {
    if (Test-Git @('merge-base', '--is-ancestor', $head, $tip)) { Invoke-Git @('merge', '--ff-only', '--quiet', $tip) | Out-Null }
    else { Write-Line 'Local history diverged from the reviewed commit. Stopping.'; exit 2 }
  }
  $now = (Invoke-Git @('rev-parse', 'HEAD')) | Select-Object -First 1
  $extra = @(Get-Gated @('diff', '--name-only', $tip, $now))
  if ($extra.Count) { Write-Line 'Code differs from what was reviewed. Stopping.'; exit 2 }
  Set-Content -LiteralPath $ApprovedFile -Value $now -Encoding ascii
  Write-Line "Approved at $($now.Substring(0, 10)). The runner starts pinned to this commit."
  exit 0
} catch {
  Write-Line "Gate stopped: $($_.Exception.Message). Nothing was run."
  exit 2
}
