# UzakMasa agent - Windows PowerShell 5.1, sifir bagimlilik. Dosya ASCII tutulur (BOM/kodlama sorunu olmasin).
$AGENT_VERSION = 15
$ErrorActionPreference = 'Stop'
$dir = Join-Path $env:LOCALAPPDATA 'UzakMasa'
$cfg = Get-Content (Join-Path $dir 'config.json') -Raw | ConvertFrom-Json
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
[Net.ServicePointManager]::Expect100Continue = $false
[Net.ServicePointManager]::UseNagleAlgorithm = $false
[Net.ServicePointManager]::DefaultConnectionLimit = 16
try { $u0 = [Uri]$cfg.db; if ([Net.WebRequest]::GetSystemWebProxy().GetProxy($u0) -eq $u0) { [Net.WebRequest]::DefaultWebProxy = $null } } catch {}
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public static class UM {
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, int d, UIntPtr e);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr e);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("kernel32.dll")] public static extern bool GetSystemTimes(out long idle, out long kernel, out long user);
  [DllImport("kernel32.dll")] public static extern ulong GetTickCount64();
  [StructLayout(LayoutKind.Sequential)] public struct MEM { public uint len; public uint load; public ulong total; public ulong avail; public ulong tpage; public ulong apage; public ulong tvirt; public ulong avirt; public ulong ext; }
  [DllImport("kernel32.dll")] public static extern bool GlobalMemoryStatusEx(ref MEM m);
}
"@
[void][UM]::SetProcessDPIAware()

# tek kopya (guncelleme sonrasi eski surecin cikmasini bekler)
$mtx = New-Object Threading.Mutex($false, 'Local\UzakMasaAgent')
$got = $false
try { $got = $mtx.WaitOne(15000) } catch [Threading.AbandonedMutexException] { $got = $true }
if (-not $got) { exit }

$logPath = Join-Path $dir 'agent.log'
function Log($m) {
  try {
    Add-Content -Path $logPath -Value ("{0} {1}" -f (Get-Date -Format 's'), $m)
    if ((Get-Item $logPath).Length -gt 200KB) { Set-Content $logPath -Value ("{0} log kesildi" -f (Get-Date -Format 's')) }
  } catch {}
}

function Db($method, $path, $obj = $null) {
  $p = @{ Uri = "$($cfg.db)$path.json"; Method = $method; UseBasicParsing = $true; TimeoutSec = 30 }
  if ($null -ne $obj) {
    $json = ConvertTo-Json -InputObject $obj -Depth 8 -Compress
    $p.Body = [Text.Encoding]::UTF8.GetBytes($json)
    $p.ContentType = 'application/json; charset=utf-8'
  }
  $r = Invoke-WebRequest @p
  if ($r.Content) { return ($r.Content | ConvertFrom-Json) }
}
function DbRaw($method, $path, $json) {
  $p = @{ Uri = "$($cfg.db)$path.json"; Method = $method; UseBasicParsing = $true; TimeoutSec = 60
          Body = [Text.Encoding]::UTF8.GetBytes($json); ContentType = 'application/json; charset=utf-8' }
  [void](Invoke-WebRequest @p)
}
function DbString($path) {
  $r = Invoke-WebRequest -Uri "$($cfg.db)$path.json" -UseBasicParsing -TimeoutSec 60
  $s = $r.Content
  if ($null -eq $s -or $s -eq 'null') { return $null }
  return $s.Trim('"').Replace('\/', '/')
}

$base = "/{0}/$($cfg.key)/$($cfg.id)"   # {0} = info|q|fr|box

# ---------- ekran ----------
function Get-Bounds { [Windows.Forms.Screen]::PrimaryScreen.Bounds }
function Get-Frame {
  param($hi, $fast)
  $b = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object Drawing.Bitmap $b.Width, $b.Height
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [Drawing.Point]::Empty, $b.Size)
  $g.Dispose()
  $scale = [Math]::Min(1.0, $(if ($hi) { 1920.0 } elseif ($fast) { 860.0 } else { 1100.0 }) / $b.Width)
  $tw = [int]($b.Width * $scale); $th = [int]($b.Height * $scale)
  $small = New-Object Drawing.Bitmap $tw, $th
  $g2 = [Drawing.Graphics]::FromImage($small)
  $g2.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::Bilinear
  $g2.DrawImage($bmp, 0, 0, $tw, $th)
  $g2.Dispose(); $bmp.Dispose()
  $enc = [Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.MimeType -eq 'image/jpeg' }
  $ep = New-Object Drawing.Imaging.EncoderParameters 1
  $ep.Param[0] = New-Object Drawing.Imaging.EncoderParameter ([Drawing.Imaging.Encoder]::Quality), ([long]$(if ($hi) { 62 } elseif ($fast) { 42 } else { 50 }))
  $ms = New-Object IO.MemoryStream
  $small.Save($ms, $enc, $ep)
  $small.Dispose()
  return @{ bytes = $ms.ToArray(); w = $tw; h = $th }
}
$script:lastHash = ''
function Send-Frame($hi) {
  $f = Get-Frame $hi
  $md5 = [Security.Cryptography.MD5]::Create()
  $h = [BitConverter]::ToString($md5.ComputeHash($f.bytes))
  if ($h -eq $script:lastHash) { return }
  $script:lastHash = $h
  $b64 = [Convert]::ToBase64String($f.bytes)
  $json = '{"img":"data:image/jpeg;base64,' + $b64 + '","w":' + $f.w + ',"h":' + $f.h + ',"ts":{".sv":"timestamp"}}'
  DbRaw 'PUT' ($base -f 'fr') $json
}

