param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [switch]$SkipFlutter
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$manifest = Join-Path $taskRoot 'native/core-host/Cargo.toml'
$cargoArgs = @('build', '--locked', '--manifest-path', $manifest, '--bin', 'flvp-core-host')
if ($Configuration -eq 'Release') { $cargoArgs += '--release' }
& cargo @cargoArgs
if ($LASTEXITCODE -ne 0) { throw 'Native Windows build failed' }
$profile = $Configuration.ToLowerInvariant()
$hostDestination = Join-Path $taskRoot 'windows/core'
New-Item -ItemType Directory -Force -Path $hostDestination | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot "native/core-host/target/$profile/flvp-core-host.exe") -Destination $hostDestination
if (-not $SkipFlutter) {
    Push-Location $taskRoot
    try {
        & flutter build windows "--$profile"
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed' }
    } finally { Pop-Location }
}
