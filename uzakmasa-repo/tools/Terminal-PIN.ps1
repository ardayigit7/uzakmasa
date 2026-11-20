# UzakMasa terminal PIN'i: bos birakirsan terminal kapanir
$dir = Join-Path $env:LOCALAPPDATA 'UzakMasa'
$cp = Join-Path $dir 'config.json'
$cfg = Get-Content $cp -Raw | ConvertFrom-Json
Write-Host 'UzakMasa terminal PIN ayari' -ForegroundColor Cyan
Write-Host 'En az 8 karakter, harf+rakam onerilir. Bos birakip Enter = terminali kapat.'
$a = Read-Host 'Yeni PIN' -AsSecureString
$pin = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($a))
if ($pin) {
  $b = Read-Host 'Tekrar' -AsSecureString
  $pin2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR([Runtime.InteropServices.Marshal]::SecureStringToBSTR($b))
  if ($pin -ne $pin2) { Write-Host 'Eslesmedi, degisiklik yok.' -ForegroundColor Red; Read-Host 'Enter'; exit }
  if ($pin.Length -lt 8) { Write-Host 'Uyari: kisa PIN tahmin edilebilir.' -ForegroundColor Yellow }
  $salt = [Text.Encoding]::UTF8.GetBytes('uzakmasa-term|' + $cfg.id)
  $kdf = New-Object Security.Cryptography.Rfc2898DeriveBytes($pin, $salt, 200000, [Security.Cryptography.HashAlgorithmName]::SHA256)
  $hex = ([BitConverter]::ToString($kdf.GetBytes(32))).Replace('-', '').ToLower()
  $cfg | Add-Member -NotePropertyName shk -NotePropertyValue $hex -Force
  Write-Host 'PIN kaydedildi. Telefonda Terminal > PIN ile ayni PIN''i gir.' -ForegroundColor Green
} else {
  $cfg.PSObject.Properties.Remove('shk')
  Write-Host 'Terminal kapatildi.' -ForegroundColor Yellow
}
[IO.File]::WriteAllText($cp, ($cfg | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding $false))
Get-CimInstance Win32_Process -Filter "name='powershell.exe'" | Where-Object { $_.CommandLine -like '*UzakMasa\agent.ps1*' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
Start-Sleep -Seconds 1
Start-Process wscript.exe -ArgumentList ('"' + (Join-Path $dir 'start.vbs') + '"')
Write-Host 'Ajan yeniden baslatildi.'
Start-Sleep -Seconds 2