# Kareler ayri is parcaciginda gonderilir; boylece tiklamalar kare yuklemesini beklemez
$sync = [hashtable]::Synchronized(@{ mode = ''; modeNow = $true; sseState = ''; sseEvents = 0; kick = $false; qurl = "$($cfg.db)$($base -f 'q').json"; on = $false; hi = $false; url = "$($cfg.db)$($base -f 'fr').json"; gf = ${function:Get-Frame}.ToString(); err = ''; lh = ''; fast = 0L })
$frameWorker = {
  param($sync, $slot)
  $ErrorActionPreference = 'Stop'
  Add-Type -AssemblyName System.Windows.Forms, System.Drawing
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  [Net.ServicePointManager]::Expect100Continue = $false
  [Net.ServicePointManager]::DefaultConnectionLimit = 16
  $gf = [scriptblock]::Create($sync.gf)
  $md5 = [Security.Cryptography.MD5]::Create()
  # 3 kanal sirayla kare yakalar; her kanal yuklerken digeri yeni kareyi yakalar
  Start-Sleep -Milliseconds (90 * $slot)
  while ($true) {
    if (-not $sync.on) { Start-Sleep -Milliseconds 150; continue }
    try {
      $fast = ([DateTime]::UtcNow.Ticks -lt $sync.fast) -and -not $sync.hi
      $ts = [long]([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalMilliseconds
      $f = & $gf $sync.hi $fast
      $h = [BitConverter]::ToString($md5.ComputeHash($f.bytes))
      if ($h -eq $sync.lh) { Start-Sleep -Milliseconds 90; continue }
      $sync.lh = $h
      $json = '{"img":"data:image/jpeg;base64,' + [Convert]::ToBase64String($f.bytes) + '","w":' + $f.w + ',"h":' + $f.h + ',"c":' + $ts + ',"ts":{".sv":"timestamp"}}'
      [void](Invoke-WebRequest -Uri $sync.url -Method PUT -UseBasicParsing -TimeoutSec 30 -Body ([Text.Encoding]::UTF8.GetBytes($json)) -ContentType 'application/json; charset=utf-8')
    } catch { $sync.err = $_.Exception.Message; $sync.lh = ''; Start-Sleep -Milliseconds 700 }
  }
}
# Komut kuyrugunu canli dinle (Firebase olay akisi): yeni komut gelince ana donguyu hemen uyandir
$sseWorker = {
  param($sync)
  [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
  while ($true) {
    try {
      $req = [Net.HttpWebRequest]::Create($sync.qurl)
      $req.Accept = 'text/event-stream'; $req.Timeout = 20000; $req.ReadWriteTimeout = 75000; $req.AllowAutoRedirect = $true; $req.KeepAlive = $true
      $resp = $req.GetResponse()
      $sync.sseState = 'bagli ' + [int]$resp.StatusCode
      $sr = New-Object IO.StreamReader($resp.GetResponseStream())
      while ($true) {
        $line = $sr.ReadLine()
        if ($null -eq $line) { break }
        if ($line.StartsWith('event: put') -or $line.StartsWith('event: patch')) { $sync.kick = $true; $sync.sseEvents++ }
      }
      $sr.Close(); $resp.Close()
    } catch { $sync.sseState = 'hata: ' + $_.Exception.Message; Start-Sleep -Seconds 3 }
  }
}
$ssePs = [powershell]::Create()
[void]$ssePs.AddScript($sseWorker).AddArgument($sync)
[void]$ssePs.BeginInvoke()

# Mod bilgisini (Disaridayim/Evdeyim) arka planda dakikada bir oku; zamanlanmis gorev sorgusu yavas
$modeWorker = {
  param($sync)
  while ($true) {
    try { $t = Get-ScheduledTask -TaskName Nobet -ErrorAction Stop; $sync.mode = $(if ($t.State -eq 'Disabled') { 'home' } else { 'out' }) } catch { $sync.mode = '' }
    $sync.modeNow = $false
    for ($i = 0; $i -lt 600 -and -not $sync.modeNow; $i++) { Start-Sleep -Milliseconds 100 }
  }
}
$modePs = [powershell]::Create()
[void]$modePs.AddScript($modeWorker).AddArgument($sync)
[void]$modePs.BeginInvoke()

$framePs = @()
foreach ($slot in 0..2) {
  $fp = [powershell]::Create()
  [void]$fp.AddScript($frameWorker).AddArgument($sync).AddArgument($slot)
  [void]$fp.BeginInvoke()
  $framePs += $fp
}

# ---------- durum ----------
function Get-ModeRaw {
  try { $t = Get-ScheduledTask -TaskName Nobet -ErrorAction Stop; if ($t.State -eq 'Disabled') { return 'home' } else { return 'out' } } catch { return '' }
}
$script:cpuPrev = $null
function Get-Cpu {
  $i = 0L; $k = 0L; $u = 0L
  [void][UM]::GetSystemTimes([ref]$i, [ref]$k, [ref]$u)
  $cur = @($i, ($k + $u)); $p = $script:cpuPrev; $script:cpuPrev = $cur
  if (-not $p) { return 0 }
  $dt = $cur[1] - $p[1]; if ($dt -le 0) { return 0 }
  return [int][Math]::Max(0, [Math]::Min(100, 100 * (1 - ($cur[0] - $p[0]) / $dt)))
}
function Send-Info {
  $m = New-Object UM+MEM; $m.len = [uint32][Runtime.InteropServices.Marshal]::SizeOf([type][UM+MEM])
  [void][UM]::GlobalMemoryStatusEx([ref]$m)
  $disks = @([IO.DriveInfo]::GetDrives() | Where-Object { $_.DriveType -eq 'Fixed' -and $_.IsReady } | ForEach-Object {
    @{ n = $_.Name.TrimEnd('\'); t = [math]::Round($_.TotalSize / 1GB, 1); f = [math]::Round($_.AvailableFreeSpace / 1GB, 1) } })
  $fg = ''
  try {
    $h = [UM]::GetForegroundWindow(); $procId = 0
    [void][UM]::GetWindowThreadProcessId($h, [ref]$procId)
    $fg = (Get-Process -Id $procId -ErrorAction Stop).ProcessName
  } catch {}
  $bat = -1; $ac = $true
  try { $pw = [Windows.Forms.SystemInformation]::PowerStatus; $ac = ([string]$pw.PowerLineStatus -ne 'Offline'); if ([string]$pw.BatteryChargeStatus -notmatch 'NoSystemBattery') { $bat = [int][Math]::Round($pw.BatteryLifePercent * 100) } } catch {}
  $script:bat = $bat; $script:ac = $ac
  $info = @{
    bat = $bat; ac = $ac; sh = [bool]$cfg.shk
    name = $cfg.name; os = 'Windows'; user = $env:USERNAME; ver = $AGENT_VERSION
    cpu = (Get-Cpu)
    ramT = [math]::Round($m.total / 1GB, 1)
    ramF = [math]::Round($m.avail / 1GB, 1)
    disks = $disks; fg = $fg; up = [int]([UM]::GetTickCount64() / 60000); mode = $sync.mode
    ts = @{ '.sv' = 'timestamp' }
  }
  Db 'PUT' ($base -f 'info') $info | Out-Null
}

# ---------- fare / klavye ----------
function Move-Mouse($x, $y) {
  $b = Get-Bounds
  [void][UM]::SetCursorPos([int]($b.X + $x * ($b.Width - 1)), [int]($b.Y + $y * ($b.Height - 1)))
}
function Mouse-Flag($f, $d = 0) { [UM]::mouse_event($f, 0, 0, $d, [UIntPtr]::Zero) }
function Esc-Keys($t) {
  $sb = New-Object Text.StringBuilder
  foreach ($c in $t.ToCharArray()) {
    if ('+^%~(){}[]'.Contains([string]$c)) { [void]$sb.Append('{' + $c + '}') } else { [void]$sb.Append($c) }
  }
  return $sb.ToString()
}
$keyMap = @{ ENTER='{ENTER}'; ESC='{ESC}'; TAB='{TAB}'; BACKSPACE='{BS}'; DELETE='{DEL}'; UP='{UP}'; DOWN='{DOWN}'; LEFT='{LEFT}'; RIGHT='{RIGHT}'
             HOME='{HOME}'; END='{END}'; PGUP='{PGUP}'; PGDN='{PGDN}'; SPACE=' ' }
1..12 | ForEach-Object { $keyMap["F$_"] = "{F$_}" }

function Do-Mouse($c) {
  switch ($c.a) {
    'move'   { Move-Mouse $c.x $c.y }
    'click'  { Move-Mouse $c.x $c.y; Mouse-Flag 2; Mouse-Flag 4 }
    'dbl'    { Move-Mouse $c.x $c.y; Mouse-Flag 2; Mouse-Flag 4; Start-Sleep -Milliseconds 60; Mouse-Flag 2; Mouse-Flag 4 }
    'right'  { Move-Mouse $c.x $c.y; Mouse-Flag 8; Mouse-Flag 16 }
    'down'   { Move-Mouse $c.x $c.y; Mouse-Flag 2 }
    'up'     { Move-Mouse $c.x $c.y; Mouse-Flag 4 }
    'scroll' { Mouse-Flag 2048 ([int]$c.d) }
  }
}
function Do-Key($c) {
  if ($c.text) {
    $t = [string]$c.text
    if ($t -match '[^\x20-\x7E]') {
      Set-Clipboard -Value $t
      [Windows.Forms.SendKeys]::SendWait('^v')
    } else { [Windows.Forms.SendKeys]::SendWait((Esc-Keys $t)) }
    return
  }
  if ($c.key -eq 'WIN') {
    [UM]::keybd_event(0x5B, 0, 0, [UIntPtr]::Zero); [UM]::keybd_event(0x5B, 0, 2, [UIntPtr]::Zero); return
  }
  $k = $keyMap[[string]$c.key]
  if (-not $k) { $k = (Esc-Keys ([string]$c.key).ToLower()) }
  $prefix = ''
  foreach ($m in @($c.mods)) { switch ($m) { 'ctrl' { $prefix += '^' } 'alt' { $prefix += '%' } 'shift' { $prefix += '+' } } }
  [Windows.Forms.SendKeys]::SendWait($prefix + $k)
}

# ---------- dosyalar ----------
$userRoot = [Environment]::GetFolderPath('UserProfile')
function Safe-Path($p) {
  if (-not $p) { return $userRoot }
  $full = [IO.Path]::GetFullPath($p)
  if ($full -eq $userRoot -or $full.StartsWith($userRoot + '\', [StringComparison]::OrdinalIgnoreCase)) { return $full }
  throw 'Yol kullanici klasoru disinda'
}
function Do-Ls($c) {
  $res = @{ root = $userRoot }
  try {
    $p = Safe-Path $c.path
    $items = @(Get-ChildItem -LiteralPath $p -ErrorAction Stop | Sort-Object @{Expression = { -not $_.PSIsContainer }}, Name | Select-Object -First 400 | ForEach-Object {
      @{ n = $_.Name; d = [bool]$_.PSIsContainer; s = $(if ($_.PSIsContainer) { 0 } else { $_.Length }) } })
    $res.path = $p; $res.items = $items
  } catch { $res.err = [string]$_.Exception.Message }
  Db 'PUT' ("/box/$($cfg.key)/$($cfg.id)/res/$($c.rid)") $res | Out-Null
}
$bigMax = 100MB
$chunkSize = 2400000
function Do-Dl($c) {
  $out = "/box/$($cfg.key)/$($cfg.id)/res/$($c.rid)"
  try {
    $p = Safe-Path $c.path
    $fi = Get-Item -LiteralPath $p -ErrorAction Stop
    if ($fi.PSIsContainer) { throw 'Klasor indirilemez' }
    if ($fi.Length -gt $bigMax) { throw 'Dosya 100 MB ustu' }
    if ($fi.Length -gt $chunkSize) {
      # buyuk dosya: once bilgi, sonra parcalar /box/.../out/<rid>/<i>
      $n = [int][Math]::Ceiling($fi.Length / $chunkSize)
      Db 'PUT' $out @{ name = $fi.Name; n = $n; size = $fi.Length } | Out-Null
      $buf = New-Object byte[] $chunkSize
      $fs = [IO.File]::OpenRead($p)
      try {
        for ($i = 0; $i -lt $n; $i++) {
          $r = $fs.Read($buf, 0, $chunkSize)
          DbRaw 'PUT' "/box/$($cfg.key)/$($cfg.id)/out/$($c.rid)/$i" ('"' + [Convert]::ToBase64String($buf, 0, $r) + '"')
          if (($i % 5) -eq 4) { try { Send-Info } catch {} }
        }
      } finally { $fs.Close() }
      Log "buyuk dosya gonderildi: $p"
      return
    }
    $b64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($p))
    $name = ($fi.Name | ConvertTo-Json -Compress)
    DbRaw 'PUT' $out ('{"name":' + $name + ',"b64":"' + $b64 + '"}')
  } catch { Db 'PUT' $out @{ err = [string]$_.Exception.Message } | Out-Null }
}
function Do-File($c) {
  $node = "/box/$($cfg.key)/$($cfg.id)/in/$($c.id)"
  $name = Db 'GET' "$node/name"
  if (-not $name) { return }
  $safe = [IO.Path]::GetFileName([string]$name)
  foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) { $safe = $safe.Replace([string]$ch, '_') }
  if (-not $safe) { $safe = 'dosya' }
  $dest = Join-Path $userRoot 'Downloads\UzakMasa'
  New-Item -ItemType Directory -Force -Path $dest | Out-Null
  $target = Join-Path $dest $safe
  if (Test-Path $target) {
    $target = Join-Path $dest ((Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + $safe)
  }
  $n = 0
  if ($c.n) { $n = [int]$c.n }
  if ($n -gt 0) {
    # buyuk dosya: parcalar /in/<id>/p/<i>
    $fs = [IO.File]::Open($target, [IO.FileMode]::Create)
    try {
      for ($i = 0; $i -lt $n; $i++) {
        $part = DbString "$node/p/$i"
        if (-not $part) { throw "parca eksik: $i" }
        $bytes = [Convert]::FromBase64String($part)
        $fs.Write($bytes, 0, $bytes.Length)
        Db 'DELETE' "$node/p/$i" | Out-Null
        Db 'PUT' "$node/done" ($i + 1) | Out-Null
        if (($i % 5) -eq 4) { try { Send-Info } catch {} }
      }
    } finally { $fs.Close() }
  } else {
    $b64 = DbString "$node/b64"
    if (-not $b64) { return }
    [IO.File]::WriteAllBytes($target, [Convert]::FromBase64String($b64))
  }
  Db 'DELETE' $node | Out-Null
  Log "dosya alindi: $target"
}

# ---------- pano / ses / guc ----------
function Do-Clip($c) {
  if ($c.a -eq 'set') {
    if ($c.text) { Set-Clipboard -Value ([string]$c.text) }
    return
  }
  $t = ''
  try { $t = [string](Get-Clipboard -Raw) } catch {}
  if ($t.Length -gt 100000) { $t = $t.Substring(0, 100000) }
  Db 'PUT' ("/box/$($cfg.key)/$($cfg.id)/res/$($c.rid)") @{ text = $t; ok = 1 } | Out-Null
}
function Tap-Key($vk) {
  [UM]::keybd_event([byte]$vk, 0, 0, [UIntPtr]::Zero)
  [UM]::keybd_event([byte]$vk, 0, 2, [UIntPtr]::Zero)
}
function Do-Power($c) {
  switch ([string]$c.a) {
    'volup'   { Tap-Key 175; Tap-Key 175; Tap-Key 175 }
    'voldown' { Tap-Key 174; Tap-Key 174; Tap-Key 174 }
    'mute'    { Tap-Key 173 }
    'play'    { Tap-Key 179 }
    'next'    { Tap-Key 176 }
    'prev'    { Tap-Key 177 }
    'bright'  {
      $v = [Math]::Max(0, [Math]::Min(100, [int]$c.v))
      [void](Get-WmiObject -Namespace root/WMI -Class WmiMonitorBrightnessMethods -ErrorAction Stop).WmiSetBrightness(1, $v)
    }
    'lock'    { Start-Process -FilePath rundll32.exe -ArgumentList 'user32.dll,LockWorkStation' }
    'restart' { Log 'yeniden baslat'; Start-Process -FilePath shutdown.exe -ArgumentList '/r /t 5' -WindowStyle Hidden }
    'off'     { Log 'kapat'; Start-Process -FilePath shutdown.exe -ArgumentList '/s /t 5' -WindowStyle Hidden }
  }
}

# ---------- telefona bildirim (ntfy) ----------
$ntopic = ''
try {
  $sha = [Security.Cryptography.SHA256]::Create()
  $hex = [BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes([string]$cfg.key))).Replace('-', '').ToLower()
  $ntopic = 'um-' + $hex.Substring(0, 24)
} catch {}
function Push($msg) {
  if (-not $ntopic) { return }
  try {
    [void](Invoke-WebRequest -Uri "https://ntfy.sh/$ntopic" -Method POST -UseBasicParsing -TimeoutSec 10 -Headers @{ Title = "UzakMasa - $($cfg.name)" } -Body ([Text.Encoding]::UTF8.GetBytes([string]$msg)))
  } catch {}
}

# ---------- terminal (PIN imzali) ----------
# Komut ancak telefonda girilen PIN ile imzalanmissa calisir. PIN Firebase'e gitmez;
# laptopta sadece PIN'in SHA-256 ozeti (config.json -> shk) durur.
$script:shUsed = @{}
$script:shJobs = @{}
$script:shCwd = $userRoot
function Hex($b) { return ([BitConverter]::ToString($b)).Replace('-', '').ToLower() }
function Sh-Res($rid, $obj) { Db 'PUT' ("/box/$($cfg.key)/$($cfg.id)/res/$rid") $obj | Out-Null }
function Do-Shell($c) {
  $rid = [string]$c.rid
  if (-not $cfg.shk) { Sh-Res $rid @{ err = 'Terminal kapali: laptopta Terminal-PIN.cmd ile PIN belirlenmemis.'; done = 1 }; return }
  $cmdText = [string]$c.cmd; $ts = [long]$c.ts; $nonce = [string]$c.n
  $now = [long]([DateTime]::UtcNow - [DateTime]'1970-01-01').TotalMilliseconds
  $hm = New-Object Security.Cryptography.HMACSHA256
  $kb = New-Object byte[] 32
  for ($i = 0; $i -lt 32; $i++) { $kb[$i] = [Convert]::ToByte($cfg.shk.Substring($i * 2, 2), 16) }
  $hm.Key = $kb
  $want = Hex ($hm.ComputeHash([Text.Encoding]::UTF8.GetBytes("$nonce|$ts|$cmdText")))
  if ($want -ne [string]$c.sig) { Log 'terminal: imza hatali'; Sh-Res $rid @{ err = 'PIN yanlis.'; done = 1 }; return }
  if ([Math]::Abs($now - $ts) -gt 120000) { Sh-Res $rid @{ err = 'Komut zaman asimina ugradi (saat farki?).'; done = 1 }; return }
  if ($script:shUsed.ContainsKey($nonce)) { return }
  $script:shUsed[$nonce] = $now
  if ($script:shUsed.Count -gt 500) { $script:shUsed = @{} }
  Log ("terminal: " + $(if ($cmdText.Length -gt 120) { $cmdText.Substring(0, 120) } else { $cmdText }))
  Notify 'Uzaktan terminal komutu calistirildi'
  $wrapped = "[Console]::OutputEncoding=[Text.Encoding]::UTF8; `$ProgressPreference='SilentlyContinue'; Set-Location -LiteralPath '" + $script:shCwd.Replace("'", "''") + "'; try { " + $cmdText + " } catch { Write-Output (`$_ | Out-String) }; Write-Output ('__CWD__' + (Get-Location).Path)"
  $enc = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($wrapped))
  $psi = New-Object Diagnostics.ProcessStartInfo
  $psi.FileName = 'powershell.exe'
  $psi.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $enc"
  $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
  $psi.StandardOutputEncoding = [Text.Encoding]::UTF8; $psi.StandardErrorEncoding = [Text.Encoding]::UTF8
  $p = [Diagnostics.Process]::Start($psi)
  $script:shJobs[$rid] = @{ p = $p; o = $p.StandardOutput.ReadToEndAsync(); e = $p.StandardError.ReadToEndAsync(); t = Get-Date }
}
function Poll-Shell {
  foreach ($rid in @($script:shJobs.Keys)) {
    $j = $script:shJobs[$rid]
    $late = ((Get-Date) - $j.t).TotalSeconds -gt 90
    if (-not $j.p.HasExited -and -not $late) { continue }
    if ($late -and -not $j.p.HasExited) { try { $j.p.Kill() } catch {} }
    $out = ''; $er = ''
    try { $out = [string]$j.o.Result } catch {}
    try { $er = [string]$j.e.Result } catch {}
    $m = [regex]::Match($out, '__CWD__(.+?)\s*$')
    if ($m.Success) { $script:shCwd = $m.Groups[1].Value.Trim(); $out = $out.Substring(0, $m.Index) }
    $txt = ($out + $er).TrimEnd()
    if ($late) { $txt += "`n[90 sn doldu, durduruldu]" }
    if ($txt.Length -gt 60000) { $txt = $txt.Substring(0, 60000) + "`n[cikti kesildi]" }
    Sh-Res $rid @{ out = $txt; cwd = $script:shCwd; code = $(if ($j.p.HasExited) { $j.p.ExitCode } else { -1 }); done = 1 }
    $script:shJobs.Remove($rid)
  }
}

# ---------- uygulamalar ----------
$script:startApps = $null
$script:startAppsAt = [DateTime]::MinValue
function Get-AppList {
  if (-not $script:startApps -or ((Get-Date) - $script:startAppsAt).TotalMinutes -gt 10) {
    $list = @()
    try { $list = @(Get-StartApps | Where-Object { $_.Name -and $_.AppID } | ForEach-Object { @{ n = [string]$_.Name; id = [string]$_.AppID } }) } catch { Log "startapps hatasi: $($_.Exception.Message)" }
    $script:startApps = $list; $script:startAppsAt = Get-Date
  }
  return $script:startApps
}
function Do-Apps($c) {
  $out = "/box/$($cfg.key)/$($cfg.id)/res/$($c.rid)"
  $run = @(Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle -and $_.Id -ne $PID } | Sort-Object ProcessName | ForEach-Object {
    @{ pid = $_.Id; n = $_.ProcessName; t = $_.MainWindowTitle; m = [int]($_.WorkingSet64 / 1MB) } })
  $res = @{ run = $run; ok = 1 }
  if ($c.all) { $res.all = @(Get-AppList) }
  Db 'PUT' $out $res | Out-Null
}
function Do-Launch($c) {
  $id = [string]$c.id
  $known = @(Get-AppList | Where-Object { $_.id -eq $id }).Count -gt 0
  if (-not $known) { $script:startAppsAt = [DateTime]::MinValue; $known = @(Get-AppList | Where-Object { $_.id -eq $id }).Count -gt 0 }
  if (-not $known) { Log "bilinmeyen uygulama: $id"; return }
  Start-Process -FilePath explorer.exe -ArgumentList "shell:AppsFolder\$id"
  Log "baslatildi: $id"
}
function Do-Kill($c) {
  $p = Get-Process -Id ([int]$c.pid) -ErrorAction Stop
  if ($p.Id -eq $PID) { return }
  if ($c.force) { Stop-Process -Id $p.Id -Force } else { [void]$p.CloseMainWindow() }
  Log "kapat: $($p.ProcessName) zorla=$([bool]$c.force)"
}

function Do-Mode($c) {
  $t = if ($c.v -eq 'out') { 'UM-Disari' } else { 'UM-Ev' }
  Log "mod: $t"
  Start-Process -FilePath schtasks.exe -ArgumentList @('/run', '/tn', $t) -WindowStyle Hidden
  Start-Sleep -Seconds 6
  $sync.modeNow = $true
  $script:lastInfo = [DateTime]::MinValue
}

function Handle($c) {
  switch ($c.t) {
    'm'    { $sync.fast = [DateTime]::UtcNow.AddMilliseconds(1500).Ticks; Do-Mouse $c }
    'k'    { $sync.fast = [DateTime]::UtcNow.AddMilliseconds(1500).Ticks; Do-Key $c }
    'sh'   { Do-Shell $c }
    'ls'   { Do-Ls $c }
    'dl'   { Do-Dl $c }
    'file' { Do-File $c }
    'mode' { Do-Mode $c }
    'apps' { Do-Apps $c }
    'launch' { Do-Launch $c }
    'kill' { Do-Kill $c }
    'clip' { Do-Clip $c }
    'pow'  { Do-Power $c }
    'hib'  { Log 'hibernate'; Start-Sleep -Seconds 2; Start-Process -FilePath shutdown.exe -ArgumentList '/h' -WindowStyle Hidden }
  }
}

# ---------- gorunmez baslatici ----------
# Windows Terminal varsayilan konsolsa "-WindowStyle Hidden" pencereyi gizleyemez; wscript ile tamamen gizli acilir
$vbs = Join-Path $dir 'start.vbs'
function Ensure-Launcher {
  try {
    $agentPath = Join-Path $dir 'agent.ps1'
    $line = 'CreateObject("WScript.Shell").Run "powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File """ + "' + $agentPath + '" + """", 0, False'
    if (-not (Test-Path $vbs) -or (Get-Content $vbs -Raw).Trim() -ne $line) { Set-Content -Path $vbs -Value $line -Encoding Unicode }
    $want = 'wscript.exe "' + $vbs + '"'
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if ((Get-ItemProperty -Path $runKey -Name UzakMasa -ErrorAction SilentlyContinue).UzakMasa -ne $want) { Set-ItemProperty -Path $runKey -Name UzakMasa -Value $want; Log 'baslatici wscript yapildi' }
  } catch { Log "baslatici hatasi: $($_.Exception.Message)" }
}

# ---------- guncelleme ----------
function Check-Update {
  try {
    $r = Invoke-WebRequest -Uri "$($cfg.url)/agent.ps1" -UseBasicParsing -TimeoutSec 30
    if ($r.Content -match '\$AGENT_VERSION\s*=\s*(\d+)' -and [int]$Matches[1] -gt $AGENT_VERSION) {
      $path = Join-Path $dir 'agent.ps1'
      [IO.File]::WriteAllText($path, $r.Content, (New-Object Text.UTF8Encoding $true))
      Log "guncellendi -> v$($Matches[1])"
      if (Test-Path $vbs) { Start-Process -FilePath wscript.exe -ArgumentList "`"$vbs`"" }
      else { Start-Process powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', "`"$path`"") }
      # arka plan is parcaciklari sureci acik tutar; kilidi birakip sureci tamamen kapat
      try { $mtx.ReleaseMutex() } catch {}
      [Environment]::Exit(0)
    }
  } catch { Log "guncelleme kontrol hatasi: $($_.Exception.Message)" }
}

# ---------- sag tik menusu: Gonder > UzakMasa ile gonder > <cihaz> ----------
function Sync-SendTo {
  try {
    $st = Join-Path $env:APPDATA 'Microsoft\Windows\SendTo\UzakMasa ile gonder'
    New-Item -ItemType Directory -Force -Path $st | Out-Null
    $sendPs = Join-Path $dir 'send.ps1'
    $r = Invoke-WebRequest -Uri "$($cfg.url)/send.ps1" -UseBasicParsing -TimeoutSec 30
    if (-not (Test-Path $sendPs) -or ((Get-Content $sendPs -Raw).TrimEnd() -ne $r.Content.TrimEnd())) {
      [IO.File]::WriteAllText($sendPs, $r.Content, (New-Object Text.UTF8Encoding $true))
    }
    $all = Db 'GET' "/info/$($cfg.key)"
    $want = @{}
    if ($all) {
      foreach ($p in $all.PSObject.Properties) {
        $n = [string]$p.Value.name
        if (-not $n) { $n = $p.Name }
        if ($p.Name -eq $cfg.id) { $n = "$n (bu bilgisayar)" }
        foreach ($ch in [IO.Path]::GetInvalidFileNameChars()) { $n = $n.Replace([string]$ch, '_') }
        $fn = "$n.lnk"
        if ($want.ContainsKey($fn)) { $fn = "$n ($($p.Name)).lnk" }
        $want[$fn] = $p.Name
      }
    }
    $ws = New-Object -ComObject WScript.Shell
    foreach ($k in $want.Keys) {
      $lnk = $ws.CreateShortcut((Join-Path $st $k))
      $lnk.TargetPath = (Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe')
      $lnk.Arguments = "-WindowStyle Hidden -NoProfile -ExecutionPolicy Bypass -File `"$sendPs`" -Target $($want[$k])"
      $lnk.WindowStyle = 7
      $lnk.Save()
    }
    Get-ChildItem -LiteralPath $st -Filter '*.lnk' | Where-Object { -not $want.ContainsKey($_.Name) } | Remove-Item -Force
  } catch { Log "sendto hatasi: $($_.Exception.Message)" }
}

# ---------- ana dongu ----------
$tray = $null
function Notify($text) {
  try {
    if (-not $script:tray) {
      $script:tray = New-Object Windows.Forms.NotifyIcon
      $script:tray.Icon = [Drawing.SystemIcons]::Information
      $script:tray.Visible = $true
    }
    $script:tray.ShowBalloonTip(3000, 'UzakMasa', $text, [Windows.Forms.ToolTipIcon]::Info)
  } catch {}
}

Log "basladi v$AGENT_VERSION id=$($cfg.id)"
# Windows acilista baslangic programlarini birkac dakika geciktirir; kapat
try {
  $ser = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Serialize'
  if (-not (Test-Path $ser)) { New-Item -Path $ser -Force | Out-Null }
  New-ItemProperty -Path $ser -Name StartupDelayInMSec -PropertyType DWord -Value 0 -Force | Out-Null
} catch {}
Ensure-Launcher
try { Db 'DELETE' "/box/$($cfg.key)/$($cfg.id)/out" | Out-Null } catch {}
try { Send-Info } catch {}
Check-Update
$lastUpdateCheck = Get-Date
Sync-SendTo
$lastSync = Get-Date
$lastInfo = [DateTime]::MinValue
$lastWatch = $null
$lastWatchChange = [DateTime]::MinValue
$wasScreen = $false
$errCount = 0
$lastTick = Get-Date
$pendingWake = Get-Date
$batWarned = $false

while ($true) {
  try {
    $tick = Get-Date
    if (($tick - $lastTick).TotalSeconds -gt 25) { Log 'uykudan dondu'; $pendingWake = $tick; $lastInfo = [DateTime]::MinValue; $lastUpdateCheck = [DateTime]::MinValue; $errCount = 0 }
    $lastTick = $tick
    $sync.kick = $false
    $t0 = Get-Date
    $q = Db 'GET' ($base -f 'q')
    $now = Get-Date
    $tGet = ($now - $t0).TotalMilliseconds
    if ($q -and $q.watch -and ($q.watch -ne $lastWatch)) { $lastWatch = $q.watch; $lastWatchChange = $now }
    $recent = ($now - $lastWatchChange).TotalSeconds -lt 12
    $screen = $recent -and ([string]$lastWatch -match '^s:')
    $hiRes = ([string]$lastWatch -cmatch '^S:')
    if ($screen -and -not $wasScreen) { Notify 'Ekraniniz uzaktan goruntuleniyor' }
    $wasScreen = $screen

    if ($q -and $q.c) {
      $keys = @($q.c.PSObject.Properties.Name | Sort-Object)
      $del = @{}
      foreach ($k in $keys) {
        $del[$k] = $null
        try { Handle $q.c.$k } catch { Log "komut hatasi ($k): $($_.Exception.Message)" }
      }
      Db 'PATCH' (($base -f 'q') + '/c') $del | Out-Null
    }
    if ($script:shJobs.Count) { Poll-Shell }
    $tCmd = ((Get-Date) - $now).TotalMilliseconds

    $sync.on = [bool]$screen; $sync.hi = [bool]$hiRes

    $infoEvery = if ($recent) { 10 } else { 20 }
    $t1 = Get-Date
    if (($now - $lastInfo).TotalSeconds -ge $infoEvery) { Send-Info; $lastInfo = $now }
    $tInfo = ((Get-Date) - $t1).TotalMilliseconds
    if (($tGet + $tCmd + $tInfo) -gt 1500) { Log ("yavas tur: get={0:N0} komut={1:N0} bilgi={2:N0} ms" -f $tGet, $tCmd, $tInfo) }
    if (($now - $lastUpdateCheck).TotalHours -ge 3) { Check-Update; $lastUpdateCheck = $now }
    if (($now - $lastSync).TotalMinutes -ge 5) { Sync-SendTo; $lastSync = $now }
    if ($sync.sseState -ne $script:lastSse) { $script:lastSse = $sync.sseState; Log "canli baglanti: $($sync.sseState)" }
    # bildirimler: 90 sn uyanik kaldiysa (Nobet gorevinin kisa uyanislari sayilmaz) ve pil dusukse
    if ($pendingWake -and ($now - $pendingWake).TotalSeconds -gt 90) { $pendingWake = $null; Push 'Bilgisayar acik ve hazir.' }
    if (-not $script:ac -and $script:bat -ge 0 -and $script:bat -le 20) { if (-not $batWarned) { $batWarned = $true; Push ("Pil dusuk: %{0}" -f $script:bat) } } elseif ($script:ac -or $script:bat -gt 25) { $batWarned = $false }
    $errCount = 0
    $until = (Get-Date).AddMilliseconds($(if ($script:shJobs.Count) { 300 } elseif ($recent) { 1500 } else { 3000 }))
    while (-not $sync.kick -and (Get-Date) -lt $until) { Start-Sleep -Milliseconds 15 }
  } catch {
    $sync.on = $false
    $errCount++
    Log "dongu hatasi: $($_.Exception.Message)"
    $lastTick = Get-Date
    Start-Sleep -Seconds ([Math]::Min(8, 2 * $errCount))
  }
}
