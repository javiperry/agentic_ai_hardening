# EgressPlan.ps1 - per-program outbound block rules for the agent's service account (Windows Firewall).
#
# Why not an allowlist: a one-day sample showed agents fetching arbitrary sites through their web tools, so a host/IP allowlist would
# break the product. Why not a default-outbound block: Windows Firewall profiles are machine-wide and would hit every account.
# Design: BLOCK rules scoped to the service account only (Windows Firewall block beats allow):
#   - shells, script hosts and download tools (living-off-the-land binaries) may not reach anything off the box
#   - the agent runtime (node) may use TCP 80/443 only: no other TCP ports, no UDP, no LAN / CGNAT (tailnet) / link-local ranges
#   - loopback is never matched, so local services keep working
#   - blocked connections are logged; the whole policy is exported first and a restore script is written next to it
#
# Get-EgressRulePlan is pure (testable anywhere); Set-EgressRules applies a plan on Windows (admin).

$script:NonLoopback = @('0.0.0.0-126.255.255.255', '128.0.0.0-255.255.255.255', '::2-ffff:ffff:ffff:ffff:ffff:ffff:ffff:ffff')
$script:PrivateRanges = @('10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16', '169.254.0.0/16', '100.64.0.0/10', 'fc00::/7', 'fe80::/10')
$script:Lolbins = @('powershell', 'pwsh', 'cmd', 'curl', 'certutil', 'bitsadmin', 'mshta', 'wscript', 'cscript', 'rundll32', 'regsvr32',
  'msiexec', 'ftp', 'tftp', 'finger', 'hh', 'wmic', 'msxsl')

function Get-EgressRulePlan {
  param(
    [Parameter(Mandatory)][string]$AccountSid,
    [Parameter(Mandatory)][string[]]$BlockedPrograms,   # full paths that exist on this machine
    [Parameter(Mandatory)][string[]]$RuntimePrograms,   # e.g. the agent runtime's node.exe
    [string]$Group = 'Agent egress'
  )
  if ($AccountSid -notmatch '^S-1-5-21-\d+-\d+-\d+-\d+$') { throw 'AccountSid must be a local or domain user SID' }
  if (-not $RuntimePrograms.Count) { throw 'no runtime program: the plan would not limit the agent itself' }
  $sddl = "O:LSD:(A;;CC;;;$AccountSid)"     # LocalUser condition: the rule matches only this account's traffic
  $base = @{ Group = $Group; Direction = 'Outbound'; Action = 'Block'; Profile = 'Any'; LocalUser = $sddl; Enabled = 'True' }
  $plan = @()
  foreach ($p in ($BlockedPrograms | Sort-Object -Unique)) {
    $plan += $base + @{ DisplayName = "$Group - block $p"; Program = $p; RemoteAddress = $script:NonLoopback }
  }
  foreach ($n in ($RuntimePrograms | Sort-Object -Unique)) {
    $plan += $base + @{ DisplayName = "$Group - runtime non-web TCP $n"; Program = $n; Protocol = 'TCP'; RemotePort = @('1-79', '81-442', '444-65535'); RemoteAddress = $script:NonLoopback }
    $plan += $base + @{ DisplayName = "$Group - runtime UDP $n"; Program = $n; Protocol = 'UDP'; RemoteAddress = $script:NonLoopback }
    $plan += $base + @{ DisplayName = "$Group - runtime private ranges $n"; Program = $n; RemoteAddress = $script:PrivateRanges }
  }
  return , $plan
}

function Set-EgressRules {
  # Windows only, elevated. Backs up the full policy, replaces the group, turns on blocked-connection logging, verifies the count.
  param([Parameter(Mandatory)][hashtable[]]$Plan, [Parameter(Mandatory)][string]$BackupDir)
  $group = $Plan[0].Group
  New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
  $wfw = Join-Path $BackupDir 'policy.wfw'
  & netsh advfirewall export "$wfw" | Out-Null
  if (-not (Test-Path -LiteralPath $wfw)) { return 'RESULT: FAIL - policy export failed; nothing changed' }
  $profiles = @(Get-NetFirewallProfile -PolicyStore ActiveStore)
  $restore = @("Remove-NetFirewallRule -Group '$group' -ErrorAction SilentlyContinue") + @($profiles | ForEach-Object { "Set-NetFirewallProfile -Name $($_.Name) -LogBlocked $($_.LogBlocked)" })
  [IO.File]::WriteAllLines((Join-Path $BackupDir 'restore.ps1'), [string[]]$restore)
  Get-NetFirewallRule -Group $group -ErrorAction SilentlyContinue | Remove-NetFirewallRule
  $errors = @()
  foreach ($r in $Plan) { try { New-NetFirewallRule @r -ErrorAction Stop | Out-Null } catch { $errors += "$($r.DisplayName): $($_.Exception.Message)" } }
  Set-NetFirewallProfile -All -LogBlocked True
  $live = @(Get-NetFirewallRule -Group $group -PolicyStore ActiveStore -ErrorAction SilentlyContinue)
  if ($errors.Count -or $live.Count -ne $Plan.Count) { return "RESULT: FAIL - $($live.Count)/$($Plan.Count) rules; undo: $BackupDir\restore.ps1" }
  return "RESULT: OK - $($live.Count) outbound block rules in '$group'; blocked connections logged. Undo: $BackupDir\restore.ps1"
}
