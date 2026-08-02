param(
  [Parameter(Mandatory = $true)]
  [ValidateSet('windows', 'apk', 'aab')]
  [string]$Platform,
  [switch]$ValidateOnly
)

$ErrorActionPreference = 'Stop'
$url = $env:SUPABASE_URL
$publishableKey = $env:SUPABASE_PUBLISHABLE_KEY

function Fail([string]$message) {
  Write-Error $message
  exit 2
}

if ([string]::IsNullOrWhiteSpace($url)) {
  Fail 'SUPABASE_URL is required for a cloud-enabled release build.'
}
if ([string]::IsNullOrWhiteSpace($publishableKey)) {
  Fail 'SUPABASE_PUBLISHABLE_KEY is required for a cloud-enabled release build.'
}
if ($url -match 'YOUR_PROJECT_REF|REPLACE_ME|<project-ref>') {
  Fail 'SUPABASE_URL contains a placeholder value.'
}
if ($publishableKey -match 'YOUR_PUBLIC_PUBLISHABLE_KEY|REPLACE_ME|<publishable-key>') {
  Fail 'SUPABASE_PUBLISHABLE_KEY contains a placeholder value.'
}

$parsedUrl = $null
if (-not [uri]::TryCreate($url.Trim(), [System.UriKind]::Absolute, [ref]$parsedUrl) -or
    $parsedUrl.Scheme -ne 'https' -or
    [string]::IsNullOrWhiteSpace($parsedUrl.Host)) {
  Fail 'SUPABASE_URL must be a valid HTTPS project URL.'
}

Write-Output "Release configuration validated for $Platform."
Write-Output 'Supabase URL valid: yes; publishable key present: yes.'
if ($ValidateOnly) { exit 0 }

$target = switch ($Platform) {
  'windows' { @('build', 'windows', '--release') }
  'apk' { @('build', 'apk', '--release') }
  'aab' { @('build', 'appbundle', '--release') }
}

& flutter @target `
  "--dart-define=SUPABASE_URL=$($url.Trim())" `
  "--dart-define=SUPABASE_PUBLISHABLE_KEY=$($publishableKey.Trim())"
exit $LASTEXITCODE
