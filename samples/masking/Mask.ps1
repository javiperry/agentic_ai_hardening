# Mask.ps1 - mandatory output masking for job results.
# Every line a job prints passes through Protect-Text before it is written to disk or pushed to git.
# Pure text transformation: it never reads credentials, it only recognises their shapes.
# Works on Windows PowerShell 5.1 and PowerShell 7. ASCII only.

$script:MaskPatterns = @(
  # PEM private keys first: the whole block, with real or JSON-escaped newlines; the END line is optional (output may be cut)
  '-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----(?:\\r|\\n|\r|\n|[A-Za-z0-9+/= ])*(?:-----END [A-Z0-9 ]*PRIVATE KEY-----)?',
  # Provider token shapes
  'github_pat_[A-Za-z0-9_]{20,}', 'gh[pousr]_[A-Za-z0-9]{20,}',
  'tskey-[A-Za-z0-9_-]{16,}',
  '\b(?:AKIA|ASIA)[0-9A-Z]{16}\b',
  'npm_[A-Za-z0-9]{36}\b',
  'sk-[A-Za-z0-9_-]{16,}',
  'xox[abprs]-[A-Za-z0-9-]{10,}',
  'AIza[0-9A-Za-z_-]{35}', 'ya29\.[A-Za-z0-9_-]{20,}', '(?<![\w/])1//0[A-Za-z0-9_-]{20,}',
  '\b\d{8,10}:[A-Za-z0-9_-]{35}\b',                                    # chat-bot token (numeric id + secret)
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}',     # JWT
  '(?i)(?<=\bbearer\s{1,4})[a-z0-9._~+/-]{12,}=*',                      # Authorization: Bearer <value>
  # Session material in URLs and cookies (adapt the names to your app)
  '(?<=[?&]token=)[A-Za-z0-9_-]{20,}', '(?<=session=)[A-Za-z0-9_-]{20,}',
  # Opaque 43-char URL-safe random strings (32 random bytes, base64url) that mix upper and lower case
  '(?<![\w-])(?=[\w-]{43}(?![\w-]))(?=[\w-]{0,42}[a-z])(?=[\w-]{0,42}[A-Z])[\w-]{43}(?![\w-])',
  # Personal identifiers: E.164 phone numbers and messaging ids
  '(?<=:direct:)\+?\d{5,15}\b', '\+?\d{8,15}@s\.whatsapp\.net',
  '(?<![\w+])\+\d{10,15}\b',
  # Numeric user ids in the log contexts that carry them
  '(?i)(?<=(?:\bchatId=|\bsenderId=|\bfrom=|\bowner:))\d{6,12}\b'
)

function Protect-Text([AllowEmptyString()][string]$Text) {
  foreach ($pattern in $script:MaskPatterns) { $Text = [regex]::Replace($Text, $pattern, '<MASKED>') }
  return $Text
}
