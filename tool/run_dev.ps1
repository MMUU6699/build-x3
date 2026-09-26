param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]] $FlutterArgs
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$configPath = Join-Path $repoRoot 'config\buildx.public.json'

Push-Location $repoRoot
try {
  flutter run "--dart-define-from-file=$configPath" @FlutterArgs
} finally {
  Pop-Location
}
