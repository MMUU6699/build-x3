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
  Write-Host "NOTE: SUPABASE_URL / key not provided. Building standalone release without pre-configured cloud secrets."
} else {
  Write-Host "==> Verified build configuration from $configPath"
  Write-Host "    SUPABASE_URL: $supabaseUrl"
  Write-Host "    Key present:  $([bool]$supabaseKey)"
}

Push-Location $repoRoot
try {
  $defaultFlags = @('--android-skip-build-dependency-validation')
  flutter build $Target --release "--dart-define-from-file=$configPath" @defaultFlags @FlutterArgs
} finally {
  Pop-Location
}
