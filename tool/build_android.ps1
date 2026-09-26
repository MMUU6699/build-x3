param(
  [ValidateSet('apk', 'appbundle')]
  [string] $Target = 'apk',
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArgs
)

$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'config\buildx.public.json'

if (-not (Test-Path $configPath)) {
  Write-Error "CRITICAL: Config file '$configPath' does not exist! Release builds require valid Supabase configuration."
  exit 1
}

$rawJson = Get-Content $configPath -Raw
$config = ConvertFrom-Json $rawJson
$supabaseUrl = $config.SUPABASE_URL
$supabaseKey = if ($config.SUPABASE_PUBLISHABLE_KEY) { $config.SUPABASE_PUBLISHABLE_KEY } else { $config.SUPABASE_ANON_KEY }

if ([string]::IsNullOrWhiteSpace($supabaseUrl) -or [string]::IsNullOrWhiteSpace($supabaseKey)) {
  Write-Error "CRITICAL: SUPABASE_URL and SUPABASE_PUBLISHABLE_KEY (or SUPABASE_ANON_KEY) must be non-empty in '$configPath'!"
  exit 1
}

Write-Host "==> Verified build configuration from $configPath"
Write-Host "    SUPABASE_URL: $supabaseUrl"
Write-Host "    Key present:  $([bool]$supabaseKey)"

Push-Location $repoRoot
try {
  flutter build $Target --release "--dart-define-from-file=$configPath" @FlutterArgs
} finally {
  Pop-Location
}
