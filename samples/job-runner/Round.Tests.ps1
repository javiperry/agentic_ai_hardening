# Round.Tests.ps1 - run: pwsh -NoProfile -File Round.Tests.ps1
# Builds throwaway job folders and checks the round contract end to end.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'JobLib.ps1')
$runner = Join-Path $PSScriptRoot 'Invoke-Round.ps1'
$exe = (Get-Process -Id $PID).Path
$fail = 0
function Assert-That([bool]$Cond, [string]$Label) { if (-not $Cond) { "FAIL $Label"; $script:fail++ } }

function New-Case([hashtable]$Jobs, [string]$Round) {
  $root = Join-Path ([IO.Path]::GetTempPath()) ('round-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8))
  $jobDir = Join-Path $root 'jobs'; New-Item -ItemType Directory -Path $jobDir -Force | Out-Null
  foreach ($name in $Jobs.Keys) { [IO.File]::WriteAllText((Join-Path $jobDir $name), $Jobs[$name]) }
  [IO.File]::WriteAllText((Join-Path $jobDir 'ROUND.txt'), "# round: test`n# jobs: $Round`n")
  return $root
}
function Invoke-Case([string]$Root, [string]$Answer = 'y') {
  $null = & $exe -NoProfile -File $runner -JobsDir (Join-Path $Root 'jobs') -ResultsDir (Join-Path $Root 'results') -Answer $Answer *>&1
  return $LASTEXITCODE
}
$hdrRead = "# job: read something`n# as: service`n# Changes: nothing (read-only)`n"
$hdrChange = "# job: change something`n# as: admin`n# Changes: writes a file`n# Undo: delete the file`n"
$token = 'sk-' + ('Ab1' * 8)

# 1. happy path: two jobs run in order, output masked, results written
$r = New-Case @{ '101-a.ps1' = $hdrRead + "'value $token'`n'RESULT: INFO - read'`nexit 0"; '102-b.ps1' = $hdrChange + "'RESULT: OK - done'`nexit 0" } '102 101'
Assert-That ((Invoke-Case $r) -eq 0) 'happy path exits 0'
$res101 = Get-Content (Join-Path $r 'results/101-a.txt') -Raw
Assert-That ($res101 -like '*<MASKED>*' -and -not $res101.Contains($token)) 'secret masked in result'
Assert-That (Test-Path (Join-Path $r 'results/102-b.txt')) 'second job ran'

# 2. stop at first failure: 202 fails, 203 never runs
$r = New-Case @{ '201-a.ps1' = $hdrRead + "'RESULT: OK - fine'`nexit 0"; '202-b.ps1' = $hdrRead + "'RESULT: FAIL - broke'`nexit 1"; '203-c.ps1' = $hdrRead + "'RESULT: OK - x'`nexit 0" } '201 202 203'
Assert-That ((Invoke-Case $r) -eq 1) 'failing round exits 1'
Assert-That (-not (Test-Path (Join-Path $r 'results/203-c.txt'))) 'job after the failure did not run'

# 3. RESULT/exit mismatch counts as failure (a job that says OK but exits 1 is not trusted)
$r = New-Case @{ '301-a.ps1' = $hdrRead + "'RESULT: OK - claims ok'`nexit 1"; '302-b.ps1' = $hdrRead + "'RESULT: OK - x'`nexit 0" } '301 302'
Assert-That ((Invoke-Case $r) -eq 1) 'mismatch stops the round'
Assert-That ((Get-Content (Join-Path $r 'results/301-a.txt') -Raw) -like '*runner: RESULT OK does not match exit 1*') 'mismatch recorded'

# 4. refused before anything runs: ESC byte, missing Undo, missing header
$esc = [string][char]27
foreach ($bad in @(($hdrRead + "'" + $esc + "[2Jhidden'`n'RESULT: OK - x'"), ("# job: x`n# as: admin`n# Changes: writes`n'RESULT: OK - x'"), "'RESULT: OK - no header'")) {
  $r = New-Case @{ '401-ok.ps1' = $hdrChange + "New-Item -ItemType File -Path (Join-Path `$PSScriptRoot 'ran.flag') | Out-Null`n'RESULT: OK - x'`nexit 0"; '402-bad.ps1' = $bad } '401 402'
  Assert-That ((Invoke-Case $r) -eq 2) 'bad job refuses the round'
  Assert-That (-not (Test-Path (Join-Path $r 'jobs/ran.flag'))) 'no job ran when one was refused'
}

# 5. no approval -> nothing runs; jobs never run twice
$r = New-Case @{ '501-a.ps1' = $hdrRead + "'RESULT: OK - x'`nexit 0" } '501'
Assert-That ((Invoke-Case $r 'Y') -eq 0 -and -not @(Get-ChildItem (Join-Path $r 'results') -Filter '*.txt').Count) 'only a lowercase y approves'
$null = Invoke-Case $r 'y'
Assert-That ((Invoke-Case $r 'y') -eq 2) 'a job with a result is never re-run'

# 6. chained guard
$d = Join-Path ([IO.Path]::GetTempPath()) ('guard-' + [guid]::NewGuid().ToString('N').Substring(0, 8)); New-Item -ItemType Directory $d | Out-Null
Set-Content (Join-Path $d '601-a.txt') "exit: 0`nRESULT: OK - fine"
Set-Content (Join-Path $d '602-b.txt') "exit: 0`nRESULT: INFO - read only"
Assert-That ((Assert-PrevResultOk $d @('601')) -eq '') 'guard passes on OK'
Assert-That ((Assert-PrevResultOk $d @('601', '602')) -like '*did not end OK*') 'guard blocks on INFO'
Assert-That ((Assert-PrevResultOk $d @('603')) -like '*no result*') 'guard blocks on missing result'

if ($fail) { "round tests: $fail failure(s)"; exit 1 }
'round tests: all cases passed'
exit 0
