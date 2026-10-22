# Invoke-Round.ps1 - run one approved round of jobs: show every job, ask once, run in number order, stop at the first failure.
#
# Sanitised sample of the pattern. The real runner also chose the host account per job (admin vs service), refused to start
# unless a trusted launcher had pinned the reviewed commit, scanned results with gitleaks and pushed them to git.
#
#   pwsh -File Invoke-Round.ps1 -JobsDir .\jobs -ResultsDir .\results
# ROUND.txt in JobsDir:   # round: <title>
#                         # jobs: 101 102 103
param(
  [Parameter(Mandatory)][string]$JobsDir,
  [Parameter(Mandatory)][string]$ResultsDir,
  [string]$RoundFile = (Join-Path $JobsDir 'ROUND.txt'),
  [string]$Answer          # tests only: the reply to the approval prompt; a human types it otherwise
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JobLib.ps1')
. (Join-Path $PSScriptRoot '..\masking\Mask.ps1')

function Write-Safe([string]$Text) { Write-Host ($Text -replace '[^\t\r\n\x20-\x7E]', '?') }

if (-not (Test-Path -LiteralPath $RoundFile)) { Write-Safe 'No ROUND.txt: nothing to run.'; exit 2 }
$jobLine = @(Get-Content -LiteralPath $RoundFile | Where-Object { $_ -match '^#\s*jobs:' } | Select-Object -First 1)
$numbers = @(if ($jobLine.Count) { ($jobLine[0] -replace '^#\s*jobs:', '').Trim() -split '\s+' | Where-Object { $_ } })
if (-not $numbers.Count -or @($numbers | Where-Object { $_ -notmatch '^\d{3}$' }).Count) { Write-Safe 'ROUND.txt has no usable "# jobs:" line: nothing runs.'; exit 2 }
$numbers = @($numbers | Sort-Object -Unique)

# Resolve and validate the whole round before asking: one bad job stops the round before anything runs.
New-Item -ItemType Directory -Path $ResultsDir -Force | Out-Null
$plan = @()
foreach ($n in $numbers) {
  $files = @(Get-ChildItem -LiteralPath $JobsDir -Filter "$n-*.ps1")
  if ($files.Count -ne 1) { Write-Safe "Job ${n}: expected exactly one file, found $($files.Count). Nothing runs."; exit 2 }
  if (@(Get-ChildItem -LiteralPath $ResultsDir -Filter "$n-*.txt").Count) { Write-Safe "Job $n already has a result; jobs never run twice. Nothing runs."; exit 2 }
  $text = [IO.File]::ReadAllText($files[0].FullName)
  $bad = Test-JobText $text
  $hdr = Get-JobHeader $text
  if ($bad -or $hdr.Problems.Count) { Write-Safe "Job $n refused: $(@($bad) + $hdr.Problems -join '; '). Nothing runs."; exit 2 }
  $plan += [pscustomobject]@{ Number = $n; File = $files[0]; Text = $text; Header = $hdr.Fields }
}

foreach ($p in $plan) {
  Write-Safe "`n===== $($p.File.Name)  [as: $($p.Header['as'])]"
  Write-Safe $p.Text
}
$reply = if ($PSBoundParameters.ContainsKey('Answer')) { $Answer } else { Read-Host "`nRun these $($plan.Count) job(s) in order, stopping at the first failure? [y/N]" }
if ($reply -cne 'y') { Write-Safe 'Not approved. Nothing ran.'; exit 0 }

$exe = (Get-Process -Id $PID).Path
foreach ($p in $plan) {
  $started = Get-Date
  $out = @(& $exe -NoProfile -NonInteractive -File $p.File.FullName 2>&1 | ForEach-Object { "$_" })
  $code = $LASTEXITCODE
  $masked = @($out | ForEach-Object { Protect-Text $_ })
  $r = Get-LastResult $masked
  $verdict = if (-not $r) { 'no RESULT line' } elseif ($r.Exit -ne $code) { "RESULT $($r.Status) does not match exit $code" } else { '' }
  $head = @("job: $($p.File.Name)", "ran: $($started.ToString('s'))", "seconds: $([int]((Get-Date) - $started).TotalSeconds)",
    "ps: $($PSVersionTable.PSVersion)", "exit: $code")
  if ($verdict) { $head += "runner: $verdict" }
  $resultFile = Join-Path $ResultsDir ($p.File.BaseName + '.txt')
  [IO.File]::WriteAllLines($resultFile, [string[]]($head + '' + $masked))
  Write-Safe "$($p.File.Name): exit $code $(if ($r) { $r.Line })"
  if ($code -ne 0 -or $verdict) { Write-Safe "Round stopped at job $($p.Number)$(if ($verdict) { " ($verdict)" }). Later jobs did not run."; exit 1 }
}
Write-Safe "Round done: $($plan.Count) job(s) OK."
exit 0
