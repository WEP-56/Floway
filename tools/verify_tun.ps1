param(
    [string]$Executable = 'D:\FLVPcore\windows\core\flvp-core-host.exe',
    [string]$Support    = "$env:TEMP\flvp-elev-tun",
    [int]$Port          = 17891
)
$ErrorActionPreference = 'Stop'
Remove-Item $Support -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path $Support -Force | Out-Null

$config = @{
    'mixed-port' = $Port; 'allow-lan' = $false; 'bind-address' = '127.0.0.1'
    'mode' = 'rule'; 'log-level' = 'warn'; 'ipv6' = $false
    'dns' = @{ 'enable' = $false }
    'tun' = @{
        'enable' = $true; 'auto-route' = $true; 'mtu' = 1500
        'address' = '198.18.0.1'; 'netmask' = '255.255.0.0'
        'fake-ip-range' = '198.18.0.0/16'
    }
    'proxies' = @()
    'proxy-groups' = @(@{ 'name' = 'PROXY'; 'type' = 'select'; 'proxies' = @('DIRECT') })
    'rules' = @('MATCH,DIRECT')
} | ConvertTo-Json -Depth 8 -Compress

$hash = -join ([Security.Cryptography.SHA256]::Create().ComputeHash(
    [Text.Encoding]::UTF8.GetBytes($config)) | ForEach-Object { $_.ToString('x2') })

$requests = @(
    @{ requestId = 'c'; operation = 'capabilities'; arguments = @{} },
    @{ requestId = 't1'; operation = 'start'; expectedGeneration = 0
       expectedAppliedRevision = 0
       arguments = @{ config = $config; configHash = $hash; revision = 1 } },
    @{ requestId = 's'; operation = 'status'; arguments = @{} }
) | ForEach-Object { $_ | ConvertTo-Json -Depth 8 -Compress }

$reqFile = Join-Path $Support 'requests.jsonl'
$resFile = Join-Path $Support 'responses.jsonl'
Set-Content -LiteralPath $reqFile -Value ($requests -join "`n") -NoNewline

$inner = Join-Path $Support 'run-inner.ps1'
@"
`$ErrorActionPreference = 'Stop'
Get-Content -LiteralPath '$reqFile' -Raw |
    & '$Executable' --app-support-dir '$Support' *> '$resFile'
"@ | Set-Content -LiteralPath $inner -Encoding UTF8

Write-Host "正在请求管理员权限（UAC）..."
$proc = Start-Process -FilePath 'powershell.exe' `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $inner) `
    -Verb RunAs -Wait -PassThru
Write-Host "elevated exit=$($proc.ExitCode)"
Write-Host "`n=== responses ==="
Get-Content -LiteralPath $resFile -ErrorAction SilentlyContinue
Write-Host "`n=== wintun adapters present? ==="
Get-NetAdapter -ErrorAction SilentlyContinue |
    Where-Object { $_.InterfaceDescription -like '*Wintun*' } |
    Select-Object Name, InterfaceDescription, Status, ifIndex
