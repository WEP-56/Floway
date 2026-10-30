param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Debug',
    [string]$AndroidSdk = "$env:LOCALAPPDATA/Android/sdk",
    [string]$NdkVersion = '28.2.13676358',
    [switch]$SkipFlutter
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent
$ndk = Join-Path $AndroidSdk "ndk/$NdkVersion"
$clang = Join-Path $ndk 'toolchains/llvm/prebuilt/windows-x86_64/bin'
if (-not (Test-Path -LiteralPath $clang)) { throw "NDK not installed: $ndk" }
$targets = @(
    @{ Triple = 'aarch64-linux-android'; Clang = 'aarch64-linux-android26-clang.cmd'; Abi = 'arm64-v8a' },
    @{ Triple = 'x86_64-linux-android'; Clang = 'x86_64-linux-android26-clang.cmd'; Abi = 'x86_64' }
)
$saved = @{}
try {
    foreach ($target in $targets) {
        $triple = $target.Triple
        $targetUpper = $triple.Replace('-', '_').ToUpperInvariant()
        $vars = @{
            "CARGO_TARGET_${targetUpper}_LINKER" = (Join-Path $clang $target.Clang)
            "CC_$($triple.Replace('-', '_'))" = (Join-Path $clang $target.Clang)
            "AR_$($triple.Replace('-', '_'))" = (Join-Path $clang 'llvm-ar.exe')
            "CARGO_TARGET_${targetUpper}_RUSTFLAGS" = '-C link-arg=-Wl,-z,max-page-size=16384'
        }
        foreach ($key in $vars.Keys) {
            $saved[$key] = [Environment]::GetEnvironmentVariable($key, 'Process')
            [Environment]::SetEnvironmentVariable($key, $vars[$key], 'Process')
        }
        $cargoArgs = @('build', '--locked', '--manifest-path', (Join-Path $taskRoot 'native/core-host/Cargo.toml'),
            '--target', $triple, '--lib')
        if ($Configuration -eq 'Release') { $cargoArgs += '--release' }
        & cargo @cargoArgs
        if ($LASTEXITCODE -ne 0) { throw "Rust Android build failed: $triple" }
        $destination = Join-Path $taskRoot "android/app/src/main/jniLibs/$($target.Abi)"
        New-Item -ItemType Directory -Force -Path $destination | Out-Null
        Copy-Item -LiteralPath (Join-Path $taskRoot "native/core-host/target/$triple/$($Configuration.ToLowerInvariant())/libflvp_host.so") -Destination $destination
    }
} finally {
    foreach ($key in $saved.Keys) { [Environment]::SetEnvironmentVariable($key, $saved[$key], 'Process') }
}
if (-not $SkipFlutter) {
    Push-Location $taskRoot
    try {
        & flutter build apk "--$($Configuration.ToLowerInvariant())" --target-platform android-arm64,android-x64
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Android build failed' }
    } finally { Pop-Location }
}
