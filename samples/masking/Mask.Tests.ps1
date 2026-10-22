# Mask.Tests.ps1 - run: pwsh -NoProfile -File Mask.Tests.ps1   (also runs on Windows PowerShell 5.1)
# Synthetic values only, assembled at runtime so secret scanners do not flag this file.
# Failure messages name the case, never the tested value.
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'Mask.ps1')

$blob = ('aB3' * 14) + 'x'          # 43 chars, mixed case
$digits = '4' * 9
$cases = [ordered]@{
  api          = 'sk-' + ('Ab1' * 8)
  botToken     = ('1' * 9) + ':' + ('Ab' * 17) + 'x'
  opaque       = $blob
  urlToken     = 'https://localhost/?token=' + $blob
  cookie       = 'session=' + $blob
  directPeer   = 'whatsapp:direct:+' + ('5' * 11)
  jid          = ('5' * 11) + '@s.whatsapp.net'
  phone        = 'call +' + ('5' * 11)
  chatId       = 'delivery ok chatId=' + $digits
  sender       = 'inbound senderId=' + $digits
  slack        = 'xoxb-' + ('a1' * 12)
  github       = 'ghp_' + ('Ab1' * 10)
  githubPat    = 'github' + '_pat_' + ('Ab1' * 8) + '_' + ('Cd2' * 19)
  google       = 'AIza' + ('a' * 35)
  googleAccess = 'ya29' + '.' + ('a0B' * 10)
  googleRefr   = 'refresh 1//0' + ('gH4' * 10)
  jwt          = 'eyJ' + ('a' * 12) + '.' + ('b' * 12) + '.' + ('c' * 12)
  tailscale    = 'tskey' + '-auth-' + ('k1A' * 4) + '-' + ('Zz9' * 8)
  aws          = 'AKIA' + ('ABC2' * 4)
  awsSession   = 'ASIA' + ('XYZ7' * 4)
  npm          = 'npm' + '_' + ('aB3' * 12)
  bearer       = 'Authorization: Bearer ' + ('Qx7' * 8)
  bearerLower  = 'authorization: bearer ' + ('q.x-7' * 4)
  pem          = '-----BEGIN ' + 'PRIVATE KEY-----' + "`n" + ('MIIEv' * 12) + "`n" + ('QIBADAN' * 9) + "`n" + '-----END ' + 'PRIVATE KEY-----'
  pemCut       = '-----BEGIN OPENSSH ' + 'PRIVATE KEY-----' + "`r`n" + ('b3Blbn' * 10) + "`r`n"
  pemJson      = '{"key": "-----BEGIN RSA ' + 'PRIVATE KEY-----\n' + ('MIIC' * 16) + '\n' + ('xYz' * 20) + '\n-----END RSA ' + 'PRIVATE KEY-----\n"}'
}
# fragments that must not survive anywhere in the masked text (not just "something was masked")
$leak = @{ pem = 'MIIEv'; pemCut = 'b3Blbn'; pemJson = 'xYz'; bearer = 'Qx7'; githubPat = 'Cd2' }

$fail = 0
foreach ($label in $cases.Keys) {
  $masked = Protect-Text $cases[$label]
  if ($masked -eq $cases[$label] -or $masked -notlike '*<MASKED>*') { "FAIL not masked: $label"; $fail++; continue }
  if ((Protect-Text $masked) -cne $masked) { "FAIL not idempotent: $label"; $fail++ }
  if ($leak.Contains($label) -and $masked.Contains($leak[$label])) { "FAIL key material left: $label"; $fail++ }
}
# values that must pass through unchanged: masking that eats normal output makes results useless
$hex = 'abcdef' + '01234' + '56789'; $guid = ('1234' * 2) + '-1234-1234-1234-' + ('123456' * 2)
$safe = @('', '2026-10-04T16:14:53+11:00', ($hex * 4), $guid,
  'Bearer token missing', 'see https://example.com/a//b', '-----BEGIN PUBLIC KEY-----', 'tskey- prefix only', 'AKIA',
  'C:\ProgramData\App\logs\gateway.log', 'exit 0 after 152 s', 'chatId=abc')
foreach ($value in $safe) { if ((Protect-Text $value) -cne $value) { "FAIL safe value changed: [$($safe.IndexOf($value))]"; $fail++ } }

if ($fail) { "mask tests: $fail failure(s)"; exit 1 }
"mask tests: $($cases.Count) secret shapes masked (idempotent), $($safe.Count) safe values unchanged"
exit 0
