# 清理被旧版协助进程占住的网络锁 / TUN 残留。
#
# 现象：界面提示「另一个实例正在管理系统代理」，TUN 开关也动不了。
# 原因：修复前的 flvp-core-host.exe 常驻协助进程会永久持有
#       %APPDATA%\io.flvpcore\flvpcore\state\network.lock，
#       即使它自己已经空闲（state=stopped）也不释放。
# 该进程以 SYSTEM 身份运行，必须提权才能结束。

$ErrorActionPreference = 'Continue'

Write-Host '=== 1. 结束残留的 flvp-core-host 进程 ==='
Get-Process -Name 'flvp-core-host' -ErrorAction SilentlyContinue |
    ForEach-Object {
        Write-Host "  结束 PID $($_.Id)"
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
    }
Start-Sleep -Milliseconds 500

Write-Host '=== 2. 停止计划任务中的协助进程（任务本身保留）==='
Get-ScheduledTask -TaskName 'FLVPcoreHelper' -ErrorAction SilentlyContinue |
    Stop-ScheduledTask -ErrorAction SilentlyContinue

Write-Host '=== 3. 检查网络锁是否已释放 ==='
$lock = Join-Path $env:APPDATA 'io.flvpcore\flvpcore\state\network.lock'
if (Test-Path -LiteralPath $lock) {
    try {
        $handle = [IO.File]::Open($lock, 'Open', 'ReadWrite', 'None')
        $handle.Close()
        Write-Host '  锁已释放 ✓'
    } catch {
        Write-Host '  锁仍被占用 ✗ —— 可能还有其它实例在运行'
    }
} else {
    Write-Host '  锁文件不存在（无残留）'
}

Write-Host '=== 4. 清理遗留的系统代理恢复事务 ==='
$journal = Join-Path $env:APPDATA 'io.flvpcore\flvpcore\state\system-proxy.json'
if (Test-Path -LiteralPath $journal) {
    $proxy = Get-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    Write-Host "  当前 ProxyEnable=$($proxy.ProxyEnable) ProxyServer=$($proxy.ProxyServer)"
    Write-Host "  恢复日志存在：$journal"
    Write-Host '  若代理处于开启状态且指向 127.0.0.1，说明需要恢复：'
    Write-Host '    重新启动应用让宿主执行恢复，或手动在「设置 · 网络」关闭系统代理。'
} else {
    Write-Host '  无遗留恢复事务'
}

Write-Host '=== 5. 清理遗留的 DNS 接管 ==='
# TUN 模式会把物理网卡 DNS 指向内核的 fake-IP 解析器（127.0.0.1）。
# 内核已经不在了还留着这个值，整机域名解析会全部失败。
$dnsJournal = Join-Path $env:APPDATA 'io.flvpcore\flvpcore\state\system-dns.json'
if (Test-Path -LiteralPath $dnsJournal) {
    Write-Host "  发现 DNS 接管日志：$dnsJournal"
    $before = (Get-Content -LiteralPath $dnsJournal -Raw | ConvertFrom-Json).before
    foreach ($entry in $before) {
        $alias = $entry.alias
        $servers = @($entry.servers)
        $now = @(Get-DnsClientServerAddress -InterfaceAlias $alias -AddressFamily IPv4 `
            -ErrorAction SilentlyContinue).ServerAddresses
        if (-not ($now.Count -eq 1 -and $now[0] -eq '127.0.0.1')) {
            Write-Host "  $alias 当前 DNS=$($now -join ',')（已被改动，跳过）"
            continue
        }
        try {
            if ($servers.Count -eq 0) {
                Set-DnsClientServerAddress -InterfaceAlias $alias -ResetServerAddresses -ErrorAction Stop
                Write-Host "  $alias 已恢复为自动获取"
            } else {
                Set-DnsClientServerAddress -InterfaceAlias $alias -ServerAddresses $servers -ErrorAction Stop
                Write-Host "  $alias 已恢复为 $($servers -join ',')"
            }
        } catch {
            Write-Host "  $alias 恢复失败：$($_.Exception.Message)"
        }
    }
    Clear-DnsClientCache -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $dnsJournal -Force -ErrorAction SilentlyContinue
} else {
    Write-Host '  无遗留 DNS 接管'
}

Write-Host ''
Write-Host '完成。请重新启动应用，然后重新打开 TUN 开关。'
Write-Host '首次启用仍会弹出一次 UAC（因为要注册新版协助进程）。'
