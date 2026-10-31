param(
    [ValidateSet('Debug', 'Release')][string]$Configuration = 'Release',
    [switch]$SkipFlutter
)
$ErrorActionPreference = 'Stop'
$taskRoot = Split-Path $PSScriptRoot -Parent

# 正在运行的宿主会锁住自己的 exe，install 步骤随后以 MSB3073 失败，
# 报错完全看不出原因。先给出可执行的指引。
$stagedHost = Join-Path $taskRoot 'windows/core/flvp-core-host.exe'
foreach ($candidate in @($stagedHost, (Join-Path $taskRoot "build/windows/x64/runner/$Configuration/flvp-core-host.exe"))) {
    if (-not (Test-Path -LiteralPath $candidate)) { continue }
    try {
        $handle = [IO.File]::Open($candidate, 'Open', 'ReadWrite', 'None')
        $handle.Close()
    } catch {
        Write-Host "宿主二进制正被运行中的进程占用：$candidate" -ForegroundColor Yellow
        Write-Host '请先关闭应用；若协助进程仍在后台，请用管理员终端执行：' -ForegroundColor Yellow
        Write-Host '    pwsh -File tools\cleanup_stale_helper.ps1' -ForegroundColor Yellow
        throw "Cannot rebuild while $candidate is locked"
    }
}

$manifest = Join-Path $taskRoot 'native/core-host/Cargo.toml'
$cargoArgs = @('build', '--locked', '--manifest-path', $manifest, '--bin', 'flvp-core-host')
if ($Configuration -eq 'Release') { $cargoArgs += '--release' }
& cargo @cargoArgs
if ($LASTEXITCODE -ne 0) { throw 'Native Windows build failed' }
$profile = $Configuration.ToLowerInvariant()
$hostDestination = Join-Path $taskRoot 'windows/core'
New-Item -ItemType Directory -Force -Path $hostDestination | Out-Null
Copy-Item -LiteralPath (Join-Path $taskRoot "native/core-host/target/$profile/flvp-core-host.exe") -Destination $hostDestination
# TUN 需要 Wintun 驱动，内核只在 exe 同级目录（或少数几个回退位置）找它。
# 不随包发布的话，开 TUN 只会得到一句笼统的启动失败。
$wintun = Join-Path $taskRoot "native/core-host/target/$profile/wintun.dll"
if (-not (Test-Path -LiteralPath $wintun)) {
    throw "wintun.dll not found at $wintun; run 'cargo fetch' so the tun crate vendors it"
}
Copy-Item -LiteralPath $wintun -Destination $hostDestination -Force
if (-not $SkipFlutter) {
    Push-Location $taskRoot
    try {
        & flutter build windows "--$profile"
        if ($LASTEXITCODE -ne 0) { throw 'Flutter Windows build failed' }
    } finally { Pop-Location }
}
