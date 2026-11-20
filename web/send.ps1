# UzakMasa: sag tik > Gonder > UzakMasa ile gonder > cihaz. Secilen dosyalari hedef bilgisayara yollar (dosya basina 4 MB).
param([string]$Target, [Parameter(ValueFromRemainingArguments = $true)][string[]]$Files)
$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
$dir = Join-Path $env:LOCALAPPDATA 'UzakMasa'
$cfg = Get-Content (Join-Path $dir 'config.json') -Raw | ConvertFrom-Json

function Req($method, $path, $json = $null) {
  $a = @{ Uri = "$($cfg.db)$path.json"; Method = $method; UseBasicParsing = $true; TimeoutSec = 60 }
  if ($json) { $a.Body = [Text.Encoding]::UTF8.GetBytes($json); $a.ContentType = 'application/json; charset=utf-8' }
  return (Invoke-WebRequest @a).Content
}
function Ping { [void](Req 'PUT' "/q/$($cfg.key)/$Target/watch" ('"p:' + [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds() + '"')) }

$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.SystemIcons]::Information
$tray.Visible = $true
function Say($t) { $tray.ShowBalloonTip(4000, 'UzakMasa', $t, [Windows.Forms.ToolTipIcon]::Info) }

$ok = 0; $fail = 0; $why = ''
foreach ($f in $Files) {
  try {
    $fi = Get-Item -LiteralPath $f -ErrorAction Stop
    if ($fi.PSIsContainer) { throw 'Klasor gonderilemez' }
    if ($fi.Length -gt 4MB) { throw 'Dosya 4 MB ustu' }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($fi.FullName))
    $fid = [Guid]::NewGuid().ToString('N').Substring(0, 10)
    $name = ConvertTo-Json -InputObject $fi.Name -Compress
    [void](Req 'PUT' "/box/$($cfg.key)/$Target/in/$fid" ('{"name":' + $name + ',"size":' + $fi.Length + ',"b64":"' + $b64 + '"}'))
    Ping
    [void](Req 'POST' "/q/$($cfg.key)/$Target/c" ('{"t":"file","id":"' + $fid + '"}'))
    $done = $false
    for ($i = 0; $i -lt 40; $i++) {
      Start-Sleep -Milliseconds 1500
      Ping
      if ((Req 'GET' "/box/$($cfg.key)/$Target/in/$fid/name").Trim() -eq 'null') { $done = $true; break }
    }
    if ($done) { $ok++ } else { $fail++; $why = 'Bilgisayar yanit vermedi'; [void](Req 'DELETE' "/box/$($cfg.key)/$Target/in/$fid") }
  } catch { $fail++; $why = $_.Exception.Message }
}
if ($fail -eq 0) { Say "$ok dosya teslim edildi" } else { Say "$ok gonderildi, $fail basarisiz: $why" }
Start-Sleep -Seconds 5
$tray.Dispose()
