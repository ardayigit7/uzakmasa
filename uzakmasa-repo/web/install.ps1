# UzakMasa kurulum / kaldirma. Panelin verdigi komut ortam degiskenlerini ayarlayip bunu calistirir.
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$dir = Join-Path $env:LOCALAPPDATA 'UzakMasa'
$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'

# calisan eski ajani durdur
Get-CimInstance Win32_Process -Filter "Name='powershell.exe'" |
  Where-Object { $_.CommandLine -like '*UzakMasa*agent.ps1*' -and $_.ProcessId -ne $PID } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }

if ($env:UM_REMOVE -eq '1') {
  Remove-ItemProperty -Path $runKey -Name 'UzakMasa' -ErrorAction SilentlyContinue
  Start-Sleep -Milliseconds 500
  Remove-Item -Recurse -Force $dir -ErrorAction SilentlyContinue
  Write-Host 'UzakMasa kaldirildi.' -ForegroundColor Green
  return
}

$db = ([string]$env:UM_DB).TrimEnd('/')
$key = [string]$env:UM_KEY
$url = ([string]$env:UM_URL).TrimEnd('/')
if (-not $db -or -not $key -or -not $url) { throw 'Eksik parametre: UM_DB, UM_KEY, UM_URL' }

New-Item -ItemType Directory -Force -Path $dir | Out-Null
$cfgPath = Join-Path $dir 'config.json'
if (Test-Path $cfgPath) { $id = (Get-Content $cfgPath -Raw | ConvertFrom-Json).id } else { $id = [guid]::NewGuid().ToString('N').Substring(0, 10) }
$name = if ($env:UM_NAME) { $env:UM_NAME } else { $env:COMPUTERNAME }
@{ db = $db; key = $key; url = $url; id = $id; name = $name } | ConvertTo-Json | Set-Content -Path $cfgPath -Encoding UTF8

$agent = Join-Path $dir 'agent.ps1'
$r = Invoke-WebRequest -Uri "$url/agent.ps1" -UseBasicParsing
[IO.File]::WriteAllText($agent, $r.Content, (New-Object Text.UTF8Encoding $true))

$cmd = "powershell.exe -WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$agent`""
Set-ItemProperty -Path $runKey -Name 'UzakMasa' -Value $cmd
Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$agent`"")
Write-Host "UzakMasa kuruldu: $name ($id). Panelde birkac saniye icinde gorunecek." -ForegroundColor Green
