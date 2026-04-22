param(
    [Parameter(Mandatory = $true)]
    [string]$ApiBaseUrl,

    [switch]$StageForVercel
)

$ErrorActionPreference = 'Stop'

function Resolve-Flutter {
    $flutterCommand = Get-Command flutter -ErrorAction SilentlyContinue
    if ($flutterCommand) {
        return $flutterCommand.Source
    }

    if ($env:FLUTTER_ROOT) {
        $candidate = Join-Path $env:FLUTTER_ROOT 'bin\flutter.bat'
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    $fallback = 'C:\Users\VALENTINE\flutter\bin\flutter.bat'
    if (Test-Path $fallback) {
        return $fallback
    }

    throw 'Flutter was not found. Add it to PATH or set FLUTTER_ROOT before running this script.'
}

$flutter = Resolve-Flutter
$resolvedApiBaseUrl = $ApiBaseUrl.Trim().TrimEnd('/')

if ([string]::IsNullOrWhiteSpace($resolvedApiBaseUrl)) {
    throw 'ApiBaseUrl cannot be empty.'
}

Write-Host "Using Flutter: $flutter"
Write-Host "Building Flutter web with API_BASE_URL=$resolvedApiBaseUrl"

& $flutter pub get
& $flutter build web --release "--dart-define=API_BASE_URL=$resolvedApiBaseUrl"

if ($StageForVercel) {
    $sourceConfig = Join-Path $PSScriptRoot '..\deploy\vercel.static.json'
    $targetConfig = Join-Path $PSScriptRoot '..\build\web\vercel.json'
    Copy-Item $sourceConfig $targetConfig -Force
    Write-Host "Staged Vercel config at $targetConfig"
}

Write-Host 'Flutter web build complete.'
