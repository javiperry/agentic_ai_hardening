# EgressPlan.Tests.ps1 - run: pwsh -NoProfile -File EgressPlan.Tests.ps1   (pure plan checks; no firewall is touched)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'EgressPlan.ps1')
$fail = 0
function Assert-That([bool]$Cond, [string]$Label) { if (-not $Cond) { "FAIL $Label"; $script:fail++ } }

$sid = 'S-1-5-21-' + ((('1' * 9), ('2' * 9), ('3' * 9)) -join '-') + '-1001'   # synthetic, built at runtime
$blocked = @('C:\Windows\System32\cmd.exe', 'C:\Windows\System32\curl.exe', 'C:\Windows\System32\cmd.exe')
$plan = Get-EgressRulePlan -AccountSid $sid -BlockedPrograms $blocked -RuntimePrograms @('C:\Program Files\Agent\node.exe')

Assert-That ($plan.Count -eq 5) 'two unique blocked programs + three runtime rules'
Assert-That (@($plan | Where-Object { $_.Direction -ne 'Outbound' -or $_.Action -ne 'Block' }).Count -eq 0) 'every rule is an outbound block'
Assert-That (@($plan | Where-Object { $_.LocalUser -ne "O:LSD:(A;;CC;;;$sid)" }).Count -eq 0) 'every rule is scoped to the service account only'
$all = @($plan | ForEach-Object { $_.RemoteAddress })
Assert-That (-not ($all -match '^127\.' -or $all -contains '::1')) 'loopback is never listed'
Assert-That (@($plan | Where-Object { $_.RemoteAddress -contains '0.0.0.0-126.255.255.255' }).Count -ge 3) 'off-box ranges skip 127.0.0.0/8'
$tcp = @($plan | Where-Object { $_.Protocol -eq 'TCP' })[0]
Assert-That ($tcp.RemotePort -notcontains '443' -and $tcp.RemotePort -notcontains '80' -and $tcp.RemotePort -contains '444-65535') 'runtime keeps TCP 80/443 only'
Assert-That (@($plan | Where-Object { $_.Protocol -eq 'UDP' }).Count -eq 1) 'runtime UDP blocked'
Assert-That (@($plan | Where-Object { $_.RemoteAddress -contains '100.64.0.0/10' }).Count -eq 1) 'runtime cannot reach the tailnet (CGNAT) range'

$threw = $false; try { $null = Get-EgressRulePlan -AccountSid 'S-1-5-18' -BlockedPrograms $blocked -RuntimePrograms @('x') } catch { $threw = $true }
Assert-That $threw 'refuses a well-known SID (SYSTEM) - the plan is for one user account'
$threw = $false; try { $null = Get-EgressRulePlan -AccountSid $sid -BlockedPrograms $blocked -RuntimePrograms @() } catch { $threw = $true }
Assert-That $threw 'refuses a plan that does not limit the runtime'

if ($fail) { "egress tests: $fail failure(s)"; exit 1 }
'egress tests: all plan checks passed'
exit 0
