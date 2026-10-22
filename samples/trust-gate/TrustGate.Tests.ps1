# TrustGate.Tests.ps1 - run: pwsh -NoProfile -File TrustGate.Tests.ps1   (needs git)
# Builds a throwaway "remote" and clone, then checks when the gate asks, approves and refuses.
$ErrorActionPreference = 'Stop'
$gate = Join-Path $PSScriptRoot 'Invoke-TrustGate.ps1'
$exe = (Get-Process -Id $PID).Path
$fail = 0
function Assert-That([bool]$Cond, [string]$Label) { if (-not $Cond) { "FAIL $Label"; $script:fail++ } }
function Invoke-Q([string]$Dir, [string[]]$A) { & git -C $Dir -c user.email=t@example.invalid -c user.name=test @A 2>&1 | Out-Null }

$root = Join-Path ([IO.Path]::GetTempPath()) ('gate-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$up = Join-Path $root 'upstream'; $clone = Join-Path $root 'clone'; $approvedFile = Join-Path $root 'approved.txt'
New-Item -ItemType Directory -Path $up -Force | Out-Null
Invoke-Q $up @('init', '--quiet', '-b', 'main')
Set-Content (Join-Path $up 'runner.ps1') "'v1'"; New-Item -ItemType Directory (Join-Path $up 'docs') | Out-Null; Set-Content (Join-Path $up 'docs/notes.txt') 'a'
Invoke-Q $up @('add', '-A'); Invoke-Q $up @('commit', '--quiet', '-m', 'base')
& git clone --quiet $up $clone 2>&1 | Out-Null
Set-Content $approvedFile ((& git -C $clone rev-parse HEAD) | Select-Object -First 1)

function Invoke-Gate([string]$Answer) {
  $out = & $exe -NoProfile -File $gate -Repo $clone -ApprovedFile $approvedFile -Answer $Answer *>&1 | Out-String
  return [pscustomobject]@{ Code = $LASTEXITCODE; Out = $out }
}
function Push-Upstream([string]$File, [string]$Text, [string]$Msg) {
  $p = Join-Path $up $File; New-Item -ItemType Directory -Path (Split-Path $p) -Force | Out-Null
  Set-Content $p $Text; Invoke-Q $up @('add', '-A'); Invoke-Q $up @('commit', '--quiet', '-m', $Msg)
}

# 1. docs-only change: no prompt, approval moves forward
Push-Upstream 'docs/notes.txt' 'b' 'docs only'
$r = Invoke-Gate 'n'
Assert-That ($r.Code -eq 0 -and $r.Out -like '*No code changes*') 'docs-only change needs no TRUST'

# 2. code change: "n" and lowercase "trust" refuse, approval file unchanged
$before = Get-Content $approvedFile
$esc = [string][char]27
Push-Upstream 'runner.ps1' "'v2'" ("change runner " + $esc + "[2K")
$r = Invoke-Gate 'n'
Assert-That ($r.Code -eq 1) 'code change refused on n'
Assert-That (-not $r.Out.Contains($esc)) 'escape codes from commit subjects are not printed'
Assert-That ($r.Out -like '*file: runner.ps1*') 'changed file is listed'
$r = Invoke-Gate 'trust'
Assert-That ($r.Code -eq 1 -and (Get-Content $approvedFile) -eq $before) 'lowercase trust does not approve'

# 3. TRUST approves and pins the new commit
$r = Invoke-Gate 'TRUST'
$tip = (& git -C $clone rev-parse origin/main) | Select-Object -First 1
Assert-That ($r.Code -eq 0 -and (Get-Content $approvedFile) -eq $tip) 'TRUST approves and records the reviewed commit'

# 4. an uncommitted local code edit is caught too
Set-Content (Join-Path $clone 'helper.ps1') "'local edit'"
$r = Invoke-Gate 'n'
Assert-That ($r.Code -eq 1 -and $r.Out -like '*helper.ps1*') 'untracked local code needs TRUST'
Remove-Item (Join-Path $clone 'helper.ps1')

# 5. approved commit missing (history rewritten) -> refuse
Set-Content $approvedFile ('0' * 40)
$r = Invoke-Gate 'TRUST'
Assert-That ($r.Code -eq 2 -and $r.Out -like '*missing*') 'missing approved commit refuses even with TRUST'

Remove-Item -Recurse -Force $root
if ($fail) { "trust-gate tests: $fail failure(s)"; exit 1 }
'trust-gate tests: all cases passed'
exit 0
